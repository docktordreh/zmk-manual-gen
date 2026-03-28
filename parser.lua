local M = {}

local function strip_comments(text)
  local no_block = text:gsub("/%*.-%*/", "")
  local no_line = no_block:gsub("//[^\n]*", "")
  return no_line
end

local function split_tokens(text)
  local tokens = {}
  for token in text:gmatch("[^%s,]+") do
    table.insert(tokens, token)
  end
  return tokens
end

local function parse_int(raw)
  local cleaned = raw:gsub("[()]", "")
  return tonumber(cleaned)
end

local function behavior_call(ref, args)
  return {
    ref = ref,
    args = args,
  }
end

local function parse_calls(text, resolve_arity)
  local tokens = split_tokens(text)
  local calls = {}
  local index = 1

  while index <= #tokens do
    local token = tokens[index]
    if token:sub(1, 1) ~= "&" then
      index = index + 1
    else
      local ref = token:sub(2)
      local arity = resolve_arity(ref, tokens, index)
      local args = {}

      local cursor = index + 1
      while cursor <= #tokens and #args < arity do
        local candidate = tokens[cursor]
        if candidate:sub(1, 1) == "&" then
          break
        end
        table.insert(args, candidate)
        cursor = cursor + 1
      end

      table.insert(calls, behavior_call(ref, args))
      index = cursor
    end
  end

  return calls
end

local function parse_bindings_property(body, resolve_arity)
  local expression = body:match("bindings%s*=%s*([^;]-);")
  if expression == nil then
    return {}
  end

  local calls = {}
  local found_group = false

  for group in expression:gmatch("<([^>]-)>") do
    found_group = true
    local group_calls = parse_calls(group, resolve_arity)
    for _, call in ipairs(group_calls) do
      table.insert(calls, call)
    end
  end

  if not found_group then
    return parse_calls(expression, resolve_arity)
  end

  return calls
end

local function find_named_blocks(text, fail)
  local blocks = {}
  local cursor = 1

  while true do
    local start_idx, brace_idx, name = text:find("([%a_][%w_]*)%s*{", cursor)
    if start_idx == nil then
      break
    end

    local depth = 1
    local walk = brace_idx + 1
    while walk <= #text and depth > 0 do
      local char = text:sub(walk, walk)
      if char == "{" then
        depth = depth + 1
      elseif char == "}" then
        depth = depth - 1
      end
      walk = walk + 1
    end

    if depth ~= 0 then
      fail("unbalanced braces around block '" .. name .. "'")
    end

    local body = text:sub(brace_idx + 1, walk - 2)
    table.insert(blocks, {
      name = name,
      body = body,
    })

    cursor = walk
  end

  return blocks
end

local function parse_behaviors(text, deps)
  local cleaned = strip_comments(text)
  local blocks = {}
  local cursor = 1

  while true do
    local start_idx, brace_idx, alias = cleaned:find("([%a_][%w_]*)%s*:%s*[%a_][%w_]*%s*{", cursor)
    if start_idx == nil then
      break
    end

    local depth = 1
    local walk = brace_idx + 1
    while walk <= #cleaned and depth > 0 do
      local char = cleaned:sub(walk, walk)
      if char == "{" then
        depth = depth + 1
      elseif char == "}" then
        depth = depth - 1
      end
      walk = walk + 1
    end

    if depth ~= 0 then
      deps.fail("unbalanced braces in behaviors block '" .. alias .. "'")
    end

    local body = cleaned:sub(brace_idx + 1, walk - 2)
    local compatible = body:match('compatible%s*=%s*"([^"]+)"')
    local cells_raw = body:match("#binding%-cells%s*=%s*<%s*([%d]+)%s*>")
    local binding_cells = tonumber(cells_raw or "0") or 0
    table.insert(blocks, {
      alias = alias,
      compatible = compatible or "",
      binding_cells = binding_cells,
      body = body,
    })

    cursor = walk
  end

  local arity_map = {}
  for ref, arity in pairs(deps.builtin_arity) do
    arity_map[ref] = arity
  end
  for _, block in ipairs(blocks) do
    arity_map[block.alias] = block.binding_cells
  end

  local behaviors = {}
  for _, block in ipairs(blocks) do
    local function inner_arity(ref)
      return arity_map[ref] or 0
    end

    local bindings = parse_bindings_property(block.body, inner_arity)
    behaviors[block.alias] = {
      compatible = block.compatible,
      binding_cells = block.binding_cells,
      bindings = bindings,
    }
  end

  return behaviors
end

local function parse_layers(text, behavior_arity, deps)
  local cleaned = strip_comments(text)
  local blocks = find_named_blocks(cleaned, deps.fail)
  local keymap_body = nil

  for _, block in ipairs(blocks) do
    if block.name == "keymap" then
      keymap_body = block.body
      break
    end
  end
  if keymap_body == nil then
    deps.fail("cannot find keymap block")
  end

  local layer_blocks = find_named_blocks(keymap_body, deps.fail)
  local layers = {}

  local function arity(ref, tokens, index)
    if behavior_arity[ref] ~= nil then
      return behavior_arity[ref]
    end
    if ref == "bt" then
      local next_token = tokens[index + 1]
      if next_token == "BT_SEL" then
        return 2
      end
      if next_token == "BT_CLR" then
        return 1
      end
      return 1
    end
    return deps.builtin_arity[ref] or 0
  end

  for _, block in ipairs(layer_blocks) do
    local calls = parse_bindings_property(block.body, arity)
    if #calls > 0 then
      local display_name = block.body:match('display%-name%s*=%s*"([^"]+)"')
      table.insert(layers, {
        name = block.name,
        display_name = display_name,
        calls = calls,
      })
    end
  end

  return layers
end

local function parse_physical_keys(text, warn)
  local cleaned = strip_comments(text)
  local keys = {}

  for raw in cleaned:gmatch("<%s*&key_physical_attrs%s+([^>]+)>") do
    local values = {}
    for token in raw:gmatch("[^%s]+") do
      local parsed = parse_int(token)
      if parsed ~= nil then
        table.insert(values, parsed)
      end
    end

    if #values == 7 then
      table.insert(keys, {
        w = values[1],
        h = values[2],
        x = values[3],
        y = values[4],
        rot = values[5],
        rx = values[6],
        ry = values[7],
      })
    else
      warn("skipping malformed key_physical_attrs tuple: '" .. raw .. "'")
    end
  end

  return keys
end

local function resolve_call(call, behaviors, deps)
  local ref = call.ref

  if ref == "none" then
    return { kind = "none", call = call, legend = { tap = "None" } }
  end
  if ref == "trans" then
    return { kind = "transparent", call = call, legend = { tap = "Trns" } }
  end
  if ref == "lt" then
    return {
      kind = "hold_tap",
      call = call,
      legend = {
        tap = deps.key_label(call.args[2] or "?"),
        hold = "MO(" .. tostring(call.args[1] or "?") .. ")",
      },
    }
  end

  local behavior = behaviors[ref]
  if behavior ~= nil and behavior.compatible ~= nil then
    if behavior.compatible == "zmk,behavior-hold-tap" then
      local hold_ref = behavior.bindings[1] and behavior.bindings[1].ref or "hold"
      local tap_ref = behavior.bindings[2] and behavior.bindings[2].ref or "tap"
      local hold_call = behavior_call(hold_ref, { call.args[1] })
      local tap_call = behavior_call(tap_ref, { call.args[2] })
      return {
        kind = "hold_tap",
        call = call,
        legend = {
          tap = deps.call_label(tap_call),
          hold = deps.call_label(hold_call),
        },
      }
    end

    if behavior.compatible == "zmk,behavior-tap-dance" then
      local first = behavior.bindings[1] and deps.call_label(behavior.bindings[1]) or "Tap1"
      local second = behavior.bindings[2] and deps.call_label(behavior.bindings[2]) or "Tap2"
      return {
        kind = "tap_dance",
        call = call,
        legend = {
          tap = first,
          hold = second,
        },
      }
    end

    if behavior.compatible == "zmk,behavior-mod-morph" then
      local base = behavior.bindings[1] and deps.call_label(behavior.bindings[1]) or "Base"
      local shifted = behavior.bindings[2] and deps.call_label(behavior.bindings[2]) or "Shift"
      return {
        kind = "mod_morph",
        call = call,
        legend = {
          tap = base,
          shifted = shifted,
        },
      }
    end
  end

  return {
    kind = "simple",
    call = call,
    legend = {
      tap = deps.call_label(call),
    },
  }
end

local function resolve_layers(parsed_layers, behaviors, deps)
  local layers = {}
  for index, layer in ipairs(parsed_layers) do
    local bindings = {}
    for _, call in ipairs(layer.calls) do
      table.insert(bindings, resolve_call(call, behaviors, deps))
    end

    table.insert(layers, {
      name = layer.name,
      display_name = layer.display_name,
      index = index,
      bindings = bindings,
    })
  end
  return layers
end

function M.parse_and_resolve(input)
  local behaviors = parse_behaviors(input.behavior_text, input)
  local behavior_arity = {}
  for alias, behavior in pairs(behaviors) do
    behavior_arity[alias] = behavior.binding_cells
  end

  local parsed_layers = parse_layers(input.keymap_text, behavior_arity, input)
  local resolved_layers = resolve_layers(parsed_layers, behaviors, input)
  local physical = parse_physical_keys(input.layout_text, input.warn)

  return {
    behaviors = behaviors,
    layers = resolved_layers,
    physical = physical,
  }
end

return M
