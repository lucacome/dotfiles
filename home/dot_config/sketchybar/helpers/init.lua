-- Add the sketchybar module to the package cpath
package.cpath = package.cpath .. ";" .. (os.getenv("HOME") or "") .. "/.local/share/sketchybar_lua/?.so"

-- Build the helper binaries on every config load. make is incremental, so this
-- is a no-op when nothing changed and rebuilds when a source is newer than its
-- binary (an existence-only check left stale helpers running after edits).
local home = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

local build_log = home .. "/helpers/build.log"
local ok = os.execute("(cd '" .. home .. "/helpers' && make -s) >'" .. build_log .. "' 2>&1")
if not ok then
  io.stderr:write("[sketchybar] helper build failed; see " .. build_log .. "\n")
end

-- Start the standalone wake watchdog. It is a detached process, so it
-- survives bar reloads and even a wedged bar + lua (which is exactly when a
-- recovery trigger is needed). Guarded so a reload does not stack copies.
if exists(home .. "/helpers/wake_watch/bin/wake_watch") then
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
