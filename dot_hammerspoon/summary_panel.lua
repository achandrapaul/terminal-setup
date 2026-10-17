local summaryPanel = {}

local digestPath = os.getenv("HOME") .. "/.config/bin/digest"
local panelWidth = 720
local panelMargin = 16

local panel
local escapeHotkey
local digestTask

local function escapeHtml(text)
  return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function sectionHtml(section)
  local noteParts = {}
  for _, note in ipairs(section.notes or {}) do
    noteParts[#noteParts + 1] = string.format(
      "<div class='note'><span class='summary'>%s</span><span class='tag'>%s</span></div>",
      escapeHtml(note.summary), escapeHtml(note.source))
  end
  if #noteParts == 0 then noteParts[1] = "<div class='empty'>none</div>" end
  return string.format("<div class='section'><div class='title'>%s <span class='count'>%d</span></div>%s</div>",
    escapeHtml(section.title), #(section.notes or {}), table.concat(noteParts, "\n"))
end

local function panelHtml(report)
  local sectionParts = {}
  for _, section in ipairs(report.sections or {}) do
    sectionParts[#sectionParts + 1] = sectionHtml(section)
  end
  return [[
<!doctype html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin: 0; background: transparent; }
  .card { box-sizing: border-box; max-height: 100vh; overflow-y: auto; padding: 14px 16px; border-radius: 12px;
    background: #18181B; border: 1px solid #3B82F6; color: #E4E4E7; font: 13px -apple-system, sans-serif; }
  .header { font-weight: 600; color: #93C5FD; margin-bottom: 8px; }
  .section { margin: 10px 0 0; }
  .title { font-weight: 600; color: #FAFAFA; margin-bottom: 4px; }
  .count { color: #71717A; font-weight: 400; }
  .note { display: flex; gap: 10px; justify-content: space-between; align-items: baseline; margin: 3px 0; }
  .summary { word-break: break-word; }
  .tag { color: #60A5FA; font-size: 11px; white-space: nowrap; }
  .empty { color: #71717A; }
  .footer { margin-top: 12px; color: #A1A1AA; font-size: 11px; }
  kbd { font: 11px ui-monospace, Menlo, monospace; padding: 1px 6px; border-radius: 4px;
    background: #27272A; border: 1px solid #3F3F46; color: #FAFAFA; }
</style></head><body><div class="card">
  <div class="header">Digest · ]] .. escapeHtml(report.date) .. [[</div>
  ]] .. table.concat(sectionParts, "\n") .. [[
  <div class="footer"><kbd>Esc</kbd> close</div>
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

function summaryPanel.hide()
  if escapeHotkey then
    escapeHotkey:delete()
    escapeHotkey = nil
  end
  if panel then panel:hide() end
end

local function present(report)
  ensurePanel():html(panelHtml(report))
  panel:show()
  if not escapeHotkey then escapeHotkey = hs.hotkey.bind({}, "escape", summaryPanel.hide) end
end

function summaryPanel.show()
  if digestTask and digestTask:isRunning() then return end
  digestTask = hs.task.new(digestPath, function(exitCode, standardOutput, standardError)
    local report = exitCode == 0 and hs.json.decode(standardOutput or "")
    if not report then
      hs.alert.show("digest summary failed: " .. ((standardError or ""):match("[^\n]+") or ("exit " .. exitCode)))
      return
    end
    present(report)
  end, { "summary", "--json" })
  digestTask:start()
end

return summaryPanel
