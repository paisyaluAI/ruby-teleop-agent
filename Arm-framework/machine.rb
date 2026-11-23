# frozen_string_literal: true

IS_PRODUCTION = ENV['PRODUCTION'] == '1' || ARGV.include?('--production')

local_lib = File.expand_path('../../../libraries/Lerobot-Dataset-Ruby/lib', __dir__)
$LOAD_PATH.unshift(local_lib) if File.directory?(local_lib) && !$LOAD_PATH.include?(local_lib)

require 'lerobot-dataset-ruby'
require_relative 'controller'

# ==============================================================================
# SO-101 / 多関節ロボットアーム テレオペレーション・データ収集 & 自律推論 / リプレイ
# - 通常実行 (テレオペ & データ収集): ruby machine.rb [--dof N]
# - VLA 自律推論実行               : ruby machine.rb --vla [--dof N]
# - 記録データのリプレイ再生       : ruby machine.rb --play <DATASET_PATH> [EPISODE_INDEX]
# ==============================================================================

def parse_dof_option
  if (idx = ARGV.index('--dof')) && ARGV[idx + 1]
    Integer(ARGV[idx + 1])
  elsif ENV['DOF'] && !ENV['DOF'].strip.empty?
    Integer(ENV['DOF'])
  end
end

def parse_motors_option
  return nil unless ENV['MOTOR_NAMES'] && !ENV['MOTOR_NAMES'].strip.empty?

  ENV['MOTOR_NAMES'].split(',').map(&:strip).reject(&:empty?)
end

TARGET_FPS = (ENV['TARGET_FPS'] || 10).to_i
prompt = ENV['PROMPT'] || 'Grab the cube'
follower_port = ENV.fetch('FOLLOWER_PORT', '/dev/ttyACM1')
leader_port = ENV.fetch('LEADER_PORT', '/dev/ttyACM0')
configured_dof = parse_dof_option
configured_motors = parse_motors_option

# Mock用動画の準備 (machine-framework の dummy_video.mp4 を共有利用)
def setup_mock_video(path)
  return path if File.exist?(path)

  puts "[Mock] テスト動画が見つからないため、真っ暗なダミー動画を自動生成します: #{path}"
  require 'fileutils'
  require 'shellwords'
  FileUtils.mkdir_p(File.dirname(path))
  system("ffmpeg -f lavfi -i color=c=black:s=640x480:r=10 -t 60 -c:v libx264 -pix_fmt yuv420p #{path.shellescape} -y -loglevel error")
  path
end

def open_camera_or_mock_video
  if IS_PRODUCTION
    begin
      Libopencv.cam_open(0, 640, 480)
    rescue ArgumentError
      Libopencv.cam_open(0)
    end
  else
    shared_dummy = File.expand_path('../machine-framework/test/dummy_video.mp4', __dir__)
    mock_video_path = ENV['MOCK_VIDEO_PATH'] || shared_dummy
    setup_mock_video(mock_video_path)
    Libopencv.open_mp4(mock_video_path)
  end
end

def capture_frame_bytes
  Libopencv.take_picture
rescue RuntimeError
  Libopencv.set_frame_pos(0) rescue nil
  Libopencv.take_picture rescue nil
end

def format_joints(values, names)
  names.each_with_index.map do |name, i|
    "#{name}:#{values.fetch(i, 0.0).to_f.round(1)}"
  end.join(', ')
end

# ------------------------------------------------------------------------------
# モード1: エピソードリプレイ再生 (--play <DATASET_PATH> [EPISODE_INDEX])
# ------------------------------------------------------------------------------
if ARGV.first == '--play'
  dataset_dir = ARGV[1] || ENV['DATASET_PATH']
  episode_idx = Integer(ARGV[2] || ENV.fetch('EPISODE_INDEX', '0'))
  if dataset_dir.nil?
    warn '使い方: ruby machine.rb --play DATASET_PATH [EPISODE_INDEX]'
    exit 1
  end

  reader = Lerobot::Dataset::Ruby::Reader.new(dataset_dir)
  fps = (reader.info['fps'] || TARGET_FPS).to_f
  dataset_dof = reader.info.dig('features', 'action', 'shape', 0) || configured_dof
  dataset_names = reader.info.dig('features', 'action', 'names') || configured_motors
  arm = SO101::Follower.new(
    port: follower_port,
    mock: !IS_PRODUCTION,
    dof: dataset_dof,
    motors: dataset_names
  )

  begin
    ep = reader.episode(episode_idx)
    puts "アーム エピソード #{episode_idx} を再生します (#{ep[:length]} フレーム, #{arm.dof}軸)"
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    ep[:frames].each_with_index do |frame, idx|
      deadline = started_at + (idx / fps)
      sleep_time = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep(sleep_time) if sleep_time.positive?

      action = Array(frame.fetch(:action)).map(&:to_f)
      arm.send_action(action)
      puts "フレーム #{idx}: [#{format_joints(action, arm.motor_names)}]" if (idx % 10).zero?
    end
  ensure
    arm&.termination
  end
  puts '再生終了'
  exit 0
end

# ------------------------------------------------------------------------------
# モード2: VLA 非同期推論による自律制御 (--vla または VLA=1)
# ------------------------------------------------------------------------------
if ARGV.include?('--vla') || ENV['VLA'] == '1'
  require_relative '../machine-framework/lerobot_client_wrapper'

  server_url = ENV['INFERENCE_SERVER_URL'] || 'http://127.0.0.1:8080'
  async_prefetch = ARGV.include?('--async') || ENV['ASYNC_PREFETCH'] == '1'
  create_steps = (ENV['CREATE_STEPS'] || (async_prefetch ? 30 : 10)).to_i
  exec_steps = (ENV['EXEC_STEPS'] || create_steps).to_i
  prefetch_threshold = (ENV['PREFETCH_THRESHOLD'] || 15).to_i

  arm = SO101::Follower.new(
    port: follower_port,
    mock: !IS_PRODUCTION,
    dof: configured_dof,
    motors: configured_motors
  )

  puts '=================================================='
  puts "  LeRobot (SmolVLA) #{arm.dof}軸アーム 自律推論システム"
  puts "  モード: #{IS_PRODUCTION ? '本番実機' : 'Mock'}"
  puts "  タスク: #{prompt}"
  puts "  推論サーバー: #{server_url}"
  puts "  推論方式: #{async_prefetch ? "非同期先読み (残り#{prefetch_threshold}で次を要求)" : '逐次 (残り1で次を要求)'}"
  puts '=================================================='

  vla_client = LeRobot::VLAAsyncClient.new(
    server_url: server_url,
    prompt: prompt,
    exec_steps: exec_steps,
    create_steps: create_steps,
    async_prefetch: async_prefetch,
    prefetch_threshold: prefetch_threshold
  )

  open_camera_or_mock_video

  unless vla_client.connect
    warn "推論サーバー (#{server_url}) に接続できませんでした。"
    arm.termination
    exit 1
  end

  running = true
  trap('INT') { running = false }

  begin
    step = 0
    frame_interval = 1.0 / TARGET_FPS
    next_frame_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    while running
      image_bytes = capture_frame_bytes
      current_state = arm.get_state
      action = vla_client.next_action(image_bytes, current_state, prompt)

      if action
        arm.send_action(action)
        if (step % TARGET_FPS).zero?
          puts "[Step #{step}] #{format_joints(action, arm.motor_names)} (キュー残: #{vla_client.queue_size})"
        end
      end

      step += 1
      next_frame_time += frame_interval
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      remaining = next_frame_time - now
      if remaining.positive?
        sleep(remaining)
      elsif (now - next_frame_time) > frame_interval
        next_frame_time = now
      end
    end
  ensure
    arm&.termination
    vla_client&.stop
    Libopencv.destroy_window
    puts 'アーム自律推論動作を安全に終了しました。'
  end
  exit 0
end

# ------------------------------------------------------------------------------
# モード3 (デフォルト): Leader-Follower テレオペレーション & データセット収集
# ------------------------------------------------------------------------------
dataset_path = if IS_PRODUCTION
                 "output_dataset/#{Time.now.strftime('%Y%m%d_%H%M')}"
               else
                 "output_dataset/mock_#{Time.now.strftime('%Y%m%d_%H%M')}"
               end

controller = Controller.new(
  mock: !IS_PRODUCTION,
  leader_port: leader_port,
  dof: configured_dof,
  motors: configured_motors
)

arm = SO101::Follower.new(
  port: follower_port,
  mock: !IS_PRODUCTION,
  dof: controller.dof,
  motors: controller.joint_names
)

feature_names = controller.joint_names.map { |n| "#{n}.pos" }
writer = Lerobot::Dataset::Ruby::Writer.new(
  output_dir: dataset_path,
  fps: TARGET_FPS,
  action_names: feature_names,
  state_names: feature_names
)

puts '=================================================='
puts "  SO-101 / 多関節アーム (#{controller.dof}軸) テレオペレーション & データ収集"
puts "  モード: #{IS_PRODUCTION ? '本番実機 (Leader-Follower)' : 'Mock'}"
puts "  タスク: #{prompt}"
puts "  出力先: #{dataset_path}"
puts '=================================================='

open_camera_or_mock_video
writer.start_recording

number = 0

begin
  loop do
    puts "\n待機中... [S]キーでエピソード記録開始 / [Q]キーでセッション終了"

    loop do
      controller.poll
      break if controller.process_finish
      break if controller.process_start

      action = controller.get_action
      arm.send_action(action)
      sleep(0.03)
    end

    break if controller.process_finish

    begin
      puts ">>> エピソード #{number} 記録開始 ([Enter]: 保存して停止 / [D]: 破棄して停止)"
      writer.start_episode(task: prompt)
      episode_frame_idx = 0
      frame_interval = 1.0 / TARGET_FPS
      next_frame_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      loop do
        controller.poll

        state = arm.get_state
        action = controller.get_action
        arm.send_action(action)

        image_bytes = capture_frame_bytes
        if image_bytes
          writer.add_frame(
            action: action,
            state: state,
            image_bytes: image_bytes
          )
          if (episode_frame_idx % 30).zero?
            puts "フレーム #{episode_frame_idx} 保存 (#{format_joints(action, arm.motor_names)})"
          end
        else
          puts "フレーム #{episode_frame_idx} の画像取得に失敗"
        end

        episode_frame_idx += 1

        if controller.process_stop
          writer.save_episode(save: true)
          puts "<<< エピソード #{number} を保存しました (#{episode_frame_idx} フレーム)"
          number += 1
          break
        end

        if controller.process_discard
          writer.save_episode(save: false)
          puts "<<< エピソード #{number} を破棄しました"
          break
        end

        if controller.process_finish
          writer.save_episode(save: true)
          puts "<<< エピソード #{number} を保存して終了します (#{episode_frame_idx} フレーム)"
          number += 1
          break
        end

        next_frame_time += frame_interval
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        remaining_time = next_frame_time - now

        if remaining_time.positive?
          sleep(remaining_time)
        elsif (now - next_frame_time) > frame_interval
          puts 'フレーム落ちが発生しました。目標FPSを維持できませんでした。'
          next_frame_time = now
        end
      end

      break if controller.process_finish
    ensure
      arm.stop
    end
  end
rescue Interrupt
  puts "\n割り込みを受信しました。保存して終了します..."
ensure
  if writer
    writer.stop_recording
    writer.save
  end
  controller&.termination
  arm&.termination
  Libopencv.destroy_window
  puts '終了'
end
