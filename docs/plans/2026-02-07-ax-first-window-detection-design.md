# AX-First Window Detection for Global Switcher

## Problem

The global switcher's window detection starts from CG (Core Graphics), which sees every surface the compositor draws -- GPU helpers, companion windows, off-screen buffers -- and then tries to filter them down to "real" windows with heuristics. This is backwards and fragile.

## Solution

Flip the pipeline: start from AX (Accessibility), which only reports windows apps consider user-facing. Use CG only for supplementary data (z-ordering, bounds for off-space windows).

## Architecture

```
1. NSWorkspace.runningApplications
   -> activationPolicy == .regular, exclude own PID, exclude hidden

2. Per app: discover windows via AX
   a. Standard: kAXWindowsAttribute (current space)
   b. Brute-force: _AXUIElementCreateWithRemoteToken, IDs 0..999 (other spaces)
   c. Merge + deduplicate by CGWindowID

3. Per window: validate via WindowDiscriminator
   -> subrole check (AXStandardWindow / AXDialog)
   -> 24 app-specific overrides
   -> min size 100x50
   -> must-have guards (JetBrains, Steam, Fusion360, ColorSlurp)

4. Per valid window: enrich with CG data
   -> CGWindowID via _AXUIElementGetWindow
   -> bounds from CGWindowListCopyWindowInfo
   -> Build WindowInfo

5. Sort by MRU + CG z-order (unchanged)
6. Build switcher items with group matching (unchanged)
```

## New Files

### `Tabbed/Accessibility/PrivateAPIs.swift`

Declares `_AXUIElementCreateWithRemoteToken` and provides the brute-force window discovery function.

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

Iterates IDs 0-999 with 100ms timeout. Only keeps elements with valid subroles per WindowDiscriminator.

### `Tabbed/Accessibility/WindowDiscriminator.swift`

Static `isActualWindow` function with all 24 app-specific overrides.

Universal filters:
- CGWindowID != 0
- width > 100 AND height > 50

Default accepted subroles: `AXStandardWindow`, `AXDialog`

App overrides (bypass or extend subrole check):

| App | Bundle ID | Rule |
|-----|-----------|------|
| Books | com.apple.iBooksX | Accept all (animation subrole glitch) |
| Keynote | com.apple.iWork.Keynote | Accept all (fake fullscreen) |
| Preview | com.apple.Preview | Accept standard/dialog (level 1 OK) |
| IINA | com.colliderli.iina | Accept all (floating video) |
| FL Studio | com.image-line.flstudio | Accept if title non-empty |
| CrossOver | wine64-preloader (no bundle) | Accept AXUnknown + level 0 |
| scrcpy | scrcpy (no bundle) | Accept floating standard window |
| OpenBoard | org.oe-f.OpenBoard | Accept all |
| Adobe Audition | com.adobe.Audition | Accept floating windows |
| Adobe After Effects | com.adobe.AfterEffects | Accept floating windows |
| Steam | com.valvesoftware.steam | Accept if title+role non-nil; reject empty title/nil role |
| World of Warcraft | com.blizzard.worldofwarcraft | Accept if role == window |
| Battle.net | net.battle.bootstrapper | Accept if role == window |
| Firefox | org.mozilla.firefox* | Accept if role == window AND height > 400 |
| VLC | org.videolan.vlc* | Accept if role == window |
| SanGuoShaAirWD | SanGuoShaAirWD | Accept all |
| DVDFab | com.goland.dvdfab.macos | Accept all |
| Dr. Betotte | com.ssworks.drbetotte | Accept all |
| Android Emulator | qemu-system (no bundle) | Accept if title non-empty |
| AutoCAD | com.autodesk.AutoCAD* | Accept AXDocumentWindow |
| JetBrains IDEs | com.jetbrains.* / com.google.android.studio* | Must have standard subrole OR non-empty title; min 100x100 |
| Fusion 360 | com.autodesk.fusion360 | Reject empty title |
| ColorSlurp | com.IdeaPunch.ColorSlurp | Must be standard window |

## Modified Files

### `WindowManager.swift`

- Rewrite `windowsInZOrderAllSpaces()` to use AX-first pipeline
- Keep return type `[WindowInfo]` identical
- Use CG window list only for bounds lookup and z-order hint
- `refreshWindowList()` and `windowsInZOrder()` stay unchanged (they serve different purposes)

### `AccessibilityHelper.swift`

- Add `getRole(of:)` helper (needed by WindowDiscriminator)
- The existing `_AXUIElementGetWindow` declaration stays (already there)

## What Does NOT Change

- `WindowInfo` struct
- `SwitcherItem` / `SwitcherItemBuilder`
- `handleGlobalSwitcher()` in AppDelegate
- MRU sorting logic
- Group matching logic (ID + frame-based)
- Switcher UI / presentation
