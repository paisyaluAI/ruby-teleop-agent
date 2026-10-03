IS_PRODUCTION = ENV['PRODUCTION'] == '1' || ARGV.include?('--production')

if IS_PRODUCTION
  require_relative 'tire'
else
  require_relative 'tire_mock'
end

require 'sdl2'
require 'lerobot-dataset-ruby'
require_relative 'lerobot_client_wrapper'

prompt = ENV['PROMPT'] || 'Go to the blue star'
server_url = ENV['INFERENCE_SERVER_URL'] || ENV['ADRESS'] || 'http://127.0.0.1:8080'

puts "=================================================="
puts "  LeRobot (SmolVLA) 4WD 自律推論走行システム"
puts "  モード: #{IS_PRODUCTION ? '本番実機' : 'Mock'}"
puts "  タスク: #{prompt}"
puts "  推論サーバー: #{server_url}"
puts "=================================================="

machine = Tire.new
create_steps = (ENV['CREATE_STEPS'] || 10).to_i
exec_steps = (ENV['EXEC_STEPS'] || create_steps).to_i
vla_client = LeRobot::VLAAsyncClient.new(server_url: server_url, prompt: prompt, exec_steps: exec_steps, create_steps: create_steps)

TARGET_FPS = 10
frame_interval = 1.0 / TARGET_FPS

# Mock用動画の準備（動画ファイルがない場合でも、真っ黒なダミー動画を自動生成してあるように見せる）
def setup_mock_video(path)
  return path if File.exist?(path)

  puts "[Mock] テスト動画が見つからないため、真っ暗なダミー動画を自動生成します: #{path}"
  require 'fileutils'
  require 'shellwords'
  FileUtils.mkdir_p(File.dirname(path))
  system("ffmpeg -f lavfi -i color=c=black:s=640x480:r=10 -t 60 -c:v libx264 -pix_fmt yuv420p #{path.shellescape} -y -loglevel error")
  path
end

# カメラ初期化 (本番: 実カメラ / Mock: テスト動画または真っ暗なダミー動画)
if IS_PRODUCTION
  Libopencv.cam_open(0, 640, 480)
else
  mock_video_path = ENV['MOCK_VIDEO_PATH'] || File.expand_path('test/dummy_video.mp4', __dir__)
  setup_mock_video(mock_video_path)
  Libopencv.open_mp4(mock_video_path)
end

# 推論サーバー接続
unless vla_client.connect
  warn "推論サーバー (#{server_url}) に接続できませんでした。"
  exit 1
end

running = true
trap('INT') do
  puts "\n停止シグナルを受信しました。"
  running = false
end

puts "走行待機中... 自律推論を開始します (Ctrl+C でも終了可)。"

begin
  puts "自律走行開始"
  step = 0
  current_left = 0.0
  current_right = 0.0
  next_frame_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  while running
    # 1. 画像取得 (動画終端時は自動で先頭に巻き戻してループ取得)
    image_bytes = begin
      Libopencv.take_picture
    rescue RuntimeError
      Libopencv.set_frame_pos(0) rescue nil
      Libopencv.take_picture rescue nil
    end

    # 2. VLA 推論アクション取得 (ノンブロッキング)
    action = vla_client.next_action(image_bytes, [current_left, current_right], prompt)

    if action
      current_left = action[0].to_f.clamp(-1.0, 1.0)
      current_right = action[1].to_f.clamp(-1.0, 1.0)

      # モデルの意図した出力をそのままタイヤへ反映 (学習データと完全一致)
      machine.left_tire(current_left)
      machine.right_tire(current_right)

      if step % TARGET_FPS == 0
        puts "[Step #{step}] L:#{current_left.round(2)}, R:#{current_right.round(2)} (キュー残: #{vla_client.queue_size})"
      end
    else
      # キュー枯渇時は安全一時停止
      current_left = 0.0
      current_right = 0.0
      machine.left_tire(0)
      machine.right_tire(0)
    end

    step += 1

    # 目標FPS (10Hz) 維持
    next_frame_time += frame_interval
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sleep_time = next_frame_time - now

    if sleep_time > 0
      SDL2.delay((sleep_time * 1000).to_i)
    elsif (now - next_frame_time) > frame_interval
      next_frame_time = now
    end
  end
ensure
  # 終了時の安全停止処理 (machine.rb と共通)
  machine.left_tire(0)
  machine.right_tire(0)
  machine.termination
  vla_client.stop
  Libopencv.destroy_window
  puts "自律走行を安全に終了しました。"
end
