-- Wake state that survives bar reloads.
-- The watchdog restarts the bar (--reload) after system wake, which wipes
-- all Lua state. Widgets that need to react to a wake after the reload (e.g.
-- the aerospace refresh guard, a weather retry) read this file instead of
-- subscribing to system_woke themselves, keeping the watchdog the only
-- subscriber.
local M = {}

local config_dir = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")
local state_file = config_dir .. "/.wake-state"

function M.recent_woke(within_seconds)
  local f = io.open(state_file, "r")
  if not f then return false end
  local stamp = tonumber(f:read("*a"))
  f:close()
  return stamp ~= nil and (os.time() - stamp) <= within_seconds
end

function M.record_woke()
  local f = io.open(state_file, "w")
  if f then
    f:write(os.time())
    f:close()
  end
end

return M