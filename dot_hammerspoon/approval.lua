local promptCapture = require("prompt_capture")
local claudeState = require("claude_state")
local paneJump = require("pane_jump")

local approval = {}

local tmuxPath = "/opt/homebrew/bin/tmux"
local panelWidth = 640
local panelMargin = 16
local captureRetryLimit = 10
local captureRetryDelaySeconds = 0.3
local approvalLog = hs.logger.new("approval", "info")

local waitingEntries = {}
local activeSessionId
local panel
local panelHotkeys = {}
local captureAttempts = {}
local retryTimer
local renderedKey

local function escapeHtml(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function activeEntry()
  for entryIndex, entry in ipairs(waitingEntries) do
    if entry.session.session_id == activeSessionId then return entry, entryIndex end
  end
  return nil
end

local function hasTabs(prompt)
  for _, textLine in ipairs(prompt.textLines) do
    if textLine.text and textLine.text:find("←", 1, true) and textLine.text:find("→", 1, true) then return true end
  end
  return false
end

local function panelHtml(entry, entryIndex)
  local session, prompt = entry.session, entry.prompt
  local projectName = session.cwd and session.cwd:match("([^/]+)/?$") or session.pane
  local bodyParts = {}
  for _, textLine in ipairs(prompt.textLines) do
    bodyParts[#bodyParts + 1] = textLine.rule and "<hr>" or ("<div class='line'>" .. escapeHtml(textLine.text) .. "</div>")
  end
  local optionParts = {}
  for _, option in ipairs(prompt.options) do
    optionParts[#optionParts + 1] = string.format(
      "<div class='option'><kbd>⌥%d</kbd><span>%d. %s</span></div>",
      option.number, option.number, escapeHtml(option.label))
  end
  local sessionCount = #waitingEntries > 1 and string.format(" · %d of %d", entryIndex, #waitingEntries) or ""
  local footerParts = { "<kbd>⌥Y</kbd> option 1", "<kbd>⌥N</kbd> cancel", "<kbd>⌥G</kbd> go to session" }
  if hasTabs(prompt) then footerParts[#footerParts + 1] = "<kbd>⌥←</kbd><kbd>⌥→</kbd> switch tab / submit" end
  if #waitingEntries > 1 then footerParts[#footerParts + 1] = "<kbd>⌥Tab</kbd> next session" end

  return [[
<!doctype html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin: 0; background: transparent; }
  .card { margin: 0; padding: 14px 16px; border-radius: 12px; background: #18181B;
    border: 1px solid #EF4444; color: #E4E4E7; font: 13px -apple-system, sans-serif; }
  .header { font-weight: 600; color: #FCA5A5; }
  .path { color: #71717A; font-size: 11px; margin: 2px 0 10px; word-break: break-all; }
  .line { font-family: ui-monospace, Menlo, monospace; white-space: pre-wrap; word-break: break-word; margin: 2px 0; }
  hr { border: none; border-top: 1px dashed #3F3F46; margin: 6px 0; }
  .option { display: flex; gap: 10px; align-items: baseline; margin: 5px 0; }
  kbd { font: 11px ui-monospace, Menlo, monospace; padding: 1px 6px; border-radius: 4px;
    background: #27272A; border: 1px solid #3F3F46; color: #FAFAFA; white-space: nowrap; }
  .footer { margin-top: 10px; color: #A1A1AA; font-size: 11px; display: flex; gap: 14px; }
</style></head><body><div class="card">
  <div class="header">Claude · ]] .. escapeHtml(projectName) .. sessionCount .. [[</div>
  <div class="path">]] .. escapeHtml((session.cwd or "") .. "  ·  pane " .. session.pane) .. [[</div>
  ]] .. table.concat(bodyParts, "\n") .. [[
  <div class="options">]] .. table.concat(optionParts, "\n") .. [[</div>
  <div class="footer">]] .. table.concat(footerParts, "<span>·</span>") .. [[</div>
</div></body></html>]]
end

local function fitPanelToContent()
  panel:evaluateJavaScript("document.querySelector('.card').getBoundingClientRect().height", function(contentHeight)
    if not contentHeight or not panel then return end
    local panelFrame = panel:frame()
    panelFrame.h = math.ceil(contentHeight)
    panel:frame(panelFrame)
  end)
end

local function ensurePanel()
  if panel then return panel end
  local screenFrame = hs.screen.mainScreen():frame()
  panel = hs.webview.new({
    x = screenFrame.x + screenFrame.w - panelWidth - panelMargin,
    y = screenFrame.y + panelMargin,
    w = panelWidth,
    h = 200,
  })
  panel:windowStyle({ "borderless", "nonactivating" })
  panel:transparent(true)
  panel:allowTextEntry(false)
  panel:level(hs.drawing.windowLevels.floating)
  panel:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
  panel:navigationCallback(function(navigationAction)
    if navigationAction == "didFinishNavigation" then fitPanelToContent() end
  end)
  return panel
end

local function clearHotkeys()
  for _, hotkey in ipairs(panelHotkeys) do hotkey:delete() end
  panelHotkeys = {}
end

local function bindPanelKey(key, handler)
  panelHotkeys[#panelHotkeys + 1] = hs.hotkey.bind({ "alt" }, key, handler)
end

local function render()
  local entry, entryIndex = activeEntry()
  local renderKey = entry and table.concat({ entry.session.session_id, entry.prompt.signature, entryIndex, #waitingEntries }, "\0")
  if renderKey == renderedKey then return end
  renderedKey = renderKey
  clearHotkeys()
  if not entry then
    if panel then panel:hide() end
    return
  end
  ensurePanel():html(panelHtml(entry, entryIndex))
  panel:show()
  for _, option in ipairs(entry.prompt.options) do
    if option.number <= 9 then
      bindPanelKey(tostring(option.number), function() approval.choose(option.number) end)
    end
  end
  bindPanelKey("y", function() approval.choose(1) end)
  bindPanelKey("n", approval.cancel)
  bindPanelKey("tab", approval.cycle)
  bindPanelKey("g", approval.jump)
  if hasTabs(entry.prompt) then
    bindPanelKey("left", function() approval.moveTab("Left") end)
    bindPanelKey("right", function() approval.moveTab("Right") end)
  end
end

local function scheduleCaptureRetry(session)
  local attemptKey = session.session_id .. ":" .. session.updated
  captureAttempts[attemptKey] = (captureAttempts[attemptKey] or 0) + 1
  if captureAttempts[attemptKey] > captureRetryLimit then
    claudeState.markResolved(session)
    return
  end
  if retryTimer and retryTimer:running() then return end
  retryTimer = hs.timer.doAfter(captureRetryDelaySeconds, function()
    approval.update(claudeState.sessions())
  end)
end

function approval.update(sessions)
  local entries = {}
  for _, session in ipairs(sessions) do
    local prompt = promptCapture.capture(session.pane)
    if prompt then
      entries[#entries + 1] = { session = session, prompt = prompt }
    elseif session.status == "waiting" then
      scheduleCaptureRetry(session)
    end
  end
  waitingEntries = entries
  if not activeEntry() then
    activeSessionId = entries[1] and entries[1].session.session_id
  end
  render()
end

function approval.isOpen()
  return activeEntry() ~= nil
end

local function sendToActivePane(keyName, requireOption)
  local entry = activeEntry()
  if not entry then return end
  local currentPrompt = promptCapture.capture(entry.session.pane)
  if not currentPrompt or currentPrompt.signature ~= entry.prompt.signature then
    hs.alert.show("Claude's prompt changed; panel refreshed, nothing sent")
    approval.update(claudeState.sessions())
    return
  end
  if requireOption then
    local optionExists = false
    for _, option in ipairs(currentPrompt.options) do
      if option.number == requireOption then optionExists = true end
    end
    if not optionExists then return end
  end
  local _, succeeded = hs.execute(tmuxPath .. " send-keys -t '" .. entry.session.pane .. "' " .. keyName)
  approvalLog.i(string.format("sent %s to pane %s session %s (%s) succeeded=%s",
    keyName, entry.session.pane, entry.session.session_id, entry.session.cwd or "", tostring(succeeded)))
  if not succeeded then
    hs.alert.show("Couldn't send to pane " .. entry.session.pane)
    return
  end
  claudeState.markResolved(entry.session)
end

function approval.choose(optionNumber)
  sendToActivePane(tostring(optionNumber), optionNumber)
end

function approval.cancel()
  sendToActivePane("Escape")
end

function approval.moveTab(direction)
  sendToActivePane(direction)
end

function approval.jump()
  local entry = activeEntry()
  if entry then paneJump.to(entry.session.pane) end
end

function approval.cycle()
  local _, entryIndex = activeEntry()
  if not entryIndex or #waitingEntries < 2 then return end
  activeSessionId = waitingEntries[entryIndex % #waitingEntries + 1].session.session_id
  render()
end

return approval
