function love.conf(t)
    t.window.title = "JustParkour"
    t.window.width = 800
    t.window.height = 450
    t.window.resizable = false
    t.window.vsync = 1
    t.console = false

    -- Disable modules we don't use
    t.modules.physics = false
    t.modules.video = false
    t.modules.touch = false
    t.modules.joystick = false
end
