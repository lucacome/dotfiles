local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local utils = require("helpers.utils")

local trim = utils.trim
local parse_lines = utils.parse_lines
local shell_quote = utils.shell_quote

local active_interface = "en0"
local active_service = "Wi-Fi"
local active_is_wifi = true
local waking = false
local copy_label_to_clipboard
local wifi  -- forward declaration so refresh_icon (defined below) can close over it

local function restart_network_provider(iface)
  sbar.exec("killall network_load >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/network_load/bin/network_load "
    .. shell_quote(iface) .. " network_update 2.0")
end

local function normalize_speed(value)
  local s = trim(value):gsub("%s+", " "):gsub("(%d)%s*(%a+[Pp][Ss])$", "%1 %2")
  return s
end

local function refresh_icon()
  if waking then return end
  sbar.exec("route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'", function(out)
    local iface = trim(out)
    if iface ~= "" then active_interface = iface end
    sbar.exec("ipconfig getifaddr " .. active_interface .. " 2>/dev/null", function(addr)
      local connected = trim(addr) ~= ""
      wifi:set({
        icon = {
          string = connected and (active_is_wifi and icons.wifi.connected or icons.wifi.ethernet)
                             or icons.wifi.disconnected,
          color = connected and colors.white or colors.red,
        },
      })
    end)
  end)
end

local popup_width = 250

sbar.add("item", { position = "right", width = settings.group_paddings })

local wifi_up = sbar.add("item", "widgets.wifi1", {
  position = "right",
  padding_left = 0,
  padding_right = 3,
  width = 86,
  icon = {
    padding_right = 0,
    font = { style = settings.font.style_map["Bold"], size = 12.0 },
    string = icons.wifi.upload,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 12.0,
    },
    width = 70,
    align = "left",
    color = colors.red,
    string = "??? Bps",
  },
  y_offset = 0,
})

local wifi_down = sbar.add("item", "widgets.wifi2", {
  position = "right",
  padding_left = 0,
  padding_right = 0,
  width = 86,
  icon = {
    padding_right = 0,
    font = { style = settings.font.style_map["Bold"], size = 12.0 },
    string = icons.wifi.download,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 12.0,
    },
    width = 70,
    align = "left",
    color = colors.blue,
    string = "??? Bps",
  },
  y_offset = 0,
})

wifi = sbar.add("item", "widgets.wifi.padding", {
  position = "right",
  padding_right = 1,
  icon = { padding_right = 1 },
  label = { drawing = false },
})

local network_watcher = sbar.add("item", {
  drawing = false,
  updates = true,
  update_freq = 5,
})

local wifi_bracket = sbar.add("bracket", "widgets.wifi.bracket", {
  wifi.name,
  wifi_up.name,
  wifi_down.name,
}, {
  background = { color = colors.bg1 },
  popup = { align = "center", height = 30 },
})

local function info_row(label_str, default, label_extra)
  local lbl = { string = default, width = popup_width / 2, align = "right" }
  if label_extra then for k, v in pairs(label_extra) do lbl[k] = v end end
  return sbar.add("item", {
    position = "popup." .. wifi_bracket.name,
    icon = { align = "left", string = label_str, width = popup_width / 2 },
    label = lbl,
  })
end

local ssid = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    font = { style = settings.font.style_map["Bold"] },
    string = icons.wifi.ethernet,
  },
  width = popup_width,
  align = "center",
  label = {
    font = { size = 15, style = settings.font.style_map["Bold"] },
    max_chars = 18,
    string = "????????????",
  },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})

local hostname = info_row("Hostname:", "????????????", { max_chars = 20 })
local ip       = info_row("IP:", "???.???.???.???")
local mask     = info_row("Subnet mask:", "???.???.???.???")
local router   = info_row("Router:", "???.???.???.???")
local iface    = info_row("Interface:", "en0")
local service  = info_row("Service:", "Wi-Fi")

local dns_items = {}

local function ensure_dns_item(index)
  if dns_items[index] then return dns_items[index] end
  local item = sbar.add("item", "widgets.wifi.dns." .. index, {
    position = "popup." .. wifi_bracket.name,
    icon = { align = "left", string = "DNS" .. index .. ":", width = popup_width / 2 },
    label = { string = "N/A", width = popup_width / 2, align = "right", max_chars = 64 },
  })
  item:subscribe("mouse.clicked", function(env)
    if copy_label_to_clipboard then copy_label_to_clipboard(env) end
  end)
  dns_items[index] = item
  return item
end

local function set_dns_servers(servers)
  local values = #servers > 0 and servers or { "N/A" }
  for i, value in ipairs(values) do
    local item = ensure_dns_item(i)
    item:set({ drawing = true, icon = { string = "DNS" .. i .. ":" }, label = { string = value } })
  end
  for i = #values + 1, #dns_items do
    dns_items[i]:set({ drawing = false })
  end
end

local function hide_details()
  wifi_bracket:set({ popup = { drawing = false } })
end

local function toggle_details()
  local should_draw = wifi_bracket:query().popup.drawing == "off"
  if not should_draw then
    hide_details()
    return
  end

  wifi_bracket:set({ popup = { drawing = true } })

  -- Detect current interface on demand (safe: user-triggered, not wake-triggered).
  sbar.exec("route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'", function(out)
    local detected = trim(out)
    if detected ~= "" then active_interface = detected end

    -- Detect wifi vs ethernet for the active interface.
    sbar.exec("networksetup -listallhardwareports 2>/dev/null", function(hw)
      local cur_port = nil
      for line in tostring(hw):gmatch("[^\r\n]+") do
        local port = line:match("^Hardware Port:%s*(.+)$")
        if port then
          cur_port = trim(port)
        else
          local dev = line:match("^Device:%s*(.+)$")
          if dev and trim(dev) == active_interface then
            active_service = cur_port or "Ethernet"
            local pl = active_service:lower()
            active_is_wifi = pl:find("wifi", 1, true) ~= nil or pl:find("wi%-fi") ~= nil
          end
        end
      end

      iface:set({ label = active_interface })
      service:set({ label = active_service })

      sbar.exec("networksetup -getcomputername 2>/dev/null", function(result)
        hostname:set({ label = trim(result) })
      end)

      sbar.exec("ipconfig getifaddr " .. active_interface .. " 2>/dev/null", function(result)
        local ip_addr = trim(result)
        ip:set({ label = ip_addr ~= "" and ip_addr or "N/A" })
        local connected = ip_addr ~= ""

        if active_is_wifi then
          if not connected then
            ssid:set({ icon = { string = icons.wifi.disconnected }, label = { string = "Not Connected" } })
          else
            sbar.exec("networksetup -listpreferredwirelessnetworks " .. active_interface
              .. " 2>/dev/null | grep -v '^Preferred networks on' | head -1 | xargs", function(preferred)
              local name = trim(preferred)
              if name ~= "" and not name:lower():find("<redacted>", 1, true) then
                ssid:set({ icon = { string = icons.wifi.connected }, label = { string = name } })
              else
                sbar.exec("ipconfig getsummary " .. active_interface
                  .. " | awk -F ' SSID : ' '/ SSID : / {print $2}'", function(s)
                  local n = trim(s)
                  ssid:set({
                    icon = { string = icons.wifi.connected },
                    label = { string = (n ~= "" and not n:lower():find("<redacted>", 1, true)) and n or "Wi-Fi" },
                  })
                end)
              end
            end)
          end
        else
          ssid:set({
            icon = { string = connected and icons.wifi.ethernet or icons.wifi.disconnected },
            label = { string = "Ethernet" },
          })
        end
      end)

      sbar.exec("ipconfig getoption " .. active_interface .. " subnet_mask 2>/dev/null", function(result)
        mask:set({ label = trim(result) ~= "" and trim(result) or "N/A" })
      end)

      sbar.exec("ipconfig getoption " .. active_interface .. " router 2>/dev/null", function(result)
        router:set({ label = trim(result) ~= "" and trim(result) or "N/A" })
      end)

      sbar.exec("scutil --dns | sed -nE 's/.*nameserver\\[[0-9]+\\][[:space:]]*:[[:space:]]*(.*)$/\\1/p' | awk '!seen[$0]++'", function(result)
        local servers = parse_lines(result)
        if #servers == 0 then
          sbar.exec("networksetup -getdnsservers " .. shell_quote(active_service) .. " 2>/dev/null", function(fallback)
            local list = {}
            for _, line in ipairs(parse_lines(fallback)) do
              if not line:match("[Tt]here aren't any DNS Servers") then
                table.insert(list, line)
              end
            end
            set_dns_servers(list)
          end)
          return
        end
        set_dns_servers(servers)
      end)
    end)
  end)
end

wifi_up:subscribe("network_update", function(env)
  local up = normalize_speed(env.upload)
  local down = normalize_speed(env.download)
  local up_num = tonumber((up:gsub("%s+", "")):match("^(%d+)")) or 0
  local dn_num = tonumber((down:gsub("%s+", "")):match("^(%d+)")) or 0
  wifi_up:set({
    icon = { color = up_num == 0 and colors.grey or colors.red },
    label = { string = up, color = up_num == 0 and colors.grey or colors.red },
  })
  wifi_down:set({
    icon = { color = dn_num == 0 and colors.grey or colors.blue },
    label = { string = down, color = dn_num == 0 and colors.grey or colors.blue },
  })
end)

wifi:subscribe("wifi_change", refresh_icon)
network_watcher:subscribe("routine", refresh_icon)

network_watcher:subscribe("system_woke", function()
  -- Guard: system_woke fires multiple times on wake; without this each firing
  -- queues a delayed restart and you end up with N network_load processes.
  if waking then return end
  waking = true
  sbar.exec("killall -9 network_load >/dev/null 2>&1")
  sbar.delay(15, function()
    waking = false
    restart_network_provider(active_interface)
    refresh_icon()
  end)
end)

wifi_up:subscribe("mouse.clicked", toggle_details)
wifi_down:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.exited.global", hide_details)

copy_label_to_clipboard = function(env)
  local label = sbar.query(env.NAME).label.value
  sbar.exec("printf '%s' " .. shell_quote(label) .. " | pbcopy")
  sbar.set(env.NAME, { label = { string = icons.clipboard, align = "center" } })
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

restart_network_provider(active_interface)
refresh_icon()
