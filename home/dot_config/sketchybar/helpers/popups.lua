-- Close popups when the user interacts with a different window.
-- Two mechanisms:
--   1. front_app_switched / space_windows_change (fires for app switches, but
--      NOT when clicking another window of the same app).
--   2. A poller that watches the frontmost window identity (pid + window
--      number) every 0.5s while a popup is open and collapses it the instant
--      it changes. This is deterministic and covers same-app window clicks,
--      leaving the bar, etc. (mouse.exited.* is unreliable in SketchyBar).
-- Open state is tracked here, not queried: the old check cost five IPC
-- round-trips per second even with every popup closed.
local M = {}

local utils = require("helpers.utils")

local registry = {}
local front_snapshot = nil
local checking_front = false

local function collapse_all()
  for _, r in pairs(registry) do
    local ok, err = pcall(r.close)
    if not ok then
      print("popups: " .. tostring(err))
    end
  end
  front_snapshot = nil
end

local function any_open()
  for _, r in pairs(registry) do
    if r.open then return true end
  end
  return false
end

local function check_frontmost()
  -- Only spawn the (expensive, window-enumerating) helper while a popup is
  -- actually open; at idle this is 2 subprocesses per second saved.
  if checking_front then return end
  if not any_open() then
    front_snapshot = nil
    return
  end
  checking_front = true
  sbar.exec("$CONFIG_DIR/helpers/frontmost_watch/bin/frontmost_watch", function(out)
    checking_front = false
    local sig = utils.trim(out)
    if not any_open() then
      front_snapshot = nil
      return
    end
    if sig == "" then
      return
    end
    if not front_snapshot then
      front_snapshot = sig
      return
    end
    if sig ~= front_snapshot then
      collapse_all()
    end
  end)
end

-- App/space-level events: closes popups on app switch or window create/destroy.
sbar.add("item", {
  drawing = false,
  updates = true,
}):subscribe({ "front_app_switched", "space_windows_change" }, collapse_all)

local observer = sbar.add("item", {
  drawing = false,
  updates = true,
  update_freq = 1,
})
observer:subscribe("routine", function()
  check_frontmost()
end)

function M.track(name, target, close)
  registry[name] = {
    target = target,
    open = false,
    close = function()
      close()
      registry[name].open = false
    end,
  }
end

function M.is_open(name)
  local r = registry[name]
  return r ~= nil and r.open
end

-- Every popup open/close goes through here so the tracked state stays true.
-- drawing is true, false or "toggle".
function M.draw(name, drawing)
  local r = registry[name]
  if not r then return end
  if drawing == "toggle" then
    drawing = not r.open
  end
  r.open = drawing and true or false
  r.target:set({ popup = { drawing = r.open } })
end

function M.close_others(name)
  for n, r in pairs(registry) do
    if n ~= name then
      pcall(r.close)
    end
  end
end

return M
