# Tabbed — Organized TODO

## Quick Switcher / Hyper Tab
- Hyper+Shift+Tab to go backwards — problem: hyper already includes shift. Consider remapping hyper to F18?

## Tab Bar UX

- Option for tabs to have max width, left-aligned instead of justified
- Setting to hide tab bar when window is full height (still usable via switcher)
  - Option to never show tab bar?
- Maybe reduce tab bar height from 28 to 24 to match menu bar on M1 Air
- Freeing a window should focus the next active tab, not the freed window
- Replace X button with - (free) for active tab, X (close) for inactive tabs (active tab closable via traffic lights)
- Close window functionality as optional config
- Quitting new-tab adder with Esc should refocus the current tab without requiring a click

## Window Management

- Drag tabs between windows; shift-select tabs to drag as a group; drag out into own window or into another
- Handle changing Spaces
  - Either drag tab bar to move group, or dragging any child window moves the whole group
- Handle fullscreening differently: rejoin group on un-fullscreen, show indicator that window is fullscreened but still in group
- Auto-capture new windows when all windows in space belong to a tabbed group (and it's fullscreen)
- Capture new windows when maximized doesn't work (bug)

## Bugs

- Signal (and possibly other apps) intercepts Ctrl+Tab even when pressing hyper+tab
- Selecting a tabbed window not by clicking does not bring the tab bar to front
- Switching to a tab briefly flashes that app's last-used window before showing the correct tab
- Fullscreen restoration on app quit is sometimes 2px too short
- Session restore shows wrong tab ordering / wrong active tab
- Fullscreen adjustment stopped working intermittently
- Tab bar sometimes appears in wrong Space/desktop
- Going from a non-grouped app on top of the tab bar into a grouped app (not by clicking) can leave the non-grouped app obscuring the tab bar
- Cross-space / cross-display bugs (needs investigation)

## Session Restore

- Simplify session restore config options

## Menu Bar

- Change menu bar style to be more native-y while still working with a hiding menu bar

## App Launcher / Spotlight

- Spotlight-style launcher: search apps, launch an app window and capture it
- Future: search the web, open in browser webview tab (unify desktop and web apps)
  - Maybe open in Helium with compact tabs, or let user choose browser

## Design

- Cycle between multiple tab bar design styles to prototype, then pick one:
  - Current design
  - Current design but with max-length tabs, draggable rest of area
  - Chrome-style tabs without painting over rest of area
  - 3+ wildcard creative designs

## Performance & Code Quality

- Performance / battery review
- Scan for dead or unnecessary duplicate code
- Set up proper logging system
- Make sure tests are everywhere
- Consider moving SwiftUI to AppKit (lifecycle hacks, not much SwiftUI code)

## Alt-Tab Integration

- As alternative to hiding windows, recreate Alt-Tab with awareness of tab groups (three app icons in one list entry)
- Desired model: Cmd+Tab for window-level, Hyper+Tab for within-group, Ctrl+Tab for within-app (Firefox, VS Code, etc.)

## Distribution

- Test compatibility with Rectangle
- Build script improvements (silent on success)
- Over-the-air update system
- $99/year signing for non-sus installs

## Maybe / Low Priority

- Double-click tab bar to fullscreen; double-click again to restore
- Mode to turn off tab display entirely, focus on alt-tab aspect only
- For windows that can't be resized, don't move them when added in fullscreen — just switch between them
- Skip windows with a minimum size in "all in space" mode
- Pinned tabs (force left, icon only)
- Window-wide close/release-all button
- Hide non-active windows completely (CGS private APIs — gave up, would require disabling SIP)
