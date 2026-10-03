# 本番用class
require_relative "ext/gpio/libgpiod_ext.so"

class Tire
    def initialize()
        @chip_path = '/dev/gpiochip0'
        @left_tire_forward_pin = 12
        @left_tire_back_pin = 16
        @right_tire_forward_pin = 20
        @right_tire_back_pin = 21

        @left_tire_forward = GPIOD::Pin.new(@chip_path, @left_tire_forward_pin)
        @left_tire_back = GPIOD::Pin.new(@chip_path, @left_tire_back_pin)
        @right_tire_forward = GPIOD::Pin.new(@chip_path, @right_tire_forward_pin)
        @right_tire_back = GPIOD::Pin.new(@chip_path, @right_tire_back_pin)
    end

    DEADZONE = 0.05

    def left_tire(value)
        val = value.to_f
        if val > DEADZONE
            @left_tire_forward.on
            @left_tire_back.off
        elsif val < -DEADZONE
            @left_tire_forward.off
            @left_tire_back.on
        else
            left_stop
        end
    end

    def right_tire(value)
        val = value.to_f
        if val > DEADZONE
            @right_tire_forward.on
            @right_tire_back.off
        elsif val < -DEADZONE
            @right_tire_forward.off
            @right_tire_back.on
        else
            right_stop
        end
    end

    def stop
        left_stop
        right_stop
    end

    def left_stop
        @left_tire_forward.off
        @left_tire_back.off
    end

    def right_stop
        @right_tire_forward.off
        @right_tire_back.off
    end

    def termination
        stop
        @left_tire_forward.off
        @left_tire_back.off
        @right_tire_forward.off
        @right_tire_back.off
    end
end