import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Dock: the applications running on the current workspace, drawn as their
// real desktop icons. Left click focuses (and cycles, when grouped), middle
// and right close, the wheel walks the row.
BarWidget {
  id: root
  moduleName: "leonavas.dock"

  // ---------------------------------------------------------------- settings
  readonly property string scope: String(setting("scope", "Current workspace"))
  readonly property bool grouped: setting("groupByApp", false) === true
  readonly property string order: String(setting("order", "Screen order"))
  readonly property bool sortByApp: root.order === "By application"
  readonly property bool sortByPosition: root.order === "Screen order"
  readonly property int iconSize: Math.max(8, Style.space(Number(setting("iconSize", 18))))
  readonly property int itemGap: Style.space(Number(setting("gap", 2)))
  readonly property bool showIndicator: setting("activeIndicator", true) !== false
  readonly property bool dimInactive: setting("dimInactive", true) !== false
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", true) !== false
  readonly property bool closeOnRight: setting("rightClickCloses", true) !== false
  readonly property var iconOverrides: setting("iconOverrides", ({}))
  readonly property var nameOverrides: setting("nameOverrides", ({}))

  // Names and icons are memoized per class, so an override edited in
  // shell.json would otherwise only show up after a shell restart.
  onNameOverridesChanged: root.nameCache = ({})
  onIconOverridesChanged: root.iconCache = ({})

  // What the hover label says. "Off" hands hovering back to the shell's own
  // tooltip, which is what the widget did before the label existed.
  readonly property string hoverLabel: String(setting("hoverLabel", "App name"))
  readonly property bool labelsEnabled: root.hoverLabel !== "Off"

  // ------------------------------------------------------------------- theme
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color activeColor: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int slot: iconSize + Style.space(8)

  // ------------------------------------------------------------------ source
  //
  // Each bar surface is per monitor, so the dock resolves the workspace of
  // the screen it is painted on rather than the globally focused one. That
  // way a second monitor's dock keeps showing that monitor's windows while
  // you work on the first.
  readonly property var barWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property var barScreen: barWindow ? barWindow.screen : null
  readonly property var hyprMonitor: barScreen ? Hyprland.monitorFor(barScreen) : null

  readonly property var targetWorkspace: {
    var monitor = root.hyprMonitor
    if (monitor && monitor.activeWorkspace) return monitor.activeWorkspace
    return Hyprland.focusedWorkspace
  }

  function collectToplevels() {
    var all = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []

    if (root.scope === "All windows") return all

    if (root.scope === "Current monitor") {
      var monitor = root.hyprMonitor
      if (!monitor) return all
      var out = []
      for (var i = 0; i < all.length; i++) {
        if (all[i] && all[i].monitor === monitor) out.push(all[i])
      }
      return out
    }

    var workspace = root.targetWorkspace
    if (!workspace || !workspace.toplevels) return []
    return workspace.toplevels.values || []
  }

  // Order the icons were first seen in. Hyprland reorders its own window list
  // as windows are focused or moved, so the dock stamps each window once and
  // sorts on that instead; otherwise the icons swap places on every focus
  // change. Mutated in place, like iconCache, so it never re-fires the binding.
  property var openOrder: ({ seq: ({}), next: 0 })

  function orderedToplevels() {
    var visible = root.collectToplevels()
    if (root.sortByPosition) return Model.sortByPosition(visible)
    var all = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []
    return Model.sortByOpenOrder(visible, all, root.openOrder)
  }

  // Hyprland emits no event when two tiles are swapped (SUPER + SHIFT + arrow)
  // or dragged into a new slot: the window list only reports the new positions
  // once it is re-read. Poll while there is more than one icon to reorder; the
  // reread is a no-op for the bindings whenever nothing actually moved.
  Timer {
    running: root.sortByPosition && root.visible && root.entryCount > 1
    interval: 250
    repeat: true
    onTriggered: Hyprland.refreshToplevels()
  }

  readonly property var entries: root.named(Model.buildEntries(root.orderedToplevels(), root.grouped, root.sortByApp))
  readonly property int entryCount: entries.length

  // buildEntries() only knows the window class, so it names each row from the
  // class alone. The rows are freshly built objects; stamping the resolved
  // name over that guess in place keeps the naming out of the pure helpers,
  // which cannot reach DesktopEntries.
  function named(rows) {
    for (var i = 0; i < rows.length; i++) rows[i].name = root.nameFor(rows[i].appId)
    return rows
  }

  // ------------------------------------------------------------------- names
  //
  // A window class is not a name, and for a web app it is barely even a hint:
  // Chromium calls the WhatsApp window "chrome-web.whatsapp.com__-Default",
  // whose last dot-segment - the part a reverse-DNS class hides its name in -
  // is the profile. So a web app is resolved through the .desktop entry it was
  // launched from, which is the only place its real name exists, and falls
  // back to the site it opens. Everything else keeps the plain class guess.
  property var nameCache: ({})

  function nameFor(appId) {
    var key = String(appId || "")
    if (key.length === 0) return "?"

    var cached = root.nameCache[key]
    if (cached !== undefined) return cached

    var resolved = root.resolveName(key)
    root.nameCache[key] = resolved
    return resolved
  }

  function resolveName(appId) {
    var override = root.nameOverrides ? root.nameOverrides[appId] : undefined
    if (override === undefined && root.nameOverrides) override = root.nameOverrides[appId.toLowerCase()]
    if (override !== undefined && String(override).length > 0) return String(override)

    var entry = root.webAppEntry(appId)
    if (entry && entry.name) return Model.capitalize(String(entry.name))

    var target = Model.webAppTarget(appId)
    if (target && target.host.length > 0) return Model.prettyHost(target.host)

    return Model.prettyName(appId)
  }

  // The .desktop entry behind a web app window, or null for anything that is
  // not one. An installed PWA files its entry under the window class itself;
  // a plain shortcut (`omarchy-launch-webapp`, a browser's "create shortcut")
  // does not, and is matched on the URL its Exec line opens instead - by host
  // equality, so a "google.com" shortcut cannot answer with Google Maps.
  //
  // Cached per class, misses included: the fallback name is a decent one, and
  // the sweep would otherwise run on every re-read of the window list.
  property var webEntryCache: ({})

  function webAppEntry(appId) {
    var key = String(appId || "")
    if (key.length === 0) return null

    var cached = root.webEntryCache[key]
    if (cached !== undefined) return cached

    var target = Model.webAppTarget(key)
    var entry = target ? root.findWebAppEntry(target, key) : null
    root.webEntryCache[key] = entry
    return entry
  }

  function findWebAppEntry(target, appId) {
    var direct = null
    try {
      direct = DesktopEntries.byId(appId)
    } catch (idError) {
      direct = null
    }
    if (direct && direct.name) return direct

    var model = DesktopEntries.applications
    var list = model ? (model.values || []) : []

    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (!entry || !entry.name) continue

      var exec = String(entry.execString || "")
      if (exec.length === 0) continue

      if (target.host.length > 0) {
        if (Model.execHost(exec) === target.host) return entry
      } else if (exec.indexOf(target.token) >= 0) {
        return entry
      }
    }

    return null
  }

  // ------------------------------------------------------------------- icons
  //
  // Resolution is per app id and never changes for the life of the process,
  // so results are memoized. Only hits are cached: a miss on an app whose
  // .desktop file lands after the shell started should resolve on a later
  // pass rather than stay a letter forever.
  property var iconCache: ({})

  function iconFor(appId) {
    var key = String(appId || "")
    if (key.length === 0) return ""

    var cached = root.iconCache[key]
    if (cached !== undefined && cached.length > 0) return cached

    var resolved = root.resolveIcon(key)
    if (resolved.length > 0) root.iconCache[key] = resolved
    return resolved
  }

  // Qt resolves a missing icon to the generic executable glyph instead of
  // failing, and so does appLibrary. Comparing against it is the only way to
  // tell a real hit from a miss, and a miss has to keep looking.
  readonly property string genericIcon: Quickshell.iconPath("application-x-executable", true)

  function themedIcon(name) {
    var value = String(name || "")
    if (value.length === 0) return ""
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var path = Quickshell.iconPath(value, true)
    if (path.length === 0 || path === root.genericIcon) return ""
    return path
  }

  // appLibrary's index also covers icons installed after the shell started,
  // which a plain themed lookup misses; fall back to the themed one when it
  // has nothing better.
  function libraryIcon(name) {
    var library = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    if (!library) return root.themedIcon(name)
    var source = String(library.iconSource(name))
    if (source.length === 0 || source === root.genericIcon) return root.themedIcon(name)
    return source
  }

  function entryIcon(name) {
    var entry = null
    try {
      entry = DesktopEntries.heuristicLookup(name)
    } catch (lookupError) {
      entry = null
    }
    if (!entry || !entry.icon) return ""
    return root.libraryIcon(String(entry.icon))
  }

  function resolveIcon(appId) {
    var override = root.iconOverrides ? root.iconOverrides[appId] : undefined
    if (override === undefined && root.iconOverrides) override = root.iconOverrides[appId.toLowerCase()]
    if (override !== undefined && String(override).length > 0) {
      var forced = root.themedIcon(String(override))
      if (forced.length > 0) return forced
    }

    // A web app's icon lives in the same entry its name does. Without it the
    // candidate list falls back to the middle of the hostname, which finds
    // the wrong brand as easily as the right one: messages.google.com would
    // come up wearing Google's icon.
    var web = root.webAppEntry(appId)
    if (web && web.icon) {
      var webIcon = root.libraryIcon(String(web.icon))
      if (webIcon.length > 0) return webIcon
    }

    var candidates = Model.iconCandidates(appId)
    if (candidates.length === 0) return ""

    // The full window class is what heuristicLookup is built for, so its
    // answer is the trustworthy one. Shortened candidates go through it only
    // after the themed lookups, where a loose match cannot outrank a real one.
    var exact = root.entryIcon(candidates[0])
    if (exact.length > 0) return exact

    for (var i = 0; i < candidates.length; i++) {
      var themed = root.themedIcon(candidates[i])
      if (themed.length > 0) return themed
    }

    for (var j = 1; j < candidates.length; j++) {
      var loose = root.entryIcon(candidates[j])
      if (loose.length > 0) return loose
    }

    return ""
  }

  // ------------------------------------------------------------------ actions
  function focusRow(row) {
    var index = Model.nextWindowIndex(row)
    if (index < 0) return
    var toplevel = row.windows[index]
    if (toplevel && toplevel.wayland) toplevel.wayland.activate()
  }

  function closeRow(row) {
    if (!row || row.windows.length === 0) return
    // Close the focused window of a group, or the only one there is.
    var index = 0
    for (var i = 0; i < row.windows.length; i++) {
      if (Model.isActive(row.windows[i])) { index = i; break }
    }
    var toplevel = row.windows[index]
    if (toplevel && toplevel.wayland) toplevel.wayland.close()
  }

  function step(delta) {
    var rows = root.entries
    if (rows.length === 0) return

    var current = -1
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].active) { current = i; break }
    }

    var next = current < 0 ? (delta > 0 ? 0 : rows.length - 1)
                           : (current + (delta > 0 ? 1 : -1) + rows.length) % rows.length
    var target = rows[next].windows[0]
    if (target && target.wayland) target.wayland.activate()
  }

  // -------------------------------------------------------------------- label
  //
  // The name of the app under the pointer, floating on the free side of the
  // bar - above the icons when the bar sits at the bottom, the way a dock
  // names what it is pointing at. One popup serves the whole row: it follows
  // the pointer from icon to icon instead of one bubble per slot.
  property Item labelTarget: null
  property Item pendingLabel: null
  property string labelPrimary: ""
  property string labelSecondary: ""

  // Long window titles would otherwise stretch the bubble across the screen.
  readonly property int labelMaxWidth: {
    var screen = root.barScreen
    var limit = screen && screen.width > 0 ? Math.round(screen.width * 0.4) : Style.space(320)
    return Math.max(Style.space(120), Math.min(limit, Style.space(420)))
  }

  function applyLabelText(item) {
    if (!item) return
    var name = item.labelName
    var title = item.labelTitle

    if (root.hoverLabel === "Window title") {
      root.labelPrimary = title.length > 0 ? title : name
      root.labelSecondary = ""
    } else if (root.hoverLabel === "App name and title") {
      root.labelPrimary = name
      root.labelSecondary = title
    } else {
      root.labelPrimary = name
      root.labelSecondary = ""
    }
  }

  // Sweeping the pointer across the row would otherwise flash a label for
  // every icon on the way, so the first one waits out a short delay. Once one
  // is up the rest are instant: at that point the label is what the eye is
  // already following.
  function requestLabel(item) {
    if (!root.labelsEnabled || !item) return
    root.pendingLabel = item
    if (root.labelTarget !== null) root.commitLabel()
    else labelTimer.restart()
  }

  function commitLabel() {
    labelTimer.stop()
    var item = root.pendingLabel
    if (!item) return
    root.applyLabelText(item)
    root.labelTarget = item
  }

  // A null item clears whatever is showing; anything else only clears its own
  // label, so a stale leave event cannot take down the next icon's.
  function dismissLabel(item) {
    if (item && root.pendingLabel !== item && root.labelTarget !== item) return
    labelTimer.stop()
    root.pendingLabel = null
    root.labelTarget = null
  }

  Timer {
    id: labelTimer
    interval: 110
    onTriggered: root.commitLabel()
  }

  // Titles change under the pointer - a browser tab switch, a file saved - and
  // the label is a snapshot, so it has to be refreshed while it is up. The
  // snapshot is what keeps the bubble from collapsing mid fade-out, once the
  // target is gone.
  Connections {
    target: root.labelTarget
    ignoreUnknownSignals: true
    function onLabelNameChanged() { root.applyLabelText(root.labelTarget) }
    function onLabelTitleChanged() { root.applyLabelText(root.labelTarget) }
  }

  onVisibleChanged: if (!visible) root.dismissLabel(null)
  onLabelsEnabledChanged: if (!root.labelsEnabled) root.dismissLabel(null)

  PopupWindow {
    id: labelPopup

    readonly property bool open: root.labelsEnabled && root.labelTarget !== null && root.labelPrimary.length > 0

    visible: open || bubble.opacity > 0
    color: "transparent"
    implicitWidth: Math.ceil(bubble.implicitWidth)
    implicitHeight: Math.ceil(bubble.implicitHeight)

    // One popup shared by every icon: the anchor is recomputed whenever the
    // pointer moves to another slot, and again once the new text has settled
    // into a different size.
    onOpenChanged: if (open) labelAnchor.updateAnchor()
    onImplicitWidthChanged: if (open) labelAnchor.updateAnchor()
    onImplicitHeightChanged: if (open) labelAnchor.updateAnchor()

    Connections {
      target: root
      function onLabelTargetChanged() { if (labelPopup.open) labelAnchor.updateAnchor() }
    }

    anchor {
      id: labelAnchor
      window: root.barWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var target = root.labelTarget
        var window = root.barWindow
        if (!target || !window) return

        var popupWidth = labelPopup.implicitWidth
        var popupHeight = labelPopup.implicitHeight
        var gap = Style.space(6)
        var position = root.bar ? String(root.bar.position) : "top"

        var localX = target.width / 2 - popupWidth / 2
        var localY = target.height + gap

        if (position === "bottom") {
          localY = -popupHeight - gap
        } else if (position === "left") {
          localX = target.width + gap
          localY = target.height / 2 - popupHeight / 2
        } else if (position === "right") {
          localX = -popupWidth - gap
          localY = target.height / 2 - popupHeight / 2
        }

        var point = window.contentItem.mapFromItem(target, localX, localY)

        // Keep the bubble on screen: the icons at either end of the row would
        // otherwise hang half of it off the edge.
        if (position === "top" || position === "bottom") {
          point.x = Math.max(gap, Math.min(point.x, window.width - popupWidth - gap))
        } else {
          point.y = Math.max(gap, Math.min(point.y, window.height - popupHeight - gap))
        }

        labelAnchor.rect.x = Math.round(point.x)
        labelAnchor.rect.y = Math.round(point.y)
      }
    }

    BorderSurface {
      id: bubble
      implicitWidth: labelColumn.implicitWidth + Style.space(20)
      implicitHeight: labelColumn.implicitHeight + Style.space(12)
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(4)
      opacity: labelPopup.open ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }

      Column {
        id: labelColumn
        anchors.centerIn: parent
        spacing: Style.space(1)

        Text {
          width: Math.min(implicitWidth, root.labelMaxWidth)
          text: root.labelPrimary
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          renderType: Text.NativeRendering
        }

        Text {
          visible: text.length > 0
          width: Math.min(implicitWidth, root.labelMaxWidth)
          text: root.labelSecondary
          color: Color.tooltip.text
          opacity: 0.65
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          renderType: Text.NativeRendering
        }
      }
    }
  }

  // ------------------------------------------------------------------- layout
  visible: !root.hideWhenEmpty || root.entryCount > 0
  implicitWidth: root.vertical ? root.barSize : (root.entryCount > 0 ? grid.implicitWidth : 0)
  implicitHeight: root.vertical ? (root.entryCount > 0 ? grid.implicitHeight : 0) : root.barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }
  Behavior on implicitHeight {
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  GridLayout {
    id: grid
    anchors.centerIn: parent
    columns: root.vertical ? 1 : Math.max(1, root.entryCount)
    columnSpacing: root.vertical ? 0 : root.itemGap
    rowSpacing: root.vertical ? root.itemGap : 0

    Repeater {
      model: root.entries

      DockItem { }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function (wheel) { root.step(wheel.angleDelta.y) }
  }

  // -------------------------------------------------------------------- item
  component DockItem: Item {
    id: item

    required property var modelData

    readonly property string appId: modelData.appId
    readonly property string label: modelData.name
    readonly property bool active: modelData.active
    readonly property int windowCount: modelData.count
    readonly property string iconSource: root.iconFor(appId)
    readonly property bool hasIcon: iconSource.length > 0 && iconImage.status !== Image.Error

    // The app, as the label says it: a grouped icon carries its window count
    // along with the name.
    readonly property string labelName: item.windowCount > 1
      ? item.label + " (" + item.windowCount + ")" : item.label

    // Blank when the window has nothing to add to the name, so the label does
    // not print "Alacritty / Alacritty".
    readonly property string labelTitle: {
      var title = String(modelData.title || "")
      return title.length > 0 && title !== item.label ? title : ""
    }

    readonly property string tooltip: item.labelTitle.length > 0
      ? item.labelName + " — " + item.labelTitle : item.labelName

    implicitWidth: root.vertical ? root.barSize : root.slot
    implicitHeight: root.vertical ? root.slot : root.barSize

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(4)
      color: root.foreground
      opacity: itemMouse.containsMouse ? Style.hoverFillAlpha
             : (item.active ? Style.selectedFillAlpha : 0)

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }

    Item {
      id: iconSlot
      anchors.centerIn: parent
      width: root.iconSize
      height: root.iconSize
      opacity: item.active || !root.dimInactive ? 1 : 0.55

      Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      Image {
        id: iconImage
        anchors.fill: parent
        visible: item.hasIcon
        fillMode: Image.PreserveAspectFit
        // Decode at physical pixels: the logical size leaves PNG icons
        // upscaled and blurry on HiDPI displays.
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        source: item.iconSource
        asynchronous: true
        smooth: true
      }

      // Nothing in the icon theme matched the window class: draw its initial
      // rather than a generic cog, so the slot still says which app it is.
      Rectangle {
        anchors.fill: parent
        visible: !item.hasIcon
        radius: Style.space(3)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)

        Text {
          anchors.centerIn: parent
          text: item.label.charAt(0).toUpperCase()
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Math.round(root.iconSize * 0.6))
          renderType: Text.NativeRendering
        }
      }
    }

    // Window count for a grouped app, tucked into the corner of the slot.
    Text {
      visible: item.windowCount > 1
      anchors.right: iconSlot.right
      anchors.bottom: iconSlot.bottom
      anchors.rightMargin: -Style.space(2)
      anchors.bottomMargin: -Style.space(3)
      text: String(item.windowCount)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    // Focus marker, on the edge the bar sits against.
    Rectangle {
      visible: root.showIndicator && item.active
      width: root.vertical ? Style.space(2) : Math.round(root.iconSize * 0.6)
      height: root.vertical ? Math.round(root.iconSize * 0.6) : Style.space(2)
      radius: height / 2
      color: root.activeColor
      anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
      anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
      anchors.bottom: root.vertical ? undefined : parent.bottom
      anchors.left: root.vertical ? parent.left : undefined
      anchors.bottomMargin: Style.space(2)
      anchors.leftMargin: Style.space(1)
    }

    MouseArea {
      id: itemMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

      onClicked: function (mouse) {
        if (root.bar) root.bar.hideTooltip(item)
        if (mouse.button === Qt.MiddleButton || (mouse.button === Qt.RightButton && root.closeOnRight)) {
          root.closeRow(item.modelData)
        } else if (mouse.button === Qt.LeftButton) {
          root.focusRow(item.modelData)
        }
      }

      onWheel: function (wheel) { root.step(wheel.angleDelta.y) }

      // The label and the shell tooltip say the same thing, so only one of
      // them ever runs. Clicking leaves the label up: the pointer is still on
      // the icon, and a dock that blanks its own label on click just blinks.
      onEntered: {
        if (root.labelsEnabled) root.requestLabel(item)
        else if (root.bar) root.bar.showTooltip(item, item.tooltip)
      }

      onExited: {
        root.dismissLabel(item)
        if (root.bar) root.bar.hideTooltip(item)
      }
    }

    // `root` is already gone when the whole widget is torn down, so the
    // guard has to cover it and not just the bar. Closing the hovered window
    // comes through here too: no leave event ever arrives for an icon that is
    // destroyed under the pointer.
    Component.onDestruction: {
      if (!root) return
      root.dismissLabel(item)
      if (root.bar) root.bar.hideTooltip(item)
    }
  }
}
