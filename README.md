# pin-folder.yazi

A plugin for [yazi](https://github.com/sxyazi/yazi) that pins a directory to
the **Parent** column.

The pinned directory isn't a static snapshot -- it's a fully interactive,
independently navigable view: browse into subdirectories, create/remove/rename
files, see live previews, all without leaving the `Parent` column. Its cursor
is independent from the `Current` column's cursor.

> **Status:** work in progress, not yet published as a package. See
> [`.debug/concept.md`](.debug/concept.md) for design notes, known issues and
> what's still being worked on, and [`CHANGELOG.md`](CHANGELOG.md) for a
> user-facing summary of what's shipped so far.

## Requirements

- yazi (developed against `26.8.15`)

## How it works

The pinned directory is backed by a real, normally-inactive yazi tab. Several
built-in components are overridden:

- `Parent` always renders that tab's `current` folder instead of the real
  parent directory.
- `Root.build` keeps `Current`/`Preview` locked to your working tab even while
  the pinned tab is temporarily made active for input (via `focus`).
- `Tab.build` draws the focus indicator line described under Keybindings
  below.
- `Tabs.redraw` prefixes the pinned tab's label with a pin icon (📌) in the
  tab bar, so it's identifiable at a glance -- it stays a normal, visible,
  clickable tab like your own.
- `Parent.click`/`Current.click` switch input focus into whichever pane you
  click before the click itself is handled, so clicking a file or folder
  always acts on the pane you clicked, not whichever pane happened to have
  focus already. Clicking blank space in `Parent` is the one exception --
  it always navigates the working tab up a level, without switching focus,
  matching vanilla yazi's own "click Parent to go up" gesture.

Because the pinned pane is a genuine tab, every built-in yazi command
(navigation, `create`/`remove`/`rename`/`yank`/`paste`, previews) works on it
unmodified -- no custom navigation logic was needed.

The pinned path persists across restarts (via yazi's DDS), the tab itself does
not -- it's recreated/reattached on demand.

## Installation

Not packaged yet. Manual setup:

This repo also keeps `init.lua` and `keymap.toml` for local development --
they're symlinked into `~/.config/yazi/` so edits here take effect on the next
yazi restart:

```sh
ln -s "$(pwd)/pin-folder.yazi" ~/.config/yazi/plugins/pin-folder.yazi
ln -s "$(pwd)/init.lua" ~/.config/yazi/init.lua
ln -s "$(pwd)/keymap.toml" ~/.config/yazi/keymap.toml
```

If you already have your own `init.lua`/`keymap.toml`, add the relevant bits
instead of symlinking the whole file:

`init.lua`:

```lua
require("pin-folder"):setup()
```

## Keybindings

`keymap.toml`:

```toml
[mgr]
prepend_keymap = [
	{ on = [ "'", "p" ], run = "plugin pin-folder pin", desc = "Pin/unpin hovered folder in the Parent column" },
	{ on = [ "'", "'" ], run = "plugin pin-folder focus", desc = "Toggle focus into the pinned folder" },
	{ on = [ "<C-c>" ], run = "plugin pin-folder close", desc = "Close the current tab, or quit if it's the last real one (blocked on the pinned tab -- use ' p to unpin instead)" },
]
```

(`'` is used instead of the more obvious `p` because `p` is already bound to
`paste` by default.)

- `' p` -- pin the hovered directory (or the current one, if nothing directory
  is hovered) into the `Parent` column and switch input focus into it; press
  again (from anywhere) to unpin. **This is the only legal way to close the
  pinned tab** -- see below.
- `' '` -- toggle input focus between your working tab and the pinned one.
  While focused on the pinned tab, all normal navigation and file operations
  apply to it, and `Current`/`Preview` stay showing your working tab
  untouched.

Clicking a file or folder in either `Parent` or `Current` also switches input
focus into that pane first, same as `' '` would -- so mouse and keyboard
agree on which pane a click actually acts on. Clicking blank space in
`Current` is a no-op either way, so it doesn't switch focus. Clicking blank
space in `Parent` is different: it navigates your *working* tab up a level
(the familiar "click Parent to go up" gesture, matching vanilla yazi) without
switching focus at all -- your working tab moves up a level in the
background regardless of which pane currently has input.

The pinned tab stays visible in the tab bar, always first (number key `1`)
and marked with a 📌 next to its name, so it's identifiable and clickable
like any other tab -- this shifts the numbering of your own tabs up by one
for as long as something is pinned. It's protected
from yazi's default `<C-c>` ("close") while it has input focus and other tabs
are still open -- that key is remapped (above) to a plugin action that no-ops
on the pinned tab instead of closing it, so `' p` is the only
default-keybinding way to close it. If the pinned tab is the *only* tab left,
`<C-c>` still quits yazi rather than becoming a dead key (matching yazi's own
"close the current tab, or quit if it's last" behavior for `close`). This
doesn't guard against a custom keymap binding `tab_close` directly to some
other key.

Closing your last *real* (non-pinned) tab quits yazi entirely instead of
leaving it open with only the pinned tab showing -- the pinned tab doesn't
count as a tab worth staying open for by itself.

While something is pinned, whichever pane -- `Parent` or `Current` -- is
currently receiving input gets a yellow line above it, inset 2 columns from
each side, so it's clear at a glance where `' '` left you. Both panes
reserve that top row at all times, whether or not they currently have
focus, so neither one changes height (and neither one's vertical borders
change length) when focus toggles between them. Change the color/style in
`FOCUS_STYLE` near the top of `pin-folder.yazi/main.lua` to taste.

## Known limitations

- The pinned folder is only live-watched by the filesystem while its tab is
  active (i.e. while focused). While pinned-but-unfocused it shows the last
  known state.
- Selection/yank markers in the `Parent` column are drawn against the working
  tab, not the pinned one -- may not line up with the pinned listing rows.
  Cosmetic only.
- Counts as one more tab against yazi's 9-tab limit while pinned.
- Only yazi's *default* `<C-c>` binding is guarded against closing the pinned
  tab. A custom keymap that binds `tab_close` (or some other command)
  directly to a different key bypasses the plugin entirely.

Yazi has no plugin hot-reload -- restart it (`q`, then `yazi`) after editing
`main.lua`, `init.lua` or `keymap.toml`.
