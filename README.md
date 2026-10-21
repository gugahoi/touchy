# Touchy

A native macOS menu-bar app that remaps **multitouch trackpad gestures** to
**keyboard shortcuts**. Configure 3-, 4-, and 5-finger swipes (in all four
directions) and taps, each to any key combination.

## How it works

- **Input:** reads raw trackpad frames from Apple's private
  `MultitouchSupport.framework` (the only way to get system-wide touch data —
  `NSEvent` touches only fire for your own focused view). No special permission
  is needed to *read* touches.
- **Recognition:** a small state machine (`GestureRecognizer`) classifies each
  touch sequence by peak finger count and centroid travel into a swipe
  (direction) or a tap, with a movement/duration threshold and a post-fire
  cooldown to debounce. Hovering/just-lifted contacts are ignored, and a swipe
  needs ≥3 fingers actually moving, so 2-finger scrolls don't misfire. The
  thresholds are tunable in the Settings tab.
- **Output:** synthesizes the bound shortcut with `CGEvent` (Quartz). This
  **requires Accessibility permission** (System Settings ▸ Privacy & Security ▸
  Accessibility).

## Build & run

```sh
./scripts/make-app.sh        # builds release, assembles & ad-hoc-signs Touchy.app
open Touchy.app
```

On first launch it asks for **Accessibility** permission — grant it so Touchy can
send keystrokes. Touchy lives in the menu bar (hand icon); click it to open the
configuration window.

To develop, you can also `swift build` and run, but key emission is most reliable
from the signed `.app` because macOS tracks the permission grant by bundle id +
signature.

## Configuring gestures

1. Click the menu-bar icon to open the config window.
2. Next to a gesture, click the action button:
   - **Record Keyboard Shortcut…** then press the key combo you want (e.g. ⌘⇧4).
     Press **Esc** to cancel.
   - **Mouse Click…** opens an editor: choose the button (Left/Right/Middle),
     any combination of ⌘/⌥/⌃/⇧ modifiers, and single vs. **double-click**.
     The click is synthesized at the current pointer location — so e.g. a
     3-finger tap mapped to ⌘ Left Click opens whatever link the pointer is over.

   Use the ✕ to clear a binding.
3. The footer shows the last recognized gesture (green dot = a bound shortcut
   fired, grey = recognized but unbound) — handy for testing.
4. The **Enabled** switch globally pauses/resumes remapping.

## Settings

Switch to the **Settings** tab at the top of the window:

- **Launch at login** registers Touchy as a login item (System Settings ▸ General
  ▸ Login Items) so it starts automatically. The login item points at the app's
  current location, so keep `Touchy.app` somewhere stable (e.g. `/Applications`).
- **Gesture recognition tuning** — changes apply immediately, so you can use the
  footer's last-gesture indicator to try them out:

  | Setting | Default | Effect |
  |---|---|---|
  | Swipe distance | 12% of trackpad | How far fingers travel before a swipe fires. Lower = more sensitive. |
  | Per-finger travel | 50% of swipe | At least 3 fingers must *each* move this share of the swipe distance, so 2-finger scrolls with a resting thumb/palm don't count. Lower it if real swipes are missed; *Off* disables the check. |
  | Max tap duration | 400 ms | Touches held longer aren't taps. |
  | Tap movement tolerance | 10% of trackpad | How far fingers may drift and still tap. |
  | Cooldown between gestures | 250 ms | Pause after a gesture fires before another can. |

  **Restore Defaults** resets the tuning (not your bindings).

## ⚠️ Gesture conflicts with macOS

macOS already owns some multi-finger gestures by default (Mission Control, switch
spaces, App Exposé, look-up). Those are marked **⚠︎** in the UI. If you bind one,
*both* the system action and your shortcut fire. To avoid that, either:

- disable the conflicting gesture in **System Settings ▸ Trackpad**, or
- prefer **5-finger** gestures, which macOS doesn't use by default.

## Notes & limitations

- Unsandboxed, ad-hoc signed — personal use, not App-Store distributable (it uses
  a private framework and posts global events).
- Rebuilding changes the binary, so macOS may ask you to re-grant Accessibility
  after a fresh build.
- Bindings persist to `~/Library/Application Support/Touchy/bindings.json` and
  recognition tuning to `settings.json` in the same folder.
- Set `TOUCHY_DEBUG=1` when launching the binary directly to log recognized
  gestures to stderr.
```sh
TOUCHY_DEBUG=1 ./Touchy.app/Contents/MacOS/Touchy
```
