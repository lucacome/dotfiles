-- Pure parsers for the weather widget (no sbar), so plain lua can test them.
local M = {}

-- Split one jq @tsv line. Empty fields are kept: dropping them shifts every
-- later column, e.g. a missing sunrise makes location show the condition.
function M.tsv(line)
  local fields = {}
  for field in (tostring(line or "") .. "\t"):gmatch("([^\t]*)\t") do
    fields[#fields + 1] = field
  end
  return fields
end

-- wttr.in astronomy times like "06:17 AM" / "08:14 PM"
function M.parse_12h(time)
  local hh, mm, ap = tostring(time or ""):match("(%d+):(%d+)%s*(%a+)")
  if not hh then return nil end
  local hour = tonumber(hh)
  ap = (ap or ""):upper()
  if ap == "PM" and hour < 12 then hour = hour + 12 end
  if ap == "AM" and hour == 12 then hour = 0 end
  return hour, mm
end

-- wttr.in dates like "2026-08-05"
function M.day_name(date)
  local y, m, d = tostring(date or ""):match("(%d+)-(%d+)-(%d+)")
  if not y then return date end
  return os.date("%A", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
end

return M
