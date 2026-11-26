-- Pure-logic checks. Run from the config dir: lua tests.lua
local utils = require("helpers.utils")
local weather = require("helpers.weather_parse")

local checks = 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    io.stderr:write(string.format("FAIL %s\n  got:  %q\n  want: %q\n",
      what, tostring(got), tostring(want)))
    os.exit(1)
  end
end

eq(utils.trim("  hi \n"), "hi", "trim strips both ends")
eq(utils.trim(nil), "", "trim nil")
eq(table.concat(utils.parse_lines("a\r\n\r\n b \n"), "|"), "a|b", "parse_lines drops empty lines")
eq(utils.shell_quote("it's"), "'it'\\''s'", "shell_quote escapes single quotes")

eq(table.concat(weather.tsv("a\t\tb"), "|"), "a||b", "tsv keeps empty fields")
eq(#weather.tsv(""), 1, "tsv empty line is one field")
eq(table.concat(weather.tsv("1\t2\t3"), "|"), "1|2|3", "tsv plain line")
eq(#weather.tsv("a\tb"), 2, "tsv no phantom trailing field")

local h, m = weather.parse_12h("06:17 AM")
eq(h, 6, "parse_12h am hour")
eq(m, "17", "parse_12h minutes")
eq((weather.parse_12h("08:14 PM")), 20, "parse_12h pm")
eq((weather.parse_12h("12:00 AM")), 0, "parse_12h midnight")
eq((weather.parse_12h("12:30 PM")), 12, "parse_12h noon")
eq(weather.parse_12h("nope"), nil, "parse_12h garbage")

eq(weather.day_name("2026-08-05"), "Wednesday", "day_name")
eq(weather.day_name("nope"), "nope", "day_name passthrough")

print(checks .. " checks passed")
