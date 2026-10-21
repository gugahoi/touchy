# Example configuration

Sample config files for Touchy, in exactly the format the app writes:

| File | What it holds |
|---|---|
| [`bindings.json`](bindings.json) | Gesture → action bindings, plus the **Enabled** switch |
| [`settings.json`](settings.json) | Gesture-recognition tuning (the **Settings** tab) |

JSON can't contain comments, so everything is explained here instead.

## Using them

Touchy reads each file from the first of these locations where it exists, and
saves in-app changes back to that same file:

1. `~/.config/touchy/`
2. `~/Library/Application Support/Touchy/`

To start from these examples (e.g. in a dotfiles repo):

```sh
mkdir -p ~/.config/touchy
cp examples/bindings.json examples/settings.json ~/.config/touchy/
```

Then restart Touchy — it reads the files at launch. Files in `~/.config/touchy`
take precedence, so any bindings you set up in the app before stay in
Application Support, unused. To keep those instead, copy them from there:
`cp ~/Library/Application\ Support/Touchy/*.json ~/.config/touchy/`.

You don't need both files: a missing file just means defaults.

## `bindings.json`

```json
{
  "bindings" : {
    "<gesture id>" : <action>,
    ...
  },
  "enabled" : true
}
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `enabled` | bool | `true` | The **Enabled** switch. `false` pauses all bindings. |
| `bindings` | object | `{}` | Gesture id → action. Gestures not listed are unbound. |

### Gesture ids

| Id | Gesture |
|---|---|
| `swipe-<fingers>-<direction>` | `fingers` is `3`, `4` or `5`; `direction` is `up`, `down`, `left` or `right` |
| `tap-<fingers>` | `fingers` is `3`, `4` or `5` |

That's 15 gestures in all, e.g. `swipe-3-up`, `swipe-5-left`, `tap-4`.
Directions are the way your fingers move on the pad — `up` is toward the top
edge (away from you) — regardless of the natural-scrolling setting. An unknown
id (e.g. a typo like `swipe-3-upp`) is kept in the file but never fires; Touchy
logs a warning about it at launch.

> **Heads-up:** macOS uses 3- and 4-finger swipes and the 3-finger tap itself by
> default. If you bind one, disable it in System Settings ▸ Trackpad, or both
> actions will fire. 5-finger gestures are free.

### Key action

Sends a keyboard shortcut.

```json
{ "type" : "key", "key" : { "keyCode" : 30, "command" : true, "shift" : true } }
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `keyCode` | integer | *required* | macOS virtual key code (see below) |
| `command`, `option`, `control`, `shift` | bool | `false` | Modifiers held with the key |

`keyCode` identifies a **physical key position** (on the US/ANSI layout), not a
character: `0` is the key labelled A on a US keyboard, whatever your layout
types there. The easiest way to find a code is to record the shortcut in the app
and copy it from the saved file. Common codes:

| Key | Code | Key | Code | Key | Code | Key | Code |
|---|---|---|---|---|---|---|---|
| A | 0 | N | 45 | 0 | 29 | `[` | 33 |
| B | 11 | O | 31 | 1 | 18 | `]` | 30 |
| C | 8 | P | 35 | 2 | 19 | `-` | 27 |
| D | 2 | Q | 12 | 3 | 20 | `=` | 24 |
| E | 14 | R | 15 | 4 | 21 | `;` | 41 |
| F | 3 | S | 1 | 5 | 23 | `'` | 39 |
| G | 5 | T | 17 | 6 | 22 | `,` | 43 |
| H | 4 | U | 32 | 7 | 26 | `.` | 47 |
| I | 34 | V | 9 | 8 | 28 | `/` | 44 |
| J | 38 | W | 13 | 9 | 25 | `\` | 42 |
| K | 40 | X | 7 | Return | 36 | `` ` `` | 50 |
| L | 37 | Y | 16 | Tab | 48 | Space | 49 |
| M | 46 | Z | 6 | Escape | 53 | Delete (⌫) | 51 |

| Key | Code | Key | Code | Key | Code | Key | Code |
|---|---|---|---|---|---|---|---|
| ← | 123 | Home | 115 | F1 | 122 | F7 | 98 |
| → | 124 | End | 119 | F2 | 120 | F8 | 100 |
| ↓ | 125 | Page Up | 116 | F3 | 99 | F9 | 101 |
| ↑ | 126 | Page Down | 121 | F4 | 118 | F10 | 109 |
| Forward Delete (⌦) | 117 | | | F5 | 96 | F11 | 103 |
| | | | | F6 | 97 | F12 | 111 |

### Click action

Clicks at the current pointer location.

```json
{ "type" : "click", "click" : { "button" : "left", "command" : true } }
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `button` | string | *required* | `"left"`, `"right"` or `"middle"` |
| `command`, `option`, `control`, `shift` | bool | `false` | Modifiers held during the click |
| `clickCount` | integer | `1` | `2` for a double-click |

### What the example binds

| Gesture | Action | Typical effect |
|---|---|---|
| `swipe-3-up` | ⇧⌘] | Next tab |
| `swipe-3-down` | ⇧⌘[ | Previous tab |
| `swipe-5-left` | ⌘[ | Back |
| `swipe-5-right` | ⌘] | Forward |
| `swipe-5-up` | ⇧⌘T | Reopen closed tab |
| `swipe-5-down` | ⌘W | Close tab/window |
| `tap-3` | ⌘ left click | Open link in new tab |
| `tap-4` | Middle click | Open link in a background tab |
| `tap-5` | Double left click | Select word / open item |

## `settings.json`

```json
{
  "recognizer" : {
    "cooldown" : 0.25,
    "fingerTravelRatio" : 0.5,
    "swipeThreshold" : 0.12,
    "tapMaxDuration" : 0.4,
    "tapMaxMovement" : 0.1
  }
}
```

Distances are fractions of the trackpad (`0.12` = 12%, as shown in the Settings
tab); durations are seconds.

| Key | Settings tab name | Default | Range | Meaning |
|---|---|---|---|---|
| `swipeThreshold` | Swipe distance | `0.12` | `0.04`–`0.30` | How far fingers travel before a swipe fires. Lower = more sensitive. |
| `fingerTravelRatio` | Per-finger travel | `0.5` | `0`–`1` | At least 3 fingers must *each* move this fraction of `swipeThreshold`, so a 2-finger scroll with a resting thumb or palm isn't a swipe. `0` turns the check off. |
| `tapMaxDuration` | Max tap duration | `0.4` | `0.1`–`1.0` | Touches held longer aren't taps. |
| `tapMaxMovement` | Tap movement tolerance | `0.1` | `0.02`–`0.20` | How far fingers may drift and still tap. |
| `cooldown` | Cooldown between gestures | `0.25` | `0`–`1.0` | Pause after a gesture fires before another can. |

Omitted keys use their defaults, and out-of-range values are clamped into range.

## Editing by hand

- **Restart Touchy** after editing — it reads the files at launch. Edits made
  while it's running are overwritten the next time you change something in the app.
- **Keep it plain JSON:** no comments. Check a file with `jq . bindings.json`
  (`jq` ships with macOS 15+; otherwise `brew install jq`).
- **Short forms are fine.** Fields marked with a default can be left out, e.g.
  `{ "type" : "click", "click" : { "button" : "middle" } }`. When Touchy next
  saves, it writes every field out, with keys sorted — the format of these
  examples. Keep your files in that format and in-app changes produce minimal diffs.
- **Mistakes don't destroy your config.** If a file can't be parsed, Touchy saves
  a copy as `bindings.json.bak` (or `settings.json.bak`) next to it and starts
  from defaults.
- **Symlinks are fine.** If `~/.config/touchy`, or a file in it, links into a
  dotfiles repo, Touchy writes through the link rather than replacing it.
