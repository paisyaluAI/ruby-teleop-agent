require_relative "../ext/gpio/libgpiod_ext.so"

CHIP_PATH = '/dev/gpiochip0'
pins = {
  "左タイヤ前進 (GPIO 12)" => 12,
  "左タイヤ後退 (GPIO 16)" => 16,
  "右タイヤ前進 (GPIO 20)" => 20,
  "右タイヤ後退 (GPIO 21)" => 21
}

puts "=== モーター駆動 GPIO ピン テスト ==="
puts "左右の各モーターを1秒ずつ順番に回転させます。"

pins.each do |name, pin_num|
  puts "\n--> #{name} を ON にします..."
  gpio = GPIOD::Pin.new(CHIP_PATH, pin_num)
  gpio.on
  sleep(1.0)
  gpio.off
  puts "    #{name} を OFF にしました。"
  sleep(0.5)
end

puts "\n全ピントグル完了。"

