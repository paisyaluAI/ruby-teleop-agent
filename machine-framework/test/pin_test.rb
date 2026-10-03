require_relative "ext/gpio/libgpiod_ext.so"

# ピンを設定
# GPIOD::Pin.new(CHIP_PATH, PIN_NUM)
# gpioをオン
# .on
# gpioをオフ
# .off

CHIP_PATH = '/dev/gpiochip0'
PIN_NUM = 12

gpio = GPIOD::Pin.new(CHIP_PATH, PIN_NUM)
gpio.on
sleep(5)
p "5s"

gpio.off
p "off"

