local claudeProjectsDir = os.getenv("HOME") .. "/.claude/projects"
local tmuxPath = "/opt/homebrew/bin/tmux"
local ghosttyBundleId = "com.mitchellh.ghostty"
local zoomBundleId = "us.zoom.xos"
local transcriptTailBytes = 1024 * 1024

local function newestTranscriptIn(projectPath)
  local newestPath, newestTime = nil, 0
  if hs.fs.attributes(projectPath, "mode") ~= "directory" then return nil end
  for fileName in hs.fs.dir(projectPath) do
    if fileName:match("%.jsonl$") then
      local filePath = projectPath .. "/" .. fileName
      local modifiedTime = hs.fs.attributes(filePath, "modification") or 0
      if modifiedTime > newestTime then
        newestPath, newestTime = filePath, modifiedTime
      end
    end
  end
  return newestPath
end

local function tmuxPopupIsOpen()
  local serverPid = hs.execute(tmuxPath .. " display-message -p '#{pid}'")
  serverPid = serverPid and serverPid:match("%d+")
  if not serverPid then return false end
  local paneTtys = {}
  for paneTty in (hs.execute(tmuxPath .. " list-panes -a -F '#{pane_tty}'") or ""):gmatch("/dev/(%S+)") do
    paneTtys[paneTty] = true
  end
  for parentPid, childTty in (hs.execute("/bin/ps -A -o ppid=,tty=") or ""):gmatch("(%d+)%s+(%S+)") do
    if parentPid == serverPid and childTty ~= "??" and not paneTtys[childTty] then
      return true
    end
  end
  return false
end

local function focusedClaudePanePath()
  if tmuxPopupIsOpen() then return nil end
  local paneInfo, succeeded = hs.execute(tmuxPath .. " display-message -p '#{pane_current_command}|#{pane_current_path}'")
  if not succeeded or not paneInfo then return nil end
  local paneCommand, panePath = paneInfo:match("^([^|]*)|(.-)%s*$")
  if not paneCommand then return nil end
  if paneCommand == "claude" or paneCommand:match("^%d+%.%d+%.%d+$") then
    return panePath
  end
  return nil
end

local function readTranscriptLines(transcriptPath, tailBytes)
  local transcriptFile = io.open(transcriptPath, "r")
  if not transcriptFile then return nil, false end
  local fileSize = transcriptFile:seek("end")
  local readStart = tailBytes and math.max(0, fileSize - tailBytes) or 0
  transcriptFile:seek("set", readStart)
  local transcriptContent = transcriptFile:read("a") or ""
  transcriptFile:close()

  local transcriptLines = {}
  for line in transcriptContent:gmatch("[^\n]+") do
    transcriptLines[#transcriptLines + 1] = line
  end
  local isTruncated = readStart > 0
  if isTruncated then table.remove(transcriptLines, 1) end
  return transcriptLines, isTruncated
end

local function findLastAssistantText(transcriptLines)
  for lineIndex = #transcriptLines, 1, -1 do
    local line = transcriptLines[lineIndex]
    if line:find('"type":"assistant"', 1, true) and line:find('"type":"text"', 1, true) then
      local entry = hs.json.decode(line)
      if entry and entry.type == "assistant" and entry.message and type(entry.message.content) == "table" then
        local textParts = {}
        for _, contentBlock in ipairs(entry.message.content) do
          if contentBlock.type == "text" and contentBlock.text then
            textParts[#textParts + 1] = contentBlock.text
          end
        end
        if #textParts > 0 then return table.concat(textParts, "\n") end
      end
    end
  end
  return nil
end

local function lastAssistantText(transcriptPath)
  local tailLines, isTruncated = readTranscriptLines(transcriptPath, transcriptTailBytes)
  if not tailLines then return nil end
  local responseText = findLastAssistantText(tailLines)
  if responseText or not isTruncated then return responseText end
  local allLines = readTranscriptLines(transcriptPath, nil)
  return allLines and findLastAssistantText(allLines)
end

local function passThrough(hotkey, modifiers, key)
  hotkey:disable()
  hs.eventtap.keyStroke(modifiers, key, 0)
  hotkey:enable()
end

local claudeCopyHotkey

local function copyClaudeLastResponse()
  local panePath = focusedClaudePanePath()
  if not panePath then
    passThrough(claudeCopyHotkey, { "ctrl" }, "y")
    return false
  end
  local transcriptPath = newestTranscriptIn(claudeProjectsDir .. "/" .. panePath:gsub("[^%w]", "-"))
  if not transcriptPath then
    hs.alert.show("No Claude transcript for " .. panePath)
    return false
  end
  local responseText = lastAssistantText(transcriptPath)
  if not responseText then
    hs.alert.show("No Claude response found")
    return false
  end
  hs.pasteboard.setContents(responseText)
  hs.alert.show("Copied Claude's last response")
  return true
end

local function setZoomMicVolumeToFull()
  for _, inputDevice in ipairs(hs.audiodevice.allInputDevices()) do
    inputDevice:setInputVolume(100)
  end
  hs.alert.show("Mic input 100%")
  return true
end

local appScopedHotkeys = {}

local function bindWhileFocused(bundleId, modifiers, key, handler)
  local hotkey = hs.hotkey.new(modifiers, key, handler)
  appScopedHotkeys[#appScopedHotkeys + 1] = { bundleId = bundleId, hotkey = hotkey }
  return hotkey
end

local function enableHotkeysFor(focusedBundleId)
  for _, scopedHotkey in ipairs(appScopedHotkeys) do
    if scopedHotkey.bundleId == focusedBundleId then
      scopedHotkey.hotkey:enable()
    else
      scopedHotkey.hotkey:disable()
    end
  end
end

local function enableHotkeysForFrontmostApp()
  local frontmostApp = hs.application.frontmostApplication()
  enableHotkeysFor(frontmostApp and frontmostApp:bundleID())
end

claudeCopyHotkey = bindWhileFocused(ghosttyBundleId, { "ctrl" }, "y", copyClaudeLastResponse)
bindWhileFocused(zoomBundleId, { "ctrl" }, "f", setZoomMicVolumeToFull)

appFocusWatcher = hs.application.watcher.new(function(_, eventType, app)
  if eventType == hs.application.watcher.activated and app then
    enableHotkeysFor(app:bundleID())
  end
end)
appFocusWatcher:start()

local wakeEvents = {
  [hs.caffeinate.watcher.systemDidWake] = true,
  [hs.caffeinate.watcher.screensDidWake] = true,
  [hs.caffeinate.watcher.screensDidUnlock] = true,
}

systemWakeWatcher = hs.caffeinate.watcher.new(function(eventType)
  if wakeEvents[eventType] then enableHotkeysForFrontmostApp() end
end)
systemWakeWatcher:start()

enableHotkeysForFrontmostApp()
