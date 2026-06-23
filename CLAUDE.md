# Touchy

Native macOS menu-bar app that remaps trackpad multitouch gestures (3/4/5-finger
swipes and taps) to keyboard shortcuts or mouse clicks. SwiftPM, no Dock icon
(`.accessory` / `LSUIElement`).

## Build & run

```sh
swift build                  # dev build
./scripts/make-app.sh        # assemble & sign Touchy.app (release)
open Touchy.app
```

There are no tests. A clean `swift build` is the bar for "done".

## Architecture (data flow)

`MultitouchReader` reads raw frames from the private `MultitouchSupport.framework`
→ `GestureRecognizer` classifies a touch sequence into a `Gesture` → `GestureEngine`
looks up the binding in `BindingStore` and calls `KeyEmitter`, which synthesizes the
event via `CGEvent`. The menu-bar UI (`TouchyApp` → `ContentView`) edits bindings and
shows the last recognized gesture.

*   `Sources/CMultitouch/` — C shim exposing the reverse-engineered framework header.
    The `Finger` struct layout is load-bearing; do not reorder fields.
*   Bindings persist as JSON in `~/Library/Application Support/Touchy/bindings.json`.

## Two facts that drive most behavior

1.  **Reading touches needs no permission; emitting events needs Accessibility.**
    `CGEvent.post(tap: .cghidEventTap)` *silently no-ops* when the app isn't trusted
    (`AXIsProcessTrusted()`). The classic symptom — "gestures recognized but shortcuts
    don't fire" — is a missing/stale Accessibility grant, not a recognition bug.

2.  **TCC grants are pinned to the code signature.** Releases are **ad-hoc signed**
    (CI has no Developer ID), so every Homebrew upgrade gets a new cdhash and the
    Accessibility grant goes stale even though System Settings still shows it enabled.
    Recover with `tccutil reset Accessibility com.gugahoi.touchy`, then re-grant.

## Threading

The multitouch frame callback (`mtFrameCallback`) runs on the framework's own thread.
Only `CGEvent` posting and lock-protected `BindingStore.activeAction` are safe there.
Anything touching `@Published` state or Text Input Source APIs (`KeyCombo.display`)
**must** hop to the main thread — see the `DispatchQueue.main.async` in `GestureEngine.handle`.

MultitouchSupport stops delivering frames after sleep and never resumes; the reader
tears down on sleep and re-arms on wake (with retry) — keep that intact.

## Conventions

*   Set `TOUCHY_DEBUG=1` to enable stderr diagnostics throughout.
*   Swift 6 toolchain but the `Touchy` target uses **v5 language mode** on purpose
    (the `@convention(c)` callback fights strict concurrency) — don't "fix" this.
*   Decoders for persisted types decode defensively (`decodeIfPresent`, legacy formats)
    so an old `bindings.json` never throws and silently drops a binding.
