# pin-folder.yazi

A plugin for [yazi](https://github.com/sxyazi/yazi) that pins a directory to
the **Parent** column.

The pinned directory isn't a static snapshot -- it's a fully interactive,
independently navigable view: browse into subdirectories, create/remove/rename
files, see live previews, all without leaving the `Parent` column. Its cursor
is independent from the `Current` column's cursor.

> **Status:** work in progress, not yet published as a package. See
> [`.debug/concept.md`](.debug/concept.md) for design notes, known issues and
> what's still being worked on.

## Requirements

- yazi (developed against `26.8.15`)

## How it works

The pinned directory is backed by a real, normally-inactive yazi tab. Two
built-in components are overridden:

- `Parent` always renders that tab's `current` folder instead of the real
  parent directory.
- `Root.build` keeps `Current`/`Preview` locked to your working tab even while
  the pinned tab is temporarily made active for input (via `focus`).

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
	{ on = [ "'", "f" ], run = "plugin pin-folder focus", desc = "Toggle focus into the pinned folder" },
]
```

(`'` is used instead of the more obvious `p` because `p` is already bound to
`paste` by default.)

- `' p` -- pin the hovered directory (or the current one, if nothing directory
  is hovered) into the `Parent` column and switch input focus into it; press
  again (from anywhere) to unpin.
- `' f` -- toggle input focus between your working tab and the pinned one.
  While focused on the pinned tab, all normal navigation and file operations
  apply to it, and `Current`/`Preview` stay showing your working tab
  untouched.

While something is pinned, whichever pane -- `Parent` or `Current` -- is
currently receiving input gets a yellow line above it, so it's clear at a
glance where `' f` left you. Change the color/style in `FOCUS_STYLE` near the
top of `pin-folder.yazi/main.lua` to taste.

## Known limitations

- The pinned folder is only live-watched by the filesystem while its tab is
  active (i.e. while focused). While pinned-but-unfocused it shows the last
  known state.
- Selection/yank markers in the `Parent` column are drawn against the working
  tab, not the pinned one -- may not line up with the pinned listing rows.
  Cosmetic only.
- Counts as one more tab against yazi's 9-tab limit while pinned.

Yazi has no plugin hot-reload -- restart it (`q`, then `yazi`) after editing
`main.lua`, `init.lua` or `keymap.toml`.
