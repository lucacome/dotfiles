local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

local cpu_alert_threshold = 80
local ram_alert_threshold = 80

-- Execute the event provider binary which provides the event "cpu_update" for
-- the cpu load data, which is fired every 2.0 seconds.
sbar.exec("killall cpu_load >/dev/null; $CONFIG_DIR/helpers/event_providers/cpu_load/bin/cpu_load cpu_update 2.0")

local ram = sbar.add("item", "widgets.cpu.ram", {
  position = "right",
  icon = {
    string = icons.ram,
    padding_right = 4,
  },
  label = {
    string = "??%",
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 12.0,
    },
    align = "left",
    padding_right = 2,
    width = 30,
  },
  padding_left = 4,
  padding_right = 4,
})

local cpu = sbar.add("item", "widgets.cpu", {
  position = "right",
  icon = {
    string = icons.cpu,
    padding_right = 4,
  },
  label = {
    string = "??%",
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 12.0,
    },
    align = "left",
    padding_right = 4,
    width = 30,
  },
  padding_left = 4,
  padding_right = 4,
})

cpu:subscribe("cpu_update", function(env)
  local load = tonumber(env.total_load) or 0
  cpu:set({
    label = string.format("%02d%%", load),
    icon = { color = load >= cpu_alert_threshold and colors.red or colors.white },
  })
end)

local function update_ram()
  sbar.exec("memory_pressure 2>/dev/null | awk -F': ' '/System-wide memory free percentage/ {gsub(/%/, \"\", $2); printf \"%d\", 100-$2}'", function(out)
    local value = tostring(out or ""):match("%d+")
    if value then
      local usage = tonumber(value) or 0
      ram:set({
        label = string.format("%02d%%", usage),
        icon = { color = usage >= ram_alert_threshold and colors.red or colors.white },
      })
    end
  end)
end

local ram_observer = sbar.add("item", {
  drawing = false,
  updates = true,
  update_freq = 2,
})

ram_observer:subscribe("routine", update_ram)
ram_observer:subscribe("system_woke", function()
  -- Use SIGKILL (-9) so a post-sleep stuck process is force-removed,
  -- then restart after a short delay.
  sbar.exec("killall -9 cpu_load >/dev/null 2>&1")
  sbar.delay(3, function()
    sbar.exec("$CONFIG_DIR/helpers/event_providers/cpu_load/bin/cpu_load cpu_update 2.0")
  end)
end)

cpu:subscribe("mouse.clicked", function(_)
  sbar.exec("open -a 'Activity Monitor'")
end)

ram:subscribe("mouse.clicked", function(_)
  sbar.exec("open -a 'Activity Monitor'")
end)

sbar.add("bracket", "widgets.cpu.bracket", { cpu.name, ram.name }, {
  background = { color = colors.bg1 }
})

update_ram()

sbar.add("item", "widgets.cpu.padding", {
  position = "right",
  width = settings.group_paddings
})
