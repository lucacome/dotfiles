-- Close popups when the user interacts with a different window.
-- Two mechanisms:
--   1. front_app_switched / space_windows_change (fires for app switches, but
--      NOT when clicking another window of the same app).
--   2. A poller that watches the frontmost window identity (pid + window
--      number) every 0.5s while a popup is open and collapses it the instant
--      it changes. This is deterministic and covers same-app window clicks,
--      leaving the bar, etc. (mouse.exited.* is unreliable in SketchyBar).
local M = {}

local registry = {}
local front_snapshot = nil
local checking_front = false
local checking_cursor = false

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

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
    local q = r.target:query()
    if q and q.popup and q.popup.drawing == "on" then
      return true
    end
  end
  return false
end

local function check_frontmost()
  if checking_front then return end
  checking_front = true
  sbar.exec("$CONFIG_DIR/helpers/frontmost_watch/bin/frontmost_watch", function(out)
    checking_front = false
    local sig = trim(out)
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

local function check_cursor()
  if checking_cursor then return end
  checking_cursor = true
  sbar.exec("$CONFIG_DIR/helpers/other_window_watch/bin/other_window_watch", function(out)
    checking_cursor = false
    if not any_open() then
      return
    end
    if trim(out) == "1" then
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
  check_cursor()
end)

function M.track(name, target, close)
  registry[name] = { target = target, close = close }
end

function M.close_others(name)
  for n, r in pairs(registry) do
    if n ~= name then
      pcall(r.close)
    end
  end
end

return M