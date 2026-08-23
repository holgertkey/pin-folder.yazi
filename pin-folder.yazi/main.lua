--- @sync entry

-- pin.yazi
--
-- Pins a directory as a second, fully interactive tab whose listing is
-- displayed in the Parent column. The pinned tab is a real yazi tab, so
-- navigation, previews and file operations (create/remove/rename/yank/paste)
-- all work on it unmodified -- they just run against that tab whenever it's
-- made active via `focus`.
--
-- Known limitations (v1):
-- - The pinned folder's listing is only live-watched by the FS while its
--   tab is active (i.e. while focused). While pinned-but-unfocused it shows
--   the last known state.
-- - Selection/yank markers in the Parent column are drawn against the main
--   tab (Tab:build passes the same tab to Rails/Markers as to Parent), so
--   they may not line up with the pinned listing. Cosmetic only.
-- - Counts as one more tab against yazi's 9-tab limit while pinned.

local M = {}

local function pin_index()
	if M.pin_id then
		for i = 1, #cx.tabs do
			if cx.tabs[i].id == M.pin_id then
				return i
			end
		end
		return nil
	end

	-- Not attached to a tab yet (fresh pin, or restored from a previous
	-- session) -- find it once by its cwd, then lock onto its id so that
	-- navigating inside the pinned tab doesn't lose track of it.
	if not M.path then
		return nil
	end
	for i = 1, #cx.tabs do
		if tostring(cx.tabs[i].current.cwd) == M.path then
			M.pin_id = cx.tabs[i].id
			return i
		end
	end
	return nil
end

local function main_index()
	if not M.main_id then
		return nil
	end
	for i = 1, #cx.tabs do
		if cx.tabs[i].id == M.main_id then
			return i
		end
	end
	return nil
end

function M:setup()
	ps.sub_remote("@pin-folder", function(body) M.path = body and body.path or nil end)

	Root.build = function(root)
		local tab = cx.active

		local pidx = pin_index()
		if pidx and cx.tabs[pidx].id == cx.active.id then
			local midx = main_index()
			if midx then
				tab = cx.tabs[midx]
			end
		end

		root._children = {
			Backdrop:new(root._area),
			Header:new(root._chunks[1], cx.active),
			Tabs:new(root._chunks[2]),
			Tab:new(root._chunks[3], tab),
			Status:new(root._chunks[4], cx.active),
			Modal:new(root._area),
		}
	end

	local parent_new = Parent.new
	Parent.new = function(self, area, tab)
		local me = parent_new(self, area, tab)

		local pidx = pin_index()
		if pidx then
			me._folder = cx.tabs[pidx].current
		end

		return me
	end
end

function M:entry(job)
	local action = job.args[1]

	local pidx = pin_index()
	local on_pin = pidx and cx.tabs[pidx].id == cx.active.id
	if not on_pin then
		M.main_id = cx.active.id
	end

	if action == "pin" then
		if M.path then
			-- Already pinned (or a pin just created moments ago, whose
			-- tab_create hasn't landed in cx.tabs yet -- tab_create is async,
			-- so pidx can still be nil here even though we're clearly pinned).
			-- Base the decision on M.path, set synchronously at pin time, not
			-- on finding a live tab.
			if pidx then
				ya.emit("tab_close", { pidx - 1 })
			end
			M.path = nil
			M.pin_id = nil
			ps.pub_to(0, "@pin-folder", nil)
			return
		end

		local hovered = cx.active.current.hovered
		local target = (hovered and hovered.cha.is_dir) and hovered.url or cx.active.current.cwd
		local origin_idx = cx.tabs.idx

		M.path = tostring(target)
		ps.pub_to(0, "@pin-folder", { path = M.path })

		ya.emit("tab_create", { target })
		ya.emit("tab_switch", { origin_idx - 1 })
	elseif action == "focus" then
		if not pidx then
			return
		end

		if on_pin then
			local midx = main_index()
			if midx then
				ya.emit("tab_switch", { midx - 1 })
			end
		else
			ya.emit("tab_switch", { pidx - 1 })
		end
	end
end

return M
