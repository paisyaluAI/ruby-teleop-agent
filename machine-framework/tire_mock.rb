# Mock用Class
class Tire
    DEADZONE = 0.05

    def initialize()
        puts "Mock 起動"
    end

    def left_tire(value)
        val = value.to_f
        state_str = if val > DEADZONE
                      "前進 (#{format('%+.2f', val)})"
                    elsif val < -DEADZONE
                      "後退 (#{format('%+.2f', val)})"
                    else
                      "停止 (0.00)"
                    end
        puts "Mock 左タイヤ制御: #{format('%+.2f', val)} [#{state_str}]"
    end

    def right_tire(value)
        val = value.to_f
        state_str = if val > DEADZONE
                      "前進 (#{format('%+.2f', val)})"
                    elsif val < -DEADZONE
                      "後退 (#{format('%+.2f', val)})"
                    else
                      "停止 (0.00)"
                    end
        puts "Mock 右タイヤ制御: #{format('%+.2f', val)} [#{state_str}]"
    end

    def stop
        puts "Mock 停止"
    end

    def left_stop
        puts "Mock 左タイヤ停止"
    end

    def right_stop
        puts "Mock 右タイヤ停止"
    end

    def termination
        self.stop
        puts "Mock 終了"
    end
end