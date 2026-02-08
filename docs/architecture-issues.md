# Architecture Issues

## 1. Frame Sync Logic is Scattered

`expectedFrames`, `shouldSuppress()`, `framesMatch()`, `clampFrameForTabBar()`, and `resyncWorkItems` are split across NotificationSuppression.swift and WindowEventHandlers.swift. This is a single coherent concern — echo cancellation for our own frame changes — but it's interleaved with unrelated event handling.

The problem shows up concretely in WindowEventHandlers: `handleWindowMoved` and `handleWindowResized` both inline the same sequence — suppress check, clamp, set expected frame, apply to other windows — but with slight variations (resize adds a delayed resync). The resync closure in `handleWindowResized` (lines 83-109) recapitulates the clamp-and-apply logic a third time. When you need to change tolerance or clamping behavior, you're editing in 3+ places.

### Plan

Create a `FrameSync` type (not a class — a simple struct/enum namespace) in `Tabbed/Platform/` or `Tabbed/features/TabGroups/`.

**What it owns:**
- `expectedFrames: [CGWindowID: (frame: CGRect, deadline: Date)]`
- `resyncWorkItems: [UUID: DispatchWorkItem]`
- `frameTolerance` and `suppressionDeadline` constants

**Methods:**
- `setExpected(_:for:)` — record expected frames
- `shouldSuppress(windowID:currentFrame:)` — check + auto-expire
- `framesMatch(_:_:)` — tolerance comparison
- `clampForTabBar(_:)` — adjust for tab bar height
- `applyFrameToGroup(group:activeWindow:frame:)` — the repeated clamp → set expected → apply to others sequence, extracted once
- `scheduleResync(groupID:after:block:)` — cancel-and-reschedule pattern for delayed resyncs

**What changes in AppDelegate:**
- `expectedFrames` and `resyncWorkItems` properties replaced by a single `frameSync: FrameSync` property
- NotificationSuppression.swift goes away entirely (its 4 methods move into FrameSync)
- `handleWindowMoved` and `handleWindowResized` shrink to: guard → `frameSync.shouldSuppress()` → `frameSync.applyFrameToGroup()` → panel positioning → `evaluateAutoCapture()`
- The resync closure calls `frameSync.applyFrameToGroup()` instead of reimplementing the logic

**Risk:** Low. This is purely moving existing logic behind a single call site. No behavioral change.


## 2. MRU State Lives Loose in AppDelegate

`globalMRU: [MRUEntry]` is an array on AppDelegate with one mutation point (`recordGlobalActivation`) and one removal point (`handleWindowDestroyed`), but it's read from `handleGlobalSwitcher` which builds the 3-phase item list. The array itself is simple, but the building logic (phases 1-3 in QuickSwitcher.swift lines 28-74) is ~45 lines of interlocked dedup sets and fallbacks that are really "given MRU + live windows + groups, produce an ordered item list." That's a pure function tangled into an AppDelegate extension.

### Plan

Create `MRUTracker` in `Tabbed/features/QuickSwitcher/`.

**What it owns:**
- `entries: [MRUEntry]` (the ordered list)

**Methods:**
- `recordActivation(_:)` — dedup + insert at front (current `recordGlobalActivation`)
- `remove(_:)` — remove entry (currently inline in `handleWindowDestroyed`)
- `removeGroupedWindows(groupWindows:)` — remove single-window entries that got grouped (currently in `addWindow`)
- `buildSwitcherItems(groups:zOrderWindows:groupFrames:) -> [SwitcherItem]` — the 3-phase construction, extracted as a pure function. Takes GroupManager state as parameters rather than reaching into it.

**What changes in AppDelegate:**
- `globalMRU` replaced by `mruTracker: MRUTracker`
- `recordGlobalActivation` calls become `mruTracker.recordActivation`
- `handleWindowDestroyed` removal becomes `mruTracker.remove`
- `handleGlobalSwitcher` shrinks: `let items = mruTracker.buildSwitcherItems(groups:zOrderWindows:groupFrames:)`
- QuickSwitcher.swift loses ~50 lines of item-building logic

**Risk:** Low. `buildSwitcherItems` is a pure function — testable in isolation. The MRU invariant (no duplicates, most-recent-first) becomes enforceable in one place.


## 3. Switcher State Transitions Are Spread Across Files

There are two pieces of state that together define the "switcher session":
1. `SwitcherController` — owns `isActive`, `scope`, panel, items, selection
2. AppDelegate — owns `cyclingGroup`, `cycleEndTime`, `isCycleCooldownActive`

These interact in `handleModifierReleased` (QuickSwitcher.swift:94-113), `handleHotkeyCycleTab` (TabCycling.swift:7-62), `handleWindowFocused` (WindowEventHandlers.swift:121), and `handleAppActivated` (WindowEventHandlers.swift:196). The guard `!switcherController.isActive, !isCycleCooldownActive` appears in two event handlers to suppress OS focus echoes during/after switching.

The concrete issue: `cyclingGroup`, `cycleEndTime`, and the cooldown check are AppDelegate state that only exists to support the switcher, but SwitcherController doesn't know about them. When `handleModifierReleased` fires, it has to coordinate between `switcherController.isActive` and `cyclingGroup` state with branching logic. The escape handler in AppDelegate.swift:133-141 duplicates the cleanup (`group.endCycle(); cyclingGroup = nil`).

### Plan

Move cycling state into `SwitcherController`.

**New SwitcherController properties:**
- `weak var cyclingGroup: TabGroup?`
- `private(set) var commitTime: Date?` (replaces `cycleEndTime`)
- `var isCooldownActive: Bool` (replaces `isCycleCooldownActive`)

**Modified SwitcherController methods:**
- `commit()` — after calling `onCommit`, set `commitTime = Date()`, call `cyclingGroup?.endCycle()`, clear `cyclingGroup`
- `dismiss()` — call `cyclingGroup?.endCycle()`, clear `cyclingGroup`, call `onDismiss`
- `startCycling(in group:)` — set `cyclingGroup`, called from `handleHotkeyCycleTab`

**What changes in AppDelegate:**
- Remove `cyclingGroup`, `cycleEndTime`, `isCycleCooldownActive`, `cycleCooldownDuration`
- `handleModifierReleased` simplifies: just `switcherController.commitOrEndCycle()` + `hotkeyManager?.stopModifierWatch()`
- The focus suppression guard becomes `!switcherController.isActive, !switcherController.isCooldownActive`
- Escape handler becomes `switcherController.dismiss()` + `hotkeyManager?.stopModifierWatch()`
- TabCycling.swift: `handleHotkeyCycleTab` calls `switcherController.startCycling(in: group)` instead of setting `cyclingGroup = group`
- The duplicated cleanup in escape/commit/dismiss collapses into SwitcherController

**Risk:** Medium. The cooldown interacts with focus event handling, so the timing needs to be preserved exactly. Test by rapid-switching and verifying no focus flicker.


## 4. AutoCapture Observer Management

AutoCapture.swift is 270 lines, all in an AppDelegate extension, using 6 AppDelegate properties (`autoCaptureGroup`, `autoCaptureScreen`, `autoCaptureObservers`, `autoCaptureAppElements`, `autoCaptureNotificationTokens`, `autoCaptureDefaultCenterTokens`). The AXObserver callback (lines 165-176) uses `Unmanaged<AppDelegate>` to get back to self, and the activate/deactivate lifecycle manages its own notification center observers.

This is already a self-contained subsystem that happens to live on AppDelegate. The only things it needs from outside are:
- `groupManager` — to check `isWindowGrouped` and iterate groups
- `sessionConfig.autoCaptureEnabled` — to gate evaluation
- `addWindow(_:to:)` — to actually capture a window
- `setExpectedFrame` — when capturing (could move to FrameSync)
- `evaluateAutoCapture()` is called from WindowEventHandlers after move/resize/destroy

### Plan

Create `AutoCaptureCoordinator` class in `Tabbed/features/AutoCapture/`.

**What it owns:**
- All 6 properties currently prefixed `autoCapture*` on AppDelegate
- `systemBundleIDs` set
- All methods currently in AutoCapture.swift: `isGroupMaximized`, `allWindowsOnScreenBelongToGroup`, `evaluateAutoCapture`, `activateAutoCapture`, `deactivateAutoCapture`, `addAutoCaptureObserver`, `removeAutoCaptureObserver`, `handleWindowCreated`, `handleAutoCaptureFocusChanged`, `captureWindowIfEligible`

**Constructor takes:**
- `groupManager: GroupManager`
- `onCapture: (WindowInfo, TabGroup) -> Void` (replaces `addWindow` call)
- `onSetExpectedFrame: (CGRect, [CGWindowID]) -> Void` (replaces `setExpectedFrame` call, or takes a `FrameSync` ref if issue #1 is done first)

**What changes in AppDelegate:**
- 6 `autoCapture*` properties replaced by `autoCaptureCoordinator: AutoCaptureCoordinator`
- AutoCapture.swift (AppDelegate extension) deleted
- WindowEventHandlers calls `autoCaptureCoordinator.evaluate()` instead of `evaluateAutoCapture()`
- Settings callback calls `autoCaptureCoordinator.evaluate()` / `.deactivate()`
- `applicationWillTerminate` calls `autoCaptureCoordinator.deactivate()`
- The `Unmanaged<AppDelegate>` in the AXObserver callback becomes `Unmanaged<AutoCaptureCoordinator>` — cleaner because the coordinator is the actual owner

**Risk:** Low-medium. The AXObserver callback and Unmanaged pointer management is the trickiest part — needs to use `[weak self]` or ensure the coordinator outlives the observers. The current code already handles this correctly for AppDelegate; same pattern applies.
