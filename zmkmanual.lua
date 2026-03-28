local M = {}

local function load_local_module(file_name)
  local module_path = kpse.find_file(file_name, "tex")
  if module_path == nil then
    module_path = file_name
  end
  local ok, module_or_err = pcall(dofile, module_path)
  if not ok then
    error("zmkmanual: failed to load module '" .. file_name .. "': " .. tostring(module_or_err))
  end
  return module_or_err
end

local labels = load_local_module("labels.lua")
local parser = load_local_module("parser.lua")
local renderer_module = load_local_module("renderer.lua")
local annotations_module = load_local_module("annotations.lua")

local tex_escape = labels.tex_escape
local tex_keycap_label = labels.tex_keycap_label
local key_label = labels.key_label
local movement_label = labels.movement_label
local normalize_display_text = labels.normalize_display_text

local state = {
  loaded = false,
  config = {},
  data = nil,
}

local builtin_arity = {
  kp = 1,
  none = 0,
  trans = 0,
  to = 1,
  mo = 1,
  lt = 2,
  mmv = 1,
  msc = 1,
  mkp = 1,
  out = 1,
  studio_unlock = 0,
}

local COMPLEXITY_THRESHOLD = 3
local ANNOTATION_COLORS = {
  "blue",
  "red",
  "teal",
  "orange",
  "violet",
  "olive",
  "magenta",
  "brown",
  "cyan",
}

local LAYER_OVERVIEW_COLORS = {
  "blue!85!black",
  "red!85!black",
  "teal!85!black",
  "orange!90!black",
  "violet!85!black",
  "olive!85!black",
  "magenta!85!black",
  "brown!85!black",
  "cyan!70!black",
}

local function fail(message)
  error("zmkmanual: " .. message)
end

local function warn(message)
  texio.write_nl("term and log", "zmkmanual warning: " .. message)
end

local function read_file(path)
  local file, open_err = io.open(path, "r")
  if file == nil then
    fail("cannot open file '" .. path .. "': " .. tostring(open_err))
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function behavior_call(ref, args)
  return {
    ref = ref,
    args = args,
  }
end

local function call_label(call)
  local ref = call.ref
  local args = call.args

  if ref == "kp" then
    return key_label(args[1])
  end
  if ref == "none" then
    return "None"
  end
  if ref == "trans" then
    return "Trns"
  end
  if ref == "mo" then
    return "MO(" .. tostring(args[1] or "?") .. ")"
  end
  if ref == "to" then
    return "TO(" .. tostring(args[1] or "?") .. ")"
  end
  if ref == "lt" then
    local layer = tostring(args[1] or "?")
    local tap = key_label(args[2] or "?")
    return "LT(" .. layer .. ")/" .. tap
  end
  if ref == "bt" then
    return "BT " .. table.concat(args, " ")
  end
  if ref == "mkp" then
    return tostring(args[1] or "MKP")
  end
  if ref == "msc" then
    local dir = movement_label(args[1]) or tostring(args[1] or "")
    return "Scr" .. dir
  end
  if ref == "mmv" then
    local dir = movement_label(args[1]) or tostring(args[1] or "")
    return "Ms" .. dir
  end
  if ref == "out" then
    return "OUT " .. tostring(args[1] or "")
  end
  if ref == "studio_unlock" then
    return "Studio"
  end

  if #args == 0 then
    return ref
  end
  return ref .. " " .. table.concat(args, " ")
end

local function call_with_single_arg(ref, value)
  if value == nil then
    return behavior_call(ref, {})
  end
  return behavior_call(ref, { value })
end

local function format_layer_ref(raw)
  local fallback = tostring(raw or "?")
  local idx = tonumber(raw)
  if idx == nil then
    return fallback
  end

  local normalized = math.floor(idx)
  local layers = state.data and state.data.layers or nil
  if layers == nil then
    return tostring(normalized)
  end

  local layer = layers[normalized + 1]
  if layer == nil then
    return tostring(normalized)
  end

  local label = layer.display_name or layer.name
  if label == nil or label == "" then
    return tostring(normalized)
  end

  return tostring(normalized) .. " (" .. label .. ")"
end

local function complexity_of_call(call, seen)
  local ref = call.ref

  if ref == "kp" or ref == "none" or ref == "trans" then
    return 1
  end
  if ref == "mo" or ref == "to" then
    return 1
  end
  if ref == "bt" or ref == "out" or ref == "mkp" or ref == "mmv" or ref == "msc" or ref == "studio_unlock" then
    return 1
  end
  if ref == "lt" then
    return 2
  end

  local behavior = state.data and state.data.behaviors and state.data.behaviors[ref] or nil
  if behavior == nil then
    return 1
  end

  local next_seen = {}
  for key, value in pairs(seen or {}) do
    next_seen[key] = value
  end
  if next_seen[ref] then
    return 1
  end
  next_seen[ref] = true

  if behavior.compatible == "zmk,behavior-hold-tap" then
    local hold_ref = behavior.bindings[1] and behavior.bindings[1].ref or "hold"
    local tap_ref = behavior.bindings[2] and behavior.bindings[2].ref or "tap"
    local hold_score = complexity_of_call(call_with_single_arg(hold_ref, call.args[1]), next_seen)
    local tap_score = complexity_of_call(call_with_single_arg(tap_ref, call.args[2]), next_seen)
    return hold_score + tap_score
  end

  if behavior.compatible == "zmk,behavior-tap-dance" then
    local total = 0
    for _, nested in ipairs(behavior.bindings) do
      total = total + complexity_of_call(nested, next_seen)
    end
    if total == 0 then
      return 1
    end
    return total
  end

  if behavior.compatible == "zmk,behavior-mod-morph" then
    local base_score = behavior.bindings[1] and complexity_of_call(behavior.bindings[1], next_seen) or 1
    local shifted_score = behavior.bindings[2] and complexity_of_call(behavior.bindings[2], next_seen) or 1
    return base_score + shifted_score
  end

  return 1
end

local function has_layer_change_call(call, seen)
  local ref = call.ref
  if ref == "mo" or ref == "to" or ref == "lt" then
    return true
  end

  local behavior = state.data and state.data.behaviors and state.data.behaviors[ref] or nil
  if behavior == nil then
    return false
  end

  local next_seen = {}
  for key, value in pairs(seen or {}) do
    next_seen[key] = value
  end
  if next_seen[ref] then
    return false
  end
  next_seen[ref] = true

  if behavior.compatible == "zmk,behavior-hold-tap" then
    local hold_ref = behavior.bindings[1] and behavior.bindings[1].ref or "hold"
    local tap_ref = behavior.bindings[2] and behavior.bindings[2].ref or "tap"
    return has_layer_change_call(call_with_single_arg(hold_ref, call.args[1]), next_seen)
      or has_layer_change_call(call_with_single_arg(tap_ref, call.args[2]), next_seen)
  end

  if behavior.compatible == "zmk,behavior-tap-dance" or behavior.compatible == "zmk,behavior-mod-morph" then
    for _, nested in ipairs(behavior.bindings) do
      if has_layer_change_call(nested, next_seen) then
        return true
      end
    end
  end

  return false
end

local function describe_call(call, seen)
  local ref = call.ref
  local args = call.args

  if ref == "kp" then
    return "Tap key " .. key_label(args[1])
  end
  if ref == "none" then
    return "No action"
  end
  if ref == "trans" then
    return "Transparent to lower layer"
  end
  if ref == "mo" then
    return "Momentary layer " .. format_layer_ref(args[1]) .. " while held"
  end
  if ref == "to" then
    return "Switch to layer " .. format_layer_ref(args[1])
  end
  if ref == "lt" then
    return "Layer-tap: tap " .. key_label(args[2] or "?") .. ", hold for layer " .. format_layer_ref(args[1])
  end
  if ref == "mmv" then
    return "Mouse move " .. tostring(args[1] or "")
  end
  if ref == "msc" then
    return "Mouse scroll " .. tostring(args[1] or "")
  end
  if ref == "mkp" then
    return "Mouse button " .. tostring(args[1] or "")
  end
  if ref == "bt" then
    return "Bluetooth action " .. table.concat(args, " ")
  end
  if ref == "out" then
    return "Output action " .. table.concat(args, " ")
  end
  if ref == "studio_unlock" then
    return "Unlock ZMK Studio"
  end

  local behavior = state.data and state.data.behaviors and state.data.behaviors[ref] or nil
  if behavior == nil then
    return "Custom action " .. call_label(call)
  end

  local next_seen = {}
  for key, value in pairs(seen or {}) do
    next_seen[key] = value
  end
  if next_seen[ref] then
    return "Recursive action " .. ref
  end
  next_seen[ref] = true

  if behavior.compatible == "zmk,behavior-hold-tap" then
    local hold_ref = behavior.bindings[1] and behavior.bindings[1].ref or "hold"
    local tap_ref = behavior.bindings[2] and behavior.bindings[2].ref or "tap"
    local hold_desc = describe_call(call_with_single_arg(hold_ref, call.args[1]), next_seen)
    local tap_desc = describe_call(call_with_single_arg(tap_ref, call.args[2]), next_seen)
    return "Hold-tap: " .. tap_desc .. "; hold: " .. hold_desc
  end

  if behavior.compatible == "zmk,behavior-tap-dance" then
    local parts = {}
    for idx, nested in ipairs(behavior.bindings) do
      table.insert(parts, "tap " .. tostring(idx) .. ": " .. describe_call(nested, next_seen))
    end
    if #parts == 0 then
      return "Tap-dance"
    end
    return "Tap-dance: " .. table.concat(parts, "; ")
  end

  if behavior.compatible == "zmk,behavior-mod-morph" then
    local base_desc = behavior.bindings[1] and describe_call(behavior.bindings[1], next_seen) or "base action"
    local shifted_desc = behavior.bindings[2] and describe_call(behavior.bindings[2], next_seen) or "shift action"
    return "Mod-morph: default " .. base_desc .. "; with shift " .. shifted_desc
  end

  return "Behavior " .. ref .. " (" .. behavior.compatible .. ")"
end

local function display_binding_name(binding)
  if binding == nil then
    return "?"
  end

  local legend = binding.legend or {}
  local parts = {}
  if legend.tap ~= nil and legend.tap ~= "" then
    table.insert(parts, legend.tap)
  end
  if legend.hold ~= nil and legend.hold ~= "" then
    table.insert(parts, legend.hold)
  end
  if legend.shifted ~= nil and legend.shifted ~= "" then
    table.insert(parts, legend.shifted)
  end

  if #parts > 0 then
    return normalize_display_text(table.concat(parts, " "))
  end

  if binding.call ~= nil then
    return normalize_display_text(call_label(binding.call))
  end

  return "?"
end

local function layer_color(index)
  return LAYER_OVERVIEW_COLORS[((index - 1) % #LAYER_OVERVIEW_COLORS) + 1]
end

local function layer_display_name(layer)
  if layer == nil then
    return "?"
  end
  return layer.display_name or layer.name or "?"
end

local function ensure_loaded()
  if not state.loaded or state.data == nil then
    fail("run \\zmkLoadConfig first")
  end
end

local function strict_or_warn(message)
  if state.config.strict then
    fail(message)
  end
  warn(message)
end

local function new_renderer()
  return renderer_module.new({
    data = state.data,
    config = state.config,
    deps = {
      tex_escape = tex_escape,
      tex_keycap_label = tex_keycap_label,
      layer_color = layer_color,
      layer_display_name = layer_display_name,
      display_binding_name = display_binding_name,
    },
  })
end

local function print_layer_body(layer)
  local entries = annotations_module.collect_complex_entries(layer, {
    complexity_of_call = complexity_of_call,
    has_layer_change_call = has_layer_change_call,
    display_binding_name = display_binding_name,
    describe_call = describe_call,
    complexity_threshold = COMPLEXITY_THRESHOLD,
    colors = ANNOTATION_COLORS,
  })

  local renderer = new_renderer()
  renderer.print_layer_body(layer, entries, function(current_entries, bounds, renderer_obj)
    annotations_module.draw_layer_annotations(current_entries, bounds, {
      physical = state.data.physical,
      scaled_key_geometry = renderer_obj.scaled_key_geometry,
      key_center = renderer_obj.key_center,
      tex_keycap_label = tex_keycap_label,
    })
  end)
end

local function ref_description(ref)
  local descriptions = {
    kp = "Key press",
    none = "No-op",
    trans = "Transparent",
    lt = "Layer-tap",
    mo = "Momentary layer",
    to = "Layer jump",
    bt = "Bluetooth",
    out = "Output switch",
    mmv = "Mouse move",
    msc = "Mouse scroll",
    mkp = "Mouse click",
    studio_unlock = "ZMK Studio",
  }

  if descriptions[ref] ~= nil then
    return descriptions[ref]
  end
  local behavior = state.data.behaviors[ref]
  if behavior ~= nil then
    return behavior.compatible
  end
  return "Custom/unknown"
end

local function count_refs()
  local counts = {}
  for _, layer in ipairs(state.data.layers) do
    for _, binding in ipairs(layer.bindings) do
      local ref = binding.call and binding.call.ref or "?"
      counts[ref] = (counts[ref] or 0) + 1
    end
  end
  return counts
end

function M.load_config(opts)
  local strict = opts.strict == true or opts.strict == "true"
  local keycap_scale = tonumber(opts.keycap_scale or "1.0")
  local overview_scale = tonumber(opts.overview_scale or "1.15")
  if keycap_scale == nil or keycap_scale <= 0 then
    fail("option 'keycap_scale' must be a positive number")
  end
  if overview_scale == nil or overview_scale <= 0 then
    fail("option 'overview_scale' must be a positive number")
  end

  local config = {
    keyboard = opts.keyboard or "",
    keymap = trim(opts.keymap or ""),
    layout = trim(opts.layout or ""),
    behaviors = trim(opts.behaviors or ""),
    keycap_scale = keycap_scale,
    overview_scale = overview_scale,
    strict = strict,
  }

  if config.keymap == "" then
    fail("option 'keymap' is required")
  end
  if config.layout == "" then
    fail("option 'layout' is required")
  end
  if config.behaviors == "" then
    fail("option 'behaviors' is required")
  end

  local keymap_text = read_file(config.keymap)
  local layout_text = read_file(config.layout)
  local behavior_text = read_file(config.behaviors)

  local parsed = parser.parse_and_resolve({
    keymap_text = keymap_text,
    layout_text = layout_text,
    behavior_text = behavior_text,
    builtin_arity = builtin_arity,
    key_label = key_label,
    call_label = call_label,
    warn = warn,
    fail = fail,
  })

  local behaviors = parsed.behaviors
  local resolved_layers = parsed.layers
  local physical = parsed.physical

  if #resolved_layers == 0 then
    fail("no layers parsed from keymap")
  end
  if #physical == 0 then
    fail("no physical keys parsed from layout")
  end

  for _, layer in ipairs(resolved_layers) do
    if #layer.bindings ~= #physical then
      local mismatch = "layer '"
        .. layer.name
        .. "' has "
        .. tostring(#layer.bindings)
        .. " bindings but layout has "
        .. tostring(#physical)
        .. " keys"
      if config.strict then
        fail(mismatch)
      else
        warn(mismatch)
      end
    end
  end

  state.config = config
  state.data = {
    layers = resolved_layers,
    physical = physical,
    behaviors = behaviors,
    combos = {},
    macros = {},
  }
  state.loaded = true

  texio.write_nl(
    "term and log",
    "zmkmanual: loaded "
      .. tostring(#resolved_layers)
      .. " layers, "
      .. tostring(#physical)
      .. " physical keys"
  )
end

function M.print_layer(layer_name)
  ensure_loaded()
  for _, layer in ipairs(state.data.layers) do
    if layer.name == layer_name or layer.display_name == layer_name then
      tex.print("\\subsection*{Layer " .. tex_escape(layer.display_name or layer.name) .. "}")
      print_layer_body(layer)
      return
    end
  end
  strict_or_warn("layer not found: " .. tostring(layer_name))
end

function M.print_layer_overview()
  ensure_loaded()
  tex.print("\\subsection*{All Layers Overlay}")
  local renderer = new_renderer()
  renderer.print_layer_overview_body()
end

function M.print_all_layers()
  ensure_loaded()
  for _, layer in ipairs(state.data.layers) do
    tex.print("\\subsection*{Layer " .. tex_escape(layer.display_name or layer.name) .. "}")
    print_layer_body(layer)
  end
end

function M.print_legend()
  ensure_loaded()
  local counts = count_refs()
  local refs = {}
  for ref, _ in pairs(counts) do
    table.insert(refs, ref)
  end
  table.sort(refs)

  tex.print("\\section*{Behavior Index}")
  tex.print("\\begin{tabular}{lll}")
  tex.print("Ref & Count & Meaning\\\\")
  tex.print("\\hline")
  for _, ref in ipairs(refs) do
    tex.print(
      tex_escape(ref)
        .. " & "
        .. tostring(counts[ref])
        .. " & "
        .. tex_escape(ref_description(ref))
        .. "\\\\"
    )
  end
  tex.print("\\end{tabular}")
end

function M.print_combos()
  ensure_loaded()
  tex.print("\\section*{Combos}")
  if #state.data.combos == 0 then
    tex.print("None defined in parsed sources.\\par")
    return
  end
end

function M.print_macros()
  ensure_loaded()
  tex.print("\\section*{Macros}")
  if #state.data.macros == 0 then
    tex.print("None defined in parsed sources.\\par")
    return
  end
end

return M
