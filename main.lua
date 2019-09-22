
function love.run()
  require "lang"; transform()

  if love.timer then love.timer.step() end

  dt, frame, time = 0, 0, 0
  local _, _, flags = love.window.getMode()
  local refresh_rate = flags.refreshrate
  local fixed_dt = 1/refresh_rate
  local accumulator = fixed_dt

  -- init()
  return function()
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        -- handle_events()
      end
    end

    if love.timer then dt = love.timer.step() end
    accumulator = accumulator + dt
    while accumulator >= fixed_dt do
      -- update(fixed_dt)
    end

    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      -- draw()
      love.graphics.present()
    end

    if love.timer then love.timer.sleep(0.001) end
  end
end
