local actions = require("actions")

local palette = {}

local actionChooser

local function runChoice(choice)
  if not choice then return end
  local action = actions.all()[choice.actionIndex]
  if action then action.handler() end
end

function palette.show()
  if not actionChooser then
    actionChooser = hs.chooser.new(runChoice)
    actionChooser:placeholderText("Run an action")
  end
  local choices = {}
  for actionIndex, action in ipairs(actions.all()) do
    choices[#choices + 1] = { text = action.name, subText = action.shortcut, actionIndex = actionIndex }
  end
  actionChooser:choices(choices)
  actionChooser:query("")
  actionChooser:show()
end

return palette
