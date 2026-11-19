#!/usr/bin/env ruby
# コントローラーで直接モーターを駆動する診断テストツール
require 'sdl2'
require_relative '../controller'
require_relative '../tire'

puts "=========================================================="
puts "  コントローラー ＆ 実機モーター 直接連動テスト"
puts "=========================================================="
puts "カメラやデータ保存を行わず、コントローラーの入力とモーター駆動を直結してテストします。"
puts ""

begin
  tire = Tire.new
  puts "[OK] Tire (GPIO) 初期化完了"
rescue => e
  puts "[ERROR] Tire 初期化失敗: #{e.message}"
  exit 1
end

begin
  controller = Controller.new
  puts "[OK] Controller 初期化完了"
rescue => e
  puts "[ERROR] Controller 初期化失敗: #{e.message}"
  tire.termination rescue nil
  exit 1
end

puts ""
puts "操作方法:"
puts "  ・左スティック前後: 左タイヤ (前進/後退)"
puts "  ・右スティック前後: 右タイヤ (前進/後退)"
puts "  ・Ctrl + C: テスト終了"
puts "----------------------------------------------------------"

begin
  loop do
    controller.poll
    left = controller.get_left_axis
    right = controller.get_right_axis

    tire.left_tire(left)
    tire.right_tire(right)

    left_status = if left > 0.05
                    "前進(GPIO12 ON)"
                  elsif left < -0.05
                    "後退(GPIO16 ON)"
                  else
                    "停止(OFF)"
                  end

    right_status = if right > 0.05
                     "前進(GPIO20 ON)"
                   elsif right < -0.05
                     "後退(GPIO21 ON)"
                   else
                     "停止(OFF)"
                   end

    print "\r[左スティック: %+.2f => %-16s] [右スティック: %+.2f => %-16s]  " % [
      left, left_status, right, right_status
    ]
    $stdout.flush

    sleep 0.05
  end
ensure
  puts "\n\n安全停止中..."
  tire.stop
  tire.termination
  puts "テスト終了"
end
