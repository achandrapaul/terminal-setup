local claudeState = {}

local tmuxPath = "/opt/homebrew/bin/tmux"
local stateDir = os.getenv("HOME") .. "/.claude/session-status"
local refreshIntervalSeconds = 1

local currentSessions = {}
local currentPaneLocations = {}
local liveClaudeCount = 0
local resolvedOverrides = {}
local changeHandler
local stateWatcher, refreshTimer, debounceTimer

local function isClaudeCommand(commandName)
  return commandName == "claude" or commandName:match("^%d+%.%d+%.%d+$") ~= nil
end

local function claudePanes()
  local panes, paneTtys = {}, {}
  local paneList = hs.execute(tmuxPath .. " list-panes -a -F '#{pane_id} #{pane_tty} #{pane_current_command} #{session_name}:#{window_index}.#{pane_index}'") or ""
  for paneId, paneTty, paneCommand, paneLocation in paneList:gmatch("(%%%d+) /dev/(%S+) (%S+) ([^\n]+)") do
    paneTtys[paneTty] = true
    if isClaudeCommand(paneCommand) then
      panes[paneId] = paneLocation
    end
  end
  return panes, paneTtys
end

local function claudeTtysOutsideTmux(paneTtys)
  local outsideTtys = {}
  for processTty, commandPath in (hs.execute("/bin/ps -A -o tty=,comm=") or ""):gmatch("(%S+)%s+([^\n]+)") do
    local commandName = commandPath:match("([^/]+)%s*$") or ""
    if processTty ~= "??" and not paneTtys[processTty] and isClaudeCommand(commandName) then
      outsideTtys[processTty] = true
    end
  end
  return outsideTtys
end

local function readSessionFile(filePath)
  local sessionFile = io.open(filePath, "r")
  if not sessionFile then return nil end
  local content = sessionFile:read("a")
  sessionFile:close()
  return hs.json.decode(content)
end

local function effectiveStatus(session)
  local override = resolvedOverrides[session.session_id]
  if override and override.updated == session.updated and override.status == session.status then return "idle" end
  if session.status == "done" then return "idle" end
  return session.status
end

local function reload()
  local livePanes, paneTtys = claudePanes()
  currentPaneLocations = livePanes
  liveClaudeCount = 0
  for _ in pairs(livePanes) do liveClaudeCount = liveClaudeCount + 1 end
  for _ in pairs(claudeTtysOutsideTmux(paneTtys)) do liveClaudeCount = liveClaudeCount + 1 end
  local newestByPane = {}
  for fileName in hs.fs.dir(stateDir) do
    if fileName:match("%.json$") then
      local session = readSessionFile(stateDir .. "/" .. fileName)
      if session and session.pane and livePanes[session.pane] then
        local existing = newestByPane[session.pane]
        if not existing or session.updated > existing.updated then
          newestByPane[session.pane] = session
        end
      end
    end
  end

  currentSessions = {}
  for _, session in pairs(newestByPane) do
    session.status = effectiveStatus(session)
    currentSessions[#currentSessions + 1] = session
  end
  table.sort(currentSessions, function(first, second) return first.updated < second.updated end)
  if changeHandler then changeHandler(currentSessions) end
end

local function scheduleReload()
  if debounceTimer then debounceTimer:stop() end
  debounceTimer = hs.timer.doAfter(0.1, reload)
end

function claudeState.sessions()
  return currentSessions
end

function claudeState.livePanes()
  return currentPaneLocations
end

function claudeState.liveClaudeCount()
  return liveClaudeCount
end

function claudeState.aggregateStatus()
  local statusRank = { waiting = 2, working = 1 }
  local topStatus, topRank = liveClaudeCount > 0 and "idle" or "none", 0
  for _, session in ipairs(currentSessions) do
    local rank = statusRank[session.status] or 0
    if rank > topRank then topStatus, topRank = session.status, rank end
  end
  return topStatus
end

function claudeState.markResolved(session)
  resolvedOverrides[session.session_id] = { updated = session.updated, status = session.status }
  scheduleReload()
end

function claudeState.start(onChange)
  changeHandler = onChange
  hs.fs.mkdir(stateDir)
  stateWatcher = hs.pathwatcher.new(stateDir, scheduleReload):start()
  refreshTimer = hs.timer.doEvery(refreshIntervalSeconds, reload)
  reload()
end

return claudeState
