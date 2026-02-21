local colors = require("colors")
local settings = require("settings")

local weather = sbar.add("item", "widgets.weather", {
  position = "right",
  icon = {
    string = "􀆺",
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

sbar.add("bracket", "widgets.weather.bracket", { weather.name }, {
  background = { color = colors.bg1 },
})

sbar.add("item", "widgets.weather.padding", {
  position = "right",
  width = settings.group_paddings,
})

local function update_weather()
  local cmd = [[
latest=$(ls -t "$HOME/Library/Containers/com.apple.weather.widget/Data/SystemData/com.apple.chrono/timelines/com.apple.weather/"*.chrono-timeline 2>/dev/null | head -1)
[ -n "$latest" ] || exit 0

temp=$(strings "$latest" 2>/dev/null | grep -E 'Current Location, *-?[0-9]+' | head -1 | sed -nE 's/.*Current Location, *(-?[0-9]+).*/\1/p')
condition=$(strings "$latest" 2>/dev/null | awk '
  /Current Location, *-?[0-9]+/ { capture=1; seen=0; next }
  capture {
    seen++
    if ($0 ~ /(Celsius|Fahrenheit), .*High of/) {
      line=$0
      sub(/^.*(Celsius|Fahrenheit), /, "", line)
      sub(/, High of.*$/, "", line)
      gsub(/^ +| +$/, "", line)
      print line
      exit
    }
    if (seen >= 6) exit
  }
' | head -1 | xargs)
night_hint=$(strings "$latest" 2>/dev/null | grep -Ei 'Night|Evening|Overnight' | head -1)

if [ -z "$condition" ]; then
  condition=$(strings "$latest" 2>/dev/null | grep -E '^[A-Za-z][A-Za-z ]+, *-?[0-9]+$' | head -1 | sed -nE 's/^([^,]+),.*/\1/p' | xargs)
fi

if [ -n "$night_hint" ]; then
  night_flag=1
else
  night_flag=0
fi

echo "$temp|$condition|$night_flag"
]]
  sbar.exec(cmd, function(output)
    local raw = tostring(output or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local temp, condition, night_flag = raw:match("^([^|]*)|([^|]*)|([^|]*)$")
    if not temp then
      temp, condition = raw:match("^([^|]*)|(.*)$")
    end
    temp = (temp or raw):gsub("^%s+", ""):gsub("%s+$", "")
    condition = (condition or ""):lower()
    local is_night = (night_flag or "") == "1"

    if temp == "" then
      weather:set({ label = { string = "--°C" } })
      return
    end

    local sf = {
      sun = "􀆭",
      moon = "􀆺",
      cloud = "􀇂",
      cloud_sun = "􀇕",
      cloud_moon = "􀇚",
      rain = "􀇄",
      snow = "􀇗",
      fog = "􀇅",
      thunder = "􀇟",
    }

    if not is_night then
      is_night = condition:find("night", 1, true)
        or condition:find("evening", 1, true)
        or condition:find("overnight", 1, true)
        or condition:find("moon", 1, true)
    end

    local icon = is_night and sf.moon or sf.sun
    if condition:find("thunder", 1, true) or condition:find("storm", 1, true) then
      icon = sf.thunder
    elseif condition:find("snow", 1, true) or condition:find("sleet", 1, true) then
      icon = sf.snow
    elseif condition:find("rain", 1, true) or condition:find("drizzle", 1, true) then
      icon = sf.rain
    elseif condition:find("fog", 1, true) or condition:find("mist", 1, true) then
      icon = sf.fog
    elseif condition:find("partly", 1, true) and condition:find("cloud", 1, true) then
      icon = is_night and sf.cloud_moon or sf.cloud_sun
    elseif condition:find("cloud", 1, true) or condition:find("overcast", 1, true) then
      icon = sf.cloud
    end

    weather:set({
      icon = { string = icon },
      label = { string = temp .. "°C" },
    })
  end)
end

weather:subscribe({ "routine", "system_woke", "forced" }, update_weather)
update_weather()
