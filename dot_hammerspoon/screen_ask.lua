local screenAsk = {}

local tmuxPath = "/opt/homebrew/bin/tmux"
local ghosttyBundleId = "com.mitchellh.ghostty"
local screenshotsDir = os.getenv("HOME") .. "/.claude/screenshots"
local claudeReadyTimeoutSeconds = 15

local function waitForClaudePrompt(paneId, onReady)
  local startedAt = os.time()
  local readinessTimer
  readinessTimer = hs.timer.doEvery(0.5, function()
    local paneText = hs.execute(tmuxPath .. " capture-pane -p -t " .. paneId) or ""
    if paneText:find("❯", 1, true) or paneText:find("? for shortcuts", 1, true) then
      readinessTimer:stop()
      onReady()
    elseif os.time() - startedAt > claudeReadyTimeoutSeconds then
      readinessTimer:stop()
      hs.alert.show("Claude didn't start in time; screenshot path is on the clipboard")
    end
  end)
end

function screenAsk.askAboutFocusedWindow()
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow then
    hs.alert.show("No focused window to capture")
    return
  end
  local windowImage = focusedWindow:snapshot()
  if not windowImage then
    hs.alert.show("Screenshot failed; check Screen Recording permission for Hammerspoon")
    return
  end

  hs.fs.mkdir(screenshotsDir)
  local screenshotPath = screenshotsDir .. "/" .. os.date("%Y%m%d-%H%M%S") .. ".png"
  windowImage:saveToFile(screenshotPath)
  hs.pasteboard.setContents(screenshotPath)

  local paneId, succeeded = hs.execute(tmuxPath .. " new-window -P -F '#{pane_id}' -n screen-ask -c " .. screenshotsDir .. " claude")
  paneId = succeeded and paneId and paneId:match("%%%d+")
  if not paneId then
    hs.alert.show("Couldn't open a tmux window; screenshot path is on the clipboard")
    return
  end
  hs.application.launchOrFocusByBundleID(ghosttyBundleId)
  waitForClaudePrompt(paneId, function()
    hs.task.new(tmuxPath, nil, { "send-keys", "-t", paneId, "-l", screenshotPath .. " " }):start()
  end)
end

return screenAsk
