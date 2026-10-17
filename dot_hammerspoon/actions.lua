local actions = {}

local registeredActions = {}
local modifierSymbols = { cmd = "⌘", ctrl = "⌃", alt = "⌥", shift = "⇧" }

local function shortcutLabel(modifiers, key)
  local symbols = {}
  for _, modifier in ipairs(modifiers) do
    symbols[#symbols + 1] = modifierSymbols[modifier] or modifier
  end
  return table.concat(symbols) .. key:upper()
end

function actions.describe(name, modifiers, key, handler)
  registeredActions[#registeredActions + 1] = {
    name = name,
    shortcut = shortcutLabel(modifiers, key),
    handler = handler,
  }
end

function actions.add(name, handler)
  registeredActions[#registeredActions + 1] = { name = name, shortcut = "", handler = handler }
end

function actions.register(name, modifiers, key, handler)
  actions.describe(name, modifiers, key, handler)
  hs.hotkey.bind(modifiers, key, handler)
end

function actions.all()
  return registeredActions
end

return actions
