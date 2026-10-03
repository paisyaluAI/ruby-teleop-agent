require 'sdl2'
# # 動く
# SDL2.init(SDL2::INIT_JOYSTICK|SDL2::INIT_EVENTS)
# sdljoy = SDL2::Joystick
# js = sdljoy.open(0)
# SDL2::Event.poll
# p js.name
# p js.axis(0)
# p js.axis(1)
# p js.axis(2)
# p js.axis(3)

# js.close

SDL2.init(SDL2::INIT_JOYSTICK|SDL2::INIT_GAMECONTROLLER|SDL2::INIT_EVENTS)
sdljoy = SDL2::Joystick
js = sdljoy.open(0)
guid = js.GUID()
p guid
gc = SDL2::GameController.open(0)
loop do
  p gc.axis(SDL2::GameController::Axis::LEFTX)
  p gc.axis(SDL2::GameController::Axis::LEFTY)
  p gc.axis(SDL2::GameController::Axis::RIGHTX)
  p gc.axis(SDL2::GameController::Axis::RIGHTY)
  sleep 1
end