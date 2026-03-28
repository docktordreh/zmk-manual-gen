local M = {}

function M.collect_complex_entries(layer, opts)
  local entries_by_key = {}
  local entries = {}

  for index, binding in ipairs(layer.bindings) do
    local call = binding.call
    if call ~= nil then
      local complexity = opts.complexity_of_call(call, {})
      local has_layer_change = opts.has_layer_change_call(call, {})
      if complexity >= opts.complexity_threshold or has_layer_change then
        local summary = opts.display_binding_name(binding)
        local description = opts.describe_call(call, {})
        local key = summary .. "\31" .. description

        local entry = entries_by_key[key]
        if entry == nil then
          entry = {
            summary = summary,
            description = description,
            key_indices = {},
            center_y_total = 0,
          }
          entries_by_key[key] = entry
          table.insert(entries, entry)
        end

        table.insert(entry.key_indices, index)
      end
    end
  end

  for idx, entry in ipairs(entries) do
    entry.color = opts.colors[((idx - 1) % #opts.colors) + 1]
  end

  return entries
end

function M.draw_layer_annotations(entries, bounds, opts)
  if #entries == 0 then
    return
  end

  for _, entry in ipairs(entries) do
    local x_total = 0
    local y_total = 0
    local top_y = nil
    for _, key_index in ipairs(entry.key_indices) do
      local geom = opts.scaled_key_geometry(opts.physical[key_index])
      local center_x, center_y = opts.key_center(geom)
      x_total = x_total + center_x
      y_total = y_total + center_y
      if top_y == nil or center_y > top_y then
        top_y = center_y
      end
    end
    entry.center_x = x_total / #entry.key_indices
    entry.center_y = y_total / #entry.key_indices
    entry.top_y = top_y or entry.center_y
  end

  local width = bounds.max_x - bounds.min_x
  local mid_x = (bounds.min_x + bounds.max_x) * 0.5
  local column_gap = 0.45
  local legend_top = bounds.min_y - 0.30

  local left_entries = {}
  local right_entries = {}
  for _, entry in ipairs(entries) do
    if entry.center_x < mid_x then
      table.insert(left_entries, entry)
    else
      table.insert(right_entries, entry)
    end
  end

  table.sort(left_entries, function(left, right)
    if math.abs(left.top_y - right.top_y) > 0.0001 then
      return left.top_y > right.top_y
    end
    return left.center_x < right.center_x
  end)
  table.sort(right_entries, function(left, right)
    if math.abs(left.top_y - right.top_y) > 0.0001 then
      return left.top_y > right.top_y
    end
    return left.center_x < right.center_x
  end)

  local has_both_sides = #left_entries > 0 and #right_entries > 0

  local col_width
  if has_both_sides then
    col_width = math.max(3.9, ((width - column_gap) / 2) - 0.2)
  else
    col_width = math.max(6.0, math.min(10.0, width - 0.3))
  end

  tex.print(string.format(
    "\\node[anchor=north west,font=\\scriptsize\\bfseries] at (%.4f,%.4f) {Legend};",
    bounds.min_x,
    legend_top
  ))

  local list_top = legend_top - 0.45

  local function estimate_box_height(raw_text)
    local chars_per_line = math.max(18, math.floor(col_width * 6.4))
    local text_len = #raw_text
    local lines = 1
    if text_len > 0 then
      lines = math.ceil(text_len / chars_per_line)
    end
    return 0.20 + (lines * 0.30)
  end

  local node_index = 0
  local function render_column(column_entries, x_left)
    if #column_entries == 0 then
      return
    end

    local cursor_y = list_top

    for _, entry in ipairs(column_entries) do
      node_index = node_index + 1
      local suffix = #entry.key_indices > 1 and (" (x" .. tostring(#entry.key_indices) .. ")") or ""
      local raw_note = entry.description .. suffix
      local note_text = opts.tex_keycap_label(raw_note)
      local node_name = "zmkann" .. tostring(node_index)

      tex.print(string.format(
        "\\node[anchor=north west,draw=%s,fill=%s!10,rounded corners=1pt,inner sep=2pt,align=left,text width=%.4fcm,font=\\scriptsize\\ttfamily] (%s) at (%.4f,%.4f) {%s};",
        entry.color,
        entry.color,
        col_width,
        node_name,
        x_left,
        cursor_y,
        note_text
      ))

      for _, key_index in ipairs(entry.key_indices) do
        tex.print(string.format("\\draw[%s,line width=0.30pt] (%s.north) -- (zmkkeycenter%d);", entry.color, node_name, key_index))
      end

      cursor_y = cursor_y - estimate_box_height(raw_note) - 0.12
    end
  end

  if has_both_sides then
    render_column(left_entries, bounds.min_x)
    render_column(right_entries, bounds.min_x + col_width + column_gap)
  elseif #left_entries > 0 then
    render_column(left_entries, bounds.min_x)
  else
    render_column(right_entries, bounds.min_x)
  end
end

return M
