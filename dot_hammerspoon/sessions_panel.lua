local claudeState = require("claude_state")
local paneJump = require("pane_jump")

local sessionsPanel = {}

local panelWidth = 720
local panelMargin = 16
local maxNumberedRows = 9
local statusColors = {
  waiting = "#EF4444",
  working = "#3B82F6",
  idle = "#22C55E",
  unknown = "#A1A1AA",
}

local panel
local panelHotkeys = {}
local renderedHtml
local isOpen = false

local function escapeHtml(text)
  return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function ageText(updatedSeconds)
  if not updatedSeconds then return "" end
  local elapsedSeconds = math.max(0, os.time() - updatedSeconds)
  if elapsedSeconds < 60 then return "<1m" end
  if elapsedSeconds < 3600 then return math.floor(elapsedSeconds / 60) .. "m" end
  if elapsedSeconds < 86400 then return math.floor(elapsedSeconds / 3600) .. "h" end
  return math.floor(elapsedSeconds / 86400) .. "d"
end

local function sessionRows()
  local sessionsByPane = {}
  for _, session in ipairs(claudeState.sessions()) do sessionsByPane[session.pane] = session end
  local rows = {}
  for paneId, paneLocation in pairs(claudeState.livePanes()) do
    local session = sessionsByPane[paneId] or {}
    rows[#rows + 1] = {
      pane = paneId,
      location = paneLocation,
      cwd = session.cwd,
      projectName = session.cwd and session.cwd:match("([^/]+)/?$") or paneId,
      status = session.status or "unknown",
      updated = session.updated,
    }
  end
  table.sort(rows, function(first, second) return first.location < second.location end)
  return rows
end

local function panelHtml(rows)
  local rowParts = {}
  for rowIndex, row in ipairs(rows) do
    local keyLabel = rowIndex <= maxNumberedRows and ("<kbd>⌥" .. rowIndex .. "</kbd>") or "<span class='nokey'></span>"
    rowParts[#rowParts + 1] = string.format([[
<div class='row'>%s<div class='main'>
  <div class='top'><span class='project'>%s</span>
    <span class='status' style='color:%s'>● %s</span><span class='age'>%s</span>
    <span class='location'>%s</span></div>
  <div class='path'>%s</div></div></div>]],
      keyLabel, escapeHtml(row.projectName), statusColors[row.status] or statusColors.unknown,
      escapeHtml(row.status), escapeHtml(ageText(row.updated)), escapeHtml(row.location), escapeHtml(row.cwd or ""))
  end
  if #rowParts == 0 then rowParts[1] = "<div class='empty'>No Claude running in tmux</div>" end
  return [[
<!doctype html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin: 0; background: transparent; }
  .card { box-sizing: border-box; max-height: 100vh; overflow-y: auto; padding: 14px 16px; border-radius: 12px;
    background: #18181B; border: 1px solid #22C55E; color: #E4E4E7; font: 13px -apple-system, sans-serif; }
  .header { font-weight: 600; color: #86EFAC; margin-bottom: 6px; }
  .row { display: flex; gap: 10px; align-items: baseline; padding: 6px 0; border-top: 1px solid #27272A; }
  .row:first-of-type { border-top: none; }
  .main { flex: 1; min-width: 0; }
  .top { display: flex; gap: 10px; align-items: baseline; }
  .project { font-weight: 600; color: #FAFAFA; }
  .age { color: #A1A1AA; }
  .location { margin-left: auto; color: #71717A; font: 11px ui-monospace, Menlo, monospace; }
  .path { color: #71717A; font-size: 11px; word-break: break-all; margin-top: 2px; }
  .nokey { display: inline-block; width: 30px; }
  .empty { color: #71717A; }
  .footer { margin-top: 10px; color: #A1A1AA; font-size: 11px; }
  kbd { font: 11px ui-monospace, Menlo, monospace; padding: 1px 6px; border-radius: 4px;
    background: #27272A; border: 1px solid #3F3F46; color: #FAFAFA; white-space: nowrap; }
</style></head><body><div class="card">
  <div class="header">Claude sessions · ]] .. #rows .. [[</div>
  ]] .. table.concat(rowParts, "\n") .. [[
  <div class="footer"><kbd>⌥1</kbd>–<kbd>⌥9</kbd> go to session · <kbd>Esc</kbd> close</div>
</div></body></html>]]
end

local function fitPanelToContent()
  panel:evaluateJavaScript("document.querySelector('.card').scrollHeight", function(contentHeight)
    if not contentHeight or not panel then return end
    local screenFrame = hs.screen.mainScreen():frame()
    local panelFrame = panel:frame()
    panelFrame.h = math.min(math.ceil(contentHeight), screenFrame.h - 2 * panelMargin)
    panel:frame(panelFrame)
  end)
end

local function ensurePanel()
  local screenFrame = hs.screen.mainScreen():frame()
  local panelFrame = {
    x = screenFrame.x + (screenFrame.w - panelWidth) / 2,
    y = screenFrame.y + panelMargin,
    w = panelWidth,
    h = 200,
  }
  if panel then
    panel:frame(panelFrame)
    return panel
  end
  panel = hs.webview.new(panelFrame)
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

function sessionsPanel.hide()
  isOpen = false
  renderedHtml = nil
  clearHotkeys()
  if panel then panel:hide() end
end

local function render()
  local rows = sessionRows()
  local html = panelHtml(rows)
  if html == renderedHtml then return end
  renderedHtml = html
  ensurePanel():html(html)
  panel:show()
  clearHotkeys()
  for rowIndex = 1, math.min(#rows, maxNumberedRows) do
    local paneId = rows[rowIndex].pane
    panelHotkeys[#panelHotkeys + 1] = hs.hotkey.bind({ "alt" }, tostring(rowIndex), function()
      sessionsPanel.hide()
      paneJump.to(paneId)
    end)
  end
  panelHotkeys[#panelHotkeys + 1] = hs.hotkey.bind({}, "escape", sessionsPanel.hide)
end

function sessionsPanel.show()
  isOpen = true
  renderedHtml = nil
  render()
end

function sessionsPanel.update()
  if isOpen then render() end
end

return sessionsPanel
