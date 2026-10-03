class Controller
    def initialize()
        SDL2.init(SDL2::INIT_EVENTS)
        @start_pressed = false
        @stop_pressed = false
        @finish_pressed = false
        @discard_pressed = false
    end

    def get_left_axis
        return @left
    end

    def get_right_axis
        return @right
    end

    def poll
        @left = 0.0
        @right = 0.0
        @start_pressed = false
        @stop_pressed = false
        @finish_pressed = false
        @discard_pressed = false

        while ev = SDL2::Event.poll
            case ev
            when SDL2::Event::Quit
                exit
            when SDL2::Event::KeyDown
                if ev.sym == SDL2::Key::W
                    @left = 1.0
                end
                if ev.sym == SDL2::Key::S
                    @left = -1.0
                end
                if ev.sym == SDL2::Key::UP
                    @right = 1.0
                end
                if ev.sym == SDL2::Key::DOWN
                    @right = -1.0
                end
                if ev.sym == SDL2::Key::T
                    @start_pressed = true
                elsif ev.sym == SDL2::Key::F
                    @stop_pressed = true
                elsif ev.sym == SDL2::Key::E
                    @finish_pressed = true
                elsif ev.sym == SDL2::Key::G
                    @discard_pressed = true
                end
            end
        end
    end

    def process_start
        @start_pressed
    end

    def process_stop
        @stop_pressed
    end

    def process_finish
        @finish_pressed
    end

    def process_discard
        @discard_pressed
    end
end