local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

local spaces = {}
local space_brackets = {}
local space_paddings = {}
local space_popups = {}
local workspace_order = {}
local refresh_generation = 0
local refresh_workspaces
local fixed_workspaces = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "Z", "X", "C", "V", "B", "N", "M" }

local letter_keyboard_rank = { Z = 10, X = 11, C = 12, V = 13, B = 14, N = 15, M = 16 }
local ignored_apps = { Finder = true }

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_quote(value)
  local s = trim(value)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function workspace_key(value)
  local k = trim(value)
  if k == "" then return nil end
  return k
end

local function parse_lines(output)
  local result = {}
  for line in tostring(output or ""):gmatch("[^\r\n]+") do
    local value = trim(line)
    if value ~= "" then
      table.insert(result, value)
    end
  end
  return result
end

local function list_equals(left, right)
  if #left ~= #right then return false end
  for i = 1, #left do
    if left[i] ~= right[i] then return false end
  end
  return true
end

local function sort_workspaces(workspaces)
  local indexed = {}

  for index, ws in ipairs(workspaces) do
    local upper = ws:upper()
    local num = tonumber(ws)
    local rank = letter_keyboard_rank[upper]

    local group = 4
    local key = index

    if num then
      group = 1
      key = num
    elseif #upper == 1 and rank then
      group = 2
      key = rank
    elseif #upper == 1 then
      group = 3
      key = string.byte(upper)
    end

    table.insert(indexed, {
      ws = ws,
      idx = index,
      group = group,
      key = key,
    })
  end

  table.sort(indexed, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    if a.key ~= b.key then return a.key < b.key end
    return a.idx < b.idx
  end)

  local sorted = {}
  for _, item in ipairs(indexed) do
    table.insert(sorted, item.ws)
  end
  return sorted
end

local function workspace_item_name(workspace)
  local normalized = workspace:gsub("[^%w_]", "_")
  return "space.item." .. normalized
end

local function workspace_padding_name(workspace)
  local normalized = workspace:gsub("[^%w_]", "_")
  return "space.padding." .. normalized
end

local function workspace_popup_name(workspace)
  local normalized = workspace:gsub("[^%w_]", "_")
  return "space.popup." .. normalized
end

local function workspace_bracket_name(workspace)
  local normalized = workspace:gsub("[^%w_]", "_")
  return "space.bracket." .. normalized
end

local function icon_line_from_apps(apps)
  local icon_line = ""
  for _, app in ipairs(apps or {}) do
    icon_line = icon_line .. (app_icons[app] or app_icons["Default"] or "")
  end
  return icon_line ~= "" and icon_line or " —"
end

local function set_selected_space(focused)
  local focused_key = workspace_key(focused)
  for _, ws in ipairs(workspace_order) do
    local selected = (ws == focused_key)
    if spaces[ws] then
      spaces[ws]:set({
        icon = { highlight = selected },
        label = { highlight = selected },
        background = { border_color = selected and colors.black or colors.bg2 },
      })
    end
    if space_brackets[ws] then
      space_brackets[ws]:set({
        background = { border_color = selected and colors.grey or colors.bg2 },
      })
    end
  end
end

local function set_workspace_visible(workspace, visible)
  if spaces[workspace] then
    spaces[workspace]:set({ drawing = visible })
  end
  if space_brackets[workspace] then
    space_brackets[workspace]:set({ drawing = visible })
  end
  if space_paddings[workspace] then
    space_paddings[workspace]:set({ width = visible and settings.group_paddings or 0 })
  end
end

local function remove_workspace_items()
  for ws, _ in pairs(space_popups) do
    sbar.remove(workspace_popup_name(ws))
  end
  for ws, _ in pairs(spaces) do
    sbar.remove(workspace_item_name(ws))
  end
  for ws, _ in pairs(space_brackets) do
    sbar.remove(workspace_bracket_name(ws))
  end
  for ws, _ in pairs(space_paddings) do
    sbar.remove(workspace_padding_name(ws))
  end
  spaces = {}
  space_brackets = {}
  space_paddings = {}
  space_popups = {}
end

local function create_workspace_item(workspace)
  local item_name = workspace_item_name(workspace)

  local space = sbar.add("item", item_name, {
    drawing = false,
    icon = {
      font = { family = settings.font.numbers },
      string = workspace,
      padding_left = 15,
      padding_right = 8,
      color = colors.white,
      highlight_color = colors.red,
    },
    label = {
      padding_right = 20,
      color = colors.grey,
      highlight_color = colors.white,
      font = "sketchybar-app-font:Regular:16.0",
      y_offset = -1,
    },
    padding_right = 1,
    padding_left = 1,
    background = {
      color = colors.bg1,
      border_width = 1,
      height = 26,
      border_color = colors.black,
    },
    popup = { background = { border_width = 5, border_color = colors.black } }
  })

  spaces[workspace] = space

  local bracket_name = workspace_bracket_name(workspace)
  local space_bracket = sbar.add("bracket", bracket_name, { space.name }, {
    drawing = false,
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 28,
      border_width = 2
    }
  })
  space_brackets[workspace] = space_bracket

  local padding = sbar.add("item", workspace_padding_name(workspace), {
    script = "",
    width = 0,
  })
  space_paddings[workspace] = padding

  local space_popup = sbar.add("item", workspace_popup_name(workspace), {
    position = "popup." .. space.name,
    padding_left = 5,
    padding_right = 0,
    background = {
      drawing = true,
      image = {
        corner_radius = 9,
        scale = 0.2,
      }
    }
  })
  space_popups[workspace] = space_popup

  space:subscribe("mouse.clicked", function(env)
    if env.BUTTON == "other" then
      space_popup:set({ background = { image = "space." .. workspace } })
      space:set({ popup = { drawing = "toggle" } })
      return
    end

    if env.BUTTON == "right" then
      local target = nil
      for _, ws in ipairs(workspace_order) do
        if ws ~= workspace then
          target = ws
          break
        end
      end

      if target then
        local move_cmd = "aerospace list-windows --workspace " .. shell_quote(workspace) .. " --format '%{window-id}'"
        sbar.exec(move_cmd, function(ids_out)
          for _, wid in ipairs(parse_lines(ids_out)) do
            sbar.exec("aerospace move-node-to-workspace " .. shell_quote(target) .. " --window-id " .. shell_quote(wid))
          end
          refresh_workspaces()
        end)
      end
    else
      sbar.exec("aerospace workspace " .. shell_quote(workspace), function(_)
        refresh_workspaces()
      end)
    end
  end)

  space:subscribe("mouse.exited", function(_)
    space:set({ popup = { drawing = false } })
  end)
end

local function initialize_workspace_items()
  remove_workspace_items()
  workspace_order = {}
  for _, ws in ipairs(fixed_workspaces) do
    table.insert(workspace_order, ws)
    create_workspace_item(ws)
    set_workspace_visible(ws, false)
  end
end

local function parse_apps_output(output)
  local apps = {}
  for _, app in ipairs(parse_lines(output)) do
    if not ignored_apps[app] then
      table.insert(apps, app)
    end
  end
  return apps
end

local function move_app_to_end(apps, focused_app)
  if not focused_app or focused_app == "" then return apps end

  local kept = {}
  local moved = false
  for _, app in ipairs(apps) do
    if app == focused_app and not moved then
      moved = true
    else
      table.insert(kept, app)
    end
  end

  if moved then
    table.insert(kept, focused_app)
    return kept
  end

  return apps
end

refresh_workspaces = function(callback)
  refresh_generation = refresh_generation + 1
  local generation = refresh_generation

  sbar.exec("aerospace list-workspaces --focused --format '%{workspace}'", function(focused_out)
    if generation ~= refresh_generation then return end
    local focused = workspace_key((parse_lines(focused_out))[1])

    sbar.exec("aerospace list-windows --focused --format '%{app-name}' 2>/dev/null", function(focused_app_out)
      if generation ~= refresh_generation then return end
      local focused_app = (parse_lines(focused_app_out))[1]
      if ignored_apps[focused_app] then focused_app = nil end

      sbar.exec("aerospace list-windows --all --format '%{workspace}\\t%{app-name}'", function(all_windows_out)
        if generation ~= refresh_generation then return end

        local apps_by_ws = {}
        for _, ws in ipairs(workspace_order) do
          apps_by_ws[ws] = {}
        end

        for _, line in ipairs(parse_lines(all_windows_out)) do
          local ws, app = line:match("^(.-)\\t(.*)$")
          if not ws then
            ws, app = line:match("^(.-)\t(.*)$")
          end

          ws = workspace_key(ws)
          app = trim(app)

          if ws and app ~= "" and not ignored_apps[app] and apps_by_ws[ws] then
            table.insert(apps_by_ws[ws], app)
          end
        end

        local visible_set = {}
        for _, ws in ipairs(workspace_order) do
          local apps = move_app_to_end(apps_by_ws[ws] or {}, focused_app)
          apps_by_ws[ws] = apps
          if #apps > 0 or (focused and ws == focused) then
            visible_set[ws] = true
          end
        end

        for _, space_name in ipairs(workspace_order) do
          local apps = apps_by_ws[space_name] or {}
          if spaces[space_name] then
            spaces[space_name]:set({ label = icon_line_from_apps(apps) })
          end
          set_workspace_visible(space_name, visible_set[space_name] == true)
        end

        set_selected_space(focused)
        if callback then callback(focused) end
      end)
    end)
  end)
end

local workspace_refresh_observer = sbar.add("item", {
  drawing = false,
  updates = true,
})

sbar.add("event", "aerospace_workspace_change")

workspace_refresh_observer:subscribe("space_windows_change", function(_)
  refresh_workspaces()
end)

workspace_refresh_observer:subscribe("aerospace_workspace_change", function(_)
  refresh_workspaces()
end)

initialize_workspace_items()

local spaces_indicator = sbar.add("item", {
  padding_left = -3,
  padding_right = 0,
  icon = {
    padding_left = 8,
    padding_right = 9,
    color = colors.grey,
    string = icons.switch.on,
  },
  label = {
    width = 0,
    padding_left = 0,
    padding_right = 8,
    string = "Spaces",
    color = colors.bg1,
  },
  background = {
    color = colors.with_alpha(colors.grey, 0.0),
    border_color = colors.with_alpha(colors.bg1, 0.0),
  }
})

spaces_indicator:subscribe("swap_menus_and_spaces", function(_)
  local currently_on = spaces_indicator:query().icon.value == icons.switch.on
  spaces_indicator:set({
    icon = currently_on and icons.switch.off or icons.switch.on
  })
end)

spaces_indicator:subscribe("mouse.entered", function(_)
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 1.0 },
        border_color = { alpha = 1.0 },
      },
      icon = { color = colors.bg1 },
      label = { width = "dynamic" }
    })
  end)
end)

spaces_indicator:subscribe("mouse.exited", function(_)
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 0.0 },
        border_color = { alpha = 0.0 },
      },
      icon = { color = colors.grey },
      label = { width = 0 }
    })
  end)
end)

spaces_indicator:subscribe("mouse.clicked", function(_)
  sbar.trigger("swap_menus_and_spaces")
end)

refresh_workspaces()
