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

The app's version comes from the nearest `v*` git tag, with the commit count as
the build number (e.g. `1.2.0 (40)`). Set `TOUCHY_VERSION=1.3.0` to override it;
the release workflow does this from the tag being released.

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
- **Version** shows the running version and build, e.g. `1.2.0 (40)` — handy
  for bug reports.
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

## Configuration files

Touchy keeps its configuration in two JSON files:

- `bindings.json` — gesture → action bindings and the Enabled switch
- `settings.json` — recognition tuning from the Settings tab

Each file is read from the **first** of these locations where it exists:

1. `~/.config/touchy/`
2. `~/Library/Application Support/Touchy/`

Changes made in the app are saved back to that same file. A file that doesn't
exist yet is created in `~/.config/touchy/` if that folder exists, otherwise in
Application Support. The Settings tab shows which location each file is using.

To keep your configuration in a dotfiles repo:

```sh
mkdir -p ~/.config/touchy
cp ~/Library/Application\ Support/Touchy/*.json ~/.config/touchy/
```

then restart Touchy. **[`examples/`](examples/)** has sample files and a full
reference for both formats: every field, gesture id and common key code. Notes:

- Files are written pretty-printed with sorted keys, so they diff cleanly.
- Symlinks are followed: if `~/.config/touchy` (or a file in it) is a symlink
  into your repo, Touchy writes through it rather than replacing the link.
- Touchy reads the files at launch; restart it after editing them by hand
  (e.g. after a `git pull`).
- Missing fields fall back to defaults. If a file can't be parsed at all, Touchy
  saves a copy as `<name>.json.bak` next to it and starts from defaults, so a
  typo never silently destroys your configuration.

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
- Configuration lives in two JSON files — see [Configuration files](#configuration-files).
- Set `TOUCHY_DEBUG=1` when launching the binary directly to log recognized
  gestures to stderr.
```sh
TOUCHY_DEBUG=1 ./Touchy.app/Contents/MacOS/Touchy
```
