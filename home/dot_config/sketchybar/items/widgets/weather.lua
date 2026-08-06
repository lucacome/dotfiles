local colors = require("colors")
local settings = require("settings")
local popups = require("helpers.popups")
local wake = require("helpers.wake")

-- SF Symbols glyphs (U+100000 supplementary plane, rendered by SF Pro / sf-symbols font)
local sf_icons = {
  sun = "􀆭",
  moon = "􀆺",
  cloud_sun = "􀇕",
  cloud_moon = "􀇚",
  cloud = "􀇂",
  rain = "􀇄",
  drizzle = "􀇆",
  heavy_rain = "􀇈",
  sleet = "􀇐",
  hail = "􀇌",
  snow = "􀇎",
  fog = "􀇊",
  thunder = "􀇞",
  thunderstorm = "􀇀",
}

-- WWO weather codes -> icon (https://worldweatheronline.com/developer/docs/wwo-weather-codes)
local code_icons = {
  [113] = "sun",    -- Clear/Sunny
  [116] = "cloud_sun", -- Partly cloudy
  [119] = "cloud",  -- Cloudy
  [122] = "cloud",  -- Overcast
  [143] = "fog",    -- Mist
  [176] = "rain",   -- Patchy rain possible
  [179] = "snow",   -- Patchy snow possible
  [182] = "sleet",  -- Patchy sleet possible
  [185] = "sleet",  -- Patchy freezing drizzle possible
  [200] = "thunder", -- Thundery outbreaks possible
  [227] = "snow",   -- Blowing snow
  [230] = "snow",   -- Blizzard
  [248] = "fog",    -- Fog
  [260] = "fog",    -- Freezing fog
  [263] = "drizzle", -- Patchy light drizzle
  [266] = "drizzle", -- Light drizzle
  [281] = "drizzle", -- Freezing drizzle
  [284] = "drizzle", -- Heavy freezing drizzle
  [293] = "drizzle", -- Patchy light rain
  [296] = "rain",   -- Light rain
  [299] = "rain",   -- Moderate rain at times
  [302] = "rain",   -- Moderate rain
  [305] = "heavy_rain", -- Heavy rain at times
  [308] = "heavy_rain", -- Heavy rain
  [311] = "rain",   -- Light freezing rain
  [314] = "rain",   -- Moderate or heavy freezing rain
  [317] = "sleet",  -- Light sleet
  [320] = "sleet",  -- Moderate or heavy sleet
  [323] = "snow",   -- Patchy light snow
  [326] = "snow",   -- Light snow
  [329] = "snow",   -- Patchy moderate snow
  [332] = "snow",   -- Moderate snow
  [335] = "snow",   -- Patchy heavy snow
  [338] = "snow",   -- Heavy snow
  [350] = "hail",   -- Ice pellets
  [353] = "rain",   -- Light rain shower
  [356] = "rain",   -- Moderate or heavy rain shower
  [359] = "heavy_rain", -- Torrential rain shower
  [362] = "sleet",  -- Light sleet showers
  [365] = "sleet",  -- Moderate or heavy sleet showers
  [368] = "snow",   -- Light snow showers
  [371] = "snow",   -- Moderate or heavy snow showers
  [374] = "hail",   -- Light showers of ice pellets
  [377] = "hail",   -- Moderate or heavy showers of ice pellets
  [386] = "thunder", -- Patchy light rain with thunder
  [389] = "thunderstorm", -- Moderate or heavy rain with thunder
  [392] = "thunder", -- Patchy light snow with thunder
  [395] = "thunderstorm", -- Moderate or heavy snow with thunder
}

local weather = sbar.add("item", "widgets.weather", {
  position = "right",
  icon = {
    string = sf_icons.moon,
    padding_right = 4,
    width = "dynamic",
  },
  label = {
    string = "--°C",
    width = "dynamic",
    align = "right",
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 12.0,
    },
  },
  width = "dynamic",
  update_freq = 300,
})

local weather_bracket = sbar.add("bracket", "widgets.weather.bracket", { weather.name }, {
  background = { color = colors.bg1 },
  popup = { align = "center", height = 30 },
})

sbar.add("item", "widgets.weather.padding", {
  position = "right",
  width = settings.group_paddings,
})

local popup_width = 300

local header = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = {
    font = { style = settings.font.style_map["Bold"] },
    string = sf_icons.cloud,
  },
  width = popup_width,
  align = "center",
  label = {
    font = { size = 15, style = settings.font.style_map["Bold"] },
    max_chars = 24,
    string = "--°C",
  },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})

local function popup_row(icon)
  return sbar.add("item", {
    position = "popup." .. weather_bracket.name,
    icon = { align = "left", string = icon, width = popup_width / 2 },
    label = { string = "", width = popup_width / 2, align = "right" },
  })
end

local popup_rows = {}
popup_rows.location = popup_row("Location:")
popup_rows.condition = popup_row("Condition:")
popup_rows.feels = popup_row("Feels like:")
popup_rows.humidity = popup_row("Humidity:")
popup_rows.wind = popup_row("Wind:")
popup_rows.uv = popup_row("UV index:")
popup_rows.highlow = popup_row("High / Low:")
popup_rows.sun = popup_row("Sunrise / Sunset:")

local forecast_rows = {}
for i = 1, 3 do
  forecast_rows[i] = popup_row("Day " .. i .. ":")
end

local function parse_12h(time)
  -- wttr.in astronomy times like "06:17 AM" / "08:14 PM"
  local hh, mm, ap = time:match("(%d+):(%d+)%s*(%a+)")
  if not hh then return nil end
  local hour = tonumber(hh)
  ap = (ap or ""):upper()
  if ap == "PM" and hour < 12 then hour = hour + 12 end
  if ap == "AM" and hour == 12 then hour = 0 end
  return hour, mm
end

local function day_name(date)
  -- wttr.in dates like "2026-08-05" -> "Wed"
  local y, m, d = date:match("(%d+)-(%d+)-(%d+)")
  if not y then return date end
  return os.date("%A", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
end

local function icon_for(code, is_night)
  local key = code_icons[code] or "cloud"
  if key == "sun" and is_night then return sf_icons.moon end
  if key == "cloud_sun" and is_night then return sf_icons.cloud_moon end
  return sf_icons[key] or sf_icons.cloud
end

local function update_weather()
  sbar.exec([[
    curl -sf --max-time 8 'https://wttr.in/?format=j2&m' 2>/dev/null | jq -r '
      . as $root |
      .current_condition[0] as $c |
      (
        [
          $c.temp_C, $c.FeelsLikeC, $c.humidity, $c.windspeedKmph, $c.winddir16Point,
          $c.uvIndex, $c.weatherCode,
          ($root.weather[0].astronomy[0].sunrise // ""),
          ($root.weather[0].astronomy[0].sunset // ""),
          ($root.weather[0].maxtempC // ""),
          ($root.weather[0].mintempC // ""),
          ($root.weather[0].date // ""),
          ($c.weatherDesc[0].value // ""),
          ($root.nearest_area[0].areaName[0].value // ""),
          ($root.nearest_area[0].region[0].value // "")
        ] | @tsv
      ),
      ( $root.weather[] | [.date, .maxtempC, .mintempC, .weatherCode, (.weatherDesc[0].value // "")] | @tsv )
    '
  ]], function(output)
    local lines = {}
    for line in (tostring(output or ""):gsub("%s+$", "")):gmatch("[^\n]+") do
      lines[#lines + 1] = line
    end

    local cur = {}
    local fields = lines[1] or ""
    local i = 1
    for field in fields:gmatch("[^\t]+") do
      cur[i] = field
      i = i + 1
    end

    local temp, code = cur[1], tonumber(cur[7])
    if temp == nil or temp == "" then
      weather:set({ icon = { string = sf_icons.sun }, label = { string = "--°C" } })
      return
    end

    -- Day/night from real sunrise/sunset times
    local is_night = false
    local hour = tonumber(os.date("%H"))
    local sun_rise_h = parse_12h(cur[8] or "")
    local sun_set_h = parse_12h(cur[9] or "")
    if hour and sun_rise_h and sun_set_h then
      is_night = hour < sun_rise_h or hour >= sun_set_h
    end

    local icon = icon_for(code, is_night)
    weather:set({
      icon = { string = icon },
      label = { string = temp .. "°C" },
    })

    local function row(name, value)
      if popup_rows[name] then
        popup_rows[name]:set({ label = { string = value or "" } })
      end
    end

    header:set({
      icon = { string = icon },
      label = { string = string.format("%s°C  %s", temp, cur[13] or "") },
    })

    row("location", string.format("%s, %s", cur[14] or "?", cur[15] or ""))
    row("condition", cur[13] or "")
    row("feels", string.format("%s°C", cur[2] or "--"))
    row("humidity", string.format("%s%%", cur[3] or "--"))
    row("wind", string.format("%s km/h %s", cur[4] or "--", cur[5] or ""))
    row("uv", cur[6] or "--")
    row("highlow", string.format("%s°C / %s°C", cur[10] or "--", cur[11] or "--"))
    row("sun", string.format("%s / %s", cur[8] or "--", cur[9] or "--"))

    for i = 1, 3 do
      local f = lines[i + 1] or ""
      local flds = {}
      local j = 1
      for field in f:gmatch("[^\t]+") do
        flds[j] = field
        j = j + 1
      end
      forecast_rows[i]:set({
        icon = { string = day_name(flds[1] or "--") .. ":" },
        label = {
          string = string.format("%s°C/%s°C", flds[2] or "--", flds[3] or "--"),
        },
      })
    end
  end)
end

weather:subscribe({ "routine", "forced" }, update_weather)

weather:subscribe("mouse.clicked", function()
  local should_draw = weather_bracket:query().popup.drawing == "off"
  if not should_draw then
    weather_bracket:set({ popup = { drawing = false } })
    return
  end
  popups.close_others("weather")
  weather_bracket:set({ popup = { drawing = true } })
update_weather()

-- The watchdog reloads the bar shortly after a wake; the network may not be
-- back yet when this module first runs, so retry once the system has settled.
if wake.recent_woke(20) then
  sbar.delay(8, update_weather)
end
end)

weather:subscribe("mouse.exited.global", function()
  weather_bracket:set({ popup = { drawing = false } })
end)

popups.track("weather", weather_bracket, function()
  weather_bracket:set({ popup = { drawing = false } })
end)

update_weather()
