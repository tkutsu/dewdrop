-- What the bar needs from Hyprland. Load it from hyprland.lua, ahead of your own
-- settings so that yours win where they overlap:
--
--   dofile(os.getenv("HOME") .. "/.config/quickshell/hypr/dewdrop.lua")
--
-- It returns the workspace module (workspaces.lua), for any keybinds you want on
-- the same ring of workspaces as the bar.

-- Popups close when a click lands outside them (src/core/OpenPopup.qml listens for these
-- as custom>>click), and the click still reaches whatever it landed on.
hl.bind("mouse:272", hl.dsp.event("click"), { non_consuming = true })
hl.bind("mouse:273", hl.dsp.event("click"), { non_consuming = true })
hl.bind("mouse:272", hl.dsp.event("click-release"), { release = true, non_consuming = true })
hl.bind("mouse:273", hl.dsp.event("click-release"), { release = true, non_consuming = true })

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
local layer_rules = {
	{ match = { namespace = "quickshell:launcher" }, ignore_alpha = 0.3, blur = true, animation = "none" },
	{ match = { namespace = "quickshell:blackout" }, blur = false, animation = "none" },
	-- The launcher's ! veil is the exception: only the compositor can fade a blur.
	{ match = { namespace = "quickshell:veil" }, blur = true, animation = "fade" },
	-- Tray menus and tooltips are child popups, so they need blur_popups on the bar.
	{ match = { namespace = "quickshell:bar" }, ignore_alpha = 0.3, blur = true, blur_popups = true },
	{ match = { namespace = "quickshell:backdrop" }, animation = "none" },
}
for _, rule in ipairs(layer_rules) do
	hl.layer_rule(rule)
end

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
