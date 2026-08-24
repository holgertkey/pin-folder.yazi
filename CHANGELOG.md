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
