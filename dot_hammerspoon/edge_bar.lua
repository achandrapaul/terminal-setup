local edgeBar = {}

local barHeight = 4
local statusColors = {
  waiting = { hex = "#EF4444" },
  working = { hex = "#3B82F6" },
  idle = { hex = "#22C55E" },
  none = { hex = "#FFFFFF" },
}

local barCanvases = {}
local shownStatus
local screenWatcher

local function buildCanvases()
  for _, canvas in ipairs(barCanvases) do canvas:delete() end
  barCanvases = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local screenFrame = screen:fullFrame()
    local canvas = hs.canvas.new({ x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = barHeight })
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior({ "canJoinAllSpaces", "stationary" })
    canvas:clickActivating(false)
    canvas:canvasMouseEvents(false)
    canvas[1] = { type = "rectangle", action = "fill", fillColor = statusColors.working }
    barCanvases[#barCanvases + 1] = canvas
  end
end

local function paint(status)
  local color = statusColors[status] or statusColors.none
  for _, canvas in ipairs(barCanvases) do
    canvas[1].fillColor = color
    canvas:show()
  end
end

function edgeBar.show(status)
  if status == shownStatus then return end
  shownStatus = status
  paint(status)
end

function edgeBar.start()
  buildCanvases()
  screenWatcher = hs.screen.watcher.new(function()
    buildCanvases()
    paint(shownStatus)
  end):start()
end

return edgeBar
