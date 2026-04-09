-- Require the sketchybar module
sbar = require("sketchybar")

-- Set the bar name, if you are using another bar instance than sketchybar
-- sbar.set_bar_name("bottom_bar")

-- Bundle the entire initial configuration into a single message to sketchybar
sbar.begin_config()
require("bar")
require("default")
require("items")
sbar.end_config()

-- After waking from sleep the bar window can fail to re-establish itself on
-- the display (especially on multi-monitor setups). Nudge sketchybar to
-- un-hide the bar. Each widget handles its own system_woke callback, so
-- sbar.update() is not needed here (and could cascade into slow work).
local wake_watcher = sbar.add("item", { drawing = false, updates = true })
wake_watcher:subscribe("system_woke", function(_)
  sbar.bar({ hidden = false })
end)

-- Run the event loop of the sketchybar module (without this there will be no
-- callback functions executed in the lua module)
sbar.event_loop()
