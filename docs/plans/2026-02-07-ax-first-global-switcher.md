# AX-First Global Switcher Rewrite

**Date:** 2026-02-07
**Status:** Design approved

## Problem

The current global switcher uses a CG-first detection pipeline — it starts with `CGWindowListCopyWindowInfo` which sees everything (GPU helper surfaces, companion windows, off-screen buffers) and then tries to filter them out with heuristics. This leads to wrong apps showing up, missing windows, and duplicate entries.

## Approach: AX-First Discovery (modeled on AltTab)

Start from AX (Accessibility) as the source of truth for window discovery. AX only reports windows that apps consider user-facing. Use CG only for supplementary data (z-ordering, bounds).

For cross-space window discovery, use the `_AXUIElementCreateWithRemoteToken` private SPI to brute-force discover AXUIElements across all Spaces.

### Detection Pipeline

1. **App Discovery** — `NSWorkspace.shared.runningApplications`, filtered by `activationPolicy == .regular`. Use `GetProcessForPID`/`GetProcessInformation` to reject XPC services.

2. **Window Discovery (per app, AX-first):**
   - Standard: `kAXWindowsAttribute` on the app's AXUIElement (current Space only)
   - Brute-force: construct AXUIElements via `_AXUIElementCreateWithRemoteToken` with 20-byte token `[pid:4][zero:4][0x636f636f:4][elementID:8]`, iterating IDs 0–999 with 100ms timeout
   - Merge both lists, deduplicate by AXUIElement identity

3. **Window Filtering:**
   - Default: accept `AXStandardWindow` and `AXDialog` subroles
   - App-specific overrides table (~20 bundle IDs)
   - Global minimum size: width > 100, height > 50
   - Skip minimized, skip hidden apps

4. **Enrichment from CG:**
   - `CGWindowID` via `_AXUIElementGetWindow` (already used)
   - CG for z-ordering and bounds
   - `CGSCopySpacesForWindows` for space membership if needed

5. **MRU sorting + group matching** — same as current `handleGlobalSwitcher()` logic

### App-Specific Override Table (from AltTab)

Default rule: accept `AXStandardWindow` or `AXDialog`, minimum 100x50px.

| App | Bundle ID | Override |
|-----|-----------|----------|
| Steam | `com.valvesoftware.steam` | Accept `AXUnknown`; reject empty-title dropdowns |
| Firefox | `org.mozilla.firefox*` | Accept `AXUnknown` fullscreen; reject tooltips (height ≤ 400) |
| JetBrains IDEs | `com.jetbrains.*` | Require title or min 100x100 |
| Adobe Audition | `com.adobe.Audition` | Accept `AXFloatingWindow` |
| Adobe After Effects | `com.adobe.AfterEffects` | Accept `AXFloatingWindow` |
| VLC | `org.videolan.vlc*` | Accept `AXUnknown` fullscreen |
| IINA | `com.colliderli.iina` | Accept floating level 2 |
| Keynote | `com.apple.iWork.Keynote` | Accept `AXUnknown` presentation |
| Books | `com.apple.iBooksX` | Accept `AXUnknown` during animations |
| Preview | `com.apple.Preview` | Accept level 1 multi-doc |
| World of Warcraft | `com.blizzard.worldofwarcraft` | Accept with `kAXWindowRole` |
| Battle.net | `net.battle.bootstrapper` | Accept `AXUnknown` |
| AutoCAD | `com.autodesk.AutoCAD*` | Accept `AXDocumentWindow` |
| OpenBoard | `org.oe-f.OpenBoard` | Blanket allow |
| FL Studio | `com.image-line.flstudio` | Blanket allow |
| DrBetotte | `com.ssworks.drbetotte` | Blanket allow |
| DVDFab | `com.goland.dvdfab.macos` | Blanket allow |
| SanGuoShaAirWD | `SanGuoShaAirWD` | Blanket allow |
| ColorSlurp | `com.IdeaPunch.ColorSlurp` | Only `AXStandardWindow` |
| Fusion360 | `com.autodesk.fusion360` | Reject empty-title side panels |
| Crossover/Wine | (no bundle ID) | Match by localizedName or path |
| scrcpy | (no bundle ID) | Match by localizedName, accept floating |
| Android Emulator | (no bundle ID) | Match by executable path regex |

### License Note

AltTab is GPLv3. We write our own implementation from scratch using the same techniques. The private API signatures are Apple's (not copyrightable). The algorithmic approaches (token format, ID iteration) are ideas/techniques, not copyrightable expression.

## Implementation Order

1. Add SPI declarations — `_AXUIElementCreateWithRemoteToken`, `GetProcessForPID`/`GetProcessInformation`, `CGSCopySpacesForWindows`
2. Build `ApplicationDiscriminator` — app-level XPC/zombie filter
3. Build `WindowDiscriminator` — the override table (pure function)
4. Build brute-force AX discovery — token construction + ID iteration with 100ms timeout
5. Rewrite `windowsInZOrderAllSpaces()` — AX-first pipeline feeding into same `[WindowInfo]` output
6. Adjust callers if needed
7. Build & test manually

## Files Changed

**New:**
- `ApplicationDiscriminator.swift`
- `WindowDiscriminator.swift`
- Possibly a private-APIs declarations file

**Modified:**
- `AccessibilityHelper.swift` — add SPI declarations, brute-force discovery method
- `WindowManager.windowsInZOrderAllSpaces()` — full rewrite
- `AppDelegate.handleGlobalSwitcher()` — adjust if needed

**Unchanged:**
- `SwitcherController`, `SwitcherPanel`, `SwitcherView` — presentation layer
- `WindowInfo` model
- `HotkeyManager`
- Group matching logic
