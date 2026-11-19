require 'sdl2'
require_relative '../controller'

puts "=== SDL2 コントローラー テストプログラム ==="
ctrl = Controller.new

puts "\nスティックやボタンを動かしてください (Ctrl+C で終了)"
puts "--------------------------------------------------------"

loop do
  ctrl.poll
  left = ctrl.get_left_axis
  right = ctrl.get_right_axis
  start = ctrl.process_start
  stop = ctrl.process_stop
  finish = ctrl.process_finish
  discard = ctrl.process_discard

  btn_status = []
  btn_status << "START" if start
  btn_status << "BACK/STOP" if stop
  btn_status << "GUIDE/FINISH" if finish
  btn_status << "DPAD_DOWN/DISCARD" if discard

  print "\r[L-Axis(前進+1/後退-1): %+.2f] [R-Axis(前進+1/後退-1): %+.2f] ボタン: [%s]          " % [
    left, right, btn_status.empty? ? "なし" : btn_status.join(", ")
  ]
  $stdout.flush
  sleep 0.05
end