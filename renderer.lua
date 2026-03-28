local M = {}

function M.new(input)
  local data = input.data
  local config = input.config
  local deps = input.deps

  local self = {}

  local function rotate_point(x, y, rx, ry, rot)
    if math.abs(rot) <= 0.001 then
      return x, y
    end

    local angle = math.rad(-rot)
    local cos_a = math.cos(angle)
    local sin_a = math.sin(angle)
    local dx = x - rx
    local dy = y - ry
    local nx = rx + (cos_a * dx) - (sin_a * dy)
    local ny = ry + (sin_a * dx) + (cos_a * dy)
    return nx, ny
  end

  function self.scaled_key_geometry(key)
    local unit = 0.01
    local x = key.x * unit
    local y = -key.y * unit
    local base_w = key.w * unit
    local base_h = key.h * unit
    local scale = config.keycap_scale or 1.0
    local w = base_w * scale
    local h = base_h * scale
    x = x + (base_w - w) * 0.5
    y = y - (base_h - h) * 0.5
    local rx = key.rx * unit
    local ry = -key.ry * unit
    local rot = (key.rot or 0) / 100

    return {
      x = x,
      y = y,
      w = w,
      h = h,
      rx = rx,
      ry = ry,
      rot = rot,
    }
  end

  function self.key_center(geom)
    local cx = geom.x + (geom.w * 0.5)
    local cy = geom.y - (geom.h * 0.5)
    return rotate_point(cx, cy, geom.rx, geom.ry, geom.rot)
  end

  local function scale_geometry(geom, factor)
    return {
      x = geom.x * factor,
      y = geom.y * factor,
      w = geom.w * factor,
      h = geom.h * factor,
      rx = geom.rx * factor,
      ry = geom.ry * factor,
      rot = geom.rot,
    }
  end

  local function key_bounds(geom)
    local corners = {
      { x = geom.x, y = geom.y },
      { x = geom.x + geom.w, y = geom.y },
      { x = geom.x, y = geom.y - geom.h },
      { x = geom.x + geom.w, y = geom.y - geom.h },
    }

    local min_x = nil
    local max_x = nil
    local min_y = nil
    local max_y = nil

    for _, corner in ipairs(corners) do
      local rx, ry = rotate_point(corner.x, corner.y, geom.rx, geom.ry, geom.rot)
      if min_x == nil or rx < min_x then
        min_x = rx
      end
      if max_x == nil or rx > max_x then
        max_x = rx
      end
      if min_y == nil or ry < min_y then
        min_y = ry
      end
      if max_y == nil or ry > max_y then
        max_y = ry
      end
    end

    return {
      min_x = min_x or 0,
      max_x = max_x or 0,
      min_y = min_y or 0,
      max_y = max_y or 0,
    }
  end

  function self.layer_bounds()
    local min_x = nil
    local max_x = nil
    local min_y = nil
    local max_y = nil

    for _, key in ipairs(data.physical) do
      local bounds = key_bounds(self.scaled_key_geometry(key))
      if min_x == nil or bounds.min_x < min_x then
        min_x = bounds.min_x
      end
      if max_x == nil or bounds.max_x > max_x then
        max_x = bounds.max_x
      end
      if min_y == nil or bounds.min_y < min_y then
        min_y = bounds.min_y
      end
      if max_y == nil or bounds.max_y > max_y then
        max_y = bounds.max_y
      end
    end

    return {
      min_x = min_x or 0,
      max_x = max_x or 0,
      min_y = min_y or 0,
      max_y = max_y or 0,
    }
  end

  local function build_highlight_map(entries)
    local highlight_map = {}
    for _, entry in ipairs(entries) do
      for _, key_index in ipairs(entry.key_indices) do
        if highlight_map[key_index] == nil then
          highlight_map[key_index] = entry.color
        end
      end
    end
    return highlight_map
  end

  local function draw_key(index, key, binding, highlight_color)
    local geom = self.scaled_key_geometry(key)
    local x = geom.x
    local y = geom.y
    local w = geom.w
    local h = geom.h
    local rx = geom.rx
    local ry = geom.ry
    local rot = geom.rot

    local tap = "?"
    local hold = nil
    local shifted = nil
    if binding ~= nil and binding.legend ~= nil then
      tap = binding.legend.tap or tap
      hold = binding.legend.hold
      shifted = binding.legend.shifted
    end

    local escaped_tap = deps.tex_keycap_label(tap)
    local escaped_hold = hold and deps.tex_keycap_label(hold) or nil
    local escaped_shifted = shifted and deps.tex_keycap_label(shifted) or nil

    local tap_box = string.format("\\zmkmanualfit{%.4fcm}{%s}", w * 0.84, escaped_tap)
    local hold_box = escaped_hold and string.format("\\zmkmanualfit{%.4fcm}{%s}", w * 0.72, escaped_hold) or nil
    local shifted_box = escaped_shifted and string.format("\\zmkmanualfit{%.4fcm}{%s}", w * 0.72, escaped_shifted) or nil

    local center_x, center_y = self.key_center(geom)
    tex.print(string.format("\\coordinate (zmkkeycenter%d) at (%.4f,%.4f);", index, center_x, center_y))

    local key_style = "zmkmanual/key"
    if highlight_color ~= nil then
      key_style = key_style .. ",draw=" .. highlight_color .. ",fill=" .. highlight_color .. "!12,line width=0.35pt"
    end

    local function emit_nodes(top_left_x, top_left_y)
      local cx = top_left_x + (w * 0.5)
      local cy = top_left_y - (h * 0.5)

      tex.print(string.format(
        "\\node[%s,anchor=north west,minimum width=%.4fcm,minimum height=%.4fcm] (zmkkey%d) at (%.4f,%.4f) {};",
        key_style,
        w,
        h,
        index,
        top_left_x,
        top_left_y
      ))
      tex.print(string.format("\\node[zmkmanual/tap] at (%.4f,%.4f) {%s};", cx, cy, tap_box))

      if hold_box ~= nil and hold_box ~= "" then
        tex.print(string.format("\\node[zmkmanual/hold] at (%.4f,%.4f) {%s};", cx, cy - h * 0.24, hold_box))
      end

      if shifted_box ~= nil and shifted_box ~= "" then
        tex.print(string.format("\\node[zmkmanual/shifted] at (%.4f,%.4f) {%s};", cx, cy + h * 0.24, shifted_box))
      end
    end

    if math.abs(rot) > 0.001 then
      local lx = x - rx
      local ly = y - ry
      tex.print(string.format("\\begin{scope}[shift={(%.4f,%.4f)},rotate=%.2f,transform shape]", rx, ry, -rot))
      emit_nodes(lx, ly)
      tex.print("\\end{scope}")
    else
      emit_nodes(x, y)
    end
  end

  local function draw_overview_key(index, key, layers, overview_scale)
    local geom = scale_geometry(self.scaled_key_geometry(key), overview_scale)
    local x = geom.x
    local y = geom.y
    local w = geom.w
    local h = geom.h
    local rx = geom.rx
    local ry = geom.ry
    local rot = geom.rot

    local line_count = #layers
    local font = line_count <= 4 and "\\scriptsize\\ttfamily" or "\\tiny\\ttfamily"
    local usable_h = h * 0.78
    local line_step = line_count <= 1 and 0 or (usable_h / (line_count - 1))
    if line_step > 0.24 then
      line_step = 0.24
    end

    local function emit_nodes(top_left_x, top_left_y)
      local cx = top_left_x + (w * 0.5)
      local cy = top_left_y - (h * 0.5)
      tex.print(string.format(
        "\\node[zmkmanual/key,anchor=north west,minimum width=%.4fcm,minimum height=%.4fcm] (zmkovkey%d) at (%.4f,%.4f) {};",
        w,
        h,
        index,
        top_left_x,
        top_left_y
      ))

      local top_line_y = cy + ((line_count - 1) * line_step * 0.5)
      for layer_index, layer in ipairs(layers) do
        local binding = layer.bindings[index]
        local label = deps.tex_keycap_label(deps.display_binding_name(binding))
        local ly = top_line_y - ((layer_index - 1) * line_step)
        tex.print(string.format(
          "\\node[font=%s,text=%s,align=center] at (%.4f,%.4f) {\\zmkmanualfit{%.4fcm}{%s}};",
          font,
          deps.layer_color(layer_index),
          cx,
          ly,
          w * 0.82,
          label
        ))
      end
    end

    if math.abs(rot) > 0.001 then
      local lx = x - rx
      local ly = y - ry
      tex.print(string.format("\\begin{scope}[shift={(%.4f,%.4f)},rotate=%.2f,transform shape]", rx, ry, -rot))
      emit_nodes(lx, ly)
      tex.print("\\end{scope}")
    else
      emit_nodes(x, y)
    end
  end

  local function draw_layer_overview_legend(bounds, layers)
    local count = #layers
    if count == 0 then
      return
    end

    local width = bounds.max_x - bounds.min_x
    local columns = count > 8 and 4 or (count > 4 and 3 or (count > 2 and 2 or 1))
    local col_gap = 0.30
    local col_width = (width - ((columns - 1) * col_gap)) / columns
    local swatch_size = 0.16
    local text_offset = 0.28
    local text_width = col_width - text_offset
    if text_width < 1.2 then
      text_width = 1.2
    end

    local title_y = bounds.min_y - 0.30
    tex.print(string.format(
      "\\node[anchor=north west,font=\\scriptsize\\bfseries] at (%.4f,%.4f) {Layer colors};",
      bounds.min_x,
      title_y
    ))

    local list_top = title_y - 0.34
    local column_entries = {}
    for col = 1, columns do
      column_entries[col] = {}
    end

    for index, layer in ipairs(layers) do
      local col = ((index - 1) % columns) + 1
      table.insert(column_entries[col], {
        index = index,
        layer = layer,
      })
    end

    local function estimate_row_height(raw_label)
      local chars_per_line = math.max(10, math.floor(text_width * 6.2))
      local lines = math.max(1, math.ceil(#raw_label / chars_per_line))
      local text_height = 0.10 + (lines * 0.24)
      local swatch_height = swatch_size + 0.03
      if text_height > swatch_height then
        return text_height
      end
      return swatch_height
    end

    for col = 1, columns do
      local x_left = bounds.min_x + ((col - 1) * (col_width + col_gap))
      local cursor_y = list_top

      for _, entry in ipairs(column_entries[col]) do
        local color = deps.layer_color(entry.index)
        local raw_label = tostring(entry.index - 1) .. " " .. deps.layer_display_name(entry.layer)
        local label = deps.tex_escape(raw_label)
        local row_height = estimate_row_height(raw_label)

        tex.print(string.format(
          "\\node[anchor=north west,draw=%s,fill=%s,minimum width=%.4fcm,minimum height=%.4fcm,inner sep=0pt] at (%.4f,%.4f) {};",
          color,
          color,
          swatch_size,
          swatch_size,
          x_left,
          cursor_y - 0.02
        ))
        tex.print(string.format(
          "\\node[anchor=north west,font=\\scriptsize\\ttfamily,text=%s,align=left,text width=%.4fcm] at (%.4f,%.4f) {%s};",
          color,
          text_width,
          x_left + text_offset,
          cursor_y,
          label
        ))

        cursor_y = cursor_y - row_height - 0.10
      end
    end
  end

  function self.print_layer_overview_body()
    local layers = data.layers
    local overview_scale = config.overview_scale or 1.15
    local base_bounds = self.layer_bounds()
    local bounds = {
      min_x = base_bounds.min_x * overview_scale,
      max_x = base_bounds.max_x * overview_scale,
      min_y = base_bounds.min_y * overview_scale,
      max_y = base_bounds.max_y * overview_scale,
    }

    tex.print("\\resizebox{\\textwidth}{!}{%")
    tex.print("\\begin{tikzpicture}[x=1cm,y=1cm]")
    for index, key in ipairs(data.physical) do
      draw_overview_key(index, key, layers, overview_scale)
    end
    draw_layer_overview_legend(bounds, layers)
    tex.print("\\end{tikzpicture}%")
    tex.print("}")
    tex.print("\\par\\medskip")
  end

  function self.print_layer_body(layer, entries, draw_annotations)
    local bounds = self.layer_bounds()
    local highlight_map = build_highlight_map(entries)

    tex.print("\\begin{center}")
    tex.print("\\resizebox{\\textwidth}{!}{%")
    tex.print("\\begin{tikzpicture}[x=1cm,y=1cm]")
    for index, key in ipairs(data.physical) do
      draw_key(index, key, layer.bindings[index], highlight_map[index])
    end

    if draw_annotations ~= nil then
      draw_annotations(entries, bounds, self)
    end

    tex.print("\\end{tikzpicture}%")
    tex.print("}")
    tex.print("\\end{center}")
    tex.print("\\par\\medskip")
  end

  return self
end

return M
