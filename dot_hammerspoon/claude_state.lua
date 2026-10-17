local claudeState = {}

local tmuxPath = "/opt/homebrew/bin/tmux"
local stateDir = os.getenv("HOME") .. "/.claude/session-status"
local claudeSessionsDir = os.getenv("HOME") .. "/.claude/sessions"
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
  local paneList = hs.execute(tmuxPath .. " list-panes -a -F '#{pane_id} #{pane_tty} #{pane_current_command} #{session_name}:#{window_index}.#{pane_index}|#{pane_current_path}'") or ""
  for paneId, paneTty, paneCommand, paneLocation, panePath in paneList:gmatch("(%%%d+) /dev/(%S+) (%S+) ([^|\n]+)|([^\n]*)") do
    paneTtys[paneTty] = true
    if isClaudeCommand(paneCommand) then
      panes[paneId] = { location = paneLocation, path = panePath }
    end
  end
  return panes, paneTtys
end

local function claudeProcesses(paneTtys)
  local outsideTtys, livePids = {}, {}
  for processId, processTty, commandPath in (hs.execute("/bin/ps -A -o pid=,tty=,comm=") or ""):gmatch("(%d+)%s+(%S+)%s+([^\n]+)") do
    local commandName = commandPath:match("([^/]+)%s*$") or ""
    if isClaudeCommand(commandName) then
      livePids[tonumber(processId)] = true
      if processTty ~= "??" and not paneTtys[processTty] then outsideTtys[processTty] = true end
    end
  end
  return outsideTtys, livePids
end

local function readSessionFile(filePath)
  local sessionFile = io.open(filePath, "r")
  if not sessionFile then return nil end
  local content = sessionFile:read("a")
  sessionFile:close()
  return hs.json.decode(content)
end

local function attachClaudeSessionInfo(livePanes, livePids)
  if hs.fs.attributes(claudeSessionsDir, "mode") ~= "directory" then return end
  for fileName in hs.fs.dir(claudeSessionsDir) do
    if fileName:match("^%d+%.json$") then
      local claudeSession = readSessionFile(claudeSessionsDir .. "/" .. fileName)
      local paneId = claudeSession and type(claudeSession.tmux) == "string" and claudeSession.tmux:match("(%%%d+)$")
      local livePane = paneId and livePanes[paneId]
      if livePane and livePids[claudeSession.pid] and (claudeSession.updatedAt or 0) >= (livePane.claudeUpdatedAt or 0) then
        livePane.name = claudeSession.name
        livePane.claudeStatus = claudeSession.status
        livePane.claudeUpdatedAt = claudeSession.updatedAt or 0
        livePane.claudeStatusSince = claudeSession.statusUpdatedAt and math.floor(claudeSession.statusUpdatedAt / 1000)
        livePane.path = claudeSession.cwd or livePane.path
      end
    end
  end
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
  local outsideTtys, livePids = claudeProcesses(paneTtys)
  for _ in pairs(outsideTtys) do liveClaudeCount = liveClaudeCount + 1 end
  attachClaudeSessionInfo(livePanes, livePids)
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
