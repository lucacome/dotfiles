hs.loadSpoon("AllBrightness")
spoon.AllBrightness:start()

function launchOrFocus(app)
	return function()
		hs.application.launchOrFocus(app)
	end
end

function runCommand(command)
	return function()
		hs.task.new(command, nil):start()
	end
end

-- helpers
local function expand(path)
	return path:gsub("^~", os.getenv("HOME"))
end
local function launchOrFocus(app)
	return function()
		hs.application.launchOrFocus(app)
	end
end
local function openPath(path)
	return function()
		hs.execute(string.format('open -a Finder "%s"', expand(path)))
	end
end
local function openURL(url)
	return function()
		hs.urlevent.openURL(url)
	end
end
local function runShell(cmd)
	return function()
		hs.execute(cmd)
	end
end

local function showHyperHelp()
	local lines = { "HYPER HELP (hold F20):" }
	for topKey, layer in pairs(layers) do
		table.insert(lines, string.format("%s: %s", topKey, layer.name))
		for k, v in pairs(layer.keys) do
			table.insert(lines, string.format("  %s %s → %s", topKey, k, v.desc))
		end
	end
	hs.alert.show(table.concat(lines, "\n"), 5) -- show for 5s
end

-- --- data: layers, keys, descriptions, action functions ---
local layers = {
	-- open layer: HYPER + o + <key>
	o = {
		name = "Open",
		keys = {
			c = {
				desc = "Calendar",
				fn = launchOrFocus("Calendar"),
			},
			i = {
				desc = "iMessage",
				fn = launchOrFocus("Messages"),
			},
			m = {
				desc = "Music",
				fn = launchOrFocus("Music"),
			},
			s = {
				desc = "Signal",
				fn = launchOrFocus("Signal"),
			},
			t = {
				desc = "Terminal",
				fn = launchOrFocus("Ghostty"),
			},
			v = {
				desc = "VSCode",
				fn = launchOrFocus("Visual Studio Code - Insiders"),
			},
			z = {
				desc = "Zoom",
				fn = launchOrFocus("zoom.us"),
			},
			b = {
				desc = "Browser",
				fn = launchOrFocus("Brave Browser"),
			},
			d = {
				desc = "Downloads",
				fn = openPath("~/Downloads"),
			},
			f = {
				desc = "Finder",
				fn = launchOrFocus("Finder"),
			},
			g = {
				desc = "Bitwarden",
				fn = launchOrFocus("Bitwarden"),
			},
			o = {
				desc = "Discord",
				fn = launchOrFocus("Discord"),
			},
		},
	},

	-- browse layer: HYPER + b + <key>
	b = {
		name = "Browse",
		keys = {
			c = {
				desc = "ChatGPT",
				fn = openURL("https://chat.openai.com"),
			},
			g = {
				desc = "GitHub",
				fn = openURL("https://www.github.com/notifications"),
			},
			r = {
				desc = "Reddit",
				fn = openURL("https://www.reddit.com"),
			},
			y = {
				desc = "YouTube",
				fn = openURL("https://www.youtube.com"),
			},
			m = {
				desc = "9to5mac",
				fn = openURL("https://9to5mac.com/"),
			},
		},
	},

	-- system layer: HYPER + s + <key>
	s = {
		name = "System",
		keys = {
			o = {
				desc = "Open Lights",
				fn = openURL("raycast://extensions/tonka3000/homeassistant/lights"),
			},
			l = {
				desc = "Lock screen",
				fn = function()
					hs.caffeinate.lockScreen()
				end,
			},
			m = {
				desc = "Sleep display",
				fn = function()
					hs.caffeinate.displaySleep()
				end,
			},
			q = {
				desc = "Quit Hammerspoon",
				fn = function()
					hs.alert.show("Reloading Hammerspoon")
					hs.reload()
				end,
			},
			c = {
				desc = "Open Camera",
				fn = openURL("raycast://extensions/raycast/system/open-camera"),
			},
			d = {
				desc = "Toggle Do Not Disturb",
				fn = openURL("raycast://extensions/yakitrak/do-not-disturb/toggle?launchType=background"),
			},
		},
	},

	-- raycast layer: HYPER + r + <key>
	r = {
		name = "Raycast",
		keys = {
			c = {
				desc = "Clipboard",
				fn = openURL("raycast://extensions/raycast/clipboard-history/clipboard-history"),
			},
			n = {
				desc = "Dismiss Notifications",
				fn = openURL("raycast://script-commands/dismiss-notifications"),
			},
			e = {
				desc = "Emoji",
				fn = openURL("raycast://extensions/raycast/emoji-symbols/search-emoji-symbols"),
			},
		},
	},
}

-- state (simplified)
local hyper = hs.hotkey.modal.new()
local submodals = {}
local activeSubmodal = nil -- track currently active submodal
local hyperHeld = false -- track if HYPER is physically held
local hyperActive = false -- track if hyper modal is active
local hyperUsedForControl = false -- track if any sublayer was used

-- build sub-modals and bindings
for topKey, layer in pairs(layers) do
	local modal = hs.hotkey.modal.new()
	submodals[topKey] = modal

	-- bind each inner key; keep modal active after action
	for k, action in pairs(layer.keys) do
		local capturedAction = action -- capture the action by value for the closure
		modal:bind({}, k, function()
			if type(capturedAction.fn) == "function" then
				pcall(capturedAction.fn)
			end
			-- intentionally DO NOT call modal:exit() so submodal remains active while HYPER is held
		end)
	end
end

-- HYPER down: enter hyper; HYPER up: exit all modals or send ESC if not used
hs.hotkey.bind({}, "F20", function()
	hyperHeld = true
	hyperUsedForControl = false -- reset: assume F20 is just being tapped
	if not hyperActive then
		hyper:enter()
		hyperActive = true
	end
end, function()
	hyperHeld = false
	-- Exit active submodal if any
	if activeSubmodal then
		pcall(function()
			activeSubmodal:exit()
		end)
		activeSubmodal = nil
	end
	-- Exit hyper
	if hyperActive then
		pcall(function()
			hyper:exit()
		end)
		hyperActive = false
	end
	-- Send ESC only if no sublayer was used
	if not hyperUsedForControl then
		hs.eventtap.keyStroke({}, "escape")
	end
end)

-- Bind sublayer keys (o, b, s, etc.) in hyper modal with press/release
-- Key down: switch to this submodal (and exit hyper to avoid conflicts)
-- Key up: exit submodal and re-enter hyper (if HYPER still held)
for topKey, _ in pairs(layers) do
	hyper:bind({}, topKey, function()
		hyperUsedForControl = true -- mark that F20 was used for a sublayer
		-- Exit previous submodal if different
		if activeSubmodal and activeSubmodal ~= submodals[topKey] then
			pcall(function()
				activeSubmodal:exit()
			end)
		end
		-- Enter new submodal
		if activeSubmodal ~= submodals[topKey] then
			-- Exit hyper to avoid key conflicts with submodal bindings
			pcall(function()
				hyper:exit()
			end)
			hyperActive = false

			activeSubmodal = submodals[topKey]
			pcall(function()
				activeSubmodal:enter()
			end)
		end
	end, function()
		-- Exit submodal and re-enter hyper (only if HYPER is still held)
		if hyperHeld and activeSubmodal and activeSubmodal == submodals[topKey] then
			pcall(function()
				activeSubmodal:exit()
			end)
			activeSubmodal = nil

			-- Re-enter hyper if HYPER is still held
			if hyperHeld and not hyperActive then
				pcall(function()
					hyper:enter()
				end)
				hyperActive = true
			end
		end
	end)
end

--
-- Auto-reload config on change.
--

function reloadConfig(files)
	for _, file in pairs(files) do
		if file:sub(-4) == ".lua" then
			hs.reload()
		end
	end
end

hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
