local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")
local utils = require("helpers.utils")

local trim = utils.trim
local parse_lines = utils.parse_lines
local shell_quote = utils.shell_quote

local spaces = {}
local space_brackets = {}
local space_paddings = {}
local workspace_order = {}
local aerospace_waking = false

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

local function set_selected(focused)
  for _, ws in ipairs(workspace_order) do
    local sel = (ws == focused)
    if spaces[ws] then
      spaces[ws]:set({
        icon = { color = sel and colors.green or colors.white },
        label = { highlight = sel },
        background = { border_color = sel and colors.black or colors.bg2 },
      })
    end
    if space_brackets[ws] then
      space_brackets[ws]:set({
        background = { border_color = sel and colors.green or colors.bg2 },
      })
    end
  end
end

local function set_visible(ws, visible)
  if spaces[ws] then spaces[ws]:set({ drawing = visible }) end
  if space_brackets[ws] then space_brackets[ws]:set({ drawing = visible }) end
  if space_paddings[ws] then
    space_paddings[ws]:set({ width = visible and settings.group_paddings or 0 })
  end
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
    script = "",
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
  sbar.exec("aerospace list-workspaces --focused --format '%{workspace}'", function(focused_out)
    local focused = trim((parse_lines(focused_out))[1] or "")
    if focused == "" then focused = nil end

    sbar.exec("aerospace list-windows --all --format '%{workspace}\\t%{app-name}'", function(wins_out)
      local apps_by_ws = {}
      for _, ws in ipairs(workspace_order) do apps_by_ws[ws] = {} end

      for _, line in ipairs(parse_lines(wins_out)) do
        local ws, app = line:match("^(.-)\\t(.*)$")
        if ws then
          ws = trim(ws)
          app = trim(app or "")
          if apps_by_ws[ws] and app ~= "" and not ignored_apps[app] then
            table.insert(apps_by_ws[ws], app)
          end
        end
      end

      for _, ws in ipairs(workspace_order) do
        local apps = apps_by_ws[ws] or {}
        set_visible(ws, #apps > 0 or ws == focused)
        if spaces[ws] then
          spaces[ws]:set({ label = icon_line(apps) })
        end
      end

      if focused then set_selected(focused) end
    end)
  end)
end

local observer = sbar.add("item", { drawing = false, updates = true })

sbar.add("event", "aerospace_workspace_change")
sbar.add("event", "aerospace_focus_changed")

observer:subscribe("space_windows_change", function()
  if not aerospace_waking then refresh_workspaces() end
end)

observer:subscribe("aerospace_focus_changed", function()
  if not aerospace_waking then refresh_workspaces() end
end)

observer:subscribe("aerospace_workspace_change", function()
  if not aerospace_waking then refresh_workspaces() end
end)

observer:subscribe("system_woke", function()
  aerospace_waking = true
  sbar.delay(15, function()
    aerospace_waking = false
    refresh_workspaces()
  end)
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
  if not currently_on then refresh_workspaces() end
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
