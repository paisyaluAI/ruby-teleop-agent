#!/usr/bin/env python
"""
LeRobot ACT HTTP 推論サーバー。
HTTP POST 経由で観測データ（画像 + 状態）を受け取り、
ACT ポリシーで推論を実行してアクションチャンクを返す。
"""

import argparse
import base64
import glob
import json
import logging
import os
import sys
import time
from datetime import datetime
from typing import Optional

import cv2
from fastapi import FastAPI, HTTPException
import numpy as np
from pydantic import BaseModel
import torch
import uvicorn

# LeRobot パス設定
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKSPACE_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
lerobot_candidates = [
    os.environ.get("LEROBOT_DIR"),
    os.path.join(WORKSPACE_ROOT, "third_party", "lerobot"),
]

for candidate in lerobot_candidates:
    if candidate:
        src_path = os.path.join(candidate, "src")
        if os.path.isdir(src_path):
            if src_path not in sys.path:
                sys.path.insert(0, src_path)
            break

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("LeRobotACTServer")


def _is_act_checkpoint(ckpt_dir: str) -> bool:
    cfg_path = os.path.join(ckpt_dir, "config.json")
    model_path = os.path.join(ckpt_dir, "model.safetensors")
    if not (os.path.exists(cfg_path) and os.path.exists(model_path)):
        return False
    with open(cfg_path, encoding="utf-8") as f:
        return json.load(f).get("type") == "act"


def get_default_checkpoint() -> Optional[str]:
    """outputs/train 配下の最新 ACT pretrained_model を探索する"""
    train_dirs = [
        os.path.join(SCRIPT_DIR, "outputs", "train"),
        os.path.join(WORKSPACE_ROOT, "training", "VLA-Learning", "outputs", "train"),
    ]
    ckpts = []
    for train_dir in train_dirs:
        if os.path.exists(train_dir):
            ckpts.extend(
                p for p in glob.glob(os.path.join(train_dir, "**", "pretrained_model"), recursive=True)
                if _is_act_checkpoint(p)
            )
    return max(ckpts, key=os.path.getmtime) if ckpts else None


def decode_image_bytes(raw_bytes: bytes) -> np.ndarray:
    """画像バイト列を RGB の NumPy 配列 (H, W, 3) に変換する"""
    arr = np.frombuffer(raw_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"Failed to decode image ({len(raw_bytes)} bytes)")
    return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


class ACTInferenceEngine:
    """ACT ポリシーのロードと推論実行"""

    def __init__(self, checkpoint_path: str, device: str = "auto", default_chunk_size: int = 30):
        if device == "auto":
            self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        else:
            self.device = torch.device(device)

        self.checkpoint_path = checkpoint_path
        self.default_chunk_size = default_chunk_size

        if not self.checkpoint_path or not os.path.exists(self.checkpoint_path):
            raise FileNotFoundError(f"ACT checkpoint not found at '{self.checkpoint_path}'")

        from lerobot.policies.act.modeling_act import ACTPolicy
        from lerobot.policies.factory import make_pre_post_processors

        logger.info(f"Loading ACT policy from: {self.checkpoint_path} on {self.device}")
        self.policy = ACTPolicy.from_pretrained(self.checkpoint_path)
        self.policy.to(self.device)
        self.policy.eval()

        self.preprocessor, self.postprocessor = make_pre_post_processors(
            policy_cfg=self.policy.config,
            pretrained_path=self.checkpoint_path,
        )
        self.image_keys = list(self.policy.config.image_features.keys())
        self.use_robot_state = self.policy.config.robot_state_feature is not None
        logger.info(
            f"ACT policy loaded successfully (images={self.image_keys}, use_state={self.use_robot_state}, "
            f"chunk_size={self.policy.config.chunk_size})."
        )

    def predict(self, image_rgb: np.ndarray, state: list[float], task: str = "", chunk_size: int = 30) -> list[list[float]]:
        target_size = chunk_size or self.default_chunk_size

        image_tensor = torch.from_numpy(image_rgb).permute(2, 0, 1).float() / 255.0
        batch = {key: image_tensor for key in self.image_keys}
        if self.use_robot_state:
            batch["observation.state"] = torch.tensor(state, dtype=torch.float32)

        processed_batch = self.preprocessor(batch)
        with torch.no_grad():
            action_chunk = self.policy.predict_action_chunk(processed_batch)
            unnormalized = self.postprocessor(action_chunk)

        actions = unnormalized[0].cpu().numpy().tolist()
        return actions[:target_size]


class PredictRequest(BaseModel):
    image: str
    state: list[float] = [0.0, 0.0]
    task: str = "Go to the red star"
    mode: str = "production"
    source_desc: str = "Live Camera"
    create_steps: Optional[int] = None
    exec_steps: Optional[int] = None


def create_app(engine: ACTInferenceEngine, default_task: str, create_steps: int, exec_steps: int) -> FastAPI:
    app = FastAPI(title="LeRobot ACT HTTP Inference Server")

    log_dir = os.path.join(SCRIPT_DIR, "outputs", "chunk_logs")
    os.makedirs(log_dir, exist_ok=True)
    chunk_log_file = os.path.join(log_dir, f"act_chunk_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.jsonl")
    logger.info(f"Chunk Log File: {chunk_log_file}")

    infer_count = 0

    @app.get("/health")
    def health():
        return {"status": "ok", "policy": "act"}

    @app.post("/predict")
    def predict(req: PredictRequest):
        nonlocal infer_count
        try:
            raw_bytes = base64.b64decode(req.image)
            image_rgb = decode_image_bytes(raw_bytes)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid image: {e}")

        infer_count += 1
        t0 = time.perf_counter()

        create_n = req.create_steps or create_steps
        exec_n = req.exec_steps or exec_steps

        if create_n <= 0:
            raise HTTPException(status_code=422, detail="create_steps must be greater than 0")
        if exec_n <= 0:
            raise HTTPException(status_code=422, detail="exec_steps must be greater than 0")
        if exec_n > create_n:
            raise HTTPException(status_code=422, detail=f"exec_steps({exec_n}) > create_steps({create_n})")

        task = req.task or default_task
        created_chunk = engine.predict(image_rgb, req.state, task, create_n)
        latency_ms = (time.perf_counter() - t0) * 1000.0

        exec_chunk = created_chunk[:exec_n]
        created_len = len(created_chunk)
        exec_len = len(exec_chunk)
        avg_left = sum(a[0] for a in exec_chunk) / exec_len if exec_len else 0.0
        avg_right = sum(a[1] for a in exec_chunk) / exec_len if exec_len else 0.0

        log_entry = {
            "timestamp": time.time(),
            "datetime": datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
            "infer_count": infer_count,
            "policy": "act",
            "mode": req.mode,
            "source_desc": req.source_desc,
            "task": task,
            "image_shape": list(image_rgb.shape),
            "state": req.state,
            "latency_ms": round(latency_ms, 2),
            "created_chunk_size": created_len,
            "chunk_size": exec_len,
            "avg_left": round(avg_left, 3),
            "avg_right": round(avg_right, 3),
            "action_chunk": exec_chunk,
            "full_action_chunk": created_chunk,
        }
        try:
            with open(chunk_log_file, "a", encoding="utf-8") as f:
                f.write(json.dumps(log_entry, ensure_ascii=False) + "\n")
        except Exception as log_err:
            logger.warning(f"Failed to write chunk log: {log_err}")

        logger.info(
            f"[ACT推論 #{infer_count}] 遅延: {latency_ms:.1f}ms | "
            f"作成: {created_len}st -> 採用: {exec_len}st | "
            f"先頭: L={exec_chunk[0][0]:+.2f}, R={exec_chunk[0][1]:+.2f}"
        )

        return {
            "type": "action_chunk",
            "policy": "act",
            "task": task,
            "action_chunk": exec_chunk,
            "full_action_chunk": created_chunk,
            "inference_latency_ms": round(latency_ms, 2),
        }

    return app


def main():
    parser = argparse.ArgumentParser(description="LeRobot ACT HTTP Inference Server")
    parser.add_argument("--checkpoint", type=str, default=get_default_checkpoint(), help="ACT checkpoint path")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Listen address")
    parser.add_argument("--port", type=int, default=8080, help="Listen port")
    parser.add_argument("--device", type=str, default="auto", help="Device (auto, cuda, cpu)")
    parser.add_argument("--task", type=str, default="Go to the red star", help="Task prompt (logged only)")
    parser.add_argument("--create-steps", "--chunk-size", type=int, default=10, help="Steps generated per chunk")
    parser.add_argument("--exec-steps", type=int, default=10, help="Steps executed per chunk")
    parser.add_argument(
        "--timeout-keep-alive",
        "--keep-alive-timeout",
        type=int,
        default=65,
        help="Keep-Alive timeout in seconds (default: 65)",
    )
    args = parser.parse_args()

    engine = ACTInferenceEngine(args.checkpoint, device=args.device, default_chunk_size=args.create_steps)
    app = create_app(engine, default_task=args.task, create_steps=args.create_steps, exec_steps=args.exec_steps)

    logger.info(f"Starting ACT HTTP server on http://{args.host}:{args.port}")
    logger.info(f"Model: {engine.checkpoint_path} ({engine.device})")
    logger.info(f"Planning: {args.create_steps} steps created -> {args.exec_steps} steps executed")
    logger.info(f"Keep-Alive: enabled (timeout={args.timeout_keep_alive}s)")

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        log_level="info",
        timeout_keep_alive=args.timeout_keep_alive,
        headers=[
            ("connection", "keep-alive"),
            ("keep-alive", f"timeout={args.timeout_keep_alive}"),
        ],
    )


if __name__ == "__main__":
    main()
