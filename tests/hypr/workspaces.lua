local source = assert(arg[0]:match("^(.*)/tests/")) .. "/hypr/workspaces.lua"
local passed = 0

-- Model workspace identity, delayed cleanup and synchronous callbacks without touching the desktop.
local function desktop(specs, active_id)
	local state = { workspaces = {}, monitors = {}, events = {}, timers = {}, changes = {} }
	local monitor = { id = 0 }
	state.monitors[1] = monitor
	local function lookup(id)
		for _, workspace in ipairs(state.workspaces) do
			if workspace.id == id then
				return workspace
			end
		end
	end
	local function create(id, count)
		local workspace = { id = id, name = tostring(id), windows = count or 0, monitor = monitor }
		table.insert(state.workspaces, workspace)
		return workspace
	end
	for _, spec in ipairs(specs) do
		local workspace = create(spec[1], spec[2])
		workspace.special = spec.special
		workspace.is_persistent = spec.persistent
	end
	monitor.active_workspace = lookup(active_id)
	if monitor.active_workspace then
		monitor.active_workspace.visible = true
	end
	function state.emit(event)
		for _, callback in ipairs(state.events[event] or {}) do
			callback()
		end
	end
	function state.focus(id)
		local target = lookup(id) or create(id)
		assert(target ~= monitor.active_workspace, "re-focusing would invoke back-and-forth")
		if monitor.active_workspace then
			monitor.active_workspace.visible = false
		end
		monitor.active_workspace = target
		target.visible = true
		state.emit("workspace.active")
	end
	function state.cleanup()
		for index = #state.workspaces, 1, -1 do
			local workspace = state.workspaces[index]
			if workspace.windows == 0 and not workspace.visible and not workspace.is_persistent then
				table.remove(state.workspaces, index)
			end
		end
		state.emit("workspace.removed")
	end
	function state.flush()
		for _, timer in ipairs(state.timers) do
			if timer.enabled then
				timer.enabled = false
				timer.callback()
				if timer.type == "oneshot" then
					timer.alive = false
					timer.enabled = false
				end
			end
		end
	end
	function state.ids()
		local ids = {}
		for _, workspace in ipairs(state.workspaces) do
			if workspace.id > 0 then
				table.insert(ids, workspace.id)
			end
		end
		table.sort(ids)
		return table.concat(ids, ",")
	end
	_G.hl = {
		workspace_rule = function() end,
		get_workspaces = function() return state.workspaces end,
		get_workspace = lookup,
		get_active_workspace = function() return monitor.active_workspace end,
		get_active_window = function() return state.window end,
		get_window = function(selector) return state.windows and state.windows[selector] end,
		get_last_workspace = function() return state.previous end,
		dispatch = function(callback) return callback() end,
		on = function(event, callback)
			state.events[event] = state.events[event] or {}
			table.insert(state.events[event], callback)
		end,
		timer = function(callback, options)
			local timer = { callback = callback, enabled = true, type = options.type, alive = true }
			function timer:set_enabled(enabled)
				if self.alive then self.enabled = enabled end
			end
			table.insert(state.timers, timer)
			return timer
		end,
		dsp = {
			focus = function(options) return function() state.focus(options.workspace) end end,
			workspace = {
				change_id = function(options)
					return function()
						assert(not lookup(options.id), "destination ID is occupied")
						if state.fail_change then error("dispatcher failed") end
						table.insert(state.changes, { options.workspace.id, options.id })
						options.workspace.id = options.id
						state.emit("workspace.created")
					end
				end,
				rename = function(options)
					return function() options.workspace.name = options.name end
				end,
			},
			window = {
				move = function(options)
					return function()
						local target = lookup(options.workspace) or create(options.workspace)
						options.window.workspace.windows = options.window.workspace.windows - 1
						target.windows = target.windows + 1
						options.window.workspace = target
						state.emit("window.move_to_workspace")
						if options.follow then state.focus(target.id) end
					end
				end,
			},
		},
	}
	state.module = dofile(source)
	state.lookup = lookup
	state.monitor = monitor
	return state
end

local function test(name, run)
	run()
	passed = passed + 1
	print("PASS " .. name)
end

test("compact sparse IDs without moving windows or focus", function()
	local state = desktop({ { 1, 1 }, { 2, 2 }, { 10, 3 }, { -99, 1 }, { -2, 1, special = true } }, 1)
	local old_ten = state.lookup(10)
	state.window = { workspace = old_ten }
	state.module.compact()
	assert(state.ids() == "1,2,3")
	assert(state.window.workspace == old_ten and old_ten.id == 3 and old_ten.windows == 3)
	assert(state.monitor.active_workspace.id == 1 and old_ten.name == "3")
	assert(state.lookup(-99) and state.lookup(-2))
end)

test("wrap both ways and reuse the only empty slot", function()
	local state = desktop({ { 1, 1 }, { 2, 1 }, { 3, 1 } }, 1)
	for _, expected in ipairs({ 2, 3, 4, 1 }) do
		state.module.cycle(1)
		assert(state.monitor.active_workspace.id == expected)
	end
	state.module.cycle(-1)
	assert(state.monitor.active_workspace.id == 4)
	state.module.cycle(1)
	assert(state.monitor.active_workspace.id == 1)
	state.cleanup()
	state.flush()
	state.module.cycle(-1)
	assert(state.monitor.active_workspace.id == 4 and state.ids() == "1,2,3,4")
end)

test("populating the empty slot unlocks exactly one more", function()
	local state = desktop({ { 1, 1 }, { 2, 0 } }, 2)
	state.lookup(2).windows = 1
	state.module.cycle(1)
	assert(state.monitor.active_workspace.id == 3)
	state.module.focus_number(5)
	assert(state.ids() == "1,2,3")
end)

test("retain a middle empty workspace until it is left and cleaned up", function()
	local state = desktop({ { 1, 1 }, { 2, 0 }, { 3, 1 }, { 4, 1 } }, 2)
	state.module.compact()
	assert(state.ids() == "1,2,3,4")
	state.module.cycle(1)
	state.flush()
	assert(state.monitor.active_workspace.id == 3 and state.ids() == "1,2,3,4")
	state.cleanup()
	state.flush()
	assert(state.ids() == "1,2,3" and state.monitor.active_workspace.id == 2)
end)

test("keep an empty workspace visible on another monitor", function()
	local state = desktop({ { 1, 1 }, { 2, 0 }, { 3, 1 } }, 1)
	local second = { id = 1, active_workspace = state.lookup(2) }
	state.lookup(2).monitor = second
	table.insert(state.monitors, second)
	state.module.compact()
	state.module.cycle(-1)
	assert(state.ids() == "1,2,3" and state.monitor.active_workspace.id == 3)
	assert(second.active_workspace.id == 2)
end)

test("no windows leaves workspace one and repeated number keys do nothing", function()
	local state = desktop({ { 1, 0 } }, 1)
	state.module.cycle(1)
	state.module.cycle(-1)
	state.module.focus_number(1)
	state.module.focus_number(8)
	assert(state.ids() == "1")
end)

test("moving the last window compacts its destination without losing the window", function()
	local state = desktop({ { 1, 1 }, { 2, 1 }, { 3, 1 } }, 2)
	state.window = { workspace = state.lookup(2) }
	state.module.move_window(1)
	assert(state.window.workspace.id == 3 and state.monitor.active_workspace.id == 3)
	state.cleanup()
	state.flush()
	assert(state.ids() == "1,2" and state.window.workspace.id == 2)
	assert(state.window.workspace.windows == 2)
end)

test("silent number moves allow only existing IDs or the next slot", function()
	local state = desktop({ { 1, 1 }, { 2, 1 } }, 1)
	state.window = { workspace = state.lookup(1) }
	state.module.move_number(8)
	assert(state.window.workspace.id == 1)
	state.module.move_number(3)
	assert(state.window.workspace.id == 3 and state.monitor.active_workspace.id == 1)
end)

test("an empty active workspace must not move Hyprland's stale active window", function()
	local state = desktop({ { 1, 1 }, { 2, 0 } }, 2)
	state.window = { workspace = state.lookup(1) }
	state.module.move_window(-1)
	state.module.move_number(2)
	assert(state.window.workspace.id == 1 and state.lookup(1).windows == 1)
end)

test("previous navigation ignores a destroyed workspace", function()
	local state = desktop({ { 1, 1 }, { 2, 1 } }, 1)
	state.previous = { id = 10 }
	state.module.previous()
	assert(state.ids() == "1,2" and state.monitor.active_workspace.id == 1)
end)

test("a failed compaction releases its reentrancy guard", function()
	local state = desktop({ { 1, 1 }, { 3, 1 } }, 1)
	state.fail_change = true
	assert(not pcall(state.module.compact))
	state.fail_change = false
	state.module.compact()
	assert(state.ids() == "1,2")
end)

test("config verification never starts a runtime timer", function()
	local state = desktop({}, nil)
	state.emit("config.reloaded")
	assert(#state.timers == 0)
end)

test("the same timer can retry cleanup and compact again on a later event", function()
	local state = desktop({ { 1, 1 }, { 2, 0 }, { 3, 1 } }, 1)
	state.emit("window.close")
	state.flush()
	assert(state.timers[1].enabled, "cleanup retry was not scheduled")
	state.cleanup()
	state.flush()
	assert(state.ids() == "1,2" and not state.timers[1].enabled)
	table.insert(state.workspaces, { id = 4, name = "4", windows = 1, monitor = state.monitor })
	state.emit("workspace.created")
	state.flush()
	assert(state.ids() == "1,2,3" and #state.timers == 1 and not state.timers[1].enabled)
end)

test("the bar callback uses the same ring", function()
	local state = desktop({ { 1, 1 }, { 2, 1 } }, 1)
	hl.dispatch(workspace_cycle(-1))
	assert(state.monitor.active_workspace.id == 3)
end)

test("a drop between workspaces moves the rest up to make room", function()
	local state = desktop({ { 1, 1 }, { 2, 2 }, { 3, 1 } }, 3)
	local second, third = state.lookup(2), state.lookup(3)
	local window = { workspace = second, mapped = true }
	state.windows = { ["address:a"] = window }
	hl.dispatch(insert_window_at(2, "a"))
	assert(state.ids() == "1,2,3,4" and window.workspace.id == 2 and window.workspace.windows == 1)
	assert(second.id == 3 and second.windows == 1 and third.id == 4 and third.name == "4")
	assert(state.monitor.active_workspace == third)
end)

test("a lone window dropped further left leaves no gap behind", function()
	local state = desktop({ { 1, 1 }, { 2, 1 }, { 3, 1 } }, 1)
	local window = { workspace = state.lookup(3), mapped = true }
	state.windows = { ["address:a"] = window }
	hl.dispatch(insert_window_at(2, "a"))
	state.cleanup()
	state.flush()
	assert(state.ids() == "1,2,3" and window.workspace.id == 2 and state.monitor.active_workspace.id == 1)
end)

test("workspaces moved up past ten keep the 0 key's name straight", function()
	local specs = {}
	for id = 1, 10 do
		specs[id] = { id, 1 }
	end
	local state = desktop(specs, 1)
	local ninth, tenth = state.lookup(9), state.lookup(10)
	tenth.name = "0"
	state.windows = { ["address:a"] = { workspace = state.lookup(1), mapped = true } }
	hl.dispatch(insert_window_at(9, "a"))
	assert(ninth.id == 10 and ninth.name == "0" and tenth.id == 11 and tenth.name == "11")
end)

test("a drop between workspaces needs the window and the workspace", function()
	local state = desktop({ { 1, 1 }, { 2, 1 } }, 1)
	state.windows = { ["address:a"] = { workspace = state.lookup(1), mapped = true } }
	hl.dispatch(insert_window_at(5, "a"))
	hl.dispatch(insert_window_at(2, "b"))
	assert(state.ids() == "1,2" and #state.changes == 0)
end)

test("numbered navigation ignores workspaces without numeric IDs", function()
	local state = desktop({ { 1, 1 }, { 2, 1 } }, 1)
	local special = { name = "special:dolphin", special = true, windows = 1 }
	local named = { name = "named", special = false, windows = 1 }
	table.insert(state.workspaces, special)
	table.insert(state.workspaces, named)
	state.module.compact()
	state.module.cycle(1)
	assert(state.monitor.active_workspace.id == 2)
	assert(special.id == nil and named.id == nil and #state.changes == 0)
end)

test("previous navigation ignores a workspace without a numeric ID", function()
	local state = desktop({ { 1, 1 } }, 1)
	state.previous = { name = "special:dolphin", special = true }
	state.module.previous()
	assert(state.monitor.active_workspace.id == 1)
end)

test("numbered moves leave a window on a workspace without a numeric ID", function()
	local state = desktop({ { 1, 1 }, { 2, 1 } }, 1)
	local named = { name = "named", windows = 1, monitor = state.monitor }
	table.insert(state.workspaces, named)
	state.monitor.active_workspace = named
	state.window = { workspace = named }
	state.module.move_number(2)
	assert(state.window.workspace == named and named.windows == 1)
end)

print(string.format("%d workspace checks passed", passed))
