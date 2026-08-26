# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project is not yet published (see README's Status line), so there are no
tagged versions yet.

## [Unreleased]

### Added

- Pin the hovered (or current) directory into the `Parent` column as a fully
  interactive, independently navigable tab (`' p`).
- Toggle input focus between the working tab and the pinned tab (`' '`).
- A colored line above whichever pane (`Parent`/`Current`) currently has
  input focus while something is pinned, inset 2 columns from each side,
  so `focus` toggling is visible. Its color follows the active theme/flavor
  (`th.tabs.active`'s own accent color) rather than a fixed color. Both
  panes reserve the line's row at all
  times, so neither one's height (or vertical borders) changes when focus
  toggles between them. The vertical border lines flanking `Current` are
  extended up onto that reserved row too, so they stay unbroken.
- The pinned path persists across yazi restarts (via DDS).
- The pinned tab stays visible in the tab bar, marked with a pin icon (📌)
  next to its name, and is pushed to the very front of the tab list at pin
  time (always number key `1`) -- the user's own tabs are numbered from `2`
  for as long as something is pinned. Not a complete guarantee -- see the
  plugin's "Known limitations" comment.
- Closing the pinned tab via yazi's default `<C-c>` ("close") is now
  blocked while it has input focus and other tabs are still open -- `' p`
  (unpin) is the only default-keybinding way to close it. If the pinned
  tab is the only tab left, `<C-c>` still quits yazi as usual.
- Closing your last real (non-pinned) tab now quits yazi entirely, instead
  of leaving it open with only the pinned tab remaining as an orphaned
  `Current`.

### Fixed

- `pin` now leaves input focus on the newly pinned tab instead of switching
  back to the working tab.
- Tab-identity tracking no longer latches onto the working tab instead of
  the pinned one when both start out at the same `cwd` (pinning the current
  directory itself, with nothing hovered).
- Tab-identity comparisons now use `tab.id.value` instead of the `tab.id`
  userdata directly -- Lua's default (reference) equality made `==` always
  false for it, regardless of which tab was actually being compared.
- Rapid repeated pin/unpin no longer creates duplicate tabs.
- The pinned folder is now actually restored after a yazi restart: the tab
  it lives in is recreated from the persisted path instead of the plugin
  silently sitting in a "pinned but nothing to show" state until the next
  manual `pin`/`unpin`. This also covers restarting with a shell that `cd`s
  to yazi's last active-tab cwd on quit (e.g. a `--cwd-file` wrapper) after
  quitting with focus on the pinned tab, which previously left the restore
  silently no-op'd because the next launch's sole tab already sat at the
  pinned path.
- After a restart, `Parent` no longer stays empty until focus is manually
  toggled onto the pinned tab: the restore now waits for the recreated
  tab's directory listing to actually finish loading before switching
  focus back to the working tab, instead of switching immediately and
  risking the (background) load getting stuck indefinitely.
- `pin` no longer creates a second, duplicate tab for the folder it just
  pinned: `ps.pub_to` turns out to deliver back to the *publishing*
  instance's own subscription, so every `pin` was also triggering the
  restart-restore logic on itself right after creating the real tab.
- Clicking a file or folder in `Parent` or `Current` now switches input
  focus into that pane first. Previously a click could act on the wrong
  tab -- e.g. clicking an item in `Parent` while focus was still on
  `Current` revealed it in the working tab instead of the pinned one whose
  listing was actually shown there, since the underlying click handlers
  always target whichever tab is currently focused, not whichever tab's
  listing is being displayed.
- Clicking blank space in `Parent` now always navigates the *working* tab
  up a level, matching vanilla yazi's own "click Parent to go up" gesture
  (`Parent` normally *is* Current's real parent), and never changes input
  focus -- it previously navigated whichever tab was actually focused
  (right after the fix above started switching focus into `Parent` first,
  that meant navigating the *pinned* tab instead).
- The mouse wheel now scrolls `Parent` -- it was completely frozen there
  before (`Parent` isn't independently scrollable at all in vanilla yazi),
  switching input focus into it first, same as clicking an entity there
  does. Scrolling `Current` while focus is on the pinned tab no longer
  moves the pinned tab's cursor instead of `Current`'s.
