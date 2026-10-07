import QtQuick
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
  property var coreHistory: []
  property var ramHistory: []
  readonly property int historyLen: 65

  // Colors matching btop theme (current.theme / Gruvbox Material)
  readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color acc: Color.accent
  readonly property color hot: Color.urgent
  readonly property color mid: Qt.rgba(0.88, 0.69, 0.41, 1.0)
  readonly property color cpuBoxColor: "#d3869b"
  readonly property color memBoxColor: "#a9b665"
  readonly property color netBoxColor: "#ea6962"
  readonly property color procBoxColor: "#7daea3"
  readonly property color divLineColor: Util.alpha(root.fg, 0.22)

  Component.onCompleted: {
    var init = []
    for (var i = 0; i < root.historyLen; i++) init.push(0.02)
    root.cpuHistory = init
    root.coreHistory = init.slice()
    root.ramHistory = init.slice()
  }

  function refresh() {
    if (!proc.running) proc.running = true
  }

  Process {
    id: proc
    command: ["python3", String(Qt.resolvedUrl("boxtop.py")).replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStats(text)
    }
  }

  Timer {
    interval: 2000
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
    var mx = 0
    for (var i = 0; i < d.cores.length; i++) mx = Math.max(mx, d.cores[i])
    coreHistory = push(coreHistory, mx / 100)
    cpuGraph.requestPaint()
    memGraph.requestPaint()
  }

  function fmtG(v) { return (Math.round(v * 10) / 10).toFixed(1) }

  // ── Reusable compact btop box container with vector lines and tabs ──
  component BtopBox: Item {
    id: boxRoot
    width: bodyCol.width - 16
    property color boxColor: root.cpuBoxColor
    property color divColor: root.divLineColor
    property string tag: ""
    property string rightText: ""
    property real divY: 0
    property string divLabel: ""
    property string footLeft: ""
    property string footRight: ""
    default property alias content: innerContent.data

    onRightTextChanged: frameCanvas.requestPaint()
    onFootLeftChanged: frameCanvas.requestPaint()
    onFootRightChanged: frameCanvas.requestPaint()
    onDivYChanged: frameCanvas.requestPaint()

    Canvas {
      id: frameCanvas
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        var w = width
        var h = height
        var r = 5
        var topY = 7.5
        var botY = h - 7.5
        var leftX = 0.5
        var rightX = w - 0.5

        ctx.lineWidth = 1
        ctx.strokeStyle = boxRoot.boxColor

        // 1. Outer border with btop corners & notches
        ctx.beginPath()
        ctx.moveTo(leftX, topY + r)
        ctx.arcTo(leftX, topY, leftX + r, topY, r) // ╭

        // Tag tab notch ─┐ ... ┌─
        var tagW = boxRoot.tag.length * 7.2 + 8
        var tagX = 10
        ctx.lineTo(tagX, topY)
        ctx.lineTo(tagX, topY + 4)
        ctx.moveTo(tagX + tagW, topY + 4)
        ctx.lineTo(tagX + tagW, topY)

        // Subtitle notch on right
        if (boxRoot.rightText.length > 0) {
          var rtW = boxRoot.rightText.length * 6.2 + 8
          var rtX = rightX - rtW - 10
          ctx.lineTo(rtX, topY)
          ctx.lineTo(rtX, topY + 4)
          ctx.moveTo(rtX + rtW, topY + 4)
          ctx.lineTo(rtX + rtW, topY)
        }

        ctx.lineTo(rightX - r, topY)
        ctx.arcTo(rightX, topY, rightX, topY + r, r) // ╮
        ctx.lineTo(rightX, botY - r)
        ctx.arcTo(rightX, botY, rightX - r, botY, r) // ╯

        // Bottom border with footer notches
        if (boxRoot.footRight.length > 0) {
          var frW = boxRoot.footRight.length * 6.2 + 8
          var frX = rightX - frW - 10
          ctx.lineTo(frX + frW, botY)
          ctx.moveTo(frX, botY)
        }

        if (boxRoot.footLeft.length > 0) {
          var flW = boxRoot.footLeft.length * 6.2 + 8
          var flX = 12
          ctx.lineTo(flX + flW, botY)
          ctx.moveTo(flX, botY)
        }

        ctx.lineTo(leftX + r, botY)
        ctx.arcTo(leftX, botY, leftX, botY - r, r) // ╰
        ctx.lineTo(leftX, topY + r)
        ctx.stroke()

        // 2. Middle divider line ├── ... ──┤
        if (boxRoot.divY > 0) {
          ctx.beginPath()
          ctx.strokeStyle = boxRoot.divColor
          ctx.moveTo(leftX, boxRoot.divY + 0.5)
          if (boxRoot.divLabel.length > 0) {
            var dlW = boxRoot.divLabel.length * 6.5 + 8
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
      font.pixelSize: 10
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
      font.pixelSize: 9
    }

    Text {
      visible: boxRoot.divY > 0 && boxRoot.divLabel.length > 0
      text: boxRoot.divLabel
      x: 16
      y: boxRoot.divY - 6
      color: root.fg
      opacity: 0.5
      font.family: Style.font.family
      font.pixelSize: 9
    }

    Text {
      visible: boxRoot.footLeft.length > 0
      text: boxRoot.footLeft
      x: 14
      y: parent.height - 14
      color: root.fg
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: 9
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
      font.pixelSize: 9
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

  // Horizontal meter with a btop-style gradient. The gradient spans the full
  // track and is revealed up to `pct`, so colour reflects absolute level.
  component GradBar: Rectangle {
    id: gb
    property real pct: 0
    property color c0: "#89b482"
    property color c1: "#7daea3"
    property color c2: "#d3869b"
    height: 8
    radius: 2
    color: Util.alpha(root.fg, 0.08)
    clip: true

    Item {
      id: gbFill
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
          GradientStop { position: 0.0; color: gb.c0 }
          GradientStop { position: 0.5; color: gb.c1 }
          GradientStop { position: 1.0; color: gb.c2 }
        }
      }
    }
  }

  component MiniBarRow: Row {
    id: mbr
    property string label: ""
    property string value: ""
    property real pct: 0
    property color c0: "#a9b665"
    property color c1: "#89b482"
    property color c2: "#7daea3"
    width: parent.width
    height: 14
    spacing: 6
    Text {
      text: mbr.label
      color: root.fg; opacity: 0.6
      font.family: Style.font.family; font.pixelSize: 10
      width: 46
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: mbr.value
      color: root.fg
      font.family: Style.font.family; font.pixelSize: 10
      width: 74
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
    }
    GradBar {
      width: mbr.width - 46 - 74 - 32 - 18
      pct: mbr.pct
      c0: mbr.c0; c1: mbr.c1; c2: mbr.c2
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: Math.round(mbr.pct * 100) + "%"
      color: root.fg; opacity: 0.6
      font.family: Style.font.family; font.pixelSize: 10
      width: 32
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  IpcHandler {
    target: "maftuuh.boxtop"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
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
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(bodyCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
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
          spacing: 8
          topPadding: 6
          bottomPadding: 6
          leftPadding: 8
          rightPadding: 8

          // ═══════════════ CPU BOX ═══════════════
          BtopBox {
            id: cpuBoxItem
            height: 134
            boxColor: root.cpuBoxColor
            tag: "¹cpu"
            rightText: (root.stats && root.stats.cpu_model ? root.stats.cpu_model + "  " : "") + (root.stats && root.stats.freq ? ((root.stats.freq / 1000).toFixed(2) + " GHz") : "")
            divY: 52
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
                  height: 14
                  spacing: 6
                  Text {
                    text: "C" + coreRow.index
                    color: root.fg; opacity: 0.6
                    font.family: Style.font.family; font.pixelSize: 10
                    width: 20
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  GradBar {
                    width: coreRow.width - 20 - 34 - 32 - 18
                    pct: root.stats.cores[coreRow.index] / 100
                    c0: "#89b482"; c1: "#7daea3"; c2: "#d3869b"
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: root.stats.cores[coreRow.index] + "%"
                    color: root.fg
                    font.family: Style.font.family; font.pixelSize: 10
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: root.stats.temp !== null ? (root.stats.temp + "°") : ""
                    color: root.fg; opacity: 0.45
                    font.family: Style.font.family; font.pixelSize: 10
                    width: 32
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }

            Canvas {
              id: cpuGraph
              y: 44
              width: parent.width
              height: 54
              onPaint: root.paintDots(this, root.cpuHistory)
            }
          }

          // ═══════════════ MEM BOX ═══════════════
          BtopBox {
            id: memBoxItem
            height: 140
            boxColor: root.memBoxColor
            tag: "²mem"
            rightText: root.stats ? (root.fmtG(root.stats.ram_used) + " / " + root.fmtG(root.stats.ram_total) + "G") : ""
            divY: 56
            divLabel: "breakdown"

            Canvas {
              id: memGraph
              width: parent.width
              height: 36
              onPaint: root.paintDots(this, root.ramHistory)
            }

            Column {
              y: 49
              width: parent.width
              spacing: 3

              MiniBarRow {
                label: "Used"
                value: root.stats ? (root.fmtG(root.stats.ram_used) + "G") : ""
                pct: root.stats ? root.stats.ram_pct / 100 : 0
                c0: "#a9b665"; c1: "#89b482"; c2: "#7daea3"
              }
              MiniBarRow {
                label: "Cached"
                value: root.stats ? (root.fmtG(root.stats.cached) + "G") : ""
                pct: root.stats && root.stats.ram_total > 0 ? root.stats.cached / root.stats.ram_total : 0
                c0: "#7daea3"; c1: "#89b482"; c2: "#d3869b"
              }
              MiniBarRow {
                label: "Swap"
                value: root.stats ? (root.fmtG(root.stats.swap_used) + "G") : ""
                pct: root.stats ? root.stats.swap_pct / 100 : 0
                c0: "#d3869b"; c1: "#7daea3"; c2: "#89b482"
              }
              MiniBarRow {
                label: "Disk /"
                value: root.stats ? (root.stats.disk_used + "G") : ""
                pct: root.stats ? root.stats.disk_pct / 100 : 0
                c0: "#d8a657"; c1: "#e78a4e"; c2: "#ea6962"
              }
            }
          }

          // ═══════════════ NET BOX ═══════════════
          BtopBox {
            id: netBoxItem
            height: 48
            boxColor: root.netBoxColor
            tag: "³net"
            rightText: root.stats && root.stats.net_iface ? root.stats.net_iface : ""

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 18

              Row {
                spacing: 5
                Text { text: "▼"; color: "#d8a657"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  text: root.stats ? root.stats.net_rx : "…"
                  color: root.fg; opacity: 0.85
                  font.family: Style.font.family; font.pixelSize: 10
                }
              }

              Row {
                spacing: 5
                Text { text: "▲"; color: "#a9b665"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  text: root.stats ? root.stats.net_tx : "…"
                  color: root.fg; opacity: 0.85
                  font.family: Style.font.family; font.pixelSize: 10
                }
              }
            }
          }

          // ═══════════════ PROC BOX ═══════════════
          BtopBox {
            id: procBoxItem
            readonly property int rows: root.stats ? Math.min(8, root.stats.procs.length) : 8
            height: 15 + 20 + rows * 14 + (rows - 1) * 2 + 10
            boxColor: root.procBoxColor
            tag: "⁴proc"
            rightText: (root.stats ? root.stats.procs.length : 0) + " tasks"
            divY: 31

            Row {
              width: parent.width
              spacing: 4
              Text { text: "PID"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: 9; width: 46 }
              Text { text: "PROGRAM"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: 9; width: parent.width - 46 - 50 - 40 - 12 }
              Text { text: "MEM"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: 9; width: 50; horizontalAlignment: Text.AlignRight }
              Text { text: "CPU%"; color: root.fg; opacity: 0.45; font.family: Style.font.family; font.pixelSize: 9; width: 40; horizontalAlignment: Text.AlignRight }
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
                  height: 14
                  spacing: 4
                  Text {
                    text: procRow.p ? procRow.p.pid : ""
                    color: root.fg; opacity: 0.35
                    font.family: Style.font.family; font.pixelSize: 10
                    width: 46
                  }
                  Text {
                    text: procRow.p ? procRow.p.name : ""
                    color: root.fg; opacity: 0.85
                    font.family: Style.font.family; font.pixelSize: 10
                    elide: Text.ElideRight
                    width: parent.width - 46 - 50 - 40 - 12
                  }
                  Text {
                    text: procRow.p ? (procRow.p.mem_mb + "M") : ""
                    color: root.fg; opacity: 0.55
                    font.family: Style.font.family; font.pixelSize: 10
                    width: 50; horizontalAlignment: Text.AlignRight
                  }
                  Text {
                    text: procRow.p ? procRow.p.cpu_pct.toFixed(1) : ""
                    color: procRow.p && procRow.p.cpu_pct > 1 ? root.procBoxColor : root.fg
                    opacity: procRow.p && procRow.p.cpu_pct > 1 ? 1.0 : 0.4
                    font.family: Style.font.family; font.pixelSize: 10
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

  // ── btop dot matrix graph renderer ──
  function coreColor(v) {
    var t = Math.max(0, Math.min(1, v))
    var a, b, k
    if (t < 0.62) { a = acc; b = mid; k = t / 0.62 }
    else { a = mid; b = hot; k = (t - 0.62) / 0.38 }
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1.0)
  }

  function paintDots(canvas, history) {
    var ctx = canvas.getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, canvas.width, canvas.height)

    var w = canvas.width, h = canvas.height
    var pitch = 4.2
    var cols = Math.floor(w / pitch)
    var rows = Math.floor(h / pitch)
    if (cols <= 0 || rows <= 0) return

    // Faint baseline dots grid across full width
    ctx.fillStyle = Util.alpha(root.fg, 0.10)
    for (var gx = 0; gx < cols; gx++) {
      for (var gy = 0; gy < rows; gy++) {
        ctx.beginPath()
        ctx.arc(gx * pitch + pitch / 2, h - (gy * pitch + pitch / 2), 1.0, 0, Math.PI * 2)
        ctx.fill()
      }
    }

    if (!history || history.length === 0) return

    var samples = history
    var n = samples.length
    for (var i = 0; i < n; i++) {
      var c = cols - n + i
      if (c < 0) continue
      var val = Math.max(0, Math.min(1, samples[i]))
      var filled = Math.max(1, Math.round(val * rows))
      var cx = c * pitch + pitch / 2
      for (var r = 0; r < filled; r++) {
        var cy = h - (r * pitch + pitch / 2)
        ctx.fillStyle = root.coreColor(r / rows)
        ctx.beginPath()
        ctx.arc(cx, cy, 1.15, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }
}
