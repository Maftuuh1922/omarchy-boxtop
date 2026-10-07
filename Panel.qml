import QtQuick
import QtQuick.Effects
import QtQml.Models
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
  property var netHistory: []
  property var netUpHistory: []
  property real netRxRate: 0
  property real netTxRate: 0
  property real netPeak: 8192   // bytes/s, shared scale for both series
  property real prevNetRx: -1
  property real prevNetTx: -1
  property real lastNetTs: 0
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
  readonly property bool landscape: opt("layout", "portrait") === "landscape"

  // Header
  readonly property string title: String(opt("title", "BOXTOP"))
  readonly property string titleFontKey: String(opt("titleFont", "pixel"))
  readonly property int titleSize: clampNum(opt("titleSize", 30), 14, 64, 30)
  readonly property int subSize: clampNum(opt("subSize", 9), 6, 20, 9)
  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/boxtop"
  readonly property string avatarSetting: String(opt("avatar", "auto"))
  readonly property string titleAlign: ["left", "right"].indexOf(String(opt("titleAlign", "left"))) >= 0 ? String(opt("titleAlign", "left")) : "left"
  readonly property string titleFamily: {
    var k = titleFontKey.toLowerCase()
    if (k === "pixel") return pixelFont.status === FontLoader.Ready ? pixelFont.name : Style.font.family
    if (k === "bebas" || k === "bebas neue") return bebasFont.status === FontLoader.Ready ? bebasFont.name : Style.font.family
    if (k === "anton") return antonFont.status === FontLoader.Ready ? antonFont.name : Style.font.family
    if (k === "mono") return Style.font.family
    return titleFontKey // an uploaded font's family, or any installed font family
  }
  readonly property bool titleIsDisplayFont: ["pixel", "bebas", "bebas neue", "anton"].indexOf(titleFontKey.toLowerCase()) >= 0
  readonly property var builtinFonts: ["pixel", "bebas", "anton", "mono"]

  FontLoader { id: pixelFont; source: Qt.resolvedUrl("fonts/PressStart2P-Regular.ttf") }
  FontLoader { id: bebasFont; source: Qt.resolvedUrl("fonts/BebasNeue-Regular.ttf") }
  FontLoader { id: antonFont; source: Qt.resolvedUrl("fonts/Anton-Regular.ttf") }

  // Uploaded fonts live in ~/.local/share/boxtop/fonts and are loaded at start.
  property var userFontFiles: []
  property var userFontNames: []
  property string pendingFontPath: ""

  function refreshUserFonts() {
    fontLister.running = false
    fontLister.running = true
  }

  Process {
    id: fontLister
    command: ["sh", "-c", 'd="${XDG_DATA_HOME:-$HOME/.local/share}/boxtop/fonts"; [ -d "$d" ] && find "$d" -maxdepth 1 -type f \\( -iname "*.ttf" -o -iname "*.otf" \\) | sort']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(l) { return l.length > 0 })
        root.userFontFiles = lines
      }
    }
  }

  Instantiator {
    model: root.userFontFiles
    delegate: FontLoader {
      required property string modelData
      source: "file://" + modelData
      onStatusChanged: {
        if (status !== FontLoader.Ready) return
        if (root.userFontNames.indexOf(name) < 0) root.userFontNames = root.userFontNames.concat([name])
        if (root.pendingFontPath === modelData) {
          root.pendingFontPath = ""
          root.setSetting("titleFont", name)
        }
      }
    }
  }

  function pickFont() {
    if (fontPicker.running) return
    root.pickingFile = true
    root.close()
    fontPicker.running = true
  }

  Process {
    id: fontPicker
    command: ["sh", "-c",
      'f=$(omarchy-file-select --title "Choose a font (.ttf / .otf)" --extensions "ttf otf") || exit 1; ' +
      '[ -f "$f" ] || exit 1; ' +
      'd="${XDG_DATA_HOME:-$HOME/.local/share}/boxtop/fonts"; mkdir -p "$d" || exit 2; ' +
      'new="$d/$(basename -- "$f")"; [ "$f" = "$new" ] || cp -- "$f" "$new" || exit 2; ' +
      'printf %s "$new"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path.length === 0) return
        root.pendingFontPath = path
        if (root.userFontFiles.indexOf(path) < 0) root.userFontFiles = root.userFontFiles.concat([path])
      }
    }
    onExited: root.reopenAfterPick()
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string userName: Quickshell.env("USER") || "user"
  property string hostName: ""
  FileView {
    path: "/etc/hostname"
    printErrors: false
    onLoaded: root.hostName = String(text() || "").trim()
  }

  function expandPath(p) {
    p = String(p || "")
    if (p.indexOf("~/") === 0) p = root.home + p.slice(1)
    return p
  }
  // "auto" uses the last uploaded photo, then ~/.face, then the AccountsService
  // icon; "none" hides it; anything else is an image path. Existence is checked
  // with a tiny shell probe so missing candidates don't spam the log.
  property string avatarPath: ""
  readonly property string avatarSource: avatarPath ? "file://" + avatarPath : ""

  function resolveAvatar() {
    var a = root.avatarSetting
    if (a === "none" || a === "") { root.avatarPath = ""; return }
    var list = a === "auto"
      ? ['"${XDG_DATA_HOME:-$HOME/.local/share}"/boxtop/avatar-*', '"$HOME/.face"', '"$HOME/.face.icon"',
         '"/var/lib/AccountsService/icons/$USER"']
      : null
    avatarProbe.command = list
      ? ["sh", "-c", "for f in " + list.join(" ") + '; do [ -f "$f" ] && { printf %s "$f"; exit 0; }; done; exit 1']
      : ["sh", "-c", '[ -f "$1" ] && printf %s "$1"', "sh", root.expandPath(a)]
    avatarProbe.running = false
    avatarProbe.running = true
  }

  onAvatarSettingChanged: resolveAvatar()

  Process {
    id: avatarProbe
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.avatarPath = String(text || "").trim()
    }
  }

  // ── Hero banner ──
  // "none" hides it, anything else is an image path (same probe as the avatar,
  // so a hand-edited path to a missing file stays silent). The banner sits at
  // the top of the card and dissolves into the card background at its bottom.
  readonly property string heroSetting: String(opt("hero", "none"))
  readonly property string heroPos: root.normalizePos(opt("heroPos", "c"))
  readonly property string avatarPos: root.normalizePos(opt("avatarPos", "c"))
  property string heroPath: ""
  readonly property string heroSource: heroPath ? "file://" + heroPath : ""
  readonly property bool heroActive: heroPath !== ""
  // Fixed banner height: shrinking the title text keeps the image size intact.
  // (Matches the old titleSize*2.8/3.2 at the default titleSize of 30.)
  readonly property int heroHeight: compact ? 84 : 96

  function normalizePos(p) {
    p = String(p || "c")
    return ["tl", "tc", "tr", "cl", "c", "cr", "bl", "bc", "br"].indexOf(p) >= 0 ? p : "c"
  }
  function posGlyph(p) {
    var m = { tl: "↖", tc: "↑", tr: "↗", cl: "←", c: "•", cr: "→", bl: "↙", bc: "↓", br: "↘" }
    return m[p] || "•"
  }
  // Cover-fit geometry for an image of iw×ih inside cw×ch, cropped towards
  // the given anchor (like CSS object-position). Aspect comes from the
  // implicit size, which keeps the source ratio whatever sourceSize asks for.
  function coverBox(iw, ih, cw, ch, p) {
    if (!(iw > 0) || !(ih > 0) || !(cw > 0) || !(ch > 0))
      return { x: 0, y: 0, w: Math.max(cw, 0), h: Math.max(ch, 0) }
    var ar = iw / ih
    var fx = p.indexOf("l") >= 0 ? 0 : (p.indexOf("r") >= 0 ? 1 : 0.5)
    var fy = p.indexOf("t") >= 0 ? 0 : (p.indexOf("b") >= 0 ? 1 : 0.5)
    var w = Math.max(cw, ch * ar)
    var h = w / ar
    return { x: -(w - cw) * fx, y: -(h - ch) * fy, w: w, h: h }
  }

  function resolveHero() {
    var h = root.heroSetting
    if (h === "none" || h === "") { root.heroPath = ""; return }
    heroProbe.command = ["sh", "-c", '[ -f "$1" ] && printf %s "$1"', "sh", root.expandPath(h)]
    heroProbe.running = false
    heroProbe.running = true
  }

  onHeroSettingChanged: resolveHero()

  Process {
    id: heroProbe
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.heroPath = String(text || "").trim()
    }
  }

  // Pick a photo with the desktop file chooser (xdg portal via omarchy-file-select)
  // and copy it to ~/.local/share/boxtop so it survives the original moving.
  // The copy gets a timestamped name so Qt's image cache never shows a stale one.
  property bool pickingFile: false

  function reopenAfterPick() {
    if (!root.pickingFile) return
    root.pickingFile = false
    root.showSettings = true
    root.open()
  }

  function pickAvatar() {
    if (avatarPicker.running) return
    root.pickingFile = true
    root.close()  // the chooser opens as a normal window; get the overlay out of its way
    avatarPicker.running = true
  }

  Process {
    id: avatarPicker
    command: ["sh", "-c",
      'f=$(omarchy-file-select --title "Choose a profile photo" --extensions "png jpg jpeg webp gif bmp") || exit 1; ' +
      '[ -f "$f" ] || exit 1; ' +
      'd="${XDG_DATA_HOME:-$HOME/.local/share}/boxtop"; mkdir -p "$d" || exit 2; ' +
      'ext=$(printf %s "${f##*.}" | tr A-Z a-z); ' +
      'new="$d/avatar-$(date +%s).$ext"; cp -- "$f" "$new" || exit 2; ' +
      'for old in "$d"/avatar-*; do [ "$old" = "$new" ] || rm -f -- "$old"; done; ' +
      'printf %s "$new"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path.length > 0) root.setSetting("avatar", path)
      }
    }
    onExited: root.reopenAfterPick()
  }

  // Same flow as the photo picker, but for the hero banner: the chosen file
  // is copied to ~/.local/share/boxtop/hero-<ts>.<ext> and older heroes go.
  function pickHero() {
    if (heroPicker.running) return
    root.pickingFile = true
    root.close()
    heroPicker.running = true
  }

  Process {
    id: heroPicker
    command: ["sh", "-c",
      'f=$(omarchy-file-select --title "Choose a banner image" --extensions "png jpg jpeg webp gif bmp") || exit 1; ' +
      '[ -f "$f" ] || exit 1; ' +
      'd="${XDG_DATA_HOME:-$HOME/.local/share}/boxtop"; mkdir -p "$d" || exit 2; ' +
      'ext=$(printf %s "${f##*.}" | tr A-Z a-z); ' +
      'new="$d/hero-$(date +%s).$ext"; cp -- "$f" "$new" || exit 2; ' +
      'for old in "$d"/hero-*; do [ "$old" = "$new" ] || rm -f -- "$old"; done; ' +
      'printf %s "$new"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path.length > 0) root.setSetting("hero", path)
      }
    }
    onExited: root.reopenAfterPick()
  }

  readonly property var boxes: {
    var b = opt("boxes", null)
    if (!b || !b.length) return boxNames
    var out = []
    for (var i = 0; i < b.length; i++) if (boxNames.indexOf(String(b[i])) >= 0) out.push(String(b[i]))
    return out.length ? out : boxNames
  }
  function showBox(name) { return root.boxes.indexOf(name) >= 0 }

  // btop numbers its tabs by position, so the superscript follows the order
  // (and skips boxes that are switched off).
  function boxTag(key) {
    var sup = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
    var n = 0
    for (var i = 0; i < order.length; i++) {
      if (!showBox(order[i])) continue
      n++
      if (order[i] === key) return sup[Math.min(n, 9)] + key
    }
    return key
  }

  // Box order (drag a box by its title strip onto another box to swap them).
  readonly property var order: {
    var o = opt("order", null)
    var out = []
    if (o && o.length) for (var i = 0; i < o.length; i++) {
      var k = String(o[i])
      if (boxNames.indexOf(k) >= 0 && out.indexOf(k) < 0) out.push(k)
    }
    for (var j = 0; j < boxNames.length; j++) if (out.indexOf(boxNames[j]) < 0) out.push(boxNames[j])
    return out
  }
  property string dragKey: ""
  property string dragTargetKey: ""

  function swapBoxes(a, b) {
    if (!a || !b || a === b) return
    var o = root.order.slice()
    var ia = o.indexOf(a), ib = o.indexOf(b)
    if (ia < 0 || ib < 0) return
    o[ia] = b; o[ib] = a
    setSetting("order", o)
  }

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
  // Card text scale: "small"/"tiny" shrink every box label for denser cards.
  readonly property string textSize: ["normal", "small", "tiny"].indexOf(String(opt("textSize", "normal"))) >= 0 ? String(opt("textSize", "normal")) : "normal"
  readonly property int fsOff: textSize === "tiny" ? -2 : textSize === "small" ? -1 : 0
  readonly property int fsSmall: Math.max(6, (compact ? 9 : 10) + fsOff)
  readonly property int fsTiny: Math.max(6, (compact ? 8 : 9) + fsOff)

  // ── Update notice ──
  // update_check.py prints the remote manifest version only when the repo has
  // a newer release than the local one; the card then offers an in-place
  // update via `omarchy plugin update` followed by a shell restart.
  property string updateVersion: ""
  property string updateState: "" // "", "working" or "failed"
  property real lastUpdateCheck: 0

  function checkForUpdate() {
    var now = Date.now()
    if (now - root.lastUpdateCheck < 900000) return // at most every 15 min
    root.lastUpdateCheck = now
    if (updateCheck.running) return
    updateCheck.running = true
  }

  function runUpdate() {
    if (updateRunner.running) return
    root.updateState = "working"
    updateRunner.running = true
  }

  function dismissUpdate() {
    root.setSetting("updateSeen", root.updateVersion)
    root.updateVersion = ""
  }

  onOpenedChanged: {
    if (root.opened) {
      root.checkForUpdate()
    } else {
      // Closing the card commits any pending edit and folds settings away,
      // so the widget never reopens straight back into the settings box.
      if (titleInput.text !== root.title) root.setSetting("title", titleInput.text)
      if (root.showSettings) root.showSettings = false
    }
  }

  Process {
    id: updateCheck
    command: ["python3", String(Qt.resolvedUrl("update_check.py")).replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = String(text || "").trim()
        if (v.length === 0) return
        root.updateVersion = v === String(root.opt("updateSeen", "")) ? "" : v
      }
    }
  }

  Process {
    id: updateRunner
    command: ["omarchy", "plugin", "update", "maftuuh.boxtop", "--yes"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.updateVersion = ""
        root.updateState = ""
        shellRestart.running = true
      } else {
        root.updateState = "failed"
      }
    }
  }

  Process {
    id: shellRestart
    command: ["omarchy", "restart", "shell"]
  }

  onPalChanged: repaintGraphs()
  onGraphStyleChanged: repaintGraphs()
  onFgChanged: repaintGraphs()

  function repaintGraphs() {
    cpuGraph.repaintAll()
    memGraph.repaintAll()
  }

  Component.onCompleted: {
    var init = []
    for (var i = 0; i < root.historyLen; i++) init.push(0.02)
    root.cpuHistory = init
    root.ramHistory = init.slice()
    var z = []
    for (var j = 0; j < root.historyLen; j++) z.push(0)
    root.netHistory = z
    root.netUpHistory = z.slice()
    resolveAvatar()
    resolveHero()
    refreshUserFonts()
  }

  // One long-running sampler while the card is open: it streams a JSON line
  // per tick and keeps the previous sample in memory, so there is no Python
  // start-up or /proc re-scan cost per refresh, and nothing runs when closed.
  property bool samplerRestarting: false

  function refresh() { restartSampler() }

  function restartSampler() {
    if (!root.opened) return
    root.samplerRestarting = true
    samplerRestartTimer.restart()
  }

  onIntervalChanged: restartSampler()
  onProcCountChanged: restartSampler()

  Timer {
    id: samplerRestartTimer
    interval: 60
    onTriggered: root.samplerRestarting = false
  }

  Process {
    id: proc
    running: root.opened && !root.samplerRestarting
    command: ["python3", String(Qt.resolvedUrl("boxtop.py")).replace(/^file:\/\//, ""),
              "--watch", String(root.interval), String(root.procCount)]
    stdout: SplitParser {
      onRead: function(line) { root.applyStats(line) }
    }
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

    // Traffic rates from the cumulative interface counters, divided by the
    // real elapsed time so a card reopen doesn't spike the chart.
    if (typeof d.net_rx_bytes === "number") {
      var now = Date.now()
      if (root.prevNetRx >= 0 && root.lastNetTs > 0) {
        var dt = Math.max(0.2, (now - root.lastNetTs) / 1000)
        root.netRxRate = Math.max(0, (d.net_rx_bytes - root.prevNetRx) / dt)
        root.netTxRate = Math.max(0, (d.net_tx_bytes - root.prevNetTx) / dt)
        // Shared rolling peak: both series stay comparable and the scale
        // eases down instead of jumping on a single burst.
        root.netPeak = Math.max(root.netRxRate, root.netTxRate, root.netPeak * 0.94, 8192)
        netHistory = push(netHistory, Math.min(1, root.netRxRate / root.netPeak))
        netUpHistory = push(netUpHistory, Math.min(1, root.netTxRate / root.netPeak))
      }
      root.prevNetRx = d.net_rx_bytes
      root.prevNetTx = d.net_tx_bytes
      root.lastNetTs = now
    }
  }

  function fmtRate(b) {
    if (b < 1024) return Math.round(b) + "B/s"
    if (b < 1048576) return Math.round(b / 1024) + "K/s"
    if (b < 1073741824) return (b / 1048576).toFixed(1) + "M/s"
    return (b / 1073741824).toFixed(2) + "G/s"
  }

  function fmtG(v) { return (Math.round(v * 10) / 10).toFixed(1) }

  // ── btop box frame: rounded/sharp corners, tab title, notches, divider ──
  component BtopBox: Item {
    id: boxRoot
    width: bodyCol.width - 2 * bodyCol.leftPadding
    property color boxColor: root.pal.cpu
    property color divColor: root.divLineColor
    property string tag: ""
    property string rightText: ""
    property real divY: 0
    property string divLabel: ""
    property string footLeft: ""
    property string footRight: ""
    property string boxKey: ""
    property real dragDx: 0
    property real dragDy: 0
    default property alias content: innerContent.data

    readonly property bool dragging: boxKey !== "" && root.dragKey === boxKey
    z: dragging ? 10 : 0
    opacity: dragging ? 0.85 : 1.0
    transform: Translate { x: boxRoot.dragDx; y: boxRoot.dragDy }
    Behavior on x { enabled: root.dragKey === ""; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: root.dragKey === ""; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // Notch widths depend only on text length, so live values (frequency,
    // load, uptime) don't force a frame repaint every tick.
    readonly property int rtLen: rightText.length
    readonly property int flLen: footLeft.length
    readonly property int frLen: footRight.length
    onBoxColorChanged: frameCanvas.requestPaint()
    onRtLenChanged: frameCanvas.requestPaint()
    onFlLenChanged: frameCanvas.requestPaint()
    onFrLenChanged: frameCanvas.requestPaint()
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

    // Drop-target highlight
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: 6
      anchors.bottomMargin: 2
      visible: boxRoot.boxKey !== "" && root.dragTargetKey === boxRoot.boxKey
      radius: root.rounded ? 6 : 0
      color: Util.alpha(boxRoot.boxColor, 0.12)
      border.width: 1
      border.color: boxRoot.boxColor
    }

    Item {
      id: innerContent
      anchors.fill: parent
      anchors.topMargin: 15
      anchors.bottomMargin: (boxRoot.footLeft.length > 0 || boxRoot.footRight.length > 0) ? 15 : 6
      anchors.leftMargin: 8
      anchors.rightMargin: 8
    }

    // Drag handle: the title strip
    MouseArea {
      enabled: boxRoot.boxKey !== ""
      x: 0
      y: 0
      width: parent.width
      height: 15
      hoverEnabled: true
      preventStealing: true
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property point startPos: Qt.point(0, 0)

      function reset() {
        boxRoot.dragDx = 0
        boxRoot.dragDy = 0
        root.dragKey = ""
        root.dragTargetKey = ""
      }
      onPressed: function(m) {
        startPos = mapToItem(boxArea, m.x, m.y)
        root.dragKey = boxRoot.boxKey
      }
      onPositionChanged: function(m) {
        if (!pressed) return
        var p = mapToItem(boxArea, m.x, m.y)
        boxRoot.dragDx = p.x - startPos.x
        boxRoot.dragDy = p.y - startPos.y
        root.dragTargetKey = boxArea.keyAt(p.x, p.y, boxRoot.boxKey)
      }
      onReleased: {
        var target = root.dragTargetKey
        var key = boxRoot.boxKey
        reset()
        if (target) root.swapBoxes(key, target)
      }
      onCanceled: reset()
    }
  }

  // ── History graph: static grid canvas + data canvas ──
  component GraphView: Item {
    id: gv
    property var history: []
    property var history2: null
    property var stops: root.pal.graph
    function repaint() { dataCanvas.requestPaint() }
    function repaintAll() { gridCanvas.requestPaint(); dataCanvas.requestPaint() }
    onHistoryChanged: if (visible) dataCanvas.requestPaint()
    onHistory2Changed: if (visible) dataCanvas.requestPaint()
    onVisibleChanged: if (visible) repaintAll()
    onWidthChanged: repaintAll()
    onHeightChanged: repaintAll()

    Canvas {
      id: gridCanvas
      anchors.fill: parent
      onPaint: root.paintGrid(this)
    }
    Canvas {
      id: dataCanvas
      anchors.fill: parent
      onPaint: root.paintData(this, gv.history, gv.history2, gv.stops)
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
    function settings(): void { root.showSettings = !root.showSettings }
    function preset(name: string): void { if (root.presetNames.indexOf(name) >= 0) root.setSetting("preset", name) }
    function graph(name: string): void { if (root.graphStyles.indexOf(name) >= 0) root.setSetting("graph", name) }
    function pickAvatar(): void { root.pickAvatar() }
    function pickHero(): void { root.pickHero() }
    function pickFont(): void { root.pickFont() }
    // Generic setter: value is parsed as JSON when possible, e.g. set shadow true
    function set(key: string, value: string): void {
      var v = value
      try { v = JSON.parse(value) } catch (e) {
        // qs ipc splits commas, so lists can be written as a/b/c
        if (value.indexOf("/") > 0 && value.indexOf("~") !== 0) v = value.split("/").filter(function(x) { return x.length })
      }
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
    contentWidth: panel.fittedContentWidth(Style.space(root.landscape ? (root.compact ? 620 : 720) : (root.compact ? 320 : 370)))
    // The Flickable reaches one padding above contentHolder, so the card only
    // needs to cover implicitHeight minus that overlap plus its own insets.
    contentHeight: panel.fittedContentHeight(bodyCol.implicitHeight - panel.padding)

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
        // Full-bleed: reach past the card padding so the hero banner can
        // span the whole card edge to edge.
        anchors.leftMargin: -panel.padding
        anchors.rightMargin: -panel.padding
        anchors.topMargin: -panel.padding
        anchors.bottomMargin: -panel.padding
        contentWidth: width
        contentHeight: bodyCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: bodyCol
          width: parent.width
          spacing: root.compact ? 6 : 8
          topPadding: root.heroActive ? 0 : 4 + panel.padding
          bottomPadding: 6
          leftPadding: 8 + panel.padding
          rightPadding: 8 + panel.padding

          layer.enabled: root.shadow
          layer.smooth: true
          layer.textureSize: Qt.size(Math.ceil(bodyCol.width * 2), Math.ceil(bodyCol.height * 2))
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.85
            shadowBlur: 0.45
            shadowHorizontalOffset: 1.5
            shadowVerticalOffset: 2
          }

          // ── Hero banner: cover-cropped image that dissolves into the card ──
          // Rendered through a layer so the mask rounds its corners and the
          // fade overlay gets clipped with it.
          Item {
            id: heroSection
            // Full-bleed to the card edges when a banner is set; otherwise it
            // is just a wrapper that keeps the header at the usual inset.
            x: root.heroActive ? 0 : bodyCol.leftPadding
            width: root.heroActive ? bodyCol.width : bodyCol.width - 2 * bodyCol.leftPadding
            height: root.heroActive ? root.heroHeight : header.height

            Item {
              id: heroContent
              visible: root.heroActive
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: heroMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }

              Item {
                id: heroClip
                anchors.fill: parent
                clip: true

                // Grayscale base: what shows through as the colour copy masks
                // away toward the bottom, so the banner loses saturation
                // before it dissolves into the card.
                Item {
                  id: heroGray
                  anchors.fill: parent
                  layer.enabled: true
                  layer.smooth: true
                  layer.effect: MultiEffect {
                    saturation: -1.0
                  }

                  Image {
                    source: root.heroSource
                    sourceSize.width: 1600
                    asynchronous: true
                    cache: true
                    readonly property var cov: root.coverBox(
                      implicitWidth, implicitHeight, heroClip.width, heroClip.height, root.heroPos)
                    width: cov.w
                    height: cov.h
                    x: cov.x
                    y: cov.y
                  }
                }

                // Colour copy on top, handed over to the grey base toward the
                // bottom via satMask (alpha ramp: white → transparent).
                Item {
                  id: heroColor
                  anchors.fill: parent
                  layer.enabled: true
                  layer.smooth: true
                  layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: satMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                  }

                  Image {
                    source: root.heroSource
                    sourceSize.width: 1600
                    asynchronous: true
                    cache: true
                    readonly property var cov: root.coverBox(
                      implicitWidth, implicitHeight, heroClip.width, heroClip.height, root.heroPos)
                    width: cov.w
                    height: cov.h
                    x: cov.x
                    y: cov.y
                  }
                }
              }

              // Dissolve into the card so the banner reads as part of it.
              // Full-height ramp: the header sits on the deep end of the fade,
              // which also keeps bright uploads from clashing with a dark card.
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                gradient: Gradient {
                  GradientStop { position: 0.0; color: "transparent" }
                  GradientStop { position: 0.38; color: Util.alpha(Color.popups.background, 0.45) }
                  GradientStop { position: 0.72; color: Util.alpha(Color.popups.background, 0.9) }
                  GradientStop { position: 1.0; color: Util.alpha(Color.popups.background, 1.0) }
                }
              }
            }

            Rectangle {
              id: heroMask
              anchors.fill: parent
              radius: Style.cornerRadius
              visible: false
              layer.enabled: true
            }

            // Saturation ramp for the colour copy: opaque at the top, gone at
            // the bottom, so the banner desaturates as it meets the card.
            Rectangle {
              id: satMask
              anchors.fill: parent
              visible: false
              layer.enabled: true
              gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 0.35; color: "#ffffff" }
                GradientStop { position: 0.95; color: "transparent" }
              }
            }

            // ── Header: avatar, title, subtitle, settings toggle ──
            // titleAlign: left (avatar left) or right (mirrored).
            Item {
              id: header
              x: root.heroActive ? bodyCol.leftPadding : 0
              y: root.heroActive ? heroSection.height - height - 6 : 0
              width: bodyCol.width - 2 * bodyCol.leftPadding
              readonly property bool hasAvatar: avatarImg.status === Image.Ready
              readonly property real avatarSize: 38 // fixed: the photo keeps its size when the title shrinks
              readonly property real gearSpace: gear.width + 10
              height: Math.max(hasAvatar ? avatarSize : 0, titleCol.implicitHeight) + 4

              Item {
                id: avatarBox
                visible: header.hasAvatar
                width: header.avatarSize
                height: width
                x: root.titleAlign === "right" ? header.width - header.gearSpace - width : 0
                y: (header.height - height) / 2

                Item {
                  id: avatarLayer
                  anchors.fill: parent
                  layer.enabled: true
                  layer.smooth: true
                  layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: avatarMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                  }

                  Item {
                    id: avatarClip
                    anchors.fill: parent
                    clip: true

                    Image {
                      id: avatarImg
                      source: root.avatarSource
                      sourceSize.width: 128
                      sourceSize.height: 128
                      asynchronous: true
                      cache: true
                      readonly property var cov: root.coverBox(
                        implicitWidth, implicitHeight, avatarClip.width, avatarClip.height, root.avatarPos)
                      width: cov.w
                      height: cov.h
                      x: cov.x
                      y: cov.y
                    }
                  }
                }
                Rectangle {
                  id: avatarMask
                  anchors.fill: parent
                  radius: width / 2
                  visible: false
                  layer.enabled: true
                }
                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: "transparent"
                  border.width: 1.5
                  border.color: root.pal.cpu
                }
              }

              Column {
                id: titleCol
                spacing: -1
                readonly property int hAlign: root.titleAlign === "right" ? Text.AlignRight : Text.AlignLeft
                x: root.titleAlign === "right" ? 2
                   : (header.hasAvatar ? avatarBox.width + 10 : 2)
                width: root.titleAlign === "right"
                     ? (header.hasAvatar ? avatarBox.x - 10 : header.width - header.gearSpace) - x
                     : header.width - header.gearSpace - x
                y: (header.height - implicitHeight) / 2

                Text {
                  width: parent.width
                  horizontalAlignment: titleCol.hAlign
                  text: root.title
                  elide: Text.ElideRight
                  color: root.fg
                  font.family: root.titleFamily
                  font.pixelSize: root.titleSize
                  font.bold: !root.titleIsDisplayFont
                  font.letterSpacing: root.titleIsDisplayFont ? 1 : 0
                  lineHeight: 0.9
                }
                Text {
                  width: parent.width
                  horizontalAlignment: titleCol.hAlign
                  text: root.userName + (root.hostName ? "@" + root.hostName : "") + (root.stats ? "  ·  up " + root.stats.uptime : "")
                  elide: Text.ElideRight
                  color: root.fg
                  opacity: 0.5
                  font.family: Style.font.family
                  font.pixelSize: root.subSize
                }
              }

              Text {
                id: gear
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.top: parent.top
                anchors.topMargin: 2
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

          }

          // ── Update notice: a slim banner offering the latest release ──
          Item {
            id: updateRow
            visible: root.updateVersion !== ""
            width: bodyCol.width - 2 * bodyCol.leftPadding
            height: visible ? 24 : 0

            Rectangle {
              anchors.fill: parent
              radius: root.rounded ? 6 : 0
              color: Util.alpha(root.pal.up, 0.12)
              border.width: 1
              border.color: Util.alpha(root.pal.up, 0.5)
            }
            Text {
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              text: root.updateState === "working" ? "updating to v" + root.updateVersion + "…"
                  : root.updateState === "failed" ? "update failed · check network"
                  : "⬆ boxtop v" + root.updateVersion + " available"
              color: root.pal.up
              font.family: Style.font.family
              font.pixelSize: root.fsSmall
            }
            Flow {
              anchors.right: parent.right
              anchors.rightMargin: 4
              anchors.verticalCenter: parent.verticalCenter
              spacing: 4
              Chip {
                label: root.updateState === "working" ? "working…" : "update"
                active: true
                onActivated: root.runUpdate()
              }
              Chip {
                label: "later"
                active: false
                onActivated: root.dismissUpdate()
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
                label: "layout"
                Chip { label: "portrait"; active: !root.landscape; onActivated: root.setSetting("layout", "portrait") }
                Chip { label: "landscape"; active: root.landscape; onActivated: root.setSetting("layout", "landscape") }
              }
              OptRow {
                label: "title"
                Rectangle {
                  width: 150
                  height: 17
                  radius: root.rounded ? 3 : 0
                  color: Util.alpha(root.fg, 0.06)
                  border.width: 1
                  border.color: titleInput.activeFocus ? root.pal.proc : "transparent"
                  TextInput {
                    id: titleInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.title
                    color: root.fg
                    selectionColor: Util.alpha(root.pal.proc, 0.4)
                    font.family: Style.font.family
                    font.pixelSize: 9
                    maximumLength: 32
                    clip: true
                    onEditingFinished: if (text !== root.title) root.setSetting("title", text)
                    Keys.onEscapePressed: { text = root.title; focus = false; keyCatcher.forceActiveFocus() }
                    Keys.onReturnPressed: { focus = false; keyCatcher.forceActiveFocus() }
                  }
                }
              }
              OptRow {
                label: "title font"
                Repeater {
                  model: root.builtinFonts
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.titleFontKey.toLowerCase() === modelData
                    onActivated: root.setSetting("titleFont", modelData)
                  }
                }
                Repeater {
                  model: root.userFontNames
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.titleFontKey === modelData
                    onActivated: root.setSetting("titleFont", modelData)
                  }
                }
                Chip { label: "upload font…"; active: false; onActivated: root.pickFont() }
              }
              OptRow {
                label: "position"
                Repeater {
                  model: ["left", "right"]
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.titleAlign === modelData
                    onActivated: root.setSetting("titleAlign", modelData)
                  }
                }
              }
              OptRow {
                label: "sys font"
                Rectangle {
                  width: 150
                  height: 17
                  radius: root.rounded ? 3 : 0
                  color: Util.alpha(root.fg, 0.06)
                  border.width: 1
                  border.color: fontInput.activeFocus ? root.pal.proc : "transparent"
                  TextInput {
                    id: fontInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.builtinFonts.indexOf(root.titleFontKey.toLowerCase()) >= 0 ? "" : root.titleFontKey
                    color: root.fg
                    selectionColor: Util.alpha(root.pal.proc, 0.4)
                    font.family: Style.font.family
                    font.pixelSize: 9
                    maximumLength: 64
                    clip: true
                    onEditingFinished: if (text.length > 0 && text !== root.titleFontKey) root.setSetting("titleFont", text)
                    Keys.onEscapePressed: { focus = false; keyCatcher.forceActiveFocus() }
                    Keys.onReturnPressed: { focus = false; keyCatcher.forceActiveFocus() }
                    Text {
                      visible: fontInput.text.length === 0 && !fontInput.activeFocus
                      anchors.verticalCenter: parent.verticalCenter
                      text: "any installed font…"
                      color: root.fg
                      opacity: 0.35
                      font.family: Style.font.family
                      font.pixelSize: 9
                    }
                  }
                }
              }
              OptRow {
                label: "title size"
                Repeater {
                  model: [16, 22, 26, 30, 34, 38, 46]
                  Chip {
                    required property int modelData
                    label: modelData + "px"
                    active: root.titleSize === modelData
                    onActivated: root.setSetting("titleSize", modelData)
                  }
                }
              }
              OptRow {
                label: "subtitle"
                Repeater {
                  model: [7, 9, 11, 13]
                  Chip {
                    required property int modelData
                    label: modelData + "px"
                    active: root.subSize === modelData
                    onActivated: root.setSetting("subSize", modelData)
                  }
                }
              }
              OptRow {
                label: "text"
                Chip { label: "normal"; active: root.textSize === "normal"; onActivated: root.setSetting("textSize", "normal") }
                Chip { label: "small"; active: root.textSize === "small"; onActivated: root.setSetting("textSize", "small") }
                Chip { label: "tiny"; active: root.textSize === "tiny"; onActivated: root.setSetting("textSize", "tiny") }
              }
              OptRow {
                label: "avatar"
                Chip { label: "upload photo…"; active: false; onActivated: root.pickAvatar() }
                Chip {
                  visible: root.avatarSetting !== "auto" && root.avatarSetting !== "none"
                  label: "custom"
                  active: true
                }
                Chip { label: "auto"; active: root.avatarSetting === "auto"; onActivated: root.setSetting("avatar", "auto") }
                Chip { label: "none"; active: root.avatarSetting === "none"; onActivated: root.setSetting("avatar", "none") }
              }
              OptRow {
                label: "hero"
                Chip { label: "upload banner…"; active: false; onActivated: root.pickHero() }
                Chip {
                  visible: root.heroSetting !== "none" && root.heroSetting !== ""
                  label: "custom"
                  active: true
                }
                Chip {
                  label: "none"
                  active: root.heroSetting === "none" || root.heroSetting === ""
                  onActivated: root.setSetting("hero", "none")
                }
              }
              OptRow {
                label: "hero pos"
                Repeater {
                  model: ["tl", "tc", "tr", "cl", "c", "cr", "bl", "bc", "br"]
                  Chip {
                    required property string modelData
                    label: root.posGlyph(modelData)
                    active: root.heroPos === modelData
                    onActivated: root.setSetting("heroPos", modelData)
                  }
                }
              }
              OptRow {
                label: "photo pos"
                Repeater {
                  model: ["tl", "tc", "tr", "cl", "c", "cr", "bl", "bc", "br"]
                  Chip {
                    required property string modelData
                    label: root.posGlyph(modelData)
                    active: root.avatarPos === modelData
                    onActivated: root.setSetting("avatarPos", modelData)
                  }
                }
              }
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
                label: "density"
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

          // ═══════════════ BOX AREA (portrait = one column, landscape = two) ═══════════════
          Item {
            id: boxArea
            width: bodyCol.width - 2 * bodyCol.leftPadding
            readonly property real gap: bodyCol.spacing
            readonly property int cols: root.landscape ? 2 : 1
            readonly property real colW: cols === 2 ? (width - gap) / 2 : width
            // Greedy placement: each visible box goes to the currently shorter column.
            readonly property var place: {
              var byKey = { cpu: cpuBoxItem, mem: memBoxItem, net: netBoxItem, proc: procBoxItem }
              var items = root.order.map(function(k) { return [k, byKey[k]] })
              var colY = [0, 0]
              var last = ["", ""]
              var out = { cpu: { x: 0, y: 0, stretch: 0 }, mem: { x: 0, y: 0, stretch: 0 },
                          net: { x: 0, y: 0, stretch: 0 }, proc: { x: 0, y: 0, stretch: 0 }, height: 0 }
              for (var i = 0; i < items.length; i++) {
                var it = items[i][1]
                if (!it.visible) continue
                var c = (cols === 2 && colY[1] < colY[0]) ? 1 : 0
                out[items[i][0]] = { x: c * (colW + gap), y: colY[c], stretch: 0 }
                last[c] = items[i][0]
                colY[c] += it.baseH + gap
              }
              // Landscape: give the shorter column's last box the leftover height
              // so the two columns end level instead of leaving a hole.
              if (cols === 2 && last[0] && last[1]) {
                var diff = Math.abs(colY[0] - colY[1])
                var short = colY[1] < colY[0] ? 1 : 0
                if (diff > 0 && diff < 400) out[last[short]].stretch = diff
              }
              out.height = Math.max(0, Math.max(colY[0], colY[1]) - gap)
              return out
            }
            height: place.height

            function keyAt(px, py, exclude) {
              var byKey = { cpu: cpuBoxItem, mem: memBoxItem, net: netBoxItem, proc: procBoxItem }
              for (var k in byKey) {
                var b = byKey[k]
                if (k === exclude || !b.visible) continue
                if (px >= b.x && px <= b.x + b.width && py >= b.y && py <= b.y + b.height) return k
              }
              return ""
            }

            // ═══════════════ CPU BOX ═══════════════
            BtopBox {
              id: cpuBoxItem
              boxKey: "cpu"
              x: boxArea.place.cpu.x
              y: boxArea.place.cpu.y
              width: boxArea.colW
              visible: root.showBox("cpu")
              readonly property int nCores: root.stats ? root.stats.cores.length : 2
              readonly property int rowH: root.compact ? 12 : 14
              readonly property int coresH: nCores * rowH + (nCores - 1) * 2
              readonly property int graphH: root.compact ? 34 : 54
              height: baseH + boxArea.place.cpu.stretch
              readonly property real baseH: 15 + coresH + 14 + graphH + 4 + 15
              boxColor: root.pal.cpu
              tag: root.boxTag("cpu")
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

              GraphView {
                id: cpuGraph
                y: cpuBoxItem.coresH + 14
                width: parent.width
                height: cpuBoxItem.graphH
                history: root.cpuHistory
              }
            }

            // ═══════════════ MEM BOX ═══════════════
            BtopBox {
              id: memBoxItem
              boxKey: "mem"
              x: boxArea.place.mem.x
              y: boxArea.place.mem.y
              width: boxArea.colW
              visible: root.showBox("mem")
              readonly property int graphH: root.compact ? 24 : 36
              readonly property int rowH: root.compact ? 12 : 14
              height: baseH + boxArea.place.mem.stretch
              readonly property real baseH: 15 + graphH + 13 + 4 * rowH + 3 * 3 + 11
              boxColor: root.pal.mem
              tag: root.boxTag("mem")
              rightText: root.stats ? (root.fmtG(root.stats.ram_used) + " / " + root.fmtG(root.stats.ram_total) + "G") : ""
              divY: 15 + graphH + 5
              divLabel: "breakdown"

              GraphView {
                id: memGraph
                width: parent.width
                height: memBoxItem.graphH
                history: root.ramHistory
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
              boxKey: "net"
              x: boxArea.place.net.x
              y: boxArea.place.net.y
              width: boxArea.colW
              visible: root.showBox("net")
              height: baseH + boxArea.place.net.stretch
              readonly property int graphH: root.compact ? 26 : 40
              readonly property real baseH: 15 + 16 + 6 + graphH + 15
              boxColor: root.pal.net
              tag: root.boxTag("net")
              footLeft: root.stats ? "total ▼ " + root.stats.net_rx + "  ▲ " + root.stats.net_tx : ""

              Row {
                id: netRates
                anchors.top: parent.top
                anchors.topMargin: 2
                spacing: 18

                Row {
                  spacing: 5
                  Text { text: "▼"; color: root.pal.down; font.pixelSize: root.fsTiny; anchors.verticalCenter: parent.verticalCenter }
                  Text {
                    text: root.stats ? root.fmtRate(root.netRxRate) : "…"
                    color: root.fg; opacity: 0.85
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                  }
                }
                Row {
                  spacing: 5
                  Text { text: "▲"; color: root.pal.up; font.pixelSize: root.fsTiny; anchors.verticalCenter: parent.verticalCenter }
                  Text {
                    text: root.stats ? root.fmtRate(root.netTxRate) : "…"
                    color: root.fg; opacity: 0.85
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                  }
                }
              }

              GraphView {
                anchors.top: netRates.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                history: root.netHistory
                history2: root.netUpHistory
                stops: [root.pal.down, root.pal.net, root.pal.up]
              }
            }

            // ═══════════════ PROC BOX ═══════════════
            BtopBox {
              id: procBoxItem
              boxKey: "proc"
              x: boxArea.place.proc.x
              y: boxArea.place.proc.y
              width: boxArea.colW
              visible: root.showBox("proc")
              readonly property int rowH: root.compact ? 12 : 14
              readonly property int rows: root.stats ? Math.min(root.procCount, root.stats.procs.length) : root.procCount
              height: baseH + boxArea.place.proc.stretch
              readonly property real baseH: 15 + 20 + rows * rowH + (rows - 1) * 2 + 10
              boxColor: root.pal.proc
              tag: root.boxTag("proc")
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
  }

  // ── Graph rendering ──
  readonly property real dotPitch: 4.2
  readonly property real barPitch: 3

  // Static background: dot grid or guide lines. Repainted only on resize,
  // style or colour change.
  function paintGrid(canvas) {
    var ctx = canvas.getContext("2d")
    ctx.reset()
    var w = canvas.width, h = canvas.height
    if (w <= 0 || h <= 0) return
    if (root.graphStyle === "dots") {
      var pitch = root.dotPitch
      var cols = Math.floor(w / pitch), rows = Math.floor(h / pitch)
      ctx.fillStyle = Util.alpha(root.fg, 0.10)
      ctx.beginPath()
      for (var gx = 0; gx < cols; gx++) {
        var cx = gx * pitch + pitch / 2
        for (var gy = 0; gy < rows; gy++) {
          var cy = h - (gy * pitch + pitch / 2)
          ctx.moveTo(cx + 1, cy)
          ctx.arc(cx, cy, 1.0, 0, Math.PI * 2)
        }
      }
      ctx.fill()
    } else {
      ctx.strokeStyle = Util.alpha(root.fg, 0.10)
      ctx.lineWidth = 1
      ctx.beginPath()
      for (var q = 1; q < 4; q++) {
        var y = Math.round(h * q / 4) + 0.5
        ctx.moveTo(0, y); ctx.lineTo(w, y)
      }
      ctx.stroke()
    }
  }

  function paintData(canvas, history, history2, stops) {
    var ctx = canvas.getContext("2d")
    ctx.reset()
    var w = canvas.width, h = canvas.height
    if (w <= 0 || h <= 0 || !history || !history.length) return
    var st = stops && stops.length === 3 ? stops : root.pal.graph
    if (root.graphStyle === "bars") paintBars(ctx, w, h, history, st)
    else if (root.graphStyle === "line") paintLine(ctx, w, h, history, st)
    else paintDots(ctx, w, h, history, st)
    if (history2 && history2.length > 1) paintUpOverlay(ctx, w, h, history2)
  }

  // Upload series: a thin line in the "up" colour drawn over the download
  // area, like btop's stacked net graph.
  function paintUpOverlay(ctx, w, h, history) {
    var n = history.length
    var step = w / (root.historyLen - 1)
    var x0 = w - (n - 1) * step
    ctx.beginPath()
    for (var i = 0; i < n; i++) {
      var x = x0 + i * step
      var y = h - 1 - Math.max(0, Math.min(1, history[i])) * (h - 2)
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
    }
    ctx.strokeStyle = root.pal.up
    ctx.lineWidth = 1.4
    ctx.lineJoin = "round"
    ctx.stroke()
  }

  function gradColor(stops, v) {
    var t = Math.max(0, Math.min(1, v))
    var a, b, k
    if (t < 0.5) { a = Qt.lighter(stops[0], 1.0); b = Qt.lighter(stops[1], 1.0); k = t / 0.5 }
    else { a = Qt.lighter(stops[1], 1.0); b = Qt.lighter(stops[2], 1.0); k = (t - 0.5) / 0.5 }
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k,
                   a.a + (b.a - a.a) * k)
  }

  // Dots are batched per row: one path + one fill per colour band instead of
  // one fill per dot.
  function paintDots(ctx, w, h, history, stops) {
    var pitch = root.dotPitch
    var cols = Math.floor(w / pitch), rows = Math.floor(h / pitch)
    if (cols <= 0 || rows <= 0) return
    var n = history.length
    var first = Math.max(0, n - cols)
    var filled = []
    var maxFilled = 0
    for (var i = first; i < n; i++) {
      var f = Math.max(1, Math.round(Math.max(0, Math.min(1, history[i])) * rows))
      filled.push(f)
      if (f > maxFilled) maxFilled = f
    }
    var startCol = cols - filled.length
    for (var r = 0; r < maxFilled; r++) {
      var cy = h - (r * pitch + pitch / 2)
      ctx.beginPath()
      for (var c = 0; c < filled.length; c++) {
        if (filled[c] <= r) continue
        var cx = (startCol + c) * pitch + pitch / 2
        ctx.moveTo(cx + 1.15, cy)
        ctx.arc(cx, cy, 1.15, 0, Math.PI * 2)
      }
      ctx.fillStyle = root.gradColor(stops, r / rows)
      ctx.fill()
    }
  }

  function paintBars(ctx, w, h, history, stops) {
    var pitch = root.barPitch
    var cols = Math.floor(w / pitch)
    var grad = ctx.createLinearGradient(0, h, 0, 0)
    grad.addColorStop(0.0, stops[0])
    grad.addColorStop(0.5, stops[1])
    grad.addColorStop(1.0, stops[2])
    ctx.fillStyle = grad
    var n = history.length
    ctx.beginPath()
    for (var i = Math.max(0, n - cols); i < n; i++) {
      var c = cols - n + i
      var bh = Math.max(1, Math.round(Math.max(0, Math.min(1, history[i])) * h))
      ctx.rect(c * pitch, h - bh, pitch - 1, bh)
    }
    ctx.fill()
  }

  function paintLine(ctx, w, h, history, stops) {
    var n = history.length
    if (n < 2) return
    var step = w / (root.historyLen - 1)
    var x0 = w - (n - 1) * step
    function px(i) { return x0 + i * step }
    function py(i) { return h - 1 - Math.max(0, Math.min(1, history[i])) * (h - 2) }

    var fill = ctx.createLinearGradient(0, h, 0, 0)
    fill.addColorStop(0.0, Util.alpha(Qt.lighter(stops[0], 1.0), 0.05))
    fill.addColorStop(1.0, Util.alpha(Qt.lighter(stops[2], 1.0), 0.35))
    ctx.beginPath()
    ctx.moveTo(px(0), h)
    for (var i = 0; i < n; i++) ctx.lineTo(px(i), py(i))
    ctx.lineTo(px(n - 1), h)
    ctx.closePath()
    ctx.fillStyle = fill
    ctx.fill()

    var stroke = ctx.createLinearGradient(0, h, 0, 0)
    stroke.addColorStop(0.0, stops[0])
    stroke.addColorStop(0.5, stops[1])
    stroke.addColorStop(1.0, stops[2])
    ctx.beginPath()
    ctx.moveTo(px(0), py(0))
    for (var j = 1; j < n; j++) ctx.lineTo(px(j), py(j))
    ctx.strokeStyle = stroke
    ctx.lineWidth = 1.5
    ctx.lineJoin = "round"
    ctx.stroke()
  }
}
