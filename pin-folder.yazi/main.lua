--- @sync entry
--- @since 26.8.15

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

-- Tab ids (tab.id) are userdata with no __eq defined on the Rust side, so
-- Lua's default (reference) equality never considers two of them equal even
-- for the same tab -- compare/store `.value` (the plain number it wraps)
-- instead, never the userdata itself.
local function id_of(tab) return tab.id.value end

local function pin_index()
	if M.pin_id then
		for i = 1, #cx.tabs do
			if id_of(cx.tabs[i]) == M.pin_id then
				return i
			end
		end
		return nil
	end

	-- Not attached to a tab yet (fresh pin, or restored from a previous
	-- session) -- find it once by its cwd, then lock onto its id so that
	-- navigating inside the pinned tab doesn't lose track of it.
	--
	-- Pinning the hovered directory when nothing directory is hovered pins
	-- the *current* directory -- the freshly created tab then starts out
	-- with the exact same cwd as the working tab (M.main_id). Exclude that
	-- one explicitly, or this would latch onto the working tab instead of
	-- the new pinned one (they're indistinguishable by cwd alone).
	if not M.path then
		return nil
	end
	for i = 1, #cx.tabs do
		if id_of(cx.tabs[i]) ~= M.main_id and tostring(cx.tabs[i].current.cwd) == M.path then
			M.pin_id = id_of(cx.tabs[i])
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
		if id_of(cx.tabs[i]) == M.main_id then
			return i
		end
	end
	return nil
end

-- Whether input focus is currently on the pinned tab, i.e. whether `focus`
-- would switch back to the working tab if invoked right now.
local function pin_focus()
	local pidx = pin_index()
	return pidx, pidx ~= nil and id_of(cx.tabs[pidx]) == id_of(cx.active)
end

-- Border drawn around whichever of Parent/Current currently has input focus,
-- while something is pinned. Change the color here to taste.
local FOCUS_STYLE = ui.Style():fg("yellow"):bold(true)

function M:setup()
	ps.sub_remote("@pin-folder", function(body)
		M.path = body and body.path or nil
		if M.path then
			-- Restored (or received from another instance) but the tab
			-- itself doesn't exist yet -- tabs don't survive a restart, so
			-- recreate it. Hand off to the sync `entry` (this callback may
			-- not run with the same guarantees) rather than touching cx here.
			ya.emit("plugin", { "pin-folder", "reattach" })
		end
	end)

	Root.build = function(root)
		local tab = cx.active

		local _, on_pin = pin_focus()
		if on_pin then
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

	-- Hide the tab bar entirely while something is pinned. The pinned tab is
	-- a real, generic tab -- shown, it invites the user to switch/close it
	-- via yazi's own tab commands (number keys, mouse clicks, `<C-c>`/
	-- `close`), which bypass this plugin entirely and desync M.path/
	-- M.pin_id/M.main_id from the tab that command just touched. Hiding the
	-- bar doesn't stop `<C-c>` from closing whatever tab is currently
	-- active, but it does remove the visible invitation to interact with
	-- the pinned tab directly.
	local tabs_height = Tabs.height
	Tabs.height = function()
		if M.path then
			return 0
		end
		return tabs_height()
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

	-- Mark whichever pane (Parent while on_pin, Current otherwise) is
	-- currently receiving input, so `focus` toggling is visible at a glance.
	-- The target chunk is padded by one row on top *before* the real build()
	-- runs (so its content is pushed down out of the way), then the border
	-- is drawn using the original, unpadded chunk -- using the padded one
	-- here would draw the line on the same row as the content, not above it.
	local tab_build = Tab.build
	Tab.build = function(self, ...)
		if not M.path then
			return tab_build(self, ...)
		end

		local _, on_pin = pin_focus()
		local target = on_pin and 1 or 2
		local original = self._chunks[target]

		self._chunks[target] = original:pad(ui.Pad.top(1))
		tab_build(self, ...)

		self._base = ya.list_merge(self._base or {}, {
			ui.Border(ui.Edge.TOP):area(original):type(ui.Border.PLAIN):style(FOCUS_STYLE),
		})
	end
end

function M:entry(job)
	local action = job.args[1]

	-- Handled ahead of the generic preamble below: both need full control
	-- over `M.main_id` at exact points the preamble doesn't give them (see
	-- the comments inline). Not reached for "pin"/"focus".
	if action == "reattach" then
		if not M.path then
			return
		end

		-- Set *before* the pin_index() guard call below, not after: with
		-- M.pin_id still nil on a fresh restart, pin_index() falls back to
		-- a cwd scan that needs a real M.main_id to exclude -- otherwise it
		-- can latch onto the very (sole) starting tab if it happens to
		-- already sit at M.path. Not hypothetical: a `--cwd-file` shell
		-- wrapper (e.g. the `y()` function in ~/.zshrc/~/.bashrc) restores
		-- the shell's cwd to wherever the active tab was on quit, so
		-- quitting with focus on the pinned tab makes the very next `yazi`
		-- launch start with its only tab already sitting at the pinned
		-- path -- exactly the collision this needs to exclude. Safe to
		-- read M.main_id further down in the "already attached" case too:
		-- pin_index() only consults it in this same cwd fallback, which
		-- never runs once M.pin_id is cached from a real earlier attach.
		M.main_id = id_of(cx.active)
		if pin_index() then
			return
		end

		ya.emit("tab_create", { Url(M.path) })
		-- tab_create is async and activates the tab it creates -- switching
		-- back to M.main_id has to wait until that's landed, hence the
		-- follow-up dispatch instead of doing it inline here.
		ya.emit("plugin", { "pin-folder", "settle" })
		return
	elseif action == "settle" then
		-- Runs once the tab_create from "reattach" above has landed, so
		-- cx.active *is* that new tab -- latch onto it directly instead of
		-- going through pin_index()'s cwd scan (which would be ambiguous
		-- for the same reason "pin" excludes M.main_id from it).
		local active = id_of(cx.active)
		if not (M.path and M.main_id and active ~= M.main_id) then
			return
		end
		M.pin_id = active

		-- Wait for the new tab's initial directory read to finish before
		-- switching focus away from it. Empirically, a background (inactive)
		-- tab's very first load can get stuck in FolderStage.Loading
		-- indefinitely once you switch away from it before it lands --
		-- switching back to `M.main_id` synchronously, right after
		-- `tab_create`, left `Parent` permanently empty until the user
		-- manually toggled focus onto the pinned tab (which finally gave it
		-- a chance to load). Polling briefly here, instead of switching back
		-- immediately, reliably avoids that: capped at 20 x 30ms so a very
		-- slow/huge/remote directory can't hang the restore -- if the cap is
		-- hit it just proceeds, same as the pre-existing "not live-watched
		-- while unfocused" limitation for such directories.
		ya.async(function()
			local loaded, n = false, 0
			while n < 20 and not loaded do
				loaded = ya.sync(function()
					local pidx = pin_index()
					return pidx == nil or cx.tabs[pidx].current.stage() ~= false
				end)()
				if not loaded then
					n = n + 1
					ya.sleep(0.03)
				end
			end

			ya.sync(function()
				local midx = main_index()
				if midx then
					ya.emit("tab_switch", { midx - 1 })
				end
				ui.render()
			end)()
		end)
		return
	end

	local pidx, on_pin = pin_focus()
	if not on_pin then
		M.main_id = id_of(cx.active)
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

		M.path = tostring(target)
		ps.pub_to(0, "@pin-folder", { path = M.path })

		-- tab_create activates the new tab itself, which is what leaves focus
		-- on the pinned folder right after pinning -- do not switch back.
		ya.emit("tab_create", { target })
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
