local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")
local utils = require("helpers.utils")

local shell_quote = utils.shell_quote

local spaces = {}
local space_brackets = {}
local space_paddings = {}
local workspace_display = {}
local workspace_order = {}
local refresh_gen = 0
local refresh_pending = false

-- Known workspaces are created in this order at load, which fixes their
-- left-to-right position; the list cannot come from the CLI without async
-- ordering problems. Any other workspace is appended the first time AeroSpace
-- reports it.
local fixed_workspaces = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "Z", "X", "C", "V", "B", "N", "M" }
local ignored_apps = { Finder = true }

local function ws_name(kind, ws)
  return "space." .. kind .. "." .. ws:gsub("[^%w_]", "_")
end

local function icon_line(apps)
  local s = ""
  for _, app in ipairs(apps) do
    s = s .. (app_icons[app] or app_icons["Default"] or "")
  end
  return s ~= "" and s or " —"
end

local function set_selected(focused, visible_set)
  visible_set = visible_set or {}
  for _, ws in ipairs(workspace_order) do
    if spaces[ws] then
      local is_focused = (ws == focused)
      local is_visible = visible_set[ws]
      spaces[ws]:set({
        icon = { color = is_focused and colors.green or (is_visible and colors.blue or colors.white) },
        label = { highlight = is_focused },
        background = { border_color = is_focused and colors.black or colors.bg2 },
      })
    end
  end
  -- Bracket sets in a separate callback to avoid SbarLua batching them with the item sets above
  sbar.delay(0, function()
    for _, ws in ipairs(workspace_order) do
      if space_brackets[ws] then
        local is_focused = (ws == focused)
        local is_visible = visible_set[ws]
        space_brackets[ws]:set({
          background = { border_color = is_focused and colors.green or (is_visible and colors.blue or colors.bg2) },
        })
      end
    end
  end)
end

local function set_visible(ws, visible)
  -- Each in its own callback so SbarLua doesn't batch them into one mach message
  sbar.delay(0, function()
    if space_paddings[ws] then
      space_paddings[ws]:set({ width = visible and settings.group_paddings or 0 })
    end
  end)
  sbar.delay(0, function()
    if space_brackets[ws] then space_brackets[ws]:set({ drawing = visible }) end
  end)
end

-- Each workspace belongs to one monitor; show its item only on that monitor's
-- bar. Updated when AeroSpace moves a workspace to another display.
local function set_display(ws, monitor)
  if workspace_display[ws] == monitor then return end
  workspace_display[ws] = monitor
  if spaces[ws] then spaces[ws]:set({ display = monitor }) end
  if space_brackets[ws] then space_brackets[ws]:set({ display = monitor }) end
  if space_paddings[ws] then space_paddings[ws]:set({ display = monitor }) end
end

local refresh_workspaces

local function create_workspace_item(ws)
  local space = sbar.add("item", ws_name("item", ws), {
    drawing = false,
    icon = {
      font = { family = settings.font.numbers },
      string = ws,
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
  })
  spaces[ws] = space

  space_brackets[ws] = sbar.add("bracket", ws_name("bracket", ws), { space.name }, {
    drawing = false,
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 28,
      border_width = 1,
    },
  })

  space_paddings[ws] = sbar.add("item", ws_name("padding", ws), {
    width = 0,
  })

  space:subscribe("mouse.clicked", function(env)
    if env.BUTTON == "left" then
      sbar.exec("aerospace workspace " .. shell_quote(ws))
    end
  end)
end

local function initialize()
  for _, ws in ipairs(workspace_order) do
    sbar.remove(ws_name("item", ws))
    sbar.remove(ws_name("bracket", ws))
    sbar.remove(ws_name("padding", ws))
  end
  spaces, space_brackets, space_paddings, workspace_order = {}, {}, {}, {}
  for _, ws in ipairs(fixed_workspaces) do
    table.insert(workspace_order, ws)
    create_workspace_item(ws)
  end
end

refresh_workspaces = function()
  -- Three events can fire for one workspace switch. Every call takes a
  -- generation number and drops its reply if a newer refresh started, so a
  -- slow older answer cannot overwrite the current highlight.
  refresh_gen = refresh_gen + 1
  local gen = refresh_gen

  -- AeroSpace 0.20+ reports focus, visibility and monitor per workspace, so
  -- one call replaces the old --focused + --visible pair. --json is decoded by
  -- sbar.exec, so nothing is parsed from text.
  sbar.exec("aerospace list-workspaces --all --format '%{workspace}%{workspace-is-focused}%{workspace-is-visible}%{monitor-appkit-nsscreen-screens-id}' --json", function(ws_list)
    if gen ~= refresh_gen or type(ws_list) ~= "table" then return end

    -- Skip if aerospace isn't responding (prevents flood/hide during wake)
    if #ws_list == 0 then return end

    local focused = nil
    local visible_set = {}
    for _, entry in ipairs(ws_list) do
      local ws = entry.workspace
      if ws and ws ~= "" then
        if not spaces[ws] then
          table.insert(workspace_order, ws)
          create_workspace_item(ws)
        end
        if entry["workspace-is-focused"] then focused = ws end
        if entry["workspace-is-visible"] then visible_set[ws] = true end
        local monitor = entry["monitor-appkit-nsscreen-screens-id"]
        if type(monitor) == "number" then
          set_display(ws, math.floor(monitor))
        end
      end
    end

    sbar.exec("aerospace list-windows --all --format '%{workspace}%{app-name}' --json", function(win_list)
      if gen ~= refresh_gen or type(win_list) ~= "table" then return end
      local apps_by_ws = {}
      for _, ws in ipairs(workspace_order) do apps_by_ws[ws] = {} end

      for _, win in ipairs(win_list) do
        local ws = win.workspace
        local app = win["app-name"]
        if apps_by_ws[ws] and app and app ~= "" and not ignored_apps[app] then
          table.insert(apps_by_ws[ws], app)
        end
      end

      for _, ws in ipairs(workspace_order) do
        local apps = apps_by_ws[ws] or {}
        local visible = #apps > 0 or ws == focused or visible_set[ws]
        if spaces[ws] then
          spaces[ws]:set({ drawing = visible, label = icon_line(apps) })
        end
        set_visible(ws, visible)
      end

      set_selected(focused, visible_set)
    end)
  end)
end

local observer = sbar.add("item", { drawing = false, updates = true })

-- Coalesce bursts of events into one refresh.
local function schedule_refresh()
  if refresh_pending then return end
  refresh_pending = true
  sbar.delay(0, function()
    refresh_pending = false
    refresh_workspaces()
  end)
end

sbar.add("event", "aerospace_workspace_change")
sbar.add("event", "aerospace_focus_changed")

observer:subscribe("space_windows_change", function()
  schedule_refresh()
end)

observer:subscribe("aerospace_focus_changed", function()
  schedule_refresh()
end)

observer:subscribe("aerospace_workspace_change", function()
  schedule_refresh()
end)

initialize()

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
  },
})

spaces_indicator:subscribe("swap_menus_and_spaces", function()
  local currently_on = spaces_indicator:query().icon.value == icons.switch.on
  spaces_indicator:set({
    icon = currently_on and icons.switch.off or icons.switch.on,
  })
  if not currently_on then schedule_refresh() end
end)

spaces_indicator:subscribe("mouse.entered", function()
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 1.0 },
        border_color = { alpha = 1.0 },
      },
      icon = { color = colors.bg1 },
      label = { width = "dynamic" },
    })
  end)
end)

spaces_indicator:subscribe("mouse.exited", function()
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 0.0 },
        border_color = { alpha = 0.0 },
      },
      icon = { color = colors.grey },
      label = { width = 0 },
    })
  end)
end)

spaces_indicator:subscribe("mouse.clicked", function()
  sbar.trigger("swap_menus_and_spaces")
end)

refresh_workspaces()
