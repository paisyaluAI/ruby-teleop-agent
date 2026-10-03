IS_PRODUCTION = ENV['PRODUCTION'] == '1'

if IS_PRODUCTION
  require_relative 'tire'
  require_relative 'controller'
  judge = false
  dataset_path = "output_dataset/#{Time.now.strftime('%Y%m%d_%H%M')}"
else
  require_relative "tire_mock"
  require_relative "controller_mock"
  judge = true
  dataset_path = "output_dataset/mock_#{Time.now.strftime('%Y%m%d_%H%M')}"
end

require "sdl2"
require "lerobot-dataset-ruby"

# 片方のタイヤのピンを同時にオンにしないでください

# 環境変数 PROMPT でタスク名を指定する
prompt = ENV['PROMPT'] || 'Go to the blue star'
puts "タスク: #{prompt}"

machine = Tire.new
controller = Controller.new

number = 0

#Episode 作成
TARGET_FPS = 10
writer = Lerobot::Dataset::Ruby::Writer.new(output_dir: dataset_path, fps: TARGET_FPS)


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

#Mockならmp4（または真っ暗なダミー動画）、実機ならカメラ
if IS_PRODUCTION
  begin
    Libopencv.cam_open(0, 640, 480)
  rescue ArgumentError
    Libopencv.cam_open(0)
  end
else
  mock_video_path = ENV['MOCK_VIDEO_PATH'] || File.expand_path('test/dummy_video.mp4', __dir__)
  setup_mock_video(mock_video_path)
  Libopencv.open_mp4(mock_video_path)
end
writer.start_recording

#完全終了まで止めない
begin
  loop do

  #controllerがstartのときになったら脱出
  loop do
    controller.poll
    #終了ボタンが押されたら完全終了
    break if controller.process_finish
    break if controller.process_start

    SDL2.delay(30) #待機
  end

  # 終了ボタンが押された場合はメインループを抜ける
  break if controller.process_finish

  begin
    p "入力受付開始"
    writer.start_episode(task: prompt)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    episode_index = 0
    frame_interval = 1.0 / TARGET_FPS
    next_frame_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    #コントローラーがstartの時だけ動く
    loop do
      #コントローラーの値を取得
      controller.poll
      left_value = controller.get_left_axis.to_f.clamp(-1.0, 1.0)
      right_value = controller.get_right_axis.to_f.clamp(-1.0, 1.0)
      
      puts "L:#{left_value.round(2)}, R:#{right_value.round(2)}" if episode_index % 30 == 0

      # 保存部分 (動画終端時は自動で先頭に巻き戻してループ取得)
      image_bytes = begin
        Libopencv.take_picture
      rescue RuntimeError
        Libopencv.set_frame_pos(0) rescue nil
        Libopencv.take_picture rescue nil
      end

      if image_bytes
        writer.add_frame(
          action: [left_value, right_value],
          state: [left_value, right_value],
          image_bytes: image_bytes,
          timestamp: Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        )
        puts "フレーム #{episode_index} を保存しました (L:#{left_value.round(2)}, R:#{right_value.round(2)})" if episode_index % 30 == 0
      else
        puts "フレーム #{episode_index} の取得に失敗"
      end
      
      episode_index += 1

      #コントローラーの値をタイヤに反映
      machine.left_tire(left_value)
      machine.right_tire(right_value)

      #キー確認
      if controller.process_stop
        writer.save_episode(save: true)
        break
      end
      if controller.process_discard
        writer.save_episode(save: false)
        break
      end

      
      # 待機時間の自動調整（目標FPSを維持）
      next_frame_time += frame_interval
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      remaining_time = next_frame_time - now

      if remaining_time > 0
        SDL2.delay((remaining_time * 1000).to_i)
      elsif (now - next_frame_time) > frame_interval
        puts "フレーム落ちが発生しました。目標FPSを維持できませんでした。"
        next_frame_time = now
      end
    end

  ensure
    # 一時停止時・終了時のタイヤ安全停止
    machine.left_tire(0)
    machine.right_tire(0)

    number += 1
    puts "#{number}回目の録画"
  end
  end
ensure
end

#プログラム全体の終了処理 
#エピソードの保存

if writer
  writer.stop_recording
  writer.save
end

machine&.termination
Libopencv.destroy_window
p "終了"