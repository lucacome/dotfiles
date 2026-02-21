local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

local active_interface = "en0"
local active_service = "Wi-Fi"
local active_is_wifi = true
local copy_label_to_clipboard

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
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

local function shell_quote(value)
  local s = trim(value)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function restart_network_provider(interface)
  sbar.exec("killall network_load >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/network_load/bin/network_load " .. interface .. " network_update 2.0")
end

local function refresh_active_network(callback)
  sbar.exec("route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'", function(default_if)
    local iface = trim(default_if)
    if iface == "" then iface = "en0" end

    sbar.exec("networksetup -listallhardwareports", function(hw)
      local service = "Ethernet"
      local is_wifi = false
      local current_port = nil

      for line in tostring(hw):gmatch("[^\r\n]+") do
        local port = line:match("^Hardware Port:%s*(.+)$")
        if port then
          current_port = trim(port)
        else
          local device = line:match("^Device:%s*(.+)$")
          if device and trim(device) == iface then
            service = current_port or service
            local normalized_service = service:lower()
            is_wifi = normalized_service:find("wifi", 1, true) ~= nil
              or normalized_service:find("wi%-fi") ~= nil
            break
          end
        end
      end

      active_is_wifi = is_wifi
      active_service = service

      if iface ~= active_interface then
        active_interface = iface
        restart_network_provider(active_interface)
      end

      if callback then callback() end
    end)
  end)
end

restart_network_provider(active_interface)

local popup_width = 250

local wifi_up = sbar.add("item", "widgets.wifi1", {
  position = "right",
  padding_left = -5,
  width = 0,
  icon = {
    padding_right = 0,
    font = {
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    string = icons.wifi.upload,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    color = colors.red,
    string = "??? Bps",
  },
  y_offset = 4,
})

local wifi_down = sbar.add("item", "widgets.wifi2", {
  position = "right",
  padding_left = -5,
  icon = {
    padding_right = 0,
    font = {
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    string = icons.wifi.download,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    color = colors.blue,
    string = "??? Bps",
  },
  y_offset = -4,
})

local wifi = sbar.add("item", "widgets.wifi.padding", {
  position = "right",
  label = { drawing = false },
})

local network_watcher = sbar.add("item", {
  drawing = false,
  updates = true,
  update_freq = 5,
})

-- Background around the item
local wifi_bracket = sbar.add("bracket", "widgets.wifi.bracket", {
  wifi.name,
  wifi_up.name,
  wifi_down.name
}, {
  background = { color = colors.bg1 },
  popup = { align = "center", height = 30 }
})

local ssid = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    font = {
      style = settings.font.style_map["Bold"]
    },
    string = icons.wifi.ethernet,
  },
  width = popup_width,
  align = "center",
  label = {
    font = {
      size = 15,
      style = settings.font.style_map["Bold"]
    },
    max_chars = 18,
    string = "????????????",
  },
  background = {
    height = 2,
    color = colors.grey,
    y_offset = -15
  }
})

local hostname = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Hostname:",
    width = popup_width / 2,
  },
  label = {
    max_chars = 20,
    string = "????????????",
    width = popup_width / 2,
    align = "right",
  }
})

local ip = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "IP:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  }
})

local mask = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Subnet mask:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  }
})

local router = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Router:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  },
})

local iface = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Interface:",
    width = popup_width / 2,
  },
  label = {
    string = "en0",
    width = popup_width / 2,
    align = "right",
  },
})

local service = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Service:",
    width = popup_width / 2,
  },
  label = {
    string = "Wi-Fi",
    width = popup_width / 2,
    align = "right",
  },
})

local dns_items = {}

local function ensure_dns_item(index)
  if dns_items[index] then return dns_items[index] end

  local item = sbar.add("item", "widgets.wifi.dns." .. index, {
    position = "popup." .. wifi_bracket.name,
    icon = {
      align = "left",
      string = "DNS" .. index .. ":",
      width = popup_width / 2,
    },
    label = {
      string = "N/A",
      width = popup_width / 2,
      align = "right",
      max_chars = 64,
    },
  })

  item:subscribe("mouse.clicked", function(env)
    if copy_label_to_clipboard then
      copy_label_to_clipboard(env)
    end
  end)

  dns_items[index] = item
  return item
end

local function set_dns_servers(servers)
  local values = servers
  if #values == 0 then
    values = { "N/A" }
  end

  for i, value in ipairs(values) do
    local item = ensure_dns_item(i)
    item:set({
      drawing = true,
      icon = { string = "DNS" .. i .. ":" },
      label = { string = value },
    })
  end

  for i = #values + 1, #dns_items do
    dns_items[i]:set({ drawing = false })
  end
end

sbar.add("item", { position = "right", width = settings.group_paddings })

wifi_up:subscribe("network_update", function(env)
  local up_color = (env.upload == "000 Bps") and colors.grey or colors.red
  local down_color = (env.download == "000 Bps") and colors.grey or colors.blue
  wifi_up:set({
    icon = { color = up_color },
    label = {
      string = env.upload,
      color = up_color
    }
  })
  wifi_down:set({
    icon = { color = down_color },
    label = {
      string = env.download,
      color = down_color
    }
  })
end)

local function refresh_network_icon()
  refresh_active_network(function()
    sbar.exec("ipconfig getifaddr " .. active_interface .. " 2>/dev/null", function(ip)
      local connected = trim(ip) ~= ""
      wifi:set({
        icon = {
          string = connected and (active_is_wifi and icons.wifi.connected or icons.wifi.ethernet) or icons.wifi.disconnected,
          color = connected and colors.white or colors.red,
        },
      })
    end)
  end)
end

wifi:subscribe({"wifi_change", "system_woke"}, refresh_network_icon)
network_watcher:subscribe("routine", refresh_network_icon)

local function hide_details()
  wifi_bracket:set({ popup = { drawing = false } })
end

local function toggle_details()
  local should_draw = wifi_bracket:query().popup.drawing == "off"
  if should_draw then
    wifi_bracket:set({ popup = { drawing = true }})
    sbar.exec("networksetup -getcomputername", function(result)
      hostname:set({ label = result })
    end)
    refresh_active_network(function()
      iface:set({ label = active_interface })
      service:set({ label = active_service })

      local function set_ssid_row(value, icon)
        ssid:set({
          icon = { string = icon },
          label = { string = value },
        })
      end

      sbar.exec("ipconfig getifaddr " .. active_interface .. " 2>/dev/null", function(result)
        local value = trim(result)
        ip:set({ label = value ~= "" and value or "N/A" })

        local connected = value ~= ""
        if active_is_wifi then
          if not connected then
            set_ssid_row("Not Connected", icons.wifi.disconnected)
            return
          end

          sbar.exec("networksetup -listpreferredwirelessnetworks " .. active_interface .. " 2>/dev/null | grep -v '^Preferred networks on' | head -1 | xargs", function(preferred_name)
            local preferred_ssid = trim(preferred_name)
            local preferred_lower = preferred_ssid:lower()

            if preferred_ssid ~= "" and preferred_lower:find("<redacted>", 1, true) == nil then
              set_ssid_row(preferred_ssid, icons.wifi.connected)
              return
            end

            sbar.exec("ipconfig getsummary " .. active_interface .. " | awk -F ' SSID : ' '/ SSID : / {print $2}'", function(summary_name)
              local fallback = trim(summary_name)
              local fallback_lower = fallback:lower()

              if fallback ~= "" and fallback_lower:find("<redacted>", 1, true) == nil then
                set_ssid_row(fallback, icons.wifi.connected)
              else
                set_ssid_row("Wi-Fi", icons.wifi.connected)
              end
            end)
          end)
        else
          set_ssid_row("Ethernet", connected and icons.wifi.ethernet or icons.wifi.disconnected)
        end
      end)

      sbar.exec("ipconfig getoption " .. active_interface .. " subnet_mask 2>/dev/null", function(result)
        local value = trim(result)
        mask:set({ label = value ~= "" and value or "N/A" })
      end)

      sbar.exec("ipconfig getoption " .. active_interface .. " router 2>/dev/null", function(result)
        local value = trim(result)
        router:set({ label = value ~= "" and value or "N/A" })
      end)

      sbar.exec("scutil --dns | sed -nE 's/.*nameserver\\[[0-9]+\\][[:space:]]*:[[:space:]]*(.*)$/\\1/p' | awk '!seen[$0]++'", function(result)
        local servers = parse_lines(result)

        if #servers == 0 then
          sbar.exec("networksetup -getdnsservers " .. shell_quote(active_service) .. " 2>/dev/null", function(fallback)
            local fallback_servers = {}
            for _, line in ipairs(parse_lines(fallback)) do
              if not line:match("[Tt]here aren't any DNS Servers") then
                table.insert(fallback_servers, line)
              end
            end

            set_dns_servers(fallback_servers)
          end)
          return
        end

        set_dns_servers(servers)
      end)
    end)
  else
    hide_details()
  end
end

wifi_up:subscribe("mouse.clicked", toggle_details)
wifi_down:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.exited.global", hide_details)

copy_label_to_clipboard = function(env)
  local label = sbar.query(env.NAME).label.value
  sbar.exec("echo \"" .. label .. "\" | pbcopy")
  sbar.set(env.NAME, { label = { string = icons.clipboard, align="center" } })
  sbar.delay(1, function()
    sbar.set(env.NAME, { label = { string = label, align = "right" } })
  end)
end

ssid:subscribe("mouse.clicked", copy_label_to_clipboard)
hostname:subscribe("mouse.clicked", copy_label_to_clipboard)
ip:subscribe("mouse.clicked", copy_label_to_clipboard)
mask:subscribe("mouse.clicked", copy_label_to_clipboard)
router:subscribe("mouse.clicked", copy_label_to_clipboard)
iface:subscribe("mouse.clicked", copy_label_to_clipboard)
service:subscribe("mouse.clicked", copy_label_to_clipboard)

refresh_network_icon()
