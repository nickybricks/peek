# Peek

A window switcher for macOS that does one thing: show me every open window, let me pick one.

## Why this exists

macOS has never had a good answer to "switch me to that other window."

`Cmd-Tab` switches between *apps*, not windows. If you have three Visual Studio Code
windows open, `Cmd-Tab` treats them as one thing — you land on whichever one happens to
be on top and then hunt for the rest. `Cmd-\`` cycles windows within an app, but only the
current app, and only blind: no previews, just windows flying past. Mission Control shows
everything, but it is a full-screen takeover that throws your whole desktop in the air
when all you wanted was to get back to the browser.

Peek is the missing middle. Press `Cmd-Tab`, see a small panel with a thumbnail of every
open window across every desktop, pick one, done. That's the entire product.

## How it works

- **`Cmd-Tab`** — every window, across all apps and all desktops (Spaces)
- **`Option-Tab`** — only the windows of the app you're currently in
- **Tap and release** — jumps straight back to the window you used before, no panel flash
- **Hold** — the panel appears; `Tab` and the arrow keys move the selection, `Shift-Tab`
  goes backwards, releasing the modifier switches
- **Mouse** — hover to select, click to switch
- **`Escape`** — cancel

Windows are ordered by when you last used them, so the previous window is always second
in the list. That's what makes tap-and-release work: it is the same flip-flop gesture as
`Cmd-Tab` between two apps, except it works per window.

The panel is a compact floating card, not a full-screen overlay — your desktop stays
visible behind it.

There are no settings, and the two shortcuts can't be remapped. That's the point: Peek is
meant to be installed once and then forgotten about. If you want knobs, see
[prior art](#prior-art) below.

## Running it

Peek has no Dock icon. It lives in the menu bar as a ▤ icon — click it for a reminder of
the shortcuts, to see whether both permissions are granted (with a shortcut into the right
System Settings pane if not), to toggle "start at login", and to quit.

Peek starts automatically every time you log in. **If you quit it, start it again the way
you'd start any app** — from Launchpad, from the Applications folder, or with Spotlight
(`Cmd-Space`, type "Peek"). No Terminal needed. While Peek isn't running, `Cmd-Tab` simply
behaves like the normal macOS app switcher again.

## Install

Requires macOS 14 or later.

**Download:** grab `Peek.zip` from the [latest release](https://github.com/nickybricks/peek/releases/latest),
unzip it, and drag `Peek.app` into your Applications folder. Double-click to start.

**Or build it yourself** (needs Xcode command line tools):

```bash
git clone https://github.com/nickybricks/peek.git
cd peek
./build.sh
```

That builds the app, installs it to `/Applications/Peek.app` and launches it.

On first launch macOS will ask for two permissions, both in
**System Settings → Privacy & Security**:

- **Accessibility** — required to intercept `Cmd-Tab` and to raise the window you pick
- **Screen Recording** — required for the window thumbnails and titles

Peek picks up the accessibility permission within a couple of seconds; no restart needed.

### A note on signing

`build.sh` signs with a Developer ID certificate if it finds one, which keeps the granted
permissions valid across rebuilds. Without a certificate it falls back to ad-hoc signing —
that works fine, but macOS treats each rebuild as a brand new app and asks for both
permissions again every time. Set `PEEK_SIGN_IDENTITY` to use your own certificate:

```bash
PEEK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

## How it's built

Around 500 lines of Swift, no dependencies. A Swift package rather than an Xcode project,
so the whole thing builds with `swift build`.

| File | Role |
| --- | --- |
| [`SwitcherController.swift`](Sources/Peek/SwitcherController.swift) | Grabs the keyboard via `CGEventTap`, owns the most-recently-used order and the panel |
| [`WindowManager.swift`](Sources/Peek/WindowManager.swift) | Lists windows (`CGWindowList`), captures thumbnails (`ScreenCaptureKit`), raises the pick (Accessibility API) |
| [`SwitcherView.swift`](Sources/Peek/SwitcherView.swift) | The SwiftUI grid |
| [`AppDelegate.swift`](Sources/Peek/AppDelegate.swift) | Menu bar item, permission prompts, login item |

Two details worth knowing if you read the code:

`CGWindowList` only guarantees front-to-back ordering when you ask for on-screen windows
only. Asking for all windows across all Spaces returns them in no meaningful order, so
Peek queries the z-order separately and merges it in.

Mapping an accessibility window handle back to a `CGWindowID` needs the private
`_AXUIElementGetWindow`, the same approach [AltTab](https://github.com/lwouis/alt-tab-macos)
and [Rectangle](https://github.com/rxhanson/Rectangle) use. There is no public API for it.

## Limitations

- Windows minimized to the Dock are listed and get un-minimized when picked, but have no
  live thumbnail
- If one app has windows on several Spaces, switching may land on the wrong Space first;
  doing this properly needs private `CGS` APIs
- The most-recently-used history lives in memory, so the very first switch after a restart
  falls back to z-order

## Prior art

[AltTab](https://github.com/lwouis/alt-tab-macos) is the mature, full-featured version of
this idea — dozens of preferences, fine-grained filtering, deep customization. Peek is
deliberately the opposite: no preferences, two shortcuts, one screen. If you want control,
use AltTab. If you want to stop thinking about it, use this.

## License

MIT
