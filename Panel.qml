import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "maftuuh.boxtop"
  ipcTarget: "maftuuh.boxtop"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var stats: null
  property var cpuHistory: []
  property var ramHistory: []
  property bool showSettings: false
  readonly property int historyLen: 120

  // ── Settings (stored on this widget's entry in ~/.config/omarchy/shell.json) ──
  readonly property var presetNames: ["theme", "btop", "catppuccin", "nord", "mono"]
  readonly property var graphStyles: ["dots", "bars", "line"]
  readonly property var boxNames: ["cpu", "mem", "net", "proc"]

  function opt(key, def) {
    var v = root.settings ? root.settings[key] : undefined
    return (v === undefined || v === null || v === "") ? def : v
  }
  function clampNum(v, lo, hi, def) {
    var n = Number(v)
    if (!isFinite(n)) return def
    return Math.max(lo, Math.min(hi, Math.round(n)))
  }

  readonly property string preset: presetNames.indexOf(String(opt("preset", "btop"))) >= 0 ? String(opt("preset", "btop")) : "btop"
  readonly property string graphStyle: graphStyles.indexOf(String(opt("graph", "dots"))) >= 0 ? String(opt("graph", "dots")) : "dots"
  readonly property bool compact: opt("compact", false) === true
  readonly property bool rounded: opt("rounded", true) !== false
  readonly property int lineWidth: clampNum(opt("lineWidth", 1), 1, 3, 1)
  readonly property int interval: clampNum(opt("interval", 2), 1, 10, 2)
  readonly property int procCount: clampNum(opt("procCount", 8), 3, 15, 8)
  readonly property bool fade: opt("fade", true) !== false
  readonly property bool shadow: opt("shadow", false) === true
  readonly property bool stroke: opt("stroke", true) !== false
  readonly property var boxes: {
    var b = opt("boxes", null)
    if (!b || !b.length) return boxNames
    var out = []
    for (var i = 0; i < b.length; i++) if (boxNames.indexOf(String(b[i])) >= 0) out.push(String(b[i]))
    return out.length ? out : boxNames
  }
  function showBox(name) { return root.boxes.indexOf(name) >= 0 }

  function setSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleBox(name) {
    var cur = root.boxes.slice()
    var i = cur.indexOf(name)
    if (i >= 0) {
      if (cur.length === 1) return
      cur.splice(i, 1)
    } else {
      cur.push(name)
      cur.sort(function(a, b) { return root.boxNames.indexOf(a) - root.boxNames.indexOf(b) })
    }
    setSetting("boxes", cur)
  }

  // ── Theme colours (read from the active Omarchy theme for the "theme" preset) ──
  property var themeColors: ({})

  FileView {
    id: themeFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var out = {}
      var lines = String(text() || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
        if (m) out[m[1]] = m[2]
      }
      root.themeColors = out
    }
  }

  Connections {
    target: Color
    function onAccentChanged() { themeFile.reload() }
  }

  function tc(name, fallback) {
    var v = root.themeColors[name]
    return v ? v : fallback
  }

  readonly property var pal: {
    var acc = Color.accent
    if (preset === "theme") {
      var t = {
        green: tc("green", "#a6e3a1"), yellow: tc("yellow", "#f9e2af"), red: tc("red", String(Color.urgent)),
        blue: tc("blue", String(acc)), magenta: tc("magenta", "#cba6f7"), cyan: tc("cyan", "#94e2d5"),
        orange: tc("orange", tc("bright_red", "#fab387"))
      }
      return {
        cpu: String(acc), mem: t.green, net: t.red, proc: t.blue,
        core: [t.cyan, t.blue, t.magenta], graph: [t.green, t.yellow, t.red],
        used: [t.green, t.cyan, t.blue], cached: [t.blue, t.cyan, t.magenta],
        swap: [t.magenta, t.blue, t.cyan], disk: [t.yellow, t.orange, t.red],
        down: t.orange, up: t.green
      }
    }
    if (preset === "catppuccin") return {
      cpu: "#cba6f7", mem: "#a6e3a1", net: "#f38ba8", proc: "#89b4fa",
      core: ["#94e2d5", "#89b4fa", "#cba6f7"], graph: ["#a6e3a1", "#f9e2af", "#f38ba8"],
      used: ["#a6e3a1", "#94e2d5", "#89b4fa"], cached: ["#89b4fa", "#94e2d5", "#cba6f7"],
      swap: ["#f5c2e7", "#cba6f7", "#89b4fa"], disk: ["#f9e2af", "#fab387", "#f38ba8"],
      down: "#fab387", up: "#a6e3a1"
    }
    if (preset === "nord") return {
      cpu: "#b48ead", mem: "#a3be8c", net: "#bf616a", proc: "#88c0d0",
      core: ["#8fbcbb", "#88c0d0", "#b48ead"], graph: ["#a3be8c", "#ebcb8b", "#bf616a"],
      used: ["#a3be8c", "#8fbcbb", "#88c0d0"], cached: ["#88c0d0", "#81a1c1", "#b48ead"],
      swap: ["#b48ead", "#81a1c1", "#88c0d0"], disk: ["#ebcb8b", "#d08770", "#bf616a"],
      down: "#d08770", up: "#a3be8c"
    }
    if (preset === "mono") {
      // Monochrome follows the text colour so it stays readable on any theme.
      acc = root.fg
      var g = [Util.alpha(acc, 0.4), Util.alpha(acc, 0.7), acc]
      return {
        cpu: acc, mem: acc, net: acc, proc: acc,
        core: g, graph: g, used: g, cached: g, swap: g, disk: g,
        down: acc, up: acc
      }
    }
    // btop (gruvbox material, matches btop's default-ish look)
    return {
      cpu: "#d3869b", mem: "#a9b665", net: "#ea6962", proc: "#7daea3",
      core: ["#89b482", "#7daea3", "#d3869b"], graph: ["#89b482", "#d8a657", "#ea6962"],
      used: ["#a9b665", "#89b482", "#7daea3"], cached: ["#7daea3", "#89b482", "#d3869b"],
      swap: ["#d3869b", "#7daea3", "#89b482"], disk: ["#d8a657", "#e78a4e", "#ea6962"],
      down: "#d8a657", up: "#a9b665"
    }
  }

  readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color divLineColor: Util.alpha(root.fg, 0.22)
  readonly property int fsSmall: compact ? 9 : 10
  readonly property int fsTiny: compact ? 8 : 9

  onPalChanged: repaintGraphs()
  onGraphStyleChanged: repaintGraphs()

  function repaintGraphs() {
    cpuGraph.requestPaint()
    memGraph.requestPaint()
  }

  Component.onCompleted: {
    var init = []
    for (var i = 0; i < root.historyLen; i++) init.push(0.02)
    root.cpuHistory = init
    root.ramHistory = init.slice()
  }

  function refresh() {
    if (!proc.running) proc.running = true
  }

  Process {
    id: proc
    command: ["python3", String(Qt.resolvedUrl("boxtop.py")).replace(/^file:\/\//, ""), String(root.procCount)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStats(text)
    }
  }

  Timer {
    interval: root.interval * 1000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  function push(list, v) {
    var n = list.slice(); n.push(v)
    while (n.length > root.historyLen) n.shift()
    return n
  }

  function applyStats(raw) {
    var d
    try { d = JSON.parse(String(raw || "").trim()) } catch (e) { return }
    stats = d
    cpuHistory = push(cpuHistory, d.cpu / 100)
    ramHistory = push(ramHistory, d.ram_pct / 100)
    repaintGraphs()
  }

  function fmtG(v) { return (Math.round(v * 10) / 10).toFixed(1) }

  // ── btop box frame: rounded/sharp corners, tab title, notches, divider ──
  component BtopBox: Item {
    id: boxRoot
    width: bodyCol.width - 16
    property color boxColor: root.pal.cpu
    property color divColor: root.divLineColor
    property string tag: ""
    property string rightText: ""
    property real divY: 0
    property string divLabel: ""
    property string footLeft: ""
    property string footRight: ""
    default property alias content: innerContent.data

    onBoxColorChanged: frameCanvas.requestPaint()
    onRightTextChanged: frameCanvas.requestPaint()
    onFootLeftChanged: frameCanvas.requestPaint()
    onFootRightChanged: frameCanvas.requestPaint()
    onDivYChanged: frameCanvas.requestPaint()
    onTagChanged: frameCanvas.requestPaint()

    Connections {
      target: root
      function onRoundedChanged() { frameCanvas.requestPaint() }
      function onLineWidthChanged() { frameCanvas.requestPaint() }
      function onStrokeChanged() { frameCanvas.requestPaint() }
      function onFgChanged() { frameCanvas.requestPaint() }
    }

    Canvas {
      id: frameCanvas
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        var lw = root.lineWidth
        var off = (lw % 2) ? 0.5 : 0
        var w = width
        var h = height
        var r = root.rounded ? 5 : 0
        var topY = 7 + off
        var botY = Math.floor(h - 8) + off
        var leftX = lw / 2
        var rightX = w - lw / 2

        ctx.lineWidth = lw
        ctx.strokeStyle = boxRoot.boxColor

        function corner(x1, y1, x2, y2) {
          if (r > 0) ctx.arcTo(x1, y1, x2, y2, r)
          else ctx.lineTo(x1, y1)
        }

        if (!root.stroke) {
          var fr = root.rounded ? 6 : 0
          var fy = 0
          var fh = h - 6
          ctx.beginPath()
          ctx.moveTo(fr, fy)
          ctx.lineTo(w - fr, fy)
          if (fr) ctx.arcTo(w, fy, w, fy + fr, fr)
          ctx.lineTo(w, fy + fh - fr)
          if (fr) ctx.arcTo(w, fy + fh, w - fr, fy + fh, fr)
          ctx.lineTo(fr, fy + fh)
          if (fr) ctx.arcTo(0, fy + fh, 0, fy + fh - fr, fr)
          ctx.lineTo(0, fy + fr)
          if (fr) ctx.arcTo(0, fy, fr, fy, fr)
          ctx.closePath()
          ctx.fillStyle = Util.alpha(root.fg, 0.06)
          ctx.fill()

          if (boxRoot.divY > 0) {
            ctx.beginPath()
            ctx.lineWidth = 1
            ctx.strokeStyle = Util.alpha(root.fg, 0.12)
            ctx.moveTo(8, boxRoot.divY + 0.5)
            ctx.lineTo(w - 8, boxRoot.divY + 0.5)
            ctx.stroke()
          }
          return
        }

        ctx.beginPath()
        ctx.moveTo(leftX, topY + r)
        corner(leftX, topY, leftX + r, topY)

        var tagW = boxRoot.tag.length * (root.fsSmall * 0.72) + 8
        var tagX = 10
        ctx.lineTo(tagX, topY)
        ctx.lineTo(tagX, topY + 4)
        ctx.moveTo(tagX + tagW, topY + 4)
        ctx.lineTo(tagX + tagW, topY)

        if (boxRoot.rightText.length > 0) {
          var rtW = boxRoot.rightText.length * (root.fsTiny * 0.69) + 8
          var rtX = rightX - rtW - 10
          ctx.lineTo(rtX, topY)
          ctx.lineTo(rtX, topY + 4)
          ctx.moveTo(rtX + rtW, topY + 4)
          ctx.lineTo(rtX + rtW, topY)
        }

        ctx.lineTo(rightX - r, topY)
        corner(rightX, topY, rightX, topY + r)
        ctx.lineTo(rightX, botY - r)
        corner(rightX, botY, rightX - r, botY)

        if (boxRoot.footRight.length > 0) {
          var frW = boxRoot.footRight.length * (root.fsTiny * 0.69) + 8
          var frX = rightX - frW - 10
          ctx.lineTo(frX + frW, botY)
          ctx.moveTo(frX, botY)
        }
        if (boxRoot.footLeft.length > 0) {
          var flW = boxRoot.footLeft.length * (root.fsTiny * 0.69) + 8
          var flX = 12
          ctx.lineTo(flX + flW, botY)
          ctx.moveTo(flX, botY)
        }

        ctx.lineTo(leftX + r, botY)
        corner(leftX, botY, leftX, botY - r)
        ctx.lineTo(leftX, topY + r)
        ctx.stroke()

        if (boxRoot.divY > 0) {
          ctx.beginPath()
          ctx.lineWidth = 1
          ctx.strokeStyle = boxRoot.divColor
          ctx.moveTo(leftX, boxRoot.divY + 0.5)
          if (boxRoot.divLabel.length > 0) {
            var dlW = boxRoot.divLabel.length * (root.fsTiny * 0.72) + 8
            var dlX = 14
            ctx.lineTo(dlX, boxRoot.divY + 0.5)
            ctx.moveTo(dlX + dlW, boxRoot.divY + 0.5)
          }
          ctx.lineTo(rightX, boxRoot.divY + 0.5)
          ctx.stroke()
        }
      }
    }

    Text {
      text: boxRoot.tag
      x: 12; y: 0
      color: boxRoot.boxColor
      font.family: Style.font.family
      font.pixelSize: root.fsSmall
      font.bold: true
    }
    Text {
      text: boxRoot.rightText
      anchors.right: parent.right
      anchors.rightMargin: 14
      y: 1
      color: root.fg
      opacity: 0.8
      font.family: Style.font.family
      font.pixelSize: root.fsTiny
    }
    Text {
      visible: boxRoot.divY > 0 && boxRoot.divLabel.length > 0
      text: boxRoot.divLabel
      x: 16
      y: boxRoot.divY - 6
      color: root.fg
      opacity: 0.5
      font.family: Style.font.family
      font.pixelSize: root.fsTiny
    }
    Text {
      visible: boxRoot.footLeft.length > 0
      text: boxRoot.footLeft
      x: 14
      y: parent.height - 14
      color: root.fg
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: root.fsTiny
    }
    Text {
      visible: boxRoot.footRight.length > 0
      text: boxRoot.footRight
      anchors.right: parent.right
      anchors.rightMargin: 14
      y: parent.height - 14
      color: root.fg
      opacity: 0.5
      font.family: Style.font.family
      font.pixelSize: root.fsTiny
    }

    Item {
      id: innerContent
      anchors.fill: parent
      anchors.topMargin: 15
      anchors.bottomMargin: (boxRoot.footLeft.length > 0 || boxRoot.footRight.length > 0) ? 15 : 6
      anchors.leftMargin: 8
      anchors.rightMargin: 8
    }
  }

  // ── Gradient meter ──
  component GradBar: Rectangle {
    id: gb
    property real pct: 0
    property var stops: ["#89b482", "#7daea3", "#d3869b"]
    height: root.compact ? 6 : 8
    radius: root.rounded ? 2 : 0
    color: Util.alpha(root.fg, 0.08)
    clip: true

    Item {
      width: gb.width * Math.max(0, Math.min(1, gb.pct))
      height: gb.height
      clip: true
      Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

      Rectangle {
        width: gb.width
        height: gb.height
        radius: gb.radius
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: gb.stops[0] }
          GradientStop { position: 0.5; color: gb.stops[1] }
          GradientStop { position: 1.0; color: gb.stops[2] }
        }
      }
    }
  }

  component MiniBarRow: Row {
    id: mbr
    property string label: ""
    property string value: ""
    property real pct: 0
    property var stops: root.pal.used
    width: parent.width
    height: root.compact ? 12 : 14
    spacing: 6
    Text {
      text: mbr.label
      color: root.fg; opacity: 0.6
      font.family: Style.font.family; font.pixelSize: root.fsSmall
      width: 46
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: mbr.value
      color: root.fg
      font.family: Style.font.family; font.pixelSize: root.fsSmall
      width: 66
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
    }
    GradBar {
      width: mbr.width - 46 - 66 - 32 - 18
      pct: mbr.pct
      stops: mbr.stops
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: Math.round(mbr.pct * 100) + "%"
      color: root.fg; opacity: 0.6
      font.family: Style.font.family; font.pixelSize: root.fsSmall
      width: 32
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // ── Settings UI ──
  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool active: false
    signal activated()
    width: chipText.implicitWidth + 12
    height: 17
    radius: root.rounded ? 3 : 0
    color: chip.active ? Util.alpha(root.pal.proc, 0.22) : (chipMouse.containsMouse ? Util.alpha(root.fg, 0.12) : Util.alpha(root.fg, 0.06))
    border.width: 1
    border.color: chip.active ? root.pal.proc : "transparent"

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: root.fg
      opacity: chip.active ? 1.0 : 0.65
      font.family: Style.font.family
      font.pixelSize: 9
      font.bold: chip.active
    }
    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.activated()
    }
  }

  component OptRow: Item {
    id: optRow
    property string label: ""
    default property alias chips: chipFlow.data
    width: parent.width
    height: Math.max(17, chipFlow.implicitHeight)
    Text {
      text: optRow.label
      width: 52
      height: 17
      verticalAlignment: Text.AlignVCenter
      color: root.fg
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: 9
    }
    Flow {
      id: chipFlow
      x: 56
      width: optRow.width - 56
      spacing: 4
    }
  }

  IpcHandler {
    target: "maftuuh.boxtop"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function preset(name: string): void { if (root.presetNames.indexOf(name) >= 0) root.setSetting("preset", name) }
    function graph(name: string): void { if (root.graphStyles.indexOf(name) >= 0) root.setSetting("graph", name) }
    // Generic setter: value is parsed as JSON when possible, e.g. set shadow true
    function set(key: string, value: string): void {
      var v = value
      try { v = JSON.parse(value) } catch (e) {}
      root.setSetting(key, v)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    slotSize: Style.bar.iconSlot
    tooltipText: "Boxtop"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    borderSpec: Border.none()
    contentWidth: panel.fittedContentWidth(Style.space(root.compact ? 320 : 370))
    contentHeight: panel.fittedContentHeight(bodyCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.showSettings) root.showSettings = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: bodyCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: bodyCol
          width: parent.width
          spacing: root.compact ? 6 : 8
          topPadding: 4
          bottomPadding: 6
          leftPadding: 8
          rightPadding: 8

          layer.enabled: root.shadow
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.85
            shadowBlur: 0.45
            shadowHorizontalOffset: 1.5
            shadowVerticalOffset: 2
          }

          // ── Header: name + settings toggle ──
          Item {
            width: bodyCol.width - 16
            height: 16

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: 2
              text: "boxtop"
              color: root.fg
              opacity: 0.35
              font.family: Style.font.family
              font.pixelSize: 9
              font.bold: true
            }

            Text {
              id: gear
              anchors.right: parent.right
              anchors.rightMargin: 2
              anchors.verticalCenter: parent.verticalCenter
              text: root.showSettings ? "\uf00d" : "\uf013"
              color: gearMouse.containsMouse || root.showSettings ? root.pal.proc : root.fg
              opacity: gearMouse.containsMouse || root.showSettings ? 1.0 : 0.55
              font.family: Style.font.family
              font.pixelSize: 12

              MouseArea {
                id: gearMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showSettings = !root.showSettings
              }
            }
          }

          // ═══════════════ SETTINGS ═══════════════
          BtopBox {
            id: settingsBox
            visible: root.showSettings
            height: setCol.implicitHeight + 24
            boxColor: Util.alpha(root.fg, 0.55)
            tag: "settings"

            Column {
              id: setCol
              width: parent.width
              spacing: 5

              OptRow {
                label: "preset"
                Repeater {
                  model: root.presetNames
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.preset === modelData
                    onActivated: root.setSetting("preset", modelData)
                  }
                }
              }
              OptRow {
                label: "graph"
                Repeater {
                  model: root.graphStyles
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.graphStyle === modelData
                    onActivated: root.setSetting("graph", modelData)
                  }
                }
              }
              OptRow {
                label: "boxes"
                Repeater {
                  model: root.boxNames
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.showBox(modelData)
                    onActivated: root.toggleBox(modelData)
                  }
                }
              }
              OptRow {
                label: "size"
                Chip { label: "normal"; active: !root.compact; onActivated: root.setSetting("compact", false) }
                Chip { label: "compact"; active: root.compact; onActivated: root.setSetting("compact", true) }
              }
              OptRow {
                label: "corners"
                Chip { label: "rounded"; active: root.rounded; onActivated: root.setSetting("rounded", true) }
                Chip { label: "sharp"; active: !root.rounded; onActivated: root.setSetting("rounded", false) }
              }
              OptRow {
                label: "stroke"
                Chip { label: "stroke"; active: root.stroke; onActivated: root.setSetting("stroke", true) }
                Chip { label: "no stroke"; active: !root.stroke; onActivated: root.setSetting("stroke", false) }
              }
              OptRow {
                label: "fade"
                Chip { label: "on"; active: root.fade; onActivated: root.setSetting("fade", true) }
                Chip { label: "off"; active: !root.fade; onActivated: root.setSetting("fade", false) }
              }
              OptRow {
                label: "shadow"
                Chip { label: "shadow"; active: root.shadow; onActivated: root.setSetting("shadow", true) }
                Chip { label: "no shadow"; active: !root.shadow; onActivated: root.setSetting("shadow", false) }
              }
              OptRow {
                label: "line"
                Repeater {
                  model: [1, 2, 3]
                  Chip {
                    required property int modelData
                    label: modelData + "px"
                    active: root.lineWidth === modelData
                    onActivated: root.setSetting("lineWidth", modelData)
                  }
                }
              }
              OptRow {
                label: "refresh"
                Repeater {
                  model: [1, 2, 3, 5]
                  Chip {
                    required property int modelData
                    label: modelData + "s"
                    active: root.interval === modelData
                    onActivated: root.setSetting("interval", modelData)
                  }
                }
              }
              OptRow {
                label: "procs"
                Repeater {
                  model: [5, 8, 10, 12]
                  Chip {
                    required property int modelData
                    label: String(modelData)
                    active: root.procCount === modelData
                    onActivated: root.setSetting("procCount", modelData)
                  }
                }
              }
            }
          }

          // ═══════════════ CPU BOX ═══════════════
          BtopBox {
            id: cpuBoxItem
            visible: root.showBox("cpu")
            readonly property int nCores: root.stats ? root.stats.cores.length : 2
            readonly property int rowH: root.compact ? 12 : 14
            readonly property int coresH: nCores * rowH + (nCores - 1) * 2
            readonly property int graphH: root.compact ? 34 : 54
            height: 15 + coresH + 14 + graphH + 4 + 15
            boxColor: root.pal.cpu
            tag: "¹cpu"
            rightText: (root.stats && root.stats.cpu_model ? root.stats.cpu_model + "  " : "") + (root.stats && root.stats.freq ? ((root.stats.freq / 1000).toFixed(2) + " GHz") : "")
            divY: 15 + coresH + 7
            divLabel: "total ▲"
            footLeft: root.stats ? ("up " + root.stats.uptime) : ""
            footRight: root.stats ? ("load " + root.stats.load + " " + root.stats.load5 + " " + root.stats.load15) : ""

            Column {
              width: parent.width
              spacing: 2

              Repeater {
                model: root.stats ? root.stats.cores.length : 0
                Row {
                  id: coreRow
                  required property int index
                  width: parent.width
                  height: cpuBoxItem.rowH
                  spacing: 6
                  Text {
                    text: "C" + coreRow.index
                    color: root.fg; opacity: 0.6
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                    width: 20
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  GradBar {
                    width: coreRow.width - 20 - 34 - 32 - 18
                    pct: root.stats.cores[coreRow.index] / 100
                    stops: root.pal.core
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: root.stats.cores[coreRow.index] + "%"
                    color: root.fg
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: root.stats.temp !== null ? (root.stats.temp + "°") : ""
                    color: root.fg; opacity: 0.45
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                    width: 32
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }

            Canvas {
              id: cpuGraph
              y: cpuBoxItem.coresH + 14
              width: parent.width
              height: cpuBoxItem.graphH
              onHeightChanged: requestPaint()
              onWidthChanged: requestPaint()
              onPaint: root.paintGraph(this, root.cpuHistory)
            }
          }

          // ═══════════════ MEM BOX ═══════════════
          BtopBox {
            id: memBoxItem
            visible: root.showBox("mem")
            readonly property int graphH: root.compact ? 24 : 36
            readonly property int rowH: root.compact ? 12 : 14
            height: 15 + graphH + 13 + 4 * rowH + 3 * 3 + 11
            boxColor: root.pal.mem
            tag: "²mem"
            rightText: root.stats ? (root.fmtG(root.stats.ram_used) + " / " + root.fmtG(root.stats.ram_total) + "G") : ""
            divY: 15 + graphH + 5
            divLabel: "breakdown"

            Canvas {
              id: memGraph
              width: parent.width
              height: memBoxItem.graphH
              onHeightChanged: requestPaint()
              onWidthChanged: requestPaint()
              onPaint: root.paintGraph(this, root.ramHistory)
            }

            Column {
              y: memBoxItem.graphH + 13
              width: parent.width
              spacing: 3

              MiniBarRow {
                label: "Used"
                value: root.stats ? (root.fmtG(root.stats.ram_used) + "G") : ""
                pct: root.stats ? root.stats.ram_pct / 100 : 0
                stops: root.pal.used
              }
              MiniBarRow {
                label: "Cached"
                value: root.stats ? (root.fmtG(root.stats.cached) + "G") : ""
                pct: root.stats && root.stats.ram_total > 0 ? root.stats.cached / root.stats.ram_total : 0
                stops: root.pal.cached
              }
              MiniBarRow {
                label: "Swap"
                value: root.stats ? (root.fmtG(root.stats.swap_used) + "G") : ""
                pct: root.stats ? root.stats.swap_pct / 100 : 0
                stops: root.pal.swap
              }
              MiniBarRow {
                label: "Disk /"
                value: root.stats ? (root.stats.disk_used + "G") : ""
                pct: root.stats ? root.stats.disk_pct / 100 : 0
                stops: root.pal.disk
              }
            }
          }

          // ═══════════════ NET BOX ═══════════════
          BtopBox {
            id: netBoxItem
            visible: root.showBox("net")
            height: root.compact ? 42 : 48
            boxColor: root.pal.net
            tag: "³net"

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 18

              Row {
                spacing: 5
                Text { text: "▼"; color: root.pal.down; font.pixelSize: root.fsTiny; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  text: root.stats ? root.stats.net_rx : "…"
                  color: root.fg; opacity: 0.85
                  font.family: Style.font.family; font.pixelSize: root.fsSmall
                }
              }
              Row {
                spacing: 5
                Text { text: "▲"; color: root.pal.up; font.pixelSize: root.fsTiny; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  text: root.stats ? root.stats.net_tx : "…"
                  color: root.fg; opacity: 0.85
                  font.family: Style.font.family; font.pixelSize: root.fsSmall
                }
              }
            }
          }

          // ═══════════════ PROC BOX ═══════════════
          BtopBox {
            id: procBoxItem
            visible: root.showBox("proc")
            readonly property int rowH: root.compact ? 12 : 14
            readonly property int rows: root.stats ? Math.min(root.procCount, root.stats.procs.length) : root.procCount
            height: 15 + 20 + rows * rowH + (rows - 1) * 2 + 10
            boxColor: root.pal.proc
            tag: "⁴proc"
            rightText: rows + " tasks"
            divY: 31

            Row {
              width: parent.width
              spacing: 4
              Text { text: "PID"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: root.fsTiny; width: 46 }
              Text { text: "PROGRAM"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: root.fsTiny; width: parent.width - 46 - 50 - 40 - 12 }
              Text { text: "MEM"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: root.fsTiny; width: 50; horizontalAlignment: Text.AlignRight }
              Text { text: "CPU%"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: root.fsTiny; width: 40; horizontalAlignment: Text.AlignRight }
            }

            Column {
              y: 20
              width: parent.width
              spacing: 2

              Repeater {
                model: procBoxItem.rows
                Row {
                  id: procRow
                  required property int index
                  readonly property var p: root.stats ? root.stats.procs[index] : null
                  width: parent.width
                  height: procBoxItem.rowH
                  opacity: root.fade && procBoxItem.rows > 1 ? 1.0 - 0.6 * (index / (procBoxItem.rows - 1)) : 1.0
                  spacing: 4
                  Text {
                    text: procRow.p ? procRow.p.pid : ""
                    color: root.fg; opacity: 0.35
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                    width: 46
                  }
                  Text {
                    text: procRow.p ? procRow.p.name : ""
                    color: root.fg; opacity: 0.85
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                    elide: Text.ElideRight
                    width: parent.width - 46 - 50 - 40 - 12
                  }
                  Text {
                    text: procRow.p ? (procRow.p.mem_mb + "M") : ""
                    color: root.fg; opacity: 0.55
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                    width: 50; horizontalAlignment: Text.AlignRight
                  }
                  Text {
                    text: procRow.p ? procRow.p.cpu_pct.toFixed(1) : ""
                    color: procRow.p && procRow.p.cpu_pct > 1 ? root.pal.proc : root.fg
                    opacity: procRow.p && procRow.p.cpu_pct > 1 ? 1.0 : 0.4
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                    width: 40; horizontalAlignment: Text.AlignRight
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // ── Graph rendering ──
  function gradColor(stops, v) {
    var t = Math.max(0, Math.min(1, v))
    var a, b, k
    if (t < 0.5) { a = Qt.lighter(stops[0], 1.0); b = Qt.lighter(stops[1], 1.0); k = t / 0.5 }
    else { a = Qt.lighter(stops[1], 1.0); b = Qt.lighter(stops[2], 1.0); k = (t - 0.5) / 0.5 }
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k,
                   a.a + (b.a - a.a) * k)
  }

  function paintGraph(canvas, history) {
    var ctx = canvas.getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    if (canvas.width <= 0 || canvas.height <= 0) return
    if (root.graphStyle === "bars") paintBars(ctx, canvas.width, canvas.height, history)
    else if (root.graphStyle === "line") paintLine(ctx, canvas.width, canvas.height, history)
    else paintDots(ctx, canvas.width, canvas.height, history)
  }

  function paintDots(ctx, w, h, history) {
    var pitch = 4.2
    var cols = Math.floor(w / pitch)
    var rows = Math.floor(h / pitch)
    if (cols <= 0 || rows <= 0) return

    ctx.fillStyle = Util.alpha(root.fg, 0.10)
    for (var gx = 0; gx < cols; gx++) {
      for (var gy = 0; gy < rows; gy++) {
        ctx.beginPath()
        ctx.arc(gx * pitch + pitch / 2, h - (gy * pitch + pitch / 2), 1.0, 0, Math.PI * 2)
        ctx.fill()
      }
    }
    if (!history || !history.length) return

    var n = history.length
    for (var i = 0; i < n; i++) {
      var c = cols - n + i
      if (c < 0) continue
      var filled = Math.max(1, Math.round(Math.max(0, Math.min(1, history[i])) * rows))
      var cx = c * pitch + pitch / 2
      for (var r = 0; r < filled; r++) {
        ctx.fillStyle = root.gradColor(root.pal.graph, r / rows)
        ctx.beginPath()
        ctx.arc(cx, h - (r * pitch + pitch / 2), 1.15, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }

  function paintBars(ctx, w, h, history) {
    var pitch = 3
    var cols = Math.floor(w / pitch)

    ctx.strokeStyle = Util.alpha(root.fg, 0.10)
    ctx.lineWidth = 1
    for (var q = 1; q < 4; q++) {
      var gy = Math.round(h * q / 4) + 0.5
      ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
    }
    if (!history || !history.length) return

    var grad = ctx.createLinearGradient(0, h, 0, 0)
    grad.addColorStop(0.0, root.pal.graph[0])
    grad.addColorStop(0.5, root.pal.graph[1])
    grad.addColorStop(1.0, root.pal.graph[2])
    ctx.fillStyle = grad

    var n = history.length
    for (var i = 0; i < n; i++) {
      var c = cols - n + i
      if (c < 0) continue
      var bh = Math.max(1, Math.round(Math.max(0, Math.min(1, history[i])) * h))
      ctx.fillRect(c * pitch, h - bh, pitch - 1, bh)
    }
  }

  function paintLine(ctx, w, h, history) {
    ctx.strokeStyle = Util.alpha(root.fg, 0.10)
    ctx.lineWidth = 1
    for (var q = 1; q < 4; q++) {
      var gy = Math.round(h * q / 4) + 0.5
      ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
    }
    if (!history || history.length < 2) return

    var n = history.length
    var step = w / (root.historyLen - 1)
    var x0 = w - (n - 1) * step
    function px(i) { return x0 + i * step }
    function py(i) { return h - 1 - Math.max(0, Math.min(1, history[i])) * (h - 2) }

    var fill = ctx.createLinearGradient(0, h, 0, 0)
    fill.addColorStop(0.0, Util.alpha(Qt.lighter(root.pal.graph[0], 1.0), 0.05))
    fill.addColorStop(1.0, Util.alpha(Qt.lighter(root.pal.graph[2], 1.0), 0.35))
    ctx.beginPath()
    ctx.moveTo(px(0), h)
    for (var i = 0; i < n; i++) ctx.lineTo(px(i), py(i))
    ctx.lineTo(px(n - 1), h)
    ctx.closePath()
    ctx.fillStyle = fill
    ctx.fill()

    var stroke = ctx.createLinearGradient(0, h, 0, 0)
    stroke.addColorStop(0.0, root.pal.graph[0])
    stroke.addColorStop(0.5, root.pal.graph[1])
    stroke.addColorStop(1.0, root.pal.graph[2])
    ctx.beginPath()
    ctx.moveTo(px(0), py(0))
    for (var j = 1; j < n; j++) ctx.lineTo(px(j), py(j))
    ctx.strokeStyle = stroke
    ctx.lineWidth = 1.5
    ctx.lineJoin = "round"
    ctx.stroke()
  }
}
