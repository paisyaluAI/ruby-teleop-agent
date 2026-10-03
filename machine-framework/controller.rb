class Controller
    def initialize()
        SDL2.init(SDL2::INIT_JOYSTICK|SDL2::INIT_GAMECONTROLLER|SDL2::INIT_EVENTS)
        puts SDL2::Joystick.num_connected_joysticks
        @gc = SDL2::GameController.open(0)
        @deadzone_p = 5000 #スティックの反応しない領域
        @deadzone_n = -5000
    end
    
    def get_left_axis
        left_y = @gc.axis(SDL2::GameController::Axis::LEFTY)
        if left_y.positive? then
            if left_y < @deadzone_p then
                left_y = 0
            end
        elsif left_y.negative? then
            if left_y > @deadzone_n then
                left_y = 0
            end
        elsif left_y.zero? then
            left_y = 0
        end


        left_y_norm = (left_y / 32767.0).clamp(-1.0, 1.0)

        return left_y_norm
    end

    def get_right_axis
        right_y = @gc.axis(SDL2::GameController::Axis::RIGHTY)
        if right_y.positive? then
            if right_y < @deadzone_p then
                right_y = 0
            end
        elsif right_y.negative? then
            if right_y > @deadzone_n then
                right_y = 0
            end
        elsif right_y.zero? then
            right_y = 0
        end
        
        right_y_norm = (right_y / 32767.0).clamp(-1.0, 1.0)
        return right_y_norm
    end

    def process_start
        @gc.button_pressed?(SDL2::GameController::Button::START)
    end

    def process_stop
        @gc.button_pressed?(SDL2::GameController::Button::BACK)
    end

    def process_finish
        @gc.button_pressed?(SDL2::GameController::Button::GUIDE)
    end

    def process_discard
        @gc.button_pressed?(SDL2::GameController::Button::DPAD_DOWN)
    end

    def poll
        while ev = SDL2::Event.poll
            case ev
            when SDL2::Event::Quit
            exit
            end
        end
        # pollが呼ばれるたびにボタンの状態をチェックして更新する
        process_start
        process_stop
        process_discard
    end
end
