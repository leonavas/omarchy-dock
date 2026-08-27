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

## Interactions

| Action | Result |
|---|---|
| Left click | Focus the window (with grouping on, cycles through the app's windows) |
| Middle click | Close the window |
| Right click | Close the window (can be turned off) |
| Scroll wheel | Walk through the workspace's windows |

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

## Configuration

Through the shell's plugin panel, or directly in `~/.config/omarchy/shell.json`:

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

| Setting | Default | What it does |
|---|---|---|
| `scope` | `Current workspace` | `Current workspace`, `Current monitor` or `All windows` |
| `order` | `Screen order` | See [Icon order](#icon-order) |
| `groupByApp` | `false` | One icon per app, with the window count in the corner |
| `iconSize` | `18` | Icon size, in px (10–32) |
| `gap` | `2` | Space between icons, in px |
| `activeIndicator` | `true` | Dash on the bar edge under the focused window |
| `dimInactive` | `true` | Dims the windows that are not focused |
| `hideWhenEmpty` | `true` | Disappears from the bar when there are no windows |
| `rightClickCloses` | `true` | Turn off to leave closing on the middle button only |
| `hoverLabel` | `App name` | What the hover label says, see [The hover label](#the-hover-label) |
| `nameOverrides` | — | Window class → name map, see [What the icons are called](#what-the-icons-are-called) |
| `iconOverrides` | — | Window class → icon map, see below |

The widget goes into the bar through the `center` section of `shell.json` (it
is this configuration's `centerAnchor`), or with `omarchy bar move
leonavas.dock --section center`.

### Icons for apps without a `.desktop`

Resolution is tried in this order: the `.desktop` entry for the window class,
the icon theme using the class and its segments (`org.omarchy.agent` →
`agent` → `omarchy.agent` → `omarchy`), and finally the app's initial inside a
frame. A generic theme icon is never accepted as a hit — if nothing specific
exists, the initial shows up.

To force an icon, use `iconOverrides` (a theme name, or an absolute path —
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

## Files

| File | Contents |
|---|---|
| `Dock.qml` | The widget: layout, icons, clicks, the hover label, the re-read timer |
| `Model.js` | Pure helpers: ordering, grouping, names, web app classes, icon candidates |
| `manifest.json` | Metadata, settings, and defaults read by the shell's panel |

## Notes

- `shell.json` reloads on save: setting changes apply immediately.
- Editing the QML reloads the plugin code, but widgets already mounted on the
  bar keep the previous version — run `omarchy restart shell` to see the
  changes.

## License

MIT — see [`LICENSE`](LICENSE). Do whatever you want with it; it comes with no
warranty and no support.
