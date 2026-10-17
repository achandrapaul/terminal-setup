local promptCapture = {}

local tmuxPath = "/opt/homebrew/bin/tmux"
local ruleCharacter = "─"
local dashedRuleCharacter = "╌"
local continuationIndent = 2

local function trimmed(line)
  return (line:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isMadeOf(line, character)
  local content = trimmed(line)
  return content ~= "" and content:gsub(character, "") == ""
end

local function paneLines(paneId)
  local paneText, succeeded = hs.execute(tmuxPath .. " capture-pane -p -J -t '" .. paneId .. "'")
  if not succeeded or not paneText then return nil end
  local lines = {}
  for line in (paneText .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = (line:gsub("%s+$", ""))
  end
  return lines
end

local function optionParts(line)
  local unmarkedLine = line:gsub("❯", " ", 1)
  return unmarkedLine:match("^%s*(%d+)%.%s+(.+)$")
end

local function isContinuation(line)
  return trimmed(line) ~= "" and not optionParts(line) and #line:match("^%s*") >= continuationIndent
end

local function findCursorIndex(lines)
  for lineIndex = #lines, 1, -1 do
    if lines[lineIndex]:match("^%s*❯%s*%d+%.%s") then return lineIndex end
  end
  return nil
end

local function collectOptions(lines, cursorIndex)
  local firstOptionIndex = cursorIndex
  for lineIndex = cursorIndex - 1, 1, -1 do
    if optionParts(lines[lineIndex]) then
      firstOptionIndex = lineIndex
    elseif not isContinuation(lines[lineIndex]) then
      break
    end
  end
  local lastOptionLineIndex = cursorIndex
  while lines[lastOptionLineIndex + 1]
    and (optionParts(lines[lastOptionLineIndex + 1]) or isContinuation(lines[lastOptionLineIndex + 1])) do
    lastOptionLineIndex = lastOptionLineIndex + 1
  end

  local options = {}
  for lineIndex = firstOptionIndex, lastOptionLineIndex do
    local number, label = optionParts(lines[lineIndex])
    if number then
      options[#options + 1] = { number = tonumber(number), label = label }
    else
      options[#options].label = options[#options].label .. " " .. trimmed(lines[lineIndex])
    end
  end
  return options, firstOptionIndex, lastOptionLineIndex
end

local function findFooter(lines, lastOptionLineIndex)
  for lineIndex = lastOptionLineIndex + 1, #lines do
    if trimmed(lines[lineIndex]) ~= "" then
      local footer = trimmed(lines[lineIndex])
      if footer:find("Esc", 1, true) or footer:find("Enter", 1, true) then return footer end
      return nil
    end
  end
  return nil
end

local function collectText(lines, firstOptionIndex)
  local textStartIndex = 1
  for lineIndex = firstOptionIndex - 1, 1, -1 do
    if isMadeOf(lines[lineIndex], ruleCharacter) then
      textStartIndex = lineIndex + 1
      break
    end
  end
  local textLines = {}
  for lineIndex = textStartIndex, firstOptionIndex - 1 do
    local line = lines[lineIndex]
    if isMadeOf(line, dashedRuleCharacter) then
      textLines[#textLines + 1] = { rule = true }
    elseif trimmed(line) ~= "" then
      textLines[#textLines + 1] = { text = trimmed(line) }
    end
  end
  return textLines
end

local function signatureOf(textLines, options)
  local parts = {}
  for _, textLine in ipairs(textLines) do parts[#parts + 1] = textLine.text or "--" end
  for _, option in ipairs(options) do parts[#parts + 1] = option.number .. ". " .. option.label end
  return table.concat(parts, "\n")
end

function promptCapture.capture(paneId)
  local lines = paneLines(paneId)
  if not lines then return nil end
  local cursorIndex = findCursorIndex(lines)
  if not cursorIndex then return nil end
  local options, firstOptionIndex, lastOptionLineIndex = collectOptions(lines, cursorIndex)
  local textLines = collectText(lines, firstOptionIndex)
  return {
    textLines = textLines,
    options = options,
    footer = findFooter(lines, lastOptionLineIndex),
    signature = signatureOf(textLines, options),
  }
end

return promptCapture
