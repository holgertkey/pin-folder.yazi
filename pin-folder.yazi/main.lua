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
-- - The pinned tab is shown in the tab bar (marked with a pin icon) and
--   pushed to the very front of cx.tabs at pin time (always number key
--   `1`), shifting the user's own tabs' numbers up by one. tab_create
--   can never insert before it (yazi always inserts at cursor+1, which
--   is at least 1), but an explicit tab-reorder command (`{`, "swap with
--   previous") issued from the tab right after it can still swap it out
--   of the front slot -- not re-enforced continuously. See .debug/concept.md.
-- - Closing the pinned tab via yazi's default Ctrl-C ("close") is blocked
--   while it has input focus and other tabs are open -- `' p` (unpin) is
--   the only way to close it. This only covers the *default* keybinding;
--   a custom keymap that binds `tab_close` directly to some other key
--   bypasses the plugin entirely.
-- - Closing your last real (non-pinned) tab quits yazi entirely rather
--   than leaving it open with only the pinned tab remaining.

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
-- while something is pinned. Derived from th.tabs.active's own background
-- (the theme's chosen "active tab" accent color) rather than a hardcoded
-- color, so it shifts with whatever flavor/theme is active instead of
-- clashing with it -- same pattern Tabs.redraw already uses elsewhere in
-- this file (`style.active:bg()`) to turn an active-tab style into a
-- plain foreground color. Computed fresh on every call rather than cached
-- as a module-level constant: every other `th.*` read in this file (and
-- in yazi's own preset components) happens inside a function that runs at
-- render time, never at bare top-level load time, so this follows that
-- same convention rather than risking `th` not being populated yet when
-- this file is first required.
--
-- Falls back through bg -> fg -> a literal color: a flavor is free to
-- style `tabs.active` with only a `fg` (recoloring/underlining the text)
-- and no `bg` at all, in which case `:bg()` resolves to the unset
-- "reset" this function's own base style started from -- using that
-- directly as our line's foreground would make the indicator invisible
-- (identical to plain terminal-default text) rather than merely
-- off-palette, on any such theme.
local function focus_style()
	local style = ui.Style():fg("reset"):bg("reset"):patch(th.tabs.active)
	local accent = style:bg()
	if not accent or accent == "reset" then
		accent = style:fg()
	end
	if not accent or accent == "reset" then
		accent = "yellow"
	end
	return ui.Style():fg(accent):bold(true)
end

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

	-- Mark the pinned tab in the bar instead of hiding it (earlier versions
	-- hid it entirely -- see .debug/concept.md item 15/17 for why that was
	-- reconsidered): prefix its label with a pin icon so it's identifiable
	-- at a glance, while staying a normal, visible, clickable tab bar entry
	-- like the user's own tabs. Height/click behavior are left as yazi's
	-- own -- only the label/style for one entry differs, so there's no need
	-- to reimplement the offset/click math the way the old hide-filter did.
	local PIN_ICON = "📌"

	local tabs_redraw = Tabs.redraw
	Tabs.redraw = function(self)
		local pidx = pin_index()
		if not pidx then
			return tabs_redraw(self)
		end
		if self.height() < 1 then
			return {}
		end

		local style = self:style()
		local lines = {
			ui.Line(th.tabs.sep_outer.open):fg(style.inactive:bg()),
		}

		local pos = lines[1]:width()
		local max = math.floor(self:inner_width() / #cx.tabs)
		for i = 1, #cx.tabs do
			local label = i == pidx and string.format(" %d %s %s ", i, PIN_ICON, cx.tabs[i].name)
				or string.format(" %d %s ", i, cx.tabs[i].name)
			local name = ui.truncate(label, { max = max })
			if i == cx.tabs.idx then
				lines[#lines + 1] = ui.Line {
					ui.Span(th.tabs.sep_inner.open):fg(style.active:bg()):bg(style.inactive:bg()),
					ui.Span(name):style(style.active),
					ui.Span(th.tabs.sep_inner.close):fg(style.active:bg()):bg(style.inactive:bg()),
				}
			else
				lines[#lines + 1] = ui.Line(name):style(style.inactive)
			end
			self._offsets[i], pos = pos, pos + lines[#lines]:width()
		end

		lines[#lines + 1] = ui.Line(th.tabs.sep_outer.close):fg(style.inactive:bg())
		return ui.Line(lines):area(self._area)
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

	-- Clicking an entity in a pane should switch input focus into it
	-- first, same as `' '` would, *before* the click itself is handled --
	-- otherwise `Entity:click()`'s `ya.emit("reveal", ...)` fires against
	-- whatever tab happens to be `cx.active` already, which can be the
	-- *other* pane's tab (e.g. clicking an item in Parent while focus is
	-- still on Current would reveal it in the working tab, not the pinned
	-- one whose listing is actually showing there). `up`/middle-click are
	-- already no-ops in the originals, so this skips the switch for those.
	local parent_click = Parent.click
	Parent.click = function(self, event, up)
		if up or event.is_middle then
			return parent_click(self, event, up)
		end

		local pidx, on_pin = pin_focus()
		local y = event.y - self._area.y + 1
		if self._folder and self._folder.window and self._folder.window[y] then
			if pidx and not on_pin then
				ya.emit("tab_switch", { pidx - 1 })
			end
			return parent_click(self, event, up)
		end

		-- Blank-space click: familiar "click Parent to go up a level"
		-- gesture (`leave`), but kept pointed at the WORKING tab, not the
		-- pinned one -- mirroring vanilla yazi, where Parent normally *is*
		-- Current's real parent, so clicking blank space there has always
		-- meant "go up from Current", never "go up in some other pane".
		-- Deliberately does *not* switch input focus (unlike the entity
		-- case above): `leave` has no tab-index argument (confirmed
		-- against `yazi-actor/src/mgr/leave.rs` -- it only ever acts on
		-- `cx.active`), so the only way to target the working tab without
		-- leaving focus there afterward is to switch to it, fire `leave`,
		-- then switch immediately back -- all three `ya.emit` calls land
		-- before the next render (same queued-dispatch ordering the entity
		-- case and item 20 already rely on), so this never becomes visible
		-- as an actual focus flicker.
		if on_pin and event.is_left then
			-- No `midx` means the working tab isn't where the plugin
			-- thinks it is (e.g. closed via some path this plugin doesn't
			-- track) -- fall through to a no-op, not to `parent_click`:
			-- that would fire `leave` against `cx.active` (the pinned
			-- tab), which is exactly the wrong-tab behavior this override
			-- exists to avoid, not a reasonable fallback for it.
			local midx = main_index()
			if midx then
				ya.emit("tab_switch", { midx - 1 })
				ya.emit("leave", {})
				ya.emit("tab_switch", { pidx - 1 })
			end
			return
		end
		return parent_click(self, event, up)
	end

	-- Unlike Parent, Current:click() has no blank-space fallback -- it only
	-- acts when the click actually lands on an entity row -- so the switch
	-- here is gated the same way (mirroring Current:click()'s own row
	-- lookup), or a blank-space click on Current while focused on the
	-- pinned tab would switch focus for a click that was otherwise a
	-- silent no-op.
	local current_click = Current.click
	Current.click = function(self, event, up)
		if not (up or event.is_middle) then
			local y = event.y - self._area.y + 1
			if self._folder and self._folder.window and self._folder.window[y] then
				local _, on_pin = pin_focus()
				if on_pin then
					local midx = main_index()
					if midx then
						ya.emit("tab_switch", { midx - 1 })
					end
				end
			end
		end
		return current_click(self, event, up)
	end

	-- `Parent:scroll()` is a no-op stub in vanilla yazi (confirmed against
	-- `parent.lua`) -- Parent is never independently scrollable there, its
	-- listing is just whatever `Current`'s own navigation happens to put
	-- in the parent directory. This plugin makes Parent an independently
	-- navigable folder, so the mouse wheel over it should move its own
	-- cursor the same way it does over Current (`Current:scroll()` is
	-- `ya.emit("arrow", { step })`, unconditionally targeting `cx.active`)
	-- -- switching focus into the pinned tab first when it isn't already
	-- there, same as an entity click in Parent already does, since `arrow`
	-- has no tab-index argument either.
	local parent_scroll = Parent.scroll
	Parent.scroll = function(self, event, step)
		local pidx, on_pin = pin_focus()
		if not pidx then
			return parent_scroll(self, event, step)
		end
		if not on_pin then
			ya.emit("tab_switch", { pidx - 1 })
		end
		ya.emit("arrow", { step })
	end

	-- Current:scroll() has the same wrong-tab exposure `Current.click`
	-- (item 20) already guards against -- `ya.emit("arrow", { step })`
	-- always targets `cx.active`, so scrolling over Current while focus is
	-- on the pinned tab would move the *pinned* tab's cursor instead of
	-- Current's, even though the wheel is visually over Current's listing.
	-- Worth guarding unconditionally (no entity-row gate needed here,
	-- unlike Current.click: scroll always acts, there's no "click that was
	-- otherwise a no-op" case to preserve) -- especially now that
	-- Parent.scroll above routinely leaves focus sitting on the pinned tab
	-- as a side effect of the user just having scrolled Parent, making
	-- this exposure easy to hit in one natural gesture.
	local current_scroll = Current.scroll
	Current.scroll = function(self, event, step)
		local _, on_pin = pin_focus()
		if on_pin then
			local midx = main_index()
			if midx then
				ya.emit("tab_switch", { midx - 1 })
			end
		end
		return current_scroll(self, event, step)
	end

	-- Mark whichever pane (Parent while on_pin, Current otherwise) is
	-- currently receiving input, so `focus` toggling is visible at a glance.
	-- Both chunks are padded by one row on top *unconditionally* (not just
	-- the focused one) *before* the real build() runs, so neither pane's
	-- height changes when focus toggles between them -- only the line's
	-- visibility does. Padding only the focused chunk (the earlier
	-- approach) made that pane shrink by a row whenever it gained focus
	-- and snap back to full height when it lost it, a visible size jump.
	-- The border itself is drawn using the original, unpadded chunk for
	-- whichever pane is the current target -- using the padded one here
	-- would draw the line on the same row as the content, not above it.
	local tab_build = Tab.build
	Tab.build = function(self, ...)
		if not M.path then
			return tab_build(self, ...)
		end

		local _, on_pin = pin_focus()
		local target = on_pin and 1 or 2
		local original_1, original_2 = self._chunks[1], self._chunks[2]

		self._chunks[1] = original_1:pad(ui.Pad.top(1))
		self._chunks[2] = original_2:pad(ui.Pad.top(1))
		tab_build(self, ...)

		-- Inset 2 columns from both sides so the line doesn't run flush
		-- edge-to-edge -- purely cosmetic, drawn against a separate,
		-- narrower rect than the ones used above to push the content down
		-- (those have to stay full-width, or the content below them would
		-- be pushed down without actually being narrowed to match).
		local original = target == 1 and original_1 or original_2
		local focus_line = ui.Border(ui.Edge.TOP):area(original:pad(ui.Pad.x(2))):type(ui.Border.PLAIN):style(focus_style())

		-- The vertical rail lines either side of Current (rail-left,
		-- between Parent/Current, and rail-right, between Current/Preview)
		-- are both built by yazi's own Rails component from *Current's*
		-- chunk alone (confirmed against `rails.lua`: both copy c[2]'s y/h
		-- untouched, only overriding x/w) -- so now that c[2] is always
		-- padded a row down (above), both rails always stop a row short of
		-- the top, regardless of focus. Draw a 1-row extension for each,
		-- in the same style/symbol Rail:redraw() itself uses, positioned
		-- exactly at Current's own left/right edge on the reserved top
		-- row, so the lines read as continuous instead of leaving a gap.
		-- Gated on the exact same conditions `rails.lua` itself uses
		-- (`c[1].w > 0` / `c[3].w > 0`) -- rail-left/rail-right don't exist
		-- at all when Parent/Preview is collapsed to zero width, and an
		-- unconditional extension would draw a floating glyph with no rail
		-- underneath it in that case.
		local extras = { focus_line }
		if original_2.w > 0 then
			local gap_row = original_2:pad(ui.Pad.bottom(original_2.h - 1))
			if self._chunks[1].w > 0 then
				extras[#extras + 1] = ui.Bar(ui.Edge.LEFT)
					:area(gap_row:pad(ui.Pad.right(gap_row.w - 1)))
					:symbol(th.mgr.border_symbol)
					:style(th.mgr.border_style)
			end
			if self._chunks[3] and self._chunks[3].w > 0 then
				extras[#extras + 1] = ui.Bar(ui.Edge.LEFT)
					:area(gap_row:pad(ui.Pad.left(gap_row.w - 1)))
					:symbol(th.mgr.border_symbol)
					:style(th.mgr.border_style)
			end
		end

		self._base = ya.list_merge(self._base or {}, extras)
	end
end

function M:entry(job)
	local action = job.args[1]

	-- Handled ahead of the generic preamble below: "reattach"/"settle" need
	-- full control over `M.main_id` at exact points the preamble doesn't
	-- give them, and "close" wants to stay fully inert (no `M.main_id`
	-- write at all) since it's the most frequently pressed, often
	-- pin-unrelated action reaching this function (see the comments
	-- inline). Not reached for "pin"/"focus".
	if action == "reattach" then
		-- Only meant for the fresh-process restore case: M.path restored
		-- from DDS with this instance's tab tracking never yet initialized.
		-- M.main_id being non-nil means a real "pin"/"focus"/"reattach" has
		-- already run in this process -- most importantly, `ps.pub_to`
		-- delivers back to the *publishing* instance's own `ps.sub_remote`
		-- (confirmed empirically), so a plain `pin` immediately triggers
		-- this same "reattach" dispatch on itself, right after tab_create
		-- has already left the new pin tab active. Without this guard, that
		-- makes M.main_id get clobbered with the pin tab's own id below,
		-- which excludes the real pin tab from pin_index()'s cwd fallback
		-- and creates a second, duplicate tab for it every single time
		-- something is pinned.
		if not M.path or M.main_id then
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
		-- Move the pinned tab to the very front of cx.tabs, right after
		-- creating it, so its label always sits first in the tab bar
		-- instead of wherever tab_create happened to insert it (cursor+1,
		-- i.e. potentially in the middle of the list). Safe to queue right
		-- after tab_create: the insertion itself is synchronous (only the
		-- directory read is async), and tab_swap does no I/O of its own.
		ya.emit("tab_swap", { "top" })
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
	elseif action == "close" then
		-- Bound (in keymap.toml) to Ctrl-C in place of yazi's default
		-- `close`, so the pinned tab can't be closed by its own most
		-- reachable default keybinding -- `' p` (unpin) is the only legal
		-- way to close it. Handled here, ahead of the generic preamble
		-- below, so a frequently-pressed, pin-unrelated key doesn't
		-- opportunistically mutate `M.main_id` (which would arm
		-- "reattach"'s `M.main_id`-set guard during the narrow startup
		-- window before a restore's self-dispatched "reattach" has
		-- landed) -- pin_focus() is read locally instead.
		local pidx, on_pin = pin_focus()
		if on_pin then
			-- Only blocks while the pinned tab isn't the sole tab left --
			-- with just the pinned tab open, `close` quitting yazi entirely
			-- isn't "closing the pinned tab", it's quitting the app (matches
			-- vanilla `close`'s own "close the current tab, or quit if it's
			-- last" semantics), so let it through rather than leaving Ctrl-C
			-- a dead key with no way to quit.
			if #cx.tabs > 1 then
				return
			end
			ya.emit("close", {})
			return
		end

		-- Closing a real (non-pinned) tab. Yazi's own `close` treats the
		-- pinned tab as just another live tab when deciding "is this the
		-- last one" -- so with one real tab plus the pinned one (2 total),
		-- vanilla `close` would just close the real tab and leave the
		-- pinned tab as the sole surviving "tab", quietly keeping yazi open
		-- showing only an accessory view. Count the pinned tab out of that
		-- decision: if this is the last *real* tab, quit outright instead
		-- (`quit` is exactly what `close` itself falls back to once
		-- `#cx.tabs <= 1` -- see yazi's own `mgr::close` actor -- so this
		-- mirrors vanilla behavior, just with the pinned tab discounted).
		local real_tabs = pidx and (#cx.tabs - 1) or #cx.tabs
		if real_tabs <= 1 then
			-- Only take the explicit `quit` path when a pinned tab is
			-- actually in the count being discounted (`pidx` non-nil) --
			-- with nothing pinned this is just `ya.emit("close", {})`,
			-- identical to every prior close on the last tab, so a
			-- no-pin session never depends on this new `quit` call.
			ya.emit(pidx and "quit" or "close", {})
			return
		end
		ya.emit("close", {})
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
		-- Move it to the very front of cx.tabs -- see the matching comment
		-- in the "reattach" branch above for why.
		ya.emit("tab_swap", { "top" })
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
