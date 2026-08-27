.pragma library

// Pure helpers for the dock widget. Kept out of the QML so the widget body
// stays layout code; every function here only reads properties off the
// Hyprland toplevel objects, which keeps QML binding capture working.

function appIdOf(toplevel) {
  if (!toplevel) return ""
  var wayland = toplevel.wayland
  if (wayland && wayland.appId) return String(wayland.appId)
  var ipc = toplevel.lastIpcObject
  if (ipc) {
    if (ipc["class"]) return String(ipc["class"])
    if (ipc["initialClass"]) return String(ipc["initialClass"])
  }
  return ""
}

function titleOf(toplevel) {
  if (!toplevel) return ""
  var title = String(toplevel.title || "")
  if (title.length > 0) return title
  var wayland = toplevel.wayland
  return wayland ? String(wayland.title || "") : ""
}

// Read both the Hyprland flag and the Wayland one: the IPC flag is the
// authoritative one, but reading both also registers both as binding
// dependencies, so focus changes repaint whichever side reports first.
function isActive(toplevel) {
  if (!toplevel) return false
  var hypr = toplevel.activated === true
  var wayland = toplevel.wayland
  var waylandActive = !!(wayland && wayland.activated)
  return hypr || waylandActive
}

function trim(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "")
}

// "org.gnome.Nautilus" -> "Nautilus", "brave-browser" -> "Brave browser".
function prettyName(appId) {
  var value = trim(appId)
  if (value.length === 0) return "?"
  var parts = value.split(".")
  if (parts.length > 2) value = parts[parts.length - 1]
  value = value.replace(/[-_]+/g, " ")
  return value.charAt(0).toUpperCase() + value.slice(1)
}

// Icon names to try, best guess first. Window classes rarely match the icon
// name exactly: reverse-DNS ids hide the real name in a middle or trailing
// segment, and vendor classes like "brave-browser" ship their icon under the
// bare vendor name.
function iconCandidates(appId) {
  var value = trim(appId)
  if (value.length === 0) return []

  var out = [value, value.toLowerCase()]
  var parts = value.toLowerCase().split(".")
  if (parts.length > 1) {
    out.push(parts[parts.length - 1])
    out.push(parts.slice(1).join("."))
    if (parts.length > 2) out.push(parts[parts.length - 2])
  }
  var dashed = value.toLowerCase().split("-")
  if (dashed.length > 1) out.push(dashed[0])

  var seen = ({})
  var unique = []
  for (var i = 0; i < out.length; i++) {
    var candidate = out[i]
    if (candidate.length === 0 || seen[candidate]) continue
    seen[candidate] = true
    unique.push(candidate)
  }
  return unique
}

// Key a window is remembered by. Hyprland addresses are unique and stable for
// the life of the window; anything without one stays unstamped.
function addressOf(toplevel) {
  if (!toplevel) return ""
  return String(toplevel.address || "")
}

// Process that owns the window, straight off the IPC payload. Only used to
// break ties on the first pass, so a window without one sorts as pid 0.
function pidOf(toplevel) {
  if (!toplevel) return 0
  var ipc = toplevel.lastIpcObject
  var pid = ipc ? Number(ipc["pid"]) : NaN
  return isNaN(pid) ? 0 : pid
}

// Where the window sits, in Hyprland's global layout coordinates. Only the
// clients payload carries it, so a window Hyprland has not described yet has
// no position.
function positionOf(toplevel) {
  var ipc = toplevel ? toplevel.lastIpcObject : null
  var at = ipc ? ipc["at"] : null
  if (!at || at.length < 2) return null
  return { x: Number(at[0]), y: Number(at[1]) }
}

// Reading order across the layout: left to right, then top to bottom. This is
// the order that follows the tiles, so swapping two windows with the keyboard
// swaps their icons too. Windows without a reported position keep the order
// they arrived in.
function sortByPosition(toplevels) {
  var rows = []
  var list = toplevels || []

  for (var i = 0; i < list.length; i++) {
    if (!list[i]) continue
    rows.push({ toplevel: list[i], at: positionOf(list[i]), index: i })
  }

  rows.sort(function (left, right) {
    if (!left.at || !right.at) return left.index - right.index
    if (left.at.x !== right.at.x) return left.at.x - right.at.x
    if (left.at.y !== right.at.y) return left.at.y - right.at.y
    return left.index - right.index
  })

  var out = []
  for (var j = 0; j < rows.length; j++) out.push(rows[j].toplevel)
  return out
}

// Stable open order. The compositor reshuffles its own window list as windows
// are focused or moved between workspaces, so sorting on the order it reports
// makes the icons jump around. The widget owns `registry`; this stamps each
// window with a sequence the first time it is seen and never renumbers it.
// `all` is every window Hyprland knows, so a window leaving the dock's scope
// (another workspace, another monitor) keeps its place when it comes back.
function sortByOpenOrder(visible, all, registry) {
  var live = ({})
  var everything = all || []

  var fresh = []
  for (var i = 0; i < everything.length; i++) {
    var key = addressOf(everything[i])
    if (key.length === 0) continue
    live[key] = true
    if (registry.seq[key] === undefined) {
      fresh.push({ key: key, pid: pidOf(everything[i]), at: i })
    }
  }

  // Windows seen for the first time are stamped oldest process first. It only
  // matters on the shell's very first pass, where the compositor's list order
  // says nothing about when each window was opened and the pid is the closest
  // stand-in for it; after that there is normally one new window per pass.
  fresh.sort(function (left, right) {
    if (left.pid !== right.pid) return left.pid - right.pid
    return left.at - right.at
  })
  for (var f = 0; f < fresh.length; f++) {
    registry.seq[fresh[f].key] = registry.next
    registry.next += 1
  }

  // Forget windows that have closed, so a long session does not accumulate a
  // stamp for every window it ever saw.
  for (var stamped in registry.seq) {
    if (!live[stamped]) delete registry.seq[stamped]
  }

  var rows = []
  var list = visible || []
  for (var j = 0; j < list.length; j++) {
    if (!list[j]) continue
    var seq = registry.seq[addressOf(list[j])]
    rows.push({ toplevel: list[j], seq: seq === undefined ? Number.MAX_VALUE : seq, at: j })
  }

  rows.sort(function (left, right) {
    if (left.seq !== right.seq) return left.seq - right.seq
    return left.at - right.at
  })

  var out = []
  for (var k = 0; k < rows.length; k++) out.push(rows[k].toplevel)
  return out
}

// Collapses the toplevel list into the rows the dock paints. Grouped mode
// keys by app id so ten terminals become one icon with a count; ungrouped
// mode keys by window address so each window keeps its own slot.
function buildEntries(toplevels, grouped, sortByApp) {
  var rows = []
  var index = ({})
  var list = toplevels || []

  for (var i = 0; i < list.length; i++) {
    var toplevel = list[i]
    if (!toplevel) continue

    var appId = appIdOf(toplevel)
    var title = titleOf(toplevel)
    var active = isActive(toplevel)
    var address = addressOf(toplevel)
    var key = grouped ? appId.toLowerCase() : (address.length > 0 ? address : appId + "#" + i)

    var row = index[key]
    if (!row) {
      row = {
        key: key,
        appId: appId,
        name: prettyName(appId),
        title: title,
        active: false,
        count: 0,
        windows: [],
        order: rows.length
      }
      index[key] = row
      rows.push(row)
    }

    row.windows.push(toplevel)
    row.count += 1
    // The focused window owns the row's title, so a grouped icon tooltips
    // the window you are actually looking at.
    if (active || row.count === 1) row.title = title
    if (active) row.active = true
  }

  if (sortByApp) {
    rows.sort(function (left, right) {
      var a = left.appId.toLowerCase()
      var b = right.appId.toLowerCase()
      if (a < b) return -1
      if (a > b) return 1
      return left.order - right.order
    })
  }

  return rows
}

// Index of the window a click should focus next: the one after the currently
// focused window, so repeated clicks cycle a grouped app's windows.
function nextWindowIndex(row) {
  if (!row || row.windows.length === 0) return -1
  if (row.windows.length === 1) return 0
  for (var i = 0; i < row.windows.length; i++) {
    if (isActive(row.windows[i])) return (i + 1) % row.windows.length
  }
  return 0
}
