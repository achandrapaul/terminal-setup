local summaryPanel = {}

local digestPath = os.getenv("HOME") .. "/.config/bin/digest"
local panelWidth = 980
local panelMargin = 16

local panel
local escapeHotkey
local digestTask

local function escapeHtml(text)
  return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local columnSections = {
  { "previous_done", "today_done" },
  { "today", "pending" },
}
local emptyMessages = {
  previous_done = "Nothing was closed",
  today_done = "Nothing closed yet",
  today = "Nothing started today",
  pending = "Nothing pending",
}
local chipStyles = {
  previous_done = { symbol = "✓", className = "done" },
  today = { symbol = "●", className = "today" },
  pending = { symbol = "◷", className = "pending" },
  today_done = { symbol = "✓", className = "done" },
}

local function dayNumber(isoText)
  local year, month, day = tostring(isoText or ""):match("^(%d+)-(%d+)-(%d+)")
  if not year then return nil end
  return math.floor(os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }) / 86400)
end

local function linkLabel(url)
  local issueKey = url:match("/browse/([A-Z][A-Z0-9]+%-%d+)")
  if issueKey then return issueKey end
  local pullNumber = url:match("/pull/(%d+)")
  if pullNumber then return "PR #" .. pullNumber end
  return url:match("^https?://([^/]+)") or url
end

local function splitLinks(summaryText)
  local linkChips = {}
  local plainText = tostring(summaryText or ""):gsub("https?://[^%s]+", function(url)
    url = url:gsub("[%.,;%)]+$", "")
    linkChips[#linkChips + 1] = string.format("<span class='link'>%s</span>", escapeHtml(linkLabel(url)))
    return ""
  end)
  plainText = plainText:gsub("%s+", " "):gsub("[%s:]+$", ""):gsub("^%s+", "")
  if tostring(summaryText or ""):find("/pull/%d+") then plainText = plainText:gsub("%s*[Pp][Rr]$", "") end
  return plainText, table.concat(linkChips)
end

local function ageBadge(note, todayNumber)
  local createdNumber = dayNumber(note.created)
  if not createdNumber or not todayNumber then return "" end
  local ageDays = todayNumber - createdNumber
  if ageDays < 1 then return "" end
  local ageClass = ageDays >= 7 and "old" or ageDays >= 3 and "aging" or "fresh"
  return string.format("<span class='age %s'>%dd</span>", ageClass, ageDays)
end

local function noteHtml(note, isDone, todayNumber)
  local plainText, linkChips = splitLinks(note.summary)
  local sourceTag = note.source ~= "#manual" and string.format("<span class='tag'>%s</span>", escapeHtml(note.source)) or ""
  return string.format(
    "<div class='note' title='%s'><span class='mark %s'>%s</span><span class='text'>%s</span>%s%s%s</div>",
    escapeHtml(note.summary):gsub("'", "&#39;"), isDone and "done" or "open", isDone and "✓" or "○",
    escapeHtml(plainText), linkChips, sourceTag, isDone and "" or ageBadge(note, todayNumber))
end

local function sectionHtml(section, todayNumber)
  local isDone = section.key == "previous_done" or section.key == "today_done"
  local noteParts = {}
  for _, note in ipairs(section.notes or {}) do
    noteParts[#noteParts + 1] = noteHtml(note, isDone, todayNumber)
  end
  if #noteParts == 0 then
    noteParts[1] = string.format("<div class='empty'>%s</div>", emptyMessages[section.key] or "Nothing here")
  end
  return string.format("<section><h2>%s<span class='count'>%d</span></h2>%s</section>",
    escapeHtml(section.title), #(section.notes or {}), table.concat(noteParts, "\n"))
end

local function headerDate(isoText)
  local year, month, day = tostring(isoText or ""):match("^(%d+)-(%d+)-(%d+)")
  if not year then return escapeHtml(isoText) end
  return os.date("%a %d %b", os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }))
end

local function panelHtml(report)
  local sectionsByKey, chipParts = {}, {}
  for _, section in ipairs(report.sections or {}) do
    sectionsByKey[section.key] = section
    local chipStyle = chipStyles[section.key] or { symbol = "•", className = "" }
    chipParts[#chipParts + 1] = string.format("<span class='chip %s'><b>%s %d</b> %s</span>",
      chipStyle.className, chipStyle.symbol, #(section.notes or {}), escapeHtml(section.title))
  end
  local todayNumber = dayNumber(report.date)
  local columnParts = {}
  for _, sectionKeys in ipairs(columnSections) do
    local sectionParts = {}
    for _, sectionKey in ipairs(sectionKeys) do
      if sectionsByKey[sectionKey] then sectionParts[#sectionParts + 1] = sectionHtml(sectionsByKey[sectionKey], todayNumber) end
    end
    columnParts[#columnParts + 1] = "<div class='column'>" .. table.concat(sectionParts, "\n") .. "</div>"
  end
  return [[
<!doctype html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin: 0; height: 100%; background: transparent; -webkit-user-select: none; cursor: default; }
  .card { box-sizing: border-box; display: flex; flex-direction: column; max-height: 100vh; border-radius: 14px;
    background: #141417; border: 1px solid #2E3A59; color: #E4E4E7; font: 13px -apple-system, sans-serif;
    box-shadow: 0 10px 30px rgba(0,0,0,.45); overflow: hidden; }
  header { padding: 14px 18px 12px; border-bottom: 1px solid #232329; }
  .title { font-size: 15px; font-weight: 650; color: #FAFAFA; }
  .title span { color: #71717A; font-weight: 500; }
  .chips { display: flex; gap: 8px; margin-top: 10px; flex-wrap: wrap; }
  .chip { padding: 3px 10px; border-radius: 999px; background: #1F1F25; color: #A1A1AA; font-size: 12px; }
  .chip b { font-weight: 600; }
  .chip.done b { color: #4ADE80; } .chip.today b { color: #60A5FA; } .chip.pending b { color: #FBBF24; }
  .columns { display: grid; grid-template-columns: 2fr 3fr; min-height: 0; flex: 1; }
  .column { overflow-y: auto; padding: 4px 18px 12px; min-height: 0; }
  .column + .column { border-left: 1px solid #232329; }
  section { margin-top: 12px; }
  h2 { display: flex; justify-content: space-between; margin: 0 0 6px; font-size: 11px; font-weight: 600;
    letter-spacing: .08em; text-transform: uppercase; color: #8B8B95; }
  .count { color: #52525B; }
  .note { display: flex; align-items: center; gap: 8px; padding: 4px 6px; margin: 0 -6px; border-radius: 6px; }
  .note:hover { background: #1C1C22; }
  .mark { flex: none; width: 14px; text-align: center; }
  .mark.done { color: #4ADE80; } .mark.open { color: #52525B; }
  .text { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .link, .tag, .age { flex: none; font-size: 11px; padding: 1px 7px; border-radius: 5px; white-space: nowrap; }
  .link { background: #172554; color: #93C5FD; font-family: ui-monospace, Menlo, monospace; }
  .tag { background: #27272A; color: #A1A1AA; }
  .age { font-variant-numeric: tabular-nums; }
  .age.fresh { color: #A1A1AA; background: #232329; }
  .age.aging { color: #FBBF24; background: #3A2A0A; }
  .age.old { color: #F87171; background: #3B1212; }
  .empty { color: #52525B; font-style: italic; padding: 2px 0 4px; }
  footer { padding: 8px 18px; border-top: 1px solid #232329; color: #71717A; font-size: 11px; }
  kbd { font: 11px ui-monospace, Menlo, monospace; padding: 1px 6px; border-radius: 4px;
    background: #27272A; border: 1px solid #3F3F46; color: #FAFAFA; }
  ::-webkit-scrollbar { width: 6px; } ::-webkit-scrollbar-thumb { background: #3F3F46; border-radius: 3px; }
</style></head><body><div class="card">
  <header><div class="title">Digest <span>· ]] .. headerDate(report.date) .. [[</span></div>
    <div class="chips">]] .. table.concat(chipParts) .. [[</div></header>
  <div class="columns">]] .. table.concat(columnParts) .. [[</div>
  <footer><kbd>Esc</kbd> close</footer>
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
  local screenFrame = hs.screen.mainScreen():frame()
  local panelFrame = {
    x = screenFrame.x + (screenFrame.w - panelWidth) / 2,
    y = screenFrame.y + panelMargin,
    w = panelWidth,
    h = screenFrame.h - 2 * panelMargin,
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
  if escapeHotkey then escapeHotkey:delete() end
  escapeHotkey = hs.hotkey.bind({}, "escape", summaryPanel.hide)
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
  end, { "summary", "--json", "--exclude=pr" })
  digestTask:start()
end

return summaryPanel
