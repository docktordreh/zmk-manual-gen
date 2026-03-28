local M = {}

local SIMPLE_SUPPORTED_REFS = {
  kp = true,
  none = true,
  trans = true,
  to = true,
  mo = true,
  lt = true,
  bt = true,
  mmv = true,
  msc = true,
  mkp = true,
  out = true,
  studio_unlock = true,
}

local function emit_soft_warning(deps, message)
  if deps.soft_warn ~= nil then
    deps.soft_warn(message)
    return
  end
  deps.warn(message)
end

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

local function behavior_call(ref, args, meta)
  return {
    ref = ref,
    args = args,
    raw = meta and meta.raw or nil,
    expected_arity = meta and meta.expected_arity or nil,
    missing_args = meta and meta.missing_args or false,
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

      local raw_tokens = { token }
      for _, arg in ipairs(args) do
        table.insert(raw_tokens, arg)
      end
      table.insert(calls, behavior_call(ref, args, {
        raw = table.concat(raw_tokens, " "),
        expected_arity = arity,
        missing_args = #args < arity,
      }))
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

local function parse_int_list(raw, fail, context)
  local values = {}
  for token in raw:gmatch("[^%s]+") do
    local parsed = parse_int(token)
    if parsed == nil then
      fail("invalid integer token '" .. token .. "' in " .. context)
    end
    table.insert(values, parsed)
  end
  return values
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

local function parse_position_map(text, keyboard, deps)
  local cleaned = strip_comments(text)
  local top_blocks = find_named_blocks(cleaned, deps.fail)
  local map_root = nil

  for _, block in ipairs(top_blocks) do
    if block.name == "keypad_position_map" then
      map_root = block
      break
    end
  end

  if map_root == nil then
    return nil
  end

  local map_blocks = find_named_blocks(map_root.body, deps.fail)
  local candidates = {}

  for _, block in ipairs(map_blocks) do
    local positions_expr = block.body:match("positions%s*=%s*<([^>]-)>")
    if positions_expr ~= nil then
      table.insert(candidates, {
        name = block.name,
        positions = parse_int_list(positions_expr, deps.fail, "position map '" .. block.name .. "'"),
      })
    end
  end

  if #candidates == 0 then
    emit_soft_warning(deps, "keypad_position_map found but no positions list detected")
    return nil
  end

  if keyboard ~= nil and keyboard ~= "" then
    for _, candidate in ipairs(candidates) do
      if candidate.name == keyboard then
        return candidate.positions
      end
    end
    emit_soft_warning(
      deps,
      "position map for keyboard '" .. keyboard .. "' not found; using '" .. candidates[1].name .. "'"
    )
  elseif #candidates > 1 then
    emit_soft_warning(deps, "multiple position maps detected; using '" .. candidates[1].name .. "'")
  end

  return candidates[1].positions
end

local function apply_position_map(physical, positions, deps)
  if positions == nil then
    return physical
  end

  if #positions ~= #physical then
    deps.fail(
      "position map has " .. tostring(#positions) .. " entries but layout has " .. tostring(#physical) .. " keys"
    )
  end

  local remapped = {}
  local used = {}

  for logical_index, physical_index in ipairs(positions) do
    if physical_index ~= math.floor(physical_index) then
      deps.fail("position map entry at index " .. tostring(logical_index) .. " is not an integer")
    end
    if physical_index < 0 or physical_index >= #physical then
      deps.fail(
        "position map entry at index "
          .. tostring(logical_index)
          .. " is out of range: "
          .. tostring(physical_index)
      )
    end
    if used[physical_index] then
      deps.fail("position map uses duplicate physical index " .. tostring(physical_index))
    end

    local mapped = physical[physical_index + 1]
    if mapped == nil then
      deps.fail("position map references missing physical index " .. tostring(physical_index))
    end

    used[physical_index] = true
    remapped[logical_index] = mapped
  end

  return remapped
end

local function parse_combos(text, behavior_arity, deps)
  local cleaned = strip_comments(text)
  local top_blocks = find_named_blocks(cleaned, deps.fail)
  local combos_block = nil

  for _, block in ipairs(top_blocks) do
    if block.name == "combos" then
      combos_block = block
      break
    end
  end

  if combos_block == nil then
    return {}
  end

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

  local combo_blocks = find_named_blocks(combos_block.body, deps.fail)
  local parsed = {}

  for _, block in ipairs(combo_blocks) do
    local key_positions_expr = block.body:match("key%-positions%s*=%s*<([^>]-)>")
    if key_positions_expr ~= nil then
      local binding_calls = parse_bindings_property(block.body, arity)
      if #binding_calls == 0 then
        emit_soft_warning(deps, "combo '" .. block.name .. "' has no bindings; skipping")
      else
        if #binding_calls > 1 then
          emit_soft_warning(deps, "combo '" .. block.name .. "' has multiple bindings; using first")
        end

        local positions = parse_int_list(key_positions_expr, deps.fail, "combo '" .. block.name .. "' key-positions")
        local layers = {}
        local layers_expr = block.body:match("layers%s*=%s*<([^>]-)>")
        if layers_expr ~= nil then
          for token in layers_expr:gmatch("[^%s]+") do
            local parsed_layer = parse_int(token)
            if parsed_layer ~= nil then
              table.insert(layers, tostring(parsed_layer))
            else
              table.insert(layers, token)
            end
          end
        end

        table.insert(parsed, {
          name = block.name,
          positions = positions,
          layers = layers,
          call = binding_calls[1],
        })
      end
    end
  end

  table.sort(parsed, function(left, right)
    return left.name < right.name
  end)

  return parsed
end

local function parse_physical_keys(text, deps)
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
      emit_soft_warning(deps, "skipping malformed key_physical_attrs tuple: '" .. raw .. "'")
    end
  end

  return keys
end

local function resolve_call(call, behaviors, deps)
  local ref = call.ref

  local function unknown(reason)
    local raw = call.raw or ("&" .. ref .. (next(call.args) and (" " .. table.concat(call.args, " ")) or ""))
    emit_soft_warning(deps, "unsupported binding '" .. raw .. "': " .. reason)
    return {
      kind = "unknown",
      call = call,
      legend = {
        tap = "?",
      },
      raw = raw,
      reason = reason,
    }
  end

  if call.missing_args then
    local expected = tostring(call.expected_arity or 0)
    local got = tostring(#call.args)
    return unknown("expected " .. expected .. " argument(s), got " .. got)
  end

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

    if behavior.compatible == "zmk,behavior-macro" then
      return {
        kind = "simple",
        call = call,
        legend = {
          tap = deps.call_label(call),
        },
      }
    end

    return unknown("behavior compatible '" .. behavior.compatible .. "' not yet supported")
  end

  if not SIMPLE_SUPPORTED_REFS[ref] then
    return unknown("unknown behavior reference")
  end

  return {
    kind = "simple",
    call = call,
    legend = {
      tap = deps.call_label(call),
    },
  }
end

local function resolve_combos(parsed_combos, behaviors, deps)
  local combos = {}

  for _, combo in ipairs(parsed_combos) do
    table.insert(combos, {
      name = combo.name,
      positions = combo.positions,
      layers = combo.layers,
      binding = resolve_call(combo.call, behaviors, deps),
    })
  end

  return combos
end

local function parse_macros(behaviors)
  local macros = {}

  for alias, behavior in pairs(behaviors) do
    if behavior.compatible == "zmk,behavior-macro" then
      table.insert(macros, {
        name = alias,
        steps = behavior.bindings,
      })
    end
  end

  table.sort(macros, function(left, right)
    return left.name < right.name
  end)

  return macros
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
  local parsed_combos = parse_combos(input.keymap_text, behavior_arity, input)
  local resolved_layers = resolve_layers(parsed_layers, behaviors, input)
  local physical = parse_physical_keys(input.layout_text, input)
  local positions = parse_position_map(input.layout_text, input.keyboard, input)
  local mapped_physical = apply_position_map(physical, positions, input)
  local combos = resolve_combos(parsed_combos, behaviors, input)
  local macros = parse_macros(behaviors)

  return {
    behaviors = behaviors,
    layers = resolved_layers,
    physical = mapped_physical,
    position_map = positions,
    combos = combos,
    macros = macros,
  }
end

return M
