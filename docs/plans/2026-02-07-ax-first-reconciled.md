# AX-First Window Detection — Reconciled Plan

**Date:** 2026-02-07
**Status:** Draft
**Supersedes:** `ax-first-window-detection-design.md`, `ax-first-global-switcher.md`

## Problem

The global switcher starts from CG (Core Graphics), which sees every surface the compositor draws — GPU helpers, companion windows, off-screen buffers — and tries to filter them down with heuristics. This is backwards and fragile.

We are rewriting it from scratch.

## Solution

Flip the pipeline: start from AX (Accessibility), which only reports windows apps consider user-facing. Use CG only for supplementary data (z-ordering, bounds).

For cross-space discovery, use `_AXUIElementCreateWithRemoteToken` to brute-force discover AXUIElements across all Spaces.

## Detection Pipeline

```
1. App discovery
   NSWorkspace.runningApplications
   -> activationPolicy == .regular
   -> exclude own PID
   -> exclude hidden apps

2. Window discovery (per app, AX-first)
   a. Set AXUIElementSetMessagingTimeout on the app element (100ms)
      This caps any single AX query so slow/hung apps don't block the loop.
   b. Standard: kAXWindowsAttribute (current space)
   c. Brute-force: _AXUIElementCreateWithRemoteToken, IDs 0..999
   d. For each discovered element, get CGWindowID via _AXUIElementGetWindow
   e. Merge both lists, deduplicate by CGWindowID

3. Window filtering via WindowDiscriminator.isActualWindow(...)
   -> CGWindowID != 0
   -> min size 100x50
   -> subrole in {AXStandardWindow, AXDialog} by default
   -> ~24 app-specific overrides
   -> skip minimized

4. Enrich with CG data
   -> Fetch CGWindowListCopyWindowInfo (once, all spaces)
   -> Look up bounds by CGWindowID
   -> Build WindowInfo

5. Sort by MRU + CG z-order (unchanged)
6. Build switcher items with group matching (unchanged)
```

## New Files

### `Tabbed/Accessibility/PrivateAPIs.swift`

All private SPI declarations and the brute-force window discovery function, isolated in one file.

Declares:
- `_AXUIElementCreateWithRemoteToken`
- `CGSGetWindowLevel` (needed for CrossOver level check)

```swift
@_silgen_name("_AXUIElementCreateWithRemoteToken") @discardableResult
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?
```

The brute-force function constructs a 20-byte token per element:

| Offset | Size | Content |
|--------|------|---------|
| 0..3 | 4B | pid (Int32, LE) |
| 4..7 | 4B | 0x00000000 |
| 8..11 | 4B | 0x636f636f ("coco") |
| 12..19 | 8B | AXUIElementID (UInt64, LE) |

Iterates IDs 0–9999. Before iterating, call `AXUIElementSetMessagingTimeout` on the app element with a 100ms timeout — this caps each individual AX attribute query so a hung app doesn't block the loop. Returns discovered AXUIElements (with their CGWindowIDs) for the caller to filter.

### `Tabbed/Accessibility/WindowDiscriminator.swift`

Static `isActualWindow` function. Pure logic, no side effects.

#### Signature

```swift
static func isActualWindow(
    cgWindowID: CGWindowID,
    subrole: String?,
    role: String?,
    title: String?,
    size: CGSize?,
    level: Int?,               // from CGSGetWindowLevel; nil if unavailable
    bundleIdentifier: String?, // nil for no-bundle apps (Wine, scrcpy, QEMU)
    localizedName: String?,    // for no-bundle app matching
    executableURL: URL?        // for no-bundle app matching
) -> Bool
```

#### Universal Filters

- `cgWindowID != 0`
- `width > 100 AND height > 50`

Default accepted subroles: `AXStandardWindow`, `AXDialog`

#### App Override Table

Derived from observed macOS app behaviors compiled by AltTab. Do not look at AltTab's source code while implementing — maintain clean-room separation.

| App | Identifier | Rule | Why |
|-----|-----------|------|-----|
| Books | `com.apple.iBooksX` | Accept all | Subrole glitches during page-turn animations |
| Keynote | `com.apple.iWork.Keynote` | Accept all | Fake fullscreen uses non-standard subrole |
| IINA | `com.colliderli.iina` | Accept all | Floating video at non-standard level 2; blanket allow is simplest |
| FL Studio | `com.image-line.flstudio` | Accept all | Non-native app with non-standard subroles |
| OpenBoard | `org.oe-f.OpenBoard` | Accept all | Non-standard windowing |
| SanGuoShaAirWD | `SanGuoShaAirWD` | Accept all | Non-standard windowing |
| DVDFab | `com.goland.dvdfab.macos` | Accept all | Non-standard windowing |
| Dr. Betotte | `com.ssworks.drbetotte` | Accept all | Non-standard windowing |
| CrossOver | no bundle; match `localizedName == "wine64-preloader"` OR path contains `/winetemp-` | Accept if role == AXWindow AND subrole == AXUnknown AND level == 0 | Wine windows: no bundle ID, AXUnknown subrole, normal level |
| scrcpy | no bundle; match `localizedName == "scrcpy"` | Accept floating standard window | No bundle ID |
| Android Emulator | no bundle; match path contains `qemu-system` | Accept if title non-empty | QEMU process, no bundle ID |
| Adobe Audition | `com.adobe.Audition` | Accept AXFloatingWindow | Tool palettes are floating |
| Adobe After Effects | `com.adobe.AfterEffects` | Accept AXFloatingWindow | Tool palettes are floating |
| Steam | `com.valvesoftware.steam` | Accept if title non-empty AND role non-nil | All windows are AXUnknown; dropdowns have empty title or nil role |
| World of Warcraft | `com.blizzard.worldofwarcraft` | Accept if role == AXWindow | Non-standard subrole |
| Battle.net | `net.battle.bootstrapper` | Accept if role == AXWindow | AXUnknown subrole but proper AXWindow role |
| Firefox | `org.mozilla.firefox*` (prefix) | Accept if role == AXWindow AND height > 400 | Fullscreen video = AXUnknown + large; tooltips = AXUnknown + small |
| VLC | `org.videolan.vlc*` (prefix) | Accept if role == AXWindow | Non-native fullscreen uses AXUnknown subrole |
| AutoCAD | `com.autodesk.AutoCAD*` (prefix) | Accept AXDocumentWindow subrole | Uses non-standard subrole for documents |
| JetBrains IDEs | `com.jetbrains.*` / `com.google.android.studio*` (prefix) | Must have standard subrole OR non-empty title; min 100x100 | Splash screens and tool windows need filtering |
| Fusion 360 | `com.autodesk.fusion360` | Reject empty title | Side panels have empty titles |
| ColorSlurp | `com.IdeaPunch.ColorSlurp` | Must be AXStandardWindow | Color picker popups should be excluded |

Note: Preview is not listed because the default rule (accept AXStandardWindow / AXDialog) already handles it correctly. No override needed.

## Modified Files

### `WindowManager.swift`

- Rewrite `windowsInZOrderAllSpaces()` to use AX-first pipeline
- Keep return type `[WindowInfo]` identical
- Use CG window list only for bounds lookup and z-order hint
- `refreshWindowList()` and `windowsInZOrder()` stay unchanged

### `AccessibilityHelper.swift`

- Add `getRole(of:)` helper (needed by WindowDiscriminator)
- Existing `_AXUIElementGetWindow` declaration stays

## What probably does not have to change

- `WindowInfo` struct
- `SwitcherItem` / `SwitcherItemBuilder`
- `handleGlobalSwitcher()` in AppDelegate
- MRU sorting logic
- Group matching logic (ID + frame-based)
- Switcher UI / presentation

## License Note

our approach, and the feature we are building, is inspired by AltTab. AltTab is GPLv3. We write our own implementation from scratch — do not reference AltTab's source code during implementation to maintain clean-room separation. The private API signatures are Apple's (not copyrightable). The token format is a fact about Apple's SPI. The app override table encodes factual observations about how apps behave with macOS accessibility APIs — these are facts, not creative expression.
