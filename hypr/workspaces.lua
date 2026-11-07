local M = {}
local compacting = false
local timer

-- The tenth workspace sits on the 0 key, so it is named for it from creation.
hl.workspace_rule({ workspace = "10", default_name = "0" })

-- Numbered workspaces share one order across monitors; named and special ones are independent.
local function numbered()
	local result = {}
	for _, workspace in ipairs(hl.get_workspaces()) do
		if type(workspace.id) == "number" and workspace.id > 0 and not workspace.special then
			table.insert(result, workspace)
		end
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

-- A monitor's active workspace stays usable even when empty or covered by a scratchpad.
local function retained(workspace)
	return workspace.windows > 0 or workspace.visible or workspace.is_persistent
		or (workspace.monitor and workspace.monitor.active_workspace == workspace)
end

local function schedule()
	-- The standalone config verifier emits reload events without a desktop or event loop.
	if not compacting and hl.get_active_workspace() then
		if not timer then
			-- One-shot timers are destroyed after firing; keep a reusable timer disarmed between events.
			timer = hl.timer(function()
				timer:set_enabled(false)
				M.compact()
			end, { timeout = 100, type = "repeat" })
		end
		timer:set_enabled(true)
	end
end

-- Give a workspace a new ID, and the name that goes with it unless it was named by hand.
local function renumber(workspace, id)
	local numeric_name = workspace.name:match("^%d+$") ~= nil
	if workspace.id ~= id then
		hl.dispatch(hl.dsp.workspace.change_id({ workspace = workspace, id = id }))
		assert(workspace.id == id, "Could not renumber workspace to " .. id)
	end
	local name = id == 10 and "0" or tostring(id)
	if numeric_name and workspace.name ~= name then
		hl.dispatch(hl.dsp.workspace.rename({ workspace = workspace, name = name }))
	end
end

-- Change whole workspace IDs after Hyprland releases empty ones, preserving windows and focus.
function M.compact()
	if compacting then
		return
	end
	local workspaces = numbered()
	for _, workspace in ipairs(workspaces) do
		if not retained(workspace) then
			-- Empty workspaces can survive until the compositor's next cleanup pass.
			schedule()
			return
		end
	end

	compacting = true
	local ok, err = xpcall(function()
		for id, workspace in ipairs(workspaces) do
			renumber(workspace, id)
		end
	end, debug.traceback)
	compacting = false
	if not ok then
		error(err)
	end
end

-- Reuse an existing visible empty workspace; otherwise append one uncreated empty slot.
local function ring()
	M.compact()
	local ids, has_empty, last_id = {}, false, 0
	for _, workspace in ipairs(numbered()) do
		if retained(workspace) then
			table.insert(ids, workspace.id)
			last_id = workspace.id
			has_empty = has_empty or workspace.windows == 0
		end
	end
	if not has_empty then
		table.insert(ids, last_id + 1)
	end
	return ids
end

local function in_ring(id)
	for _, allowed in ipairs(ring()) do
		if id == allowed then
			return true
		end
	end
	return false
end

local function focus(id)
	local active = hl.get_active_workspace()
	-- Re-focusing the same ID would trigger Hyprland's back-and-forth setting.
	if not active or active.id ~= id then
		hl.dispatch(hl.dsp.focus({ workspace = id }))
	end
end

local function relative_target(delta, ids, active)
	for index, id in ipairs(ids) do
		if active and active.id == id then
			return ids[((index - 1 + delta) % #ids) + 1]
		end
	end
	return delta > 0 and ids[1] or ids[#ids]
end

-- Cycle occupied workspaces plus one empty slot, wrapping in either direction.
function M.cycle(delta)
	local ids = ring()
	focus(relative_target(delta, ids, hl.get_active_workspace()))
end

-- Number keys may select an existing workspace or its next empty slot, never create a gap.
function M.focus_number(id)
	if in_ring(id) then
		focus(id)
	end
end

local function move_to(id, follow)
	local window = hl.get_active_window()
	local active = hl.get_active_workspace()
	if window and window.workspace and window.workspace == active and type(active.id) == "number" and active.id > 0 and active.id ~= id then
		hl.dispatch(hl.dsp.window.move({ window = window, workspace = id, follow = follow }))
	end
end

function M.move_window(delta)
	local ids = ring()
	move_to(relative_target(delta, ids, hl.get_active_workspace()), true)
end

function M.move_number(id)
	if in_ring(id) then
		move_to(id, false)
	end
end

-- Returning to a removed workspace must not recreate its old, now possibly distant ID.
function M.previous()
	M.compact()
	local previous = hl.get_last_workspace()
	if previous and type(previous.id) == "number" and previous.id > 0 and hl.get_workspace(previous.id) then
		M.focus_number(previous.id)
	end
end

-- Quickshell's dispatch API expects a Lua callback, just like a Hyprland key binding.
function workspace_cycle(delta)
	return function()
		M.cycle(delta)
	end
end

-- The bar's drag: move one window, named by address, to an existing numbered
-- workspace or the next empty slot, without following it. Either may be gone
-- by the time it lands.
function move_window_to(id, address)
	return function()
		local destination = hl.get_workspace(id)
		local window = hl.get_window("address:" .. address)
		local open = destination and not destination.special and window and window.workspace ~= destination
			or not destination and in_ring(id)
		if open and window and window.mapped and window.workspace then
			hl.dispatch(hl.dsp.window.move({ window = window, workspace = id, follow = false }))
		end
	end
end

-- The bar's drag between two workspaces: give the window a workspace of its
-- own at `id`, moving that workspace and every one after it up a number to
-- make room. Highest first, so no ID is ever taken twice.
function insert_window_at(id, address)
	return function()
		local window = hl.get_window("address:" .. address)
		local at = hl.get_workspace(id)
		if not (at and not at.special and id > 0 and window and window.mapped and window.workspace) then
			return
		end
		local workspaces = numbered()
		for index = #workspaces, 1, -1 do
			local workspace = workspaces[index]
			if workspace.id >= id then
				renumber(workspace, workspace.id + 1)
			end
		end
		hl.dispatch(hl.dsp.window.move({ window = window, workspace = id, follow = false }))
	end
end

for _, event in ipairs({
	"window.open", "window.close", "window.move_to_workspace",
	"workspace.active", "workspace.created", "workspace.removed",
	"monitor.added", "monitor.removed", "config.reloaded", "hyprland.start",
}) do
	hl.on(event, schedule)
end

return M
