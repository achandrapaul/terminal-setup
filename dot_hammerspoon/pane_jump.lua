local paneJump = {}

local tmuxPath = "/opt/homebrew/bin/tmux"
local ghosttyBundleId = "com.mitchellh.ghostty"

function paneJump.to(paneId)
  local paneTarget = "'" .. paneId .. "'"
  local _, succeeded = hs.execute(string.format("%s select-window -t %s && %s select-pane -t %s && %s switch-client -t %s",
    tmuxPath, paneTarget, tmuxPath, paneTarget, tmuxPath, paneTarget))
  if not succeeded then
    hs.alert.show("Couldn't switch to pane " .. paneId)
    return false
  end
  hs.application.launchOrFocusByBundleID(ghosttyBundleId)
  return true
end

return paneJump
