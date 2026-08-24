# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project is not yet published (see README's Status line), so there are no
tagged versions yet -- see [Versioning & publishing](CLAUDE.md#versioning--publishing)
for what "version" means for a yazi plugin distributed via `ya pkg`.

## [Unreleased]

### Added

- Pin the hovered (or current) directory into the `Parent` column as a fully
  interactive, independently navigable tab (`' p`).
- Toggle input focus between the working tab and the pinned tab (`' f`).
- A colored line above whichever pane (`Parent`/`Current`) currently has
  input focus while something is pinned, so `focus` toggling is visible.
- The pinned path persists across yazi restarts (via DDS).
- The tab bar is hidden entirely while something is pinned, so the pinned
  tab can't be switched to or closed by accident via yazi's own tab
  commands (number keys, mouse clicks).

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
