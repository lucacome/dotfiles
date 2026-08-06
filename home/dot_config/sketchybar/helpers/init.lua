-- Add the sketchybar module to the package cpath
package.cpath = package.cpath .. ";/Users/" .. os.getenv("USER") .. "/.local/share/sketchybar_lua/?.so"

-- Build the helper binaries once and reuse the result. Running `make` on every
-- config load spawns the whole recursive build chain on every reload, which
-- slows down wake recovery. The binaries only need rebuilding when their
-- sources change, so only trigger make when one of them is missing.
local home = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

local need_build = false
for _, rel in ipairs({
  "event_providers/cpu_load/bin/cpu_load",
  "event_providers/network_load/bin/network_load",
  "frontmost_watch/bin/frontmost_watch",
  "other_window_watch/bin/other_window_watch",
  "menus/bin/menus",
  "wake_watch/bin/wake_watch",
}) do
  if not exists(home .. "/helpers/" .. rel) then
    need_build = true
    break
  end
end

if need_build then
  os.execute("(cd helpers && make) >/dev/null 2>&1")
end

-- Start the standalone wake watchdog. It is a detached process, so it
-- survives bar reloads and even a wedged bar + lua (which is exactly when a
-- recovery trigger is needed). Guarded so a reload does not stack copies.
if exists(home .. "/helpers/wake_watch/bin/wake_watch") then
  -- pgrep -x matches the process name exactly, so the guard can never
  -- match the shell/config process that runs this check.
  local alive = ""
  local pipe = io.popen("/usr/bin/pgrep -x wake_watch 2>/dev/null")
  if pipe then
    alive = pipe:read("*a")
    pipe:close()
  end
  if alive == "" then
    os.execute("(" .. home .. "/helpers/wake_watch/bin/wake_watch >/dev/null 2>&1) &")
  end
end