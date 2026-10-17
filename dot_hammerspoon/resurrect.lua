local resurrect = {}

local tmuxPath = "/opt/homebrew/bin/tmux"
local scriptsDir = os.getenv("HOME") .. "/.config/tmux/plugins/tmux-resurrect/scripts"
local savesDir = os.getenv("HOME") .. "/.local/share/tmux/resurrect"

local function lastSaveTime()
  local lastSavePath = savesDir .. "/last"
  local savedFile = hs.fs.symlinkAttributes(lastSavePath) and hs.fs.attributes(lastSavePath, "modification")
  return savedFile and os.date("%d %b %H:%M", savedFile) or "never"
end

local function runScript(scriptName, onFinished)
  hs.task.new(tmuxPath, function(exitCode, _, standardError)
    if exitCode ~= 0 then
      hs.alert.show("tmux-resurrect " .. scriptName .. " failed: " .. (standardError or ""))
      return
    end
    onFinished()
  end, { "run-shell", scriptsDir .. "/" .. scriptName }):start()
end

function resurrect.save()
  runScript("save.sh", function()
    hs.alert.show("tmux saved (" .. lastSaveTime() .. ")")
  end)
end

function resurrect.restore()
  hs.alert.show("Restoring tmux from " .. lastSaveTime())
  runScript("restore.sh", function()
    hs.alert.show("tmux restored")
  end)
end

return resurrect
