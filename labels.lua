local M = {}

local key_labels = {
  -- Common aliases
  BSPC = "Bsp",
  RET = "Ent",
  RETURN = "Ent",
  ESCAPE = "Esc",
  DELETE = "Del",
  PGDOWN = "PgDn",
  PGUP = "PgUp",
  DOT = ".",
  LT = "<",
  GT = ">",
  LESS = "<",
  GREATER = ">",
  LEFT_PAREN = "(",
  RIGHT_PAREN = ")",
  LEFT_PARENTHESIS = "(",
  RIGHT_PARENTHESIS = ")",
  LEFT_SHIFT = "LSft",
  RIGHT_SHIFT = "RSft",
  LSFT = "LSft",
  RSFT = "RSft",
  LS = "LSft",
  RS = "RSft",
  LEFT_CTRL = "LCtrl",
  RIGHT_CTRL = "RCtrl",
  LCTL = "LCtrl",
  RCTL = "RCtrl",
  LEFT_ALT = "LAlt",
  RIGHT_ALT = "RAlt",
  LEFT_GUI = "LCmd",
  RIGHT_GUI = "RCmd",
  LGUI = "LCmd",
  RGUI = "RCmd",

  -- Canonical labels used in this repo
  SPACE = "Spc",
  ENTER = "Ent",
  TAB = "Tab",
  ESC = "Esc",
  BACKSPACE = "Bsp",
  DEL = "Del",
  LEFT_ARROW = "Left",
  RIGHT_ARROW = "Right",
  UP = "Up",
  DOWN = "Down",
  HOME = "Home",
  END = "End",
  PG_UP = "PgUp",
  PG_DN = "PgDn",
  LSHIFT = "LSft",
  RSHIFT = "RSft",
  LCTRL = "LCtrl",
  RCTRL = "RCtrl",
  LALT = "LAlt",
  RALT = "RAlt",
  LCMD = "LCmd",
  RCMD = "RCmd",
  APOS = "'",
  COMMA = ",",
  PERIOD = ".",
  QUESTION = "?",
  EXCLAMATION = "!",
  SEMICOLON = ";",
  COLON = ":",
  PRCNT = "%",
  ASTRK = "*",
  LBRC = "[",
  RBRC = "]",
  LBKT = "(",
  RBKT = ")",
  LPAR = "(",
  RPAR = ")",
  BSLH = "\\",
  PIPE = "|",
  HASH = "#",
  DLLR = "$",
  AMPS = "&",
  CARET = "^",
  UNDER = "_",
  PLUS = "+",
  KP_MINUS = "-",
  EQUAL = "=",
  AT = "@",
  TILDE = "~",
  GRAVE = "`",
  C_PLAY_PAUSE = "Play",
  C_STOP = "Stop",
  C_PREVIOUS = "Prev",
  C_NEXT = "Next",
  C_VOLUME_UP = "Vol+",
  C_VOLUME_DOWN = "Vol-",
  C_BRIGHTNESS_INC = "Br+",
  C_BRIGHTNESS_DEC = "Br-",
  C_AC_COPY = "Copy",
  C_AC_CUT = "Cut",
  C_AC_PASTE = "Paste",
  C_AC_UNDO = "Undo",
  C_SLEEP = "Sleep",
  C_AL_COFFEE = "Coffee",
  K_MUTE = "Mute",
  PRINTSCREEN = "PrtSc",
}

local movement_labels = {
  MOVE_LEFT = "L",
  MOVE_RIGHT = "R",
  MOVE_UP = "U",
  MOVE_DOWN = "D",
}

local symbol_patterns = {
  { pattern = "%f[%w]Bsp%f[%W]", repl = "\\ensuremath{\\leftarrow}" },
  { pattern = "%f[%w]Backspace%f[%W]", repl = "\\ensuremath{\\leftarrow}" },
  { pattern = "%f[%w]BACKSPACE%f[%W]", repl = "\\ensuremath{\\leftarrow}" },
  { pattern = "%f[%w]Ent%f[%W]", repl = "\\ensuremath{\\hookleftarrow}" },
  { pattern = "%f[%w]Return%f[%W]", repl = "\\ensuremath{\\hookleftarrow}" },
  { pattern = "%f[%w]ENTER%f[%W]", repl = "\\ensuremath{\\hookleftarrow}" },
}

function M.tex_escape(text)
  local map = {
    ["\\"] = "\\textbackslash{}",
    ["{"] = "\\{",
    ["}"] = "\\}",
    ["#"] = "\\#",
    ["$"] = "\\$",
    ["%"] = "\\%",
    ["&"] = "\\&",
    ["_"] = "\\_",
    ["^"] = "\\textasciicircum{}",
    ["~"] = "\\textasciitilde{}",
  }
  return (tostring(text or ""):gsub("[\\{}#$%%&_~^]", map))
end

function M.normalize_display_text(text)
  local normalized = tostring(text or "")
  normalized = normalized:gsub("%f[%w]SPACE%f[%W]", "Spc")
  normalized = normalized:gsub("%f[%w]SPC%f[%W]", "Spc")
  return normalized
end

function M.tex_keycap_label(text)
  local normalized = M.normalize_display_text(text)
  local escaped = M.tex_escape(normalized)
  for _, item in ipairs(symbol_patterns) do
    escaped = escaped:gsub(item.pattern, item.repl)
  end
  return escaped
end

function M.key_label(code)
  if code == nil then
    return "?"
  end
  local mapped = key_labels[code]
  if mapped ~= nil then
    return mapped
  end
  local digit = code:match("^N(%d)$")
  if digit ~= nil then
    return digit
  end
  return code
end

function M.movement_label(code)
  return movement_labels[code or ""]
end

return M
