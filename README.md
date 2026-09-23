# leonavas.dock

A bar widget for the Omarchy shell: it shows the programs open in the current
workspace as small icons — **always in the same order they sit on screen**,
even after you rearrange the windows. The point is not losing track of what is
going on in the workspace: glance at the bar and know what is open, where it
is, and what has focus, without cycling through windows to find out.

In a tiling layout windows move around constantly — you open, close, and swap
positions with `SUPER + SHIFT + arrows`. A dock that ignores that turns into a
shuffled list, and you end up hunting for the window. Here the icons travel
with the tiles.

## What it does

- One icon per window open on the active workspace **of the monitor the bar is
  drawn on** — on multi-monitor setups each bar shows its own windows.
- Order mirrors the layout: left to right, then top to bottom.
- The focused window stands out (a dash on the bar edge plus a fully opaque
  icon); the rest are dimmed.
- Hovering names the icon: a label floats on the free side of the bar —
  above the icons when the bar sits at the bottom.
- Disappears from the bar when the workspace is empty (can be turned off).
- Web apps (WhatsApp, Google Messages, …) get their real name and icon, not
  `Chrome-web.whatsapp.com`.

## Interactions

| Action | Result |
|---|---|
| Left click | Focus the window (with grouping on, cycles through the app's windows) |
| Middle click | Close the window |
| Right click | Close the window (can be turned off) |
| Scroll wheel | Move focus to the next or previous window in the row |

## The hover label

The name of the app under the pointer, in a bubble on the free side of the bar
— above the icons on a bottom bar, below them on a top one, beside them on a
vertical one. One bubble serves the whole row: it travels from icon to icon as
the pointer moves instead of fading out and back in between slots, and the
first one waits out ~110 ms so sweeping across the dock does not strobe a label
for every icon on the way. A grouped icon carries its window count in the name
(`Ghostty (3)`).

### What the icons are called

The name comes from the window class, which is usually enough
(`org.gnome.Nautilus` → Nautilus, `brave-browser` → Brave browser). Web apps
are the exception: Chromium names their window after the URL, so WhatsApp
opened with `omarchy-launch-webapp` arrives as
`chrome-web.whatsapp.com__-Default` — where the last dot-segment, the part a
reverse-DNS class normally hides its name in, is the browser profile.

Those are recognised and resolved through the `.desktop` file they were
launched from, matched on the URL its `Exec` line opens — the only place the
name the user gave them exists (`messages.google.com` → **Google Messages**,
not "Google"). Its icon is taken from the same entry. With no entry to be
found, the site itself names the icon: `web.whatsapp.com` → **Whatsapp**.

To fix any name by hand, use `nameOverrides`:

```json
{
  "id": "leonavas.dock",
  "nameOverrides": {
    "chrome-web.whatsapp.com__-Default": "WhatsApp"
  }
}
```

What the label says is the `hoverLabel` setting:

| Value | Label |
|---|---|
| `App name` (default) | `Brave` |
| `App name and title` | `Brave` with the window title under it, dimmed |
| `Window title` | `GitHub — leonavas/dock` (the app name, when the window has no title) |
| `Off` | No label; the shell's standard tooltip takes over, as before |

## Icon order

Three modes, in the `order` setting:

- **`Screen order`** (default) — follows the compositor's layout, left to right
  and top to bottom. Swapping two windows with `SUPER + SHIFT + arrows`, or
  dragging them, swaps the icons along with them.
- **`Open order`** — the sequence the windows were opened in, wherever they
  ended up. Each window is stamped the first time the dock sees it and never
  renumbered, so focus changes cannot reshuffle the row. On the first sweep (a
  freshly started shell, windows that already existed) the stamps go out in PID
  order, the closest available guess at "which one opened first".
- **`By application`** — alphabetical by window class. Every app keeps the same
  slot forever, but the row says nothing about the screen or about what you
  opened first.

### Why screen order polls

Hyprland **emits no IPC event when two windows swap places** — the new
positions only show up by re-reading the client list. So in that mode the
widget calls `Hyprland.refreshToplevels()` every 250 ms, and only while it is
visible and there is more than one icon to reorder. Measured cost on the
quickshell process: **~0.4% CPU** (roughly 4 ms per second); the re-read
repaints nothing when nothing moved. In the other two modes the timer never
runs.

## Settings

Set these in Setup > Plugins, or inline on the widget's entry in
`~/.config/omarchy/shell.json`:

```json
{
  "id": "leonavas.dock",
  "scope": "Current workspace",
  "order": "Screen order",
  "groupByApp": false,
  "iconSize": 18,
  "gap": 2,
  "activeIndicator": true,
  "dimInactive": true,
  "hideWhenEmpty": true,
  "rightClickCloses": true,
  "hoverLabel": "App name"
}
```

| Key | Default | What it does |
|---|---|---|
| `scope` | `Current workspace` | `Current workspace`, `Current monitor` or `All windows` |
| `order` | `Screen order` | See [Icon order](#icon-order) |
| `groupByApp` | `false` | One icon per app, with the window count in the corner |
| `iconSize` | `18` | Icon size, in px (10–32) |
| `gap` | `2` | Space between icons, in px (0–16) |
| `hoverLabel` | `App name` | What the hover label says, see [The hover label](#the-hover-label) |
| `activeIndicator` | `true` | A short line on the bar edge under the focused window |
| `dimInactive` | `true` | Dims the windows that are not focused |
| `hideWhenEmpty` | `true` | Hides the dock when there are no windows to show |
| `rightClickCloses` | `true` | Turn off to close windows with the middle button only |
| `nameOverrides` | — | Window class → name map, see [What the icons are called](#what-the-icons-are-called) |
| `iconOverrides` | — | Window class → icon map, see below |

Changes apply as soon as `shell.json` is saved, overrides included.

To find a window's class, focus it and run `hyprctl activewindow | grep class`.

### Icons for apps without a `.desktop`

Resolution is tried in this order: the `.desktop` entry for the window class,
the icon theme using the class and its segments (`org.omarchy.agent` →
`agent` → `omarchy.agent` → `omarchy`), and finally the app's initial inside a
frame. A generic theme icon is never accepted as a hit — if nothing specific
exists, the initial shows up.

To force an icon, use `iconOverrides` (a theme icon name, or an absolute path —
`~` is not expanded):

```json
{
  "id": "leonavas.dock",
  "iconOverrides": {
    "org.omarchy.agent": "omarchy",
    "my-app": "/home/you/.local/share/icons/my-app.png"
  }
}
```

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- Hyprland

No other dependency. The widget talks to Hyprland through Quickshell's built-in
Hyprland integration and reads `.desktop` entries through Quickshell; it runs
no external commands.

## Install

```bash
omarchy plugin add https://github.com/leonavas/omarchy-dock.git
omarchy plugin enable leonavas.dock --section center
```

It is meant for the center of the bar; `omarchy bar move leonavas.dock
--section left` (or `right`) puts it elsewhere.

## Update

```bash
omarchy plugin update leonavas.dock
```

The update shows the diff before applying it. Run `omarchy restart shell`
afterwards so widgets already on the bar pick up the new code.

## Remove

```bash
omarchy plugin disable leonavas.dock   # off the bar, files kept
omarchy plugin remove leonavas.dock    # deletes ~/.config/omarchy/plugins/leonavas.dock/
```

Disabling drops the widget's entry, with its settings, from
`~/.config/omarchy/shell.json`. Nothing else is left behind.

## What it writes

Nothing. The widget never writes a file: no `shell.json` changes of its own,
nothing under `~/.config/hypr/`, no cache on disk. Its settings are only
changed by you, through Setup > Plugins or by editing `shell.json`.

What it does at runtime:

- Reads the window list from Hyprland, and re-reads it every 250 ms in
  `Screen order` mode (see [Why screen order polls](#why-screen-order-polls)).
- Reads installed `.desktop` entries and the icon theme, for names and icons.
- Focuses or closes a window when you click its icon — the same requests a
  window manager keybinding would send. Closing asks the app to close; it can
  still show its own "unsaved changes" prompt.

Nothing is read from the network, and no sudo or pkexec is required.

## Troubleshooting

- **An app shows a letter instead of an icon.** It has no `.desktop` entry and
  no theme icon matching its class. Add it to `iconOverrides`.
- **An app has an odd name.** Add its window class to `nameOverrides`.
- **Icons do not follow a window swap right away.** Only `Screen order` tracks
  the layout; check the `order` setting.
- **Right click closed a window by accident.** Turn off `rightClickCloses`.
- **The dock is missing.** With `hideWhenEmpty` on, it hides on an empty
  workspace. Otherwise check it is on the bar: `omarchy plugin enable
  leonavas.dock --section center`.
- **Code changes do not show up.** Editing the QML reloads the plugin, but
  widgets already on the bar keep the old code until `omarchy restart shell`.

## Files

| File | Contents |
|---|---|
| `Dock.qml` | The widget: layout, icons, clicks, the hover label, the re-read timer |
| `Model.js` | Pure helpers: ordering, grouping, names, web app classes, icon candidates |
| `manifest.json` | Metadata, settings, and defaults read by the shell's panel |

## License

MIT — see [LICENSE](LICENSE). Comes with no warranty and no support.
