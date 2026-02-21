local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

local battery = sbar.add("item", "widgets.battery", {
  position = "right",
  drawing = false,
  icon = {
    font = {
      style = settings.font.style_map["Regular"],
      size = 19.0,
    }
  },
  label = { font = { family = settings.font.numbers } },
  update_freq = 180,
  popup = { align = "center" }
})

local remaining_time = sbar.add("item", {
  position = "popup." .. battery.name,
  drawing = false,
  icon = {
    string = "Time remaining:",
    width = 100,
    align = "left"
  },
  label = {
    string = "??:??h",
    width = 100,
    align = "right"
  },
})

local battery_bracket = sbar.add("bracket", "widgets.battery.bracket", { battery.name }, {
  background = { color = colors.bg1 },
  drawing = false,
})

local battery_padding = sbar.add("item", "widgets.battery.padding", {
  position = "right",
  width = settings.group_paddings,
  drawing = false,
})

local function set_battery_visibility(visible)
  battery:set({ drawing = visible })
  battery_bracket:set({ drawing = visible })
  battery_padding:set({ drawing = visible })
  remaining_time:set({ drawing = visible })
end

local function update_battery_widget()
  sbar.exec("pmset -g batt", function(batt_info)
    local has_charge = batt_info:find("(%d+)%%") ~= nil
    if batt_info:find("[Nn]o batteries") or batt_info:find("[Nn]o battery") or not has_charge then
      set_battery_visibility(false)
      return
    end

    set_battery_visibility(true)

    local icon = "!"
    local label = "?"

    local found, _, charge = batt_info:find("(%d+)%%")
    if found then
      charge = tonumber(charge)
      label = charge .. "%"
    end

    local color = colors.green
    local charging, _, _ = batt_info:find("AC Power")

    if charging then
      icon = icons.battery.charging
    else
      if found and charge > 80 then
        icon = icons.battery._100
      elseif found and charge > 60 then
        icon = icons.battery._75
      elseif found and charge > 40 then
        icon = icons.battery._50
      elseif found and charge > 20 then
        icon = icons.battery._25
        color = colors.orange
      else
        icon = icons.battery._0
        color = colors.red
      end
    end

    local lead = ""
    if found and charge < 10 then
      lead = "0"
    end

    battery:set({
      icon = {
        string = icon,
        color = color
      },
      label = { string = lead .. label },
    })
  end)
end

battery:subscribe({"routine", "power_source_change", "system_woke"}, update_battery_widget)

battery:subscribe("mouse.clicked", function(env)
  local drawing = battery:query().popup.drawing
  battery:set( { popup = { drawing = "toggle" } })

  if drawing == "off" then
    sbar.exec("pmset -g batt", function(batt_info)
      local found, _, remaining = batt_info:find(" (%d+:%d+) remaining")
      local label = found and remaining .. "h" or "No estimate"
      remaining_time:set( { label = label })
    end)
  end
end)

update_battery_widget()
