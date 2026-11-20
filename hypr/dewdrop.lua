-- What the bar needs from Hyprland. Load it from hyprland.lua, ahead of your own
-- settings so that yours win where they overlap:
--
--   dofile(os.getenv("HOME") .. "/.config/quickshell/hypr/dewdrop.lua")
--
-- It returns the workspace module (workspaces.lua), for any keybinds you want on
-- the same ring of workspaces as the bar. Load it once, since it hooks Hyprland's
-- events. To reach it from other files, keep it where `require` finds it:
--
--   package.loaded.dewdrop = dofile(os.getenv("HOME") .. "/.config/quickshell/hypr/dewdrop.lua")
--   local workspaces = require("dewdrop")   -- in keybinds.lua
--
-- The launcher and the settings window are layers, not windows, so while one is
-- up `hl.get_active_window()` still names the window behind it. A bind of yours
-- that acts on the active window has to step aside for them:
--
--   - Escape: a bind that takes Escape for an app passes it on with
--     `return { ok = false }` while a "quickshell:launcher" layer is mapped
--     (hl.get_layers()). They take every Escape from there.
--   - Closing: a close shortcut runs `qs ipc call launcher dismiss`, then
--     `qs ipc call settings dismiss`, and stops at the first that prints true.
--     Each closes its window if it was up and says whether it was.
--
-- Both hold the keyboard exclusively while they are up, so a shortcut that
-- moves to another window or workspace, or the pointer under follow_mouse,
-- does not take it from them.

-- The bar starts with Hyprland. When it stops on its own (a crash, a config that
-- will not load), Hyprland says so itself, since the bar was what showed
-- notifications, and Super+Ctrl+Alt+V starts it again. Quitting it on purpose
-- (`qs kill`, SIGTERM) stays quiet, and so does the shortcut while a bar is up.
-- A script that restarts the bar should start it the same way, so the next stop
-- is reported too:
--
--   hyprctl dispatch 'start_bar()'
--
-- A bar that dies while the screen is locked (the runtime file `locked` says
-- so, src/services/Lock.qml) is started again at once and locks again, taking
-- over from Hyprland's "lockscreen app died" screen. Three quick deaths in a
-- row and it stops trying; the shortcut works on that screen too.
local bar = [[
hyprctl dismissnotify >/dev/null
flag=${XDG_RUNTIME_DIR:-$HOME/.cache}/quickshell/locked
quick=0
while :; do
	since=$(date +%s)
	quickshell -n & pid=$!
	wait $pid
	case $? in 0 | 143) exit ;; esac
	[ $(($(date +%s) - since)) -lt 60 ] && quick=$((quick + 1)) || quick=0
	[ -s "$flag" ] && [ $quick -lt 3 ] || break
done
hyprctl notify 0 3600000 0 "Dewdrop stopped. Press Super+Ctrl+Alt+V to start it, or run qs log --pid $pid to see why."
]]

function start_bar()
	return hl.dsp.exec_cmd(bar)
end

hl.on("hyprland.start", function()
	hl.exec_cmd(bar)
end)
hl.bind("SUPER + CTRL + ALT + V", start_bar(), { locked = true, description = "Start the Bar" })
hl.config({ misc = { allow_session_lock_restore = true } })

-- Popups close when a click lands outside them (src/core/OpenPopup.qml listens for these
-- as custom>>click), and the click still reaches whatever it landed on.
hl.bind("mouse:272", hl.dsp.event("click"), { non_consuming = true })
hl.bind("mouse:273", hl.dsp.event("click"), { non_consuming = true })
hl.bind("mouse:272", hl.dsp.event("click-release"), { release = true, non_consuming = true })
hl.bind("mouse:273", hl.dsp.event("click-release"), { release = true, non_consuming = true })

-- A click outside the launcher or the settings window reaches the window under
-- it but cannot focus it, since they hold the keyboard. They call this once
-- they let go, to focus the window the click landed on. Topmost first: a shown
-- special workspace, then a fullscreen window, then floating, then tiled, and
-- among those the one focused last.
local function above(a, b)
	for i = 1, #a do
		if a[i] ~= b[i] then
			return a[i] > b[i]
		end
	end
	return false
end

function focus_under_cursor()
	return function()
		local cursor = hl.get_cursor_pos()
		if not cursor then
			return
		end
		local best, best_rank
		for _, w in ipairs(hl.get_windows({ mapped = true })) do
			local ws = w.workspace
			if ws and ws.visible and w.visible and not w.hidden
				and cursor.x >= w.at.x and cursor.x < w.at.x + w.size.x
				and cursor.y >= w.at.y and cursor.y < w.at.y + w.size.y then
				local rank = {
					ws.special and 1 or 0,
					(w.fullscreen or 0) > 0 and 1 or 0,
					(w.floating or w.pinned) and 1 or 0,
					-w.focus_history_id,
				}
				if not best or above(rank, best_rank) then
					best, best_rank = w, rank
				end
			end
		end
		if best then
			hl.dispatch(hl.dsp.focus({ window = best }))
		end
	end
end

-- The glass: the launcher and popups are thin fills over this blur, so it decides
-- whether a bright patch behind them reads as a soft glow or as a shape.
hl.config({
	decoration = {
		blur = {
			enabled = true,
			size = 5,
			passes = 3,
			ignore_opacity = true,
			noise = 0.03,
			contrast = 1.0,
			vibrancy = 0.24,
			popups = true,
		},
	},
})

-- The alpha floor keeps blur to the panels on transparent surfaces, and each
-- surface animates itself, so Hyprland's own layer animation stays out of it.
-- `order` stacks surfaces that share the overlay layer: the launcher and the
-- settings window over other apps' overlays (kitty's quick access terminal
-- would otherwise draw over them when it opens later), and the password panel
-- over everything, since a password can be asked for at any time.
local layer_rules = {
	{ match = { namespace = "quickshell:launcher" }, ignore_alpha = 0.3, blur = true, animation = "none", order = 1 },
	-- The launcher's ! veil is the exception: only the compositor can fade a blur.
	{ match = { namespace = "quickshell:veil" }, blur = true, animation = "fade" },
	-- So is the password panel, which comes and goes with its window.
	{ match = { namespace = "quickshell:polkit" }, ignore_alpha = 0.3, blur = true, animation = "fade", order = 2 },
	-- Tray menus and tooltips are child popups, so they need blur_popups on the bar.
	{ match = { namespace = "quickshell:bar" }, ignore_alpha = 0.3, blur = true, blur_popups = true },
	{ match = { namespace = "quickshell:backdrop" }, animation = "none" },
	-- The lock screen's curtain fades itself, in step with the lock.
	{ match = { namespace = "quickshell:curtain" }, animation = "none" },
}
for _, rule in ipairs(layer_rules) do
	hl.layer_rule(rule)
end

-- The terminals the bar opens for a moment (Upgrade, Install, joining a network,
-- signing in to Google) end their title in "(floating)", and float over the work
-- rather than tiling into it.
hl.window_rule({
	match = { title = ".*\\(floating\\)$" },
	float = true,
	center = true,
	size = { "monitor_w*0.6", "monitor_h*0.8" },
})

-- Popups and the veil fade their blur along with the surface, which only the
-- compositor can do. Popups arrive fast and leave faster and plainer; the veil
-- is slow enough to be seen.
hl.curve("dewdrop_smooth", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("dewdrop_linear", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })
hl.curve("dewdrop_ease", { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1.0 } } })
hl.animation({ leaf = "fadePopupsIn", enabled = true, speed = 1, bezier = "dewdrop_smooth" })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 1.2, bezier = "dewdrop_linear" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 4, bezier = "dewdrop_ease" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 2.5, bezier = "dewdrop_ease" })

-- Scrolling over the bar's workspaces and dragging a window onto one call into
-- this, which also keeps the numbered workspaces free of gaps.
local here = debug.getinfo(1, "S").source:match("^@(.*)/")
return dofile(here .. "/workspaces.lua")
