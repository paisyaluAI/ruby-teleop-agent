class Controller
    def initialize()
        SDL2.init(SDL2::INIT_JOYSTICK|SDL2::INIT_GAMECONTROLLER|SDL2::INIT_EVENTS)
        num_joysticks = SDL2::Joystick.num_connected_joysticks
        puts "接続されているコントローラー数: #{num_joysticks}"
        if num_joysticks > 0
            @gc = SDL2::GameController.open(0)
            puts "ゲームコントローラーを認識しました: #{@gc.name}"
        else
            warn "警告: ゲームコントローラーが接続されていません"
            @gc = nil
        end
        @deadzone_p = 5000 #スティックの反応しない領域
        @deadzone_n = -5000
    end
    
    def get_left_axis
        return 0.0 unless @gc
        left_y = @gc.axis(SDL2::GameController::Axis::LEFTY)
        if left_y.positive?
            if left_y < @deadzone_p
                left_y = 0
            end
        elsif left_y.negative?
            if left_y > @deadzone_n
                left_y = 0
            end
        else
            left_y = 0
        end

        # スティックを前に倒す(SDL2では負値)と前進(+1.0)、後ろに倒すと後退(-1.0)になるよう符号反転
        left_y_norm = (-left_y / 32767.0).clamp(-1.0, 1.0)

        return left_y_norm
    end

    def get_right_axis
        return 0.0 unless @gc
        right_y = @gc.axis(SDL2::GameController::Axis::RIGHTY)
        if right_y.positive?
            if right_y < @deadzone_p
                right_y = 0
            end
        elsif right_y.negative?
            if right_y > @deadzone_n
                right_y = 0
            end
        else
            right_y = 0
        end
        
        # スティックを前に倒す(SDL2では負値)と前進(+1.0)、後ろに倒すと後退(-1.0)になるよう符号反転
        right_y_norm = (-right_y / 32767.0).clamp(-1.0, 1.0)
        return right_y_norm
    end

    def process_start
        return false unless @gc
        @gc.button_pressed?(SDL2::GameController::Button::START)
    end

    def process_stop
        return false unless @gc
        @gc.button_pressed?(SDL2::GameController::Button::BACK)
    end

    def process_finish
        return false unless @gc
        @gc.button_pressed?(SDL2::GameController::Button::GUIDE)
    end

    def process_discard
        return false unless @gc
        @gc.button_pressed?(SDL2::GameController::Button::DPAD_DOWN)
    end

    def poll
        while ev = SDL2::Event.poll
            case ev
            when SDL2::Event::Quit
                exit
            end
        end
    end
end
