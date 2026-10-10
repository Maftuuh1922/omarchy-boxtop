import QtQuick
import QtQuick.Effects
import QtQml.Models
import Quickshell
import Quickshell.Io
import qs.Commons
// Qualified alias for Color: newer Qt versions ship their own `Color`
// name that can shadow the Omarchy singleton (Omarchy's own Ui does the same).
import qs.Commons as Commons
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
  readonly property var settingsTabs: ["glass", "colour", "layout", "header", "data", "presets"]
  property string settingsTab: "glass"
  property bool presetDeleteMode: false
  property bool resetArmed: false
  Timer { id: resetDisarm; interval: 4000; onTriggered: root.resetArmed = false }
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
  readonly property bool rounded: cornerRadius > 0
  readonly property int lineWidth: clampNum(opt("lineWidth", 1), 1, 3, 1)
  readonly property int interval: clampNum(opt("interval", 2), 1, 10, 2)
  readonly property int procCount: clampNum(opt("procCount", 8), 3, 15, 8)
  readonly property bool fade: opt("fade", true) !== false
  readonly property bool shadow: opt("shadow", false) === true
  // Glass boxes (no outline) by default; `stroke: true` brings back btop frames.
  readonly property bool stroke: opt("stroke", false) === true
  readonly property bool landscape: opt("layout", "portrait") === "landscape"

  // ── Liquid glass ──
  // One set of tokens (fill, hairline, highlight, text) drives the card,
  // boxes, chips, sliders and the bar pill, so every "glass style" looks
  // consistent everywhere. Everything is flat: translucent fills, 1 px
  // hairlines and a 1 px top highlight; no gradients unless the user turns
  // the btop-classic gradients back on.
  readonly property var glassStyles: ["regular", "clear", "dark", "tinted", "solid"]
  readonly property string glassStyle: glassStyles.indexOf(String(opt("glassStyle", "regular"))) >= 0 ? String(opt("glassStyle", "regular")) : "regular"
  readonly property bool glassOn: glassStyle !== "solid"
  readonly property bool hyprBlur: opt("hyprBlur", false) === true
  readonly property int blurStrength: clampNum(opt("blur", 60), 0, 100, 60)
  readonly property int glassStrength: clampNum(opt("glassOpacity", 50), 0, 100, 50)
  readonly property int tintStrength: clampNum(opt("tint", 40), 0, 100, 40)
  // Corner radius for the card; boxes and chips follow it. The old
  // `rounded: false` still means sharp corners when no radius was set.
  readonly property int cornerRadius: clampNum(opt("radius", opt("rounded", true) === false ? 0 : 14), 0, 28, 14)
  readonly property int uiScalePct: clampNum(opt("scale", 100), 80, 130, 100)
  readonly property real uiScale: uiScalePct / 100
  readonly property string motionPref: ["auto", "on", "off"].indexOf(String(opt("motion", "auto"))) >= 0 ? String(opt("motion", "auto")) : "auto"
  readonly property bool motion: motionPref === "on" || (motionPref === "auto" && !Style.reduceMotion)
  readonly property bool gradients: opt("gradients", false) === true
  readonly property bool barPill: opt("barPill", true) !== false
  readonly property string popupPos: opt("popupPos", "icon") === "center" ? "center" : "icon"
  readonly property string netUnits: opt("netUnits", "bytes") === "bits" ? "bits" : "bytes"
  readonly property string tempUnit: opt("tempUnit", "c") === "f" ? "f" : "c"
  readonly property bool updateChecks: opt("updateCheck", true) !== false
  readonly property string glassStyleHint: ({
    regular: "regular · adaptive frosted glass",
    clear: "clear · high transparency, best with blur behind",
    dark: "dark · smoked glass",
    tinted: "tinted · glass coloured by the accent",
    solid: "solid · opaque, no blur (accessibility)"
  })[glassStyle]

  readonly property int boxRadius: Math.round(cornerRadius * 0.6)
  readonly property int ctlRadius: Math.round(cornerRadius * 0.5)

  // Accent: 14 presets (the first follows the Omarchy theme), a custom hex,
  // or one of the swatches taken from the current wallpaper. Picking a preset
  // or a hex switches "from wallpaper" off.
  readonly property var accentPresets: [
    { name: "theme", hex: "" }, { name: "blue", hex: "#0a84ff" }, { name: "indigo", hex: "#5e5ce6" },
    { name: "purple", hex: "#bf5af2" }, { name: "pink", hex: "#ff375f" }, { name: "red", hex: "#ff453a" },
    { name: "orange", hex: "#ff9f0a" }, { name: "yellow", hex: "#ffd60a" }, { name: "green", hex: "#30d158" },
    { name: "mint", hex: "#63e6e2" }, { name: "teal", hex: "#40c8e0" }, { name: "cyan", hex: "#64d2ff" },
    { name: "brown", hex: "#ac8e68" }, { name: "graphite", hex: "#8e8e93" }
  ]
  readonly property string accentSetting: String(opt("accent", "theme"))
  readonly property bool accentFromWallpaper: opt("accentWallpaper", false) === true
  readonly property int wallIndex: clampNum(opt("accentWallpaperIndex", 0), 0, 4, 0)
  property var wallSwatches: []
  property string wallMean: ""
  property string wallSource: ""

  function isHex(v) { return /^#[0-9a-fA-F]{6}$/.test(String(v)) }
  function presetHex(name) {
    for (var i = 0; i < accentPresets.length; i++) if (accentPresets[i].name === name) return accentPresets[i].hex
    return null
  }
  readonly property color accentBase: {
    if (accentFromWallpaper && wallSwatches.length > 0) return wallSwatches[Math.min(wallIndex, wallSwatches.length - 1)]
    if (isHex(accentSetting)) return accentSetting
    var h = presetHex(accentSetting)
    return h ? h : Commons.Color.accent
  }

  // ── colour maths (sRGB, WCAG 2 contrast) ──
  function lin(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  function lum(c) { c = Qt.color(c); return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }
  function contrast(a, b) {
    var la = lum(a), lb = lum(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }
  function mixc(a, b, t) {
    a = Qt.color(a); b = Qt.color(b)
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  function opaque(c) { c = Qt.color(c); return Qt.rgba(c.r, c.g, c.b, 1) }
  // `top` at `alpha` over an opaque `bottom`, as the compositor blends it.
  function over(top, alpha, bottom) { return mixc(bottom, top, alpha) }

  readonly property color baseFg: Commons.Color.popups.text
  readonly property color baseBg: opaque(Commons.Color.popups.background)
  // What sits behind the glass: the wallpaper's average colour when known,
  // plus the theme background (windows behind the card). Text has to pass
  // 4.5:1 against the glass over both of them.
  readonly property var backdrops: {
    var list = [baseBg]
    if (isHex(wallMean)) list.push(wallMean)
    else list.push(lum(baseBg) > 0.4 ? "#3a3a3a" : "#b4b4b4")
    return list
  }

  readonly property color glassTint: {
    var t = tintStrength / 100
    if (glassStyle === "dark") return mixc(mixc(baseBg, "#000000", 0.6), accentBase, t * 0.12)
    if (glassStyle === "tinted") return mixc(baseBg, accentBase, 0.12 + t * 0.5)
    if (glassStyle === "clear") return mixc(baseBg, accentBase, t * 0.1)
    return mixc(baseBg, accentBase, t * 0.18)
  }
  readonly property real glassAlphaWanted: {
    var g = glassStrength / 100
    if (glassStyle === "solid") return 1.0
    if (glassStyle === "clear") return 0.16 + g * 0.36
    if (glassStyle === "dark") return 0.5 + g * 0.4
    return 0.38 + g * 0.5
  }
  function worstContrast(text, alpha) {
    var worst = 99
    for (var i = 0; i < backdrops.length; i++)
      worst = Math.min(worst, contrast(text, over(glassTint, alpha, backdrops[i])))
    return worst
  }
  // Lowest glass alpha >= wanted at which `text` passes 4.5:1, or 2 if never.
  function alphaFor(text) {
    if (worstContrast(text, glassAlphaWanted) >= 4.5) return glassAlphaWanted
    if (worstContrast(text, 1.0) < 4.5) return 2
    var lo = glassAlphaWanted, hi = 1.0
    for (var i = 0; i < 12; i++) {
      var mid = (lo + hi) / 2
      if (worstContrast(text, mid) >= 4.5) hi = mid; else lo = mid
    }
    return hi
  }
  // Pick the text colour: the theme's own when it can work, otherwise white
  // or near-black, whichever needs the least extra opacity.
  readonly property var glassSolve: {
    var cands = [baseFg, "#ffffff", "#101014"]
    var best = { text: baseFg, alpha: 2 }
    for (var i = 0; i < cands.length; i++) {
      var a = alphaFor(cands[i])
      if (a < best.alpha - (i === 0 ? -0.0001 : 0.02)) best = { text: cands[i], alpha: a }
    }
    if (best.alpha > 1) best.alpha = 1
    return best
  }
  readonly property color glassText: glassSolve.text
  readonly property real glassAlpha: glassSolve.alpha
  readonly property bool contrastBoosted: glassAlpha > glassAlphaWanted + 0.005
  readonly property bool textIsLight: lum(glassText) > 0.4
  // Effective card colour over the theme background, used to check inks.
  readonly property color glassComposite: over(glassTint, glassAlpha, baseBg)

  readonly property color cardFill: glassOn ? Util.alpha(glassTint, glassAlpha) : baseBg
  readonly property color glassBorder: !glassOn ? Util.alpha(glassText, 0.14)
    : Util.alpha(textIsLight ? "#ffffff" : "#000000", glassStyle === "clear" ? 0.26 : 0.18)
  readonly property color glassHighlight: !glassOn ? "transparent"
    : Util.alpha("#ffffff", glassStyle === "dark" ? 0.14 : (textIsLight ? 0.24 : 0.6))
  readonly property color boxFill: {
    if (glassStyle === "solid") return Util.alpha(glassText, 0.05)
    if (glassStyle === "tinted") return Util.alpha(accentBase, 0.08)
    if (glassStyle === "dark") return Util.alpha("#000000", 0.2)
    return Util.alpha(textIsLight ? "#ffffff" : "#000000", glassStyle === "clear" ? 0.08 : 0.06)
  }
  readonly property color boxBorder: Util.alpha(textIsLight ? "#ffffff" : "#000000", glassOn ? 0.12 : 0.1)
  readonly property color ctlFill: Util.alpha(glassText, 0.07)
  readonly property color ctlHover: Util.alpha(glassText, 0.13)

  // Colour `c` nudged toward the text colour until it reads at 4.5:1 on `bg`.
  function inkOn(c, bg) {
    var col = Qt.color(c)
    for (var i = 0; i <= 10; i++) {
      var m = mixc(col, glassText, i / 10)
      if (contrast(m, bg) >= 4.5) return m
    }
    return glassText
  }
  // Glass over each assumed backdrop (theme background, wallpaper average).
  readonly property var glassComposites: {
    var out = []
    for (var i = 0; i < backdrops.length; i++) out.push(over(glassTint, glassAlpha, backdrops[i]))
    return out
  }
  // Accent / palette colour used as text: must pass on every composite.
  function ink(c) {
    var col = Qt.color(c)
    for (var i = 0; i <= 10; i++) {
      var m = mixc(col, glassText, i / 10)
      var ok = true
      for (var j = 0; j < glassComposites.length && ok; j++) ok = contrast(m, glassComposites[j]) >= 4.5
      if (ok) return m
    }
    return glassText
  }
  readonly property color accentInk: ink(accentBase)
  // Text on an active chip / filled control (accent at 24 % over the glass).
  readonly property color activeFill: Util.alpha(accentBase, 0.24)
  readonly property color activeText: inkOn(glassText, over(accentBase, 0.24, glassComposite))
  // Lowest opacity at which dimmed glass text still reads at 4.5:1 over
  // every backdrop; secondary labels are clamped to it via dim().
  readonly property real minTextOpacity: {
    var bgs = glassComposites
    for (var o = 0.3; o < 1.0; o += 0.05) {
      var ok = true
      for (var j = 0; j < bgs.length && ok; j++) ok = contrast(mixc(bgs[j], glassText, o), bgs[j]) >= 4.5
      if (ok) return o
    }
    return 1.0
  }
  function dim(o) { return Math.max(o, minTextOpacity) }

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

  // Settings live on this widget's entry in ~/.config/omarchy/shell.json
  // (so `omarchy-shell maftuuh.boxtop set …` keeps working) and are mirrored
  // to ~/.config/boxtop/settings.json, which also restores them after a
  // reinstall. previewSetting() changes the look without saving (slider drag).
  function patchedEntry(changes) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var c in changes) {
      if (changes[c] === undefined || changes[c] === null) delete entry[c]
      else entry[c] = changes[c]
    }
    return entry
  }
  function persist(entry) {
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    mirrorTimer.restart()
  }
  function setSettings(changes) {
    var entry = patchedEntry(changes)
    root.settings = entry
    persist(entry)
  }
  function setSetting(key, value) {
    var c = {}
    c[key] = value
    setSettings(c)
  }
  function previewSetting(key, value) {
    var c = {}
    c[key] = value
    root.settings = patchedEntry(c)
  }
  // Reset everything except the uploaded photo / banner and update state.
  function resetDefaults() {
    var keep = ["avatar", "hero", "updateSeen"]
    var entry = { id: root.moduleName }
    for (var i = 0; i < keep.length; i++) if (root.settings[keep[i]] !== undefined) entry[keep[i]] = root.settings[keep[i]]
    root.settings = entry
    persist(entry)
    root.toast("defaults restored")
  }
  function settingsJson() {
    var o = {}
    for (var k in root.settings) if (k !== "id") o[k] = root.settings[k]
    return JSON.stringify(o)
  }

  Timer {
    id: mirrorTimer
    interval: 900
    onTriggered: {
      mirrorProc.command = ["python3", root.ctl, "mirror", "--json", root.settingsJson()]
      mirrorProc.running = true
    }
  }
  Process { id: mirrorProc }

  // A fresh widget entry (only an id, e.g. after reinstalling the plugin)
  // picks the mirrored settings back up.
  Process {
    id: restoreProc
    command: ["python3", root.ctl, "restore"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(String(text || "").trim()) } catch (e) { return }
        if (!d || typeof d !== "object") return
        delete d.id
        if (Object.keys(d).length > 0) root.setSettings(d)
      }
    }
  }

  readonly property string ctl: String(Qt.resolvedUrl("boxtopctl.py")).replace(/^file:\/\//, "")

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

  // ── Toast: a small glass pill at the bottom of the card ──
  property string toastText: ""
  function toast(msg) {
    root.toastText = String(msg || "")
    toastTimer.restart()
  }
  Timer { id: toastTimer; interval: 3600; onTriggered: root.toastText = "" }

  // ── Wallpaper palette (accent swatches + backdrop colour for contrast) ──
  property bool paletteForce: false
  function refreshPalette(force) {
    if (paletteProc.running) return
    paletteProc.command = ["python3", root.ctl, "palette", "--count", "5"].concat(force ? ["--force"] : [])
    paletteProc.running = true
  }
  Process {
    id: paletteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(String(text || "").trim()) } catch (e) { return }
        root.wallSwatches = (d.colors || []).filter(function(c) { return root.isHex(c) })
        root.wallMean = root.isHex(d.mean) ? d.mean : ""
        root.wallSource = String(d.source || "")
      }
    }
  }

  // ── Hyprland blur behind the card ──
  // Written as an Omarchy toggle file (~/.local/state/omarchy/toggles/hypr/
  // boxtop-glass.lua) that Hyprland's config loads; only touched when the
  // blur settings change, and removed for "solid" or blur off.
  readonly property string hyprBlurKey: (hyprBlur && glassOn) ? "on " + blurStrength : "off"
  property string appliedBlurKey: ""
  onHyprBlurKeyChanged: blurApplyTimer.restart()
  Timer {
    id: blurApplyTimer
    interval: 700
    onTriggered: {
      if (root.hyprBlurKey === root.appliedBlurKey) return
      if (root.appliedBlurKey === "" && root.hyprBlurKey === "off" && root.opt("hyprBlur", null) === null) {
        root.appliedBlurKey = "off" // never touch Hyprland for users who never enabled it
        return
      }
      root.appliedBlurKey = root.hyprBlurKey
      blurProc.command = ["python3", root.ctl, "hypr-glass"].concat(root.hyprBlurKey.split(" "))
      blurProc.running = true
    }
  }
  Process { id: blurProc }

  // ── Saved look presets (~/.config/boxtop/presets/*.json) ──
  property var savedPresets: []
  property string presetNameDraft: ""
  function refreshPresets() {
    presetList.running = false
    presetList.running = true
  }
  function savePreset(name) {
    name = String(name || "").trim()
    if (!/^[A-Za-z0-9][A-Za-z0-9 _.-]{0,31}$/.test(name)) { root.toast("name: letters, digits, space . _ -"); return }
    presetSave.command = ["python3", root.ctl, "preset-save", name, "--json", root.settingsJson()]
    presetSave.running = true
  }
  function loadPreset(name) {
    presetLoad.command = ["python3", root.ctl, "preset-load", name]
    presetLoad.running = true
  }
  function deletePreset(name) {
    presetDelete.command = ["python3", root.ctl, "preset-delete", name]
    presetDelete.running = true
  }
  function importPreset() {
    if (presetImport.running) return
    root.pickingFile = true
    root.close()
    presetImport.running = true
  }
  Process {
    id: presetList
    command: ["python3", root.ctl, "preset-list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.savedPresets = JSON.parse(String(text || "[]").trim() || "[]") } catch (e) { root.savedPresets = [] }
      }
    }
  }
  Process {
    id: presetSave
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.toast(code === 0 ? "preset saved to ~/.config/boxtop/presets" : "could not save preset")
      root.refreshPresets()
    }
  }
  Process {
    id: presetLoad
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(String(text || "").trim()) } catch (e) { root.toast("preset is not valid JSON"); return }
        // Keep this machine's photo, banner and update state.
        var keep = ["avatar", "hero", "updateSeen"]
        var entry = { id: root.moduleName }
        for (var i = 0; i < keep.length; i++) if (root.settings[keep[i]] !== undefined) entry[keep[i]] = root.settings[keep[i]]
        for (var k in d) if (keep.indexOf(k) < 0 && k !== "id") entry[k] = d[k]
        root.settings = entry
        root.persist(entry)
        root.toast("preset applied")
      }
    }
  }
  Process { id: presetDelete; onExited: root.refreshPresets() }
  Process {
    id: presetImport
    command: ["sh", "-c",
      'f=$(omarchy-file-select --title "Import a Boxtop preset (.json)" --extensions "json") || exit 1; ' +
      '[ -f "$f" ] || exit 1; exec python3 "$1" preset-import "$f"', "sh", root.ctl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").indexOf("imported") >= 0) root.toast("preset imported")
    }
    onExited: { root.refreshPresets(); root.reopenAfterPick() }
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
    target: Commons.Color
    function onAccentChanged() {
      themeFile.reload()
      if (root.glassOn || root.accentFromWallpaper) root.refreshPalette(false)
    }
  }

  function tc(name, fallback) {
    var v = root.themeColors[name]
    return v ? v : fallback
  }

  readonly property var pal: {
    var acc = Commons.Color.accent
    if (preset === "theme") {
      var t = {
        green: tc("green", "#a6e3a1"), yellow: tc("yellow", "#f9e2af"), red: tc("red", String(Commons.Color.urgent)),
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

  // Bar text keeps the bar's colour; card text is the contrast-checked
  // glass text (see glassSolve), so every label clears 4.5:1.
  readonly property color barFg: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property color fg: root.glassText
  readonly property color divLineColor: Util.alpha(root.fg, 0.22)
  // Card text scale: "small"/"tiny" shrink every box label for denser cards.
  readonly property string textSize: ["normal", "small", "tiny"].indexOf(String(opt("textSize", "normal"))) >= 0 ? String(opt("textSize", "normal")) : "normal"
  readonly property int fsOff: textSize === "tiny" ? -2 : textSize === "small" ? -1 : 0
  readonly property int fsSmall: Math.max(6, (compact ? 9 : 10) + fsOff)
  readonly property int fsTiny: Math.max(6, (compact ? 8 : 9) + fsOff)
  // Box frames repaint only when one of these changes, never per tick.
  readonly property string frameKey: [boxRadius, lineWidth, stroke, glassOn, String(fg), String(boxFill),
                                      String(boxBorder), String(glassHighlight)].join("|")

  // ── Built-in updater ──
  // updater.py checks GitHub (latest release tag; with no releases, the
  // VERSION file on main or new commits for git installs). It caches its
  // answer for 6 h in ~/.cache/boxtop/update.json, so the checks below
  // (shortly after start-up, every 6 h, and when the card opens) cost no
  // network traffic in between and fail quietly offline.
  readonly property string updater: String(Qt.resolvedUrl("updater.py")).replace(/^file:\/\//, "")
  property string localVersion: ""
  property var updateInfo: null
  property string updateVersion: ""   // newer version, empty when none (or dismissed)
  property string updateNotes: ""
  property string updateState: ""     // "", "working", "failed", "done"
  property string updateError: ""
  property real lastUpdateCheck: 0
  readonly property string updateStatusText: {
    var d = root.updateInfo
    if (!root.updateChecks) return "update checks off"
    if (!d) return "not checked yet"
    var ago = Math.max(0, Math.round((Date.now() / 1000 - (d.checked || 0)) / 60))
    var when = ago < 2 ? "just now" : (ago < 90 ? ago + " min ago" : Math.round(ago / 60) + " h ago")
    if (d.error && !d.available) return "offline · checked " + when
    return (d.available ? "v" + d.latest + " available" : "up to date") + " · checked " + when
  }

  FileView {
    path: String(Qt.resolvedUrl("VERSION")).replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: root.localVersion = String(text() || "").trim()
  }

  function checkForUpdate(force) {
    if (!root.updateChecks && !force) return
    var now = Date.now()
    if (!force && now - root.lastUpdateCheck < 600000) return // at most every 10 min from here
    root.lastUpdateCheck = now
    if (updateCheck.running) return
    updateCheck.command = ["python3", root.updater, "check"].concat(force ? ["--force"] : [])
    updateCheck.running = true
  }

  function runUpdate() {
    if (updateRunner.running) return
    root.updateState = "working"
    root.updateError = ""
    updateRunner.running = true
  }

  function dismissUpdate() {
    root.setSetting("updateSeen", root.updateVersion)
    root.updateVersion = ""
  }

  Timer {
    // First check a little after start-up, then every 6 hours.
    id: updateTimer
    interval: root.updateTimerFirst ? 45000 : 6 * 3600 * 1000
    running: root.updateChecks
    repeat: true
    onTriggered: { root.updateTimerFirst = false; root.checkForUpdate(false) }
  }
  property bool updateTimerFirst: true

  onOpenedChanged: {
    if (root.opened) {
      root.checkForUpdate(false)
      if (root.glassOn || root.accentFromWallpaper) root.refreshPalette(false)
      if (root.motion) popIn.restart()
    } else {
      // Closing the card commits any pending edit and folds settings away,
      // so the widget never reopens straight back into the settings box.
      if (titleField.text !== root.title) root.setSetting("title", titleField.text)
      if (root.showSettings) root.showSettings = false
    }
  }

  Process {
    id: updateCheck
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(String(text || "").trim()) } catch (e) { return }
        root.updateInfo = d
        if (d.current) root.localVersion = d.current
        var v = d.available ? String(d.latest || "") : ""
        root.updateVersion = (v !== "" && v === String(root.opt("updateSeen", ""))) ? "" : v
        root.updateNotes = String(d.notes || "")
      }
    }
  }

  Process {
    id: updateRunner
    command: ["python3", root.updater, "apply"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(String(text || "").trim()) } catch (e) { d = { ok: false, error: "updater crashed" } }
        if (d.ok) {
          root.updateState = "done"
          root.updateVersion = ""
          root.toast("updated to v" + d.to + " · reloading…")
          shellRestartTimer.restart()
        } else {
          root.updateState = "failed"
          root.updateError = String(d.error || "unknown error")
          root.toast("update failed · rolled back")
        }
      }
    }
  }

  // Let the toast show for a moment, then reload the shell so the new QML loads.
  Timer { id: shellRestartTimer; interval: 1400; onTriggered: shellRestart.running = true }
  Process {
    id: shellRestart
    command: ["sh", "-c", "command -v omarchy >/dev/null && exec omarchy restart shell; " +
                          "omarchy-shell shell rescanPlugins"]
  }

  onPalChanged: repaintGraphs()
  onGraphStyleChanged: repaintGraphs()
  onFgChanged: repaintGraphs()
  onGradientsChanged: repaintGraphs()

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
    refreshPresets()
    if (root.glassOn || root.accentFromWallpaper) refreshPalette(false)
    startupTimer.start()
  }

  Timer {
    id: startupTimer
    interval: 1500
    onTriggered: {
      var keys = Object.keys(root.settings || {}).filter(function(k) { return k !== "id" })
      if (keys.length === 0) restoreProc.running = true
      blurApplyTimer.restart()
    }
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
    if (root.netUnits === "bits") {
      var bits = b * 8
      if (bits < 1000) return Math.round(bits) + "b/s"
      if (bits < 1e6) return Math.round(bits / 1000) + "Kb/s"
      if (bits < 1e9) return (bits / 1e6).toFixed(1) + "Mb/s"
      return (bits / 1e9).toFixed(2) + "Gb/s"
    }
    if (b < 1024) return Math.round(b) + "B/s"
    if (b < 1048576) return Math.round(b / 1024) + "K/s"
    if (b < 1073741824) return (b / 1048576).toFixed(1) + "M/s"
    return (b / 1073741824).toFixed(2) + "G/s"
  }
  function fmtTemp(c) {
    if (c === null || c === undefined) return ""
    return root.tempUnit === "f" ? Math.round(c * 9 / 5 + 32) + "°F" : c + "°"
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
    Behavior on x { enabled: root.motion && root.dragKey === ""; SpringAnimation { spring: 4; damping: 0.38; epsilon: 0.25 } }
    Behavior on y { enabled: root.motion && root.dragKey === ""; SpringAnimation { spring: 4; damping: 0.38; epsilon: 0.25 } }

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
      function onFrameKeyChanged() { frameCanvas.requestPaint() }
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
        var r = Math.min(root.boxRadius, 10)
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
          // Glass box: flat translucent fill, 1 px hairline and a 1 px
          // highlight along the top edge (no gradients).
          var fr = Math.min(root.boxRadius, (h - 6) / 2)
          var fy = 0.5
          var fh = h - 6.5
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
          ctx.fillStyle = root.boxFill
          ctx.fill()
          if (root.glassOn) {
            ctx.lineWidth = 1
            ctx.strokeStyle = root.boxBorder
            ctx.stroke()
            ctx.beginPath()
            ctx.strokeStyle = root.glassHighlight
            ctx.moveTo(fr + 2, fy + 1)
            ctx.lineTo(w - fr - 2, fy + 1)
            ctx.stroke()
          }

          if (boxRoot.divY > 0) {
            ctx.beginPath()
            ctx.lineWidth = 1
            ctx.strokeStyle = Util.alpha(root.fg, 0.12)
            ctx.moveTo(8, boxRoot.divY + 0.5)
            if (boxRoot.divLabel.length > 0) {
              var gw = boxRoot.divLabel.length * (root.fsTiny * 0.72) + 8
              ctx.lineTo(12, boxRoot.divY + 0.5)
              ctx.moveTo(14 + gw, boxRoot.divY + 0.5)
            }
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
      x: 12; y: root.stroke ? 0 : 3
      color: root.ink(boxRoot.boxColor)
      font.family: Style.font.family
      font.pixelSize: root.fsSmall
      font.bold: true
    }
    Text {
      text: boxRoot.rightText
      anchors.right: parent.right
      anchors.rightMargin: 14
      y: root.stroke ? 1 : 3
      color: root.fg
      opacity: root.dim(0.8)
      font.family: Style.font.family
      font.pixelSize: root.fsTiny
    }
    Text {
      visible: boxRoot.divY > 0 && boxRoot.divLabel.length > 0
      text: boxRoot.divLabel
      x: 16
      y: boxRoot.divY - 6
      color: root.fg
      opacity: root.dim(0.5)
      font.family: Style.font.family
      font.pixelSize: root.fsTiny
    }
    Text {
      visible: boxRoot.footLeft.length > 0
      text: boxRoot.footLeft
      x: 14
      y: parent.height - 14
      color: root.fg
      opacity: root.dim(0.6)
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
      opacity: root.dim(0.5)
      font.family: Style.font.family
      font.pixelSize: root.fsTiny
    }

    // Drop-target highlight
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: 6
      anchors.bottomMargin: 2
      visible: boxRoot.boxKey !== "" && root.dragTargetKey === boxRoot.boxKey
      radius: root.boxRadius
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

  // ── Meter ──
  // Flat by default: one solid colour that steps through the palette's three
  // levels (low / mid / high). `gradients: true` restores btop's gradient.
  function levelColor(stops, v) {
    return v < 0.5 ? stops[0] : (v < 0.8 ? stops[1] : stops[2])
  }

  component GradBar: Rectangle {
    id: gb
    property real pct: 0
    property var stops: ["#89b482", "#7daea3", "#d3869b"]
    readonly property real frac: Math.max(0, Math.min(1, pct))
    height: root.compact ? 6 : 8
    radius: root.rounded ? Math.min(height / 2, root.ctlRadius + 1) : 0
    color: Util.alpha(root.fg, 0.08)
    clip: true

    Item {
      width: gb.width * gb.frac
      height: gb.height
      clip: true

      Rectangle {
        width: root.gradients ? gb.width : parent.width
        height: gb.height
        radius: gb.radius
        color: root.levelColor(gb.stops, gb.frac)
        gradient: root.gradients ? classicGrad : null
      }
    }

    Gradient {
      id: classicGrad
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: gb.stops[0] }
      GradientStop { position: 0.5; color: gb.stops[1] }
      GradientStop { position: 1.0; color: gb.stops[2] }
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
      color: root.fg; opacity: root.dim(0.6)
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
      color: root.fg; opacity: root.dim(0.6)
      font.family: Style.font.family; font.pixelSize: root.fsSmall
      width: 32
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // ── Settings UI (glass controls) ──
  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool active: false
    property color swatch: "transparent"
    signal activated()
    readonly property bool hasSwatch: swatch.a > 0
    width: chipText.implicitWidth + (hasSwatch ? 22 : 14)
    height: 18
    radius: root.rounded ? Math.min(height / 2, root.ctlRadius + 3) : 0
    color: chip.active ? root.activeFill : (chipMouse.containsMouse ? root.ctlHover : root.ctlFill)
    border.width: 1
    border.color: chip.active ? Util.alpha(root.accentBase, 0.8) : root.boxBorder
    scale: chipMouse.pressed ? 0.94 : 1.0

    Behavior on color { enabled: root.motion; ColorAnimation { duration: 140 } }
    Behavior on scale { enabled: root.motion; SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.004 } }

    // Flat top highlight: the "lit edge" of the glass.
    Rectangle {
      visible: root.glassOn
      x: chip.radius * 0.6 + 1; y: 1
      width: chip.width - 2 * x; height: 1
      color: root.glassHighlight
      opacity: 0.7
    }
    Rectangle {
      visible: chip.hasSwatch
      width: 9; height: 9; radius: 4.5
      x: 6
      anchors.verticalCenter: parent.verticalCenter
      color: chip.swatch
      border.width: 1
      border.color: root.boxBorder
    }
    Text {
      id: chipText
      x: chip.hasSwatch ? 18 : 7
      anchors.verticalCenter: parent.verticalCenter
      text: chip.label
      color: chip.active ? root.activeText : root.fg
      opacity: chip.active ? 1.0 : root.dim(0.8)
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
    property string tab: ""
    default property alias chips: chipFlow.data
    visible: tab === "" || root.settingsTab === tab
    width: parent.width
    height: visible ? Math.max(18, chipFlow.implicitHeight) : 0
    Text {
      text: optRow.label
      width: 52
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: root.fg
      opacity: root.dim(0.6)
      font.family: Style.font.family
      font.pixelSize: 9
      elide: Text.ElideRight
    }
    Flow {
      id: chipFlow
      x: 56
      width: optRow.width - 56
      spacing: 4
    }
  }

  // Glass slider: flat track, accent fill, glass knob with a hairline.
  // Dragging previews live (no disk write); releasing saves once.
  component GlassSlider: Item {
    id: sl
    property string key: ""
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property string suffix: ""
    property real live: value
    readonly property bool dragging: slMouse.pressed
    readonly property real frac: to > from ? Math.max(0, Math.min(1, (live - from) / (to - from))) : 0
    width: parent ? parent.width : 120
    height: 18
    onValueChanged: if (!dragging) live = value

    function snap(v) {
      v = Math.max(from, Math.min(to, v))
      return Math.round((v - from) / stepSize) * stepSize + from
    }
    function setFromX(px) {
      var v = snap(from + (px - track.x) / Math.max(1, track.width) * (to - from))
      if (v === live) return
      live = v
      root.previewSetting(key, v)
    }

    Rectangle {
      id: track
      x: 7
      width: sl.width - 52
      height: 4
      anchors.verticalCenter: parent.verticalCenter
      radius: 2
      color: Util.alpha(root.fg, 0.12)
      border.width: root.glassOn ? 1 : 0
      border.color: root.boxBorder
      Rectangle {
        width: Math.max(height, track.width * sl.frac)
        height: parent.height
        radius: parent.radius
        color: root.accentBase
      }
    }
    Rectangle {
      id: knob
      width: 14; height: 14; radius: 7
      x: track.x + track.width * sl.frac - width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: root.glassOn ? Util.alpha("#ffffff", root.textIsLight ? 0.92 : 0.98) : root.glassText
      border.width: 1
      border.color: Util.alpha("#000000", 0.18)
      scale: sl.dragging ? 1.18 : (slMouse.containsMouse ? 1.08 : 1.0)
      Behavior on scale { enabled: root.motion; SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.004 } }
      Behavior on x { enabled: root.motion && !sl.dragging; SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.2 } }
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 38
      horizontalAlignment: Text.AlignRight
      text: Math.round(sl.live) + sl.suffix
      color: root.fg
      opacity: root.dim(0.8)
      font.family: Style.font.family
      font.pixelSize: 9
    }
    MouseArea {
      id: slMouse
      anchors.fill: parent
      anchors.rightMargin: 40
      hoverEnabled: true
      preventStealing: true
      cursorShape: Qt.PointingHandCursor
      onPressed: function(m) { sl.setFromX(m.x) }
      onPositionChanged: function(m) { if (pressed) sl.setFromX(m.x) }
      onReleased: root.setSetting(sl.key, sl.live)
      onWheel: function(w) {
        var v = sl.snap(sl.live + (w.angleDelta.y > 0 ? sl.stepSize : -sl.stepSize) * (sl.stepSize < 5 ? 5 : 1))
        sl.live = v
        root.setSetting(sl.key, v)
      }
    }
  }

  // Glass text field used by the title, font, hex and preset-name inputs.
  component GlassField: Rectangle {
    id: gf
    property alias input: gfInput
    property alias text: gfInput.text
    property string placeholder: ""
    property int maxLen: 32
    signal committed(string value)
    width: 150
    height: 18
    radius: root.rounded ? Math.min(height / 2, root.ctlRadius + 3) : 0
    color: root.ctlFill
    border.width: 1
    border.color: gfInput.activeFocus ? root.accentBase : root.boxBorder
    TextInput {
      id: gfInput
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      verticalAlignment: TextInput.AlignVCenter
      color: root.fg
      selectionColor: Util.alpha(root.accentBase, 0.4)
      selectedTextColor: root.fg
      font.family: Style.font.family
      font.pixelSize: 9
      maximumLength: gf.maxLen
      clip: true
      onEditingFinished: gf.committed(text)
      Keys.onEscapePressed: { focus = false; keyCatcher.forceActiveFocus() }
      Keys.onReturnPressed: { focus = false; keyCatcher.forceActiveFocus() }
      Text {
        visible: gfInput.text.length === 0 && !gfInput.activeFocus
        anchors.verticalCenter: parent.verticalCenter
        text: gf.placeholder
        color: root.fg
        opacity: root.dim(0.45)
        font.family: Style.font.family
        font.pixelSize: 9
      }
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
    function glass(style: string): void { if (root.glassStyles.indexOf(style) >= 0) root.setSetting("glassStyle", style) }
    // accent <preset name | #rrggbb | wallpaper>
    function accent(value: string): void {
      if (value === "wallpaper") { root.setSetting("accentWallpaper", true); root.refreshPalette(false) }
      else if (root.isHex(value) || root.presetHex(value) !== null) root.setSettings({ accent: value, accentWallpaper: false })
    }
    function checkUpdate(): void { root.checkForUpdate(true) }
    function update(): void { root.runUpdate() }
    function reset(): void { root.resetDefaults() }
    function savePreset(name: string): void { root.savePreset(name) }
    function loadPreset(name: string): void { root.loadPreset(name) }
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

  // ── Bar pill: the chip icon sits on a small glass capsule ──
  Rectangle {
    id: barPillBg
    visible: root.barPill
    anchors.fill: parent
    anchors.topMargin: 3
    anchors.bottomMargin: 3
    anchors.leftMargin: 1
    anchors.rightMargin: 1
    radius: root.rounded ? height / 2 : 0
    color: Util.alpha(root.barFg, root.opened ? 0.16 : (root.glassStyle === "tinted" ? 0.06 : 0.08))
    border.width: 1
    border.color: root.opened ? Util.alpha(root.accentBase, 0.7) : Util.alpha(root.barFg, 0.16)
    Behavior on color { enabled: root.motion; ColorAnimation { duration: 160 } }
    Rectangle {
      visible: root.glassOn
      x: parent.radius * 0.7 + 1; y: 1
      width: parent.width - 2 * x; height: 1
      color: Util.alpha("#ffffff", 0.22)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    slotSize: Style.bar.iconSlot
    tooltipText: root.updateVersion !== "" ? "Boxtop · update v" + root.updateVersion + " available" : "Boxtop"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  // Update badge: a small accent dot with a glass ring on the bar pill.
  Rectangle {
    id: updateBadge
    visible: root.updateVersion !== ""
    width: 7; height: 7; radius: 3.5
    x: parent.width - width - 2
    y: 3
    color: root.accentBase
    border.width: 1
    border.color: Util.alpha("#ffffff", 0.75)
    scale: visible ? 1 : 0.2
    Behavior on scale { enabled: root.motion; SpringAnimation { spring: 5; damping: 0.28; epsilon: 0.01 } }
  }

  // ── Card glass: adopt the KeyboardPanel card surface ──
  // The Omarchy panel draws its own card with the theme's popup colour; we
  // bind its colour and radius to the glass tokens so the translucency and
  // the corners match the boxes. If a future Omarchy changes that structure
  // we fall back to drawing our own glass layer inside the card.
  property Item glassCard: null
  readonly property bool cardHooked: glassCard !== null
  function hookCard() {
    if (root.glassCard) return
    var it = keyCatcher.parent
    for (var depth = 0; it && depth < 4; depth++, it = it.parent) {
      if (it.contentTopInset !== undefined && it.borderSpec !== undefined && it.radius !== undefined) {
        it.color = Qt.binding(function() { return root.cardFill })
        it.radius = Qt.binding(function() { return root.cornerRadius })
        root.glassCard = it
        return
      }
    }
  }

  // Spring "pop" when the card opens (skipped with reduced motion).
  property real popScale: 1
  SpringAnimation {
    id: popIn
    target: root
    property: "popScale"
    from: 0.965
    to: 1
    spring: 4.5
    damping: 0.32
    epsilon: 0.002
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    borderSpec: Border.none()
    centerOnBar: root.popupPos === "center"
    contentWidth: panel.fittedContentWidth(Math.round(root.uiScale * Style.space(root.landscape ? (root.compact ? 620 : 720) : (root.compact ? 320 : 370))))
    // The Flickable reaches one padding above contentHolder, so the card only
    // needs to cover implicitHeight minus that overlap plus its own insets.
    contentHeight: panel.fittedContentHeight(bodyCol.implicitHeight * root.uiScale - panel.padding)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      Component.onCompleted: Qt.callLater(root.hookCard)

      // Own glass fill, only when the card surface could not be adopted.
      Rectangle {
        visible: !root.cardHooked
        anchors.fill: parent
        anchors.margins: -panel.padding
        radius: root.cornerRadius
        color: root.cardFill
      }
      onCloseRequested: {
        if (root.showSettings) root.showSettings = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        // Full-bleed: reach past the card padding so the hero banner can
        // span the whole card edge to edge.
        anchors.leftMargin: -panel.padding
        anchors.rightMargin: -panel.padding
        anchors.topMargin: -panel.padding
        anchors.bottomMargin: -panel.padding
        contentWidth: width
        contentHeight: bodyCol.implicitHeight * root.uiScale
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: bodyCol
          // Scale / density: lay out at 1/scale and scale the whole column,
          // so every row, graph and label grows or shrinks together.
          width: flick.width / root.uiScale
          transform: [
            Scale { origin.x: bodyCol.width / 2; origin.y: 0; xScale: root.popScale; yScale: root.popScale },
            Scale { xScale: root.uiScale; yScale: root.uiScale }
          ]
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
                  visible: root.gradients
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
                  // Classic mode hands the colour copy over to the grey base
                  // through a gradient mask; glass mode keeps the photo flat.
                  layer.enabled: root.gradients
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
                visible: root.gradients
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                gradient: Gradient {
                  GradientStop { position: 0.0; color: "transparent" }
                  GradientStop { position: 0.38; color: Util.alpha(Commons.Color.popups.background, 0.45) }
                  GradientStop { position: 0.72; color: Util.alpha(Commons.Color.popups.background, 0.9) }
                  GradientStop { position: 1.0; color: Util.alpha(Commons.Color.popups.background, 1.0) }
                }
              }
            }

            Rectangle {
              id: heroMask
              anchors.fill: parent
              radius: root.cornerRadius
              visible: false
              layer.enabled: true
            }

            // Saturation ramp for the colour copy: opaque at the top, gone at
            // the bottom, so the banner desaturates as it meets the card.
            Rectangle {
              id: satMask
              anchors.fill: parent
              visible: false
              layer.enabled: root.gradients
              gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 0.35; color: "#ffffff" }
                GradientStop { position: 0.95; color: "transparent" }
              }
            }

            // Glass mode: a flat frosted plate under the header keeps the
            // title legible on any banner (no gradient fade).
            Rectangle {
              visible: root.heroActive && !root.gradients
              x: header.x - 6
              y: header.y - 3
              width: header.width + 12
              height: header.height + 6
              radius: root.rounded ? Math.min(height / 2, root.boxRadius + 4) : 0
              color: Util.alpha(root.glassComposite, 0.78)
              border.width: 1
              border.color: root.boxBorder
              Rectangle {
                visible: root.glassOn
                x: parent.radius * 0.7 + 1; y: 1
                width: parent.width - 2 * x; height: 1
                color: root.glassHighlight
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
                  border.color: root.accentBase
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
                  opacity: root.dim(0.5)
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
                color: gearMouse.containsMouse || root.showSettings ? root.accentInk : root.fg
                opacity: gearMouse.containsMouse || root.showSettings ? 1.0 : root.dim(0.55)
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

          // ── Update notice: "Update available vX → vY" with notes ──
          Item {
            id: updateRow
            visible: root.updateVersion !== "" || root.updateState === "failed" || root.updateState === "working"
            width: bodyCol.width - 2 * bodyCol.leftPadding
            height: visible ? updateCol.implicitHeight + 14 : 0

            Rectangle {
              anchors.fill: parent
              radius: root.boxRadius
              color: Util.alpha(root.accentBase, 0.12)
              border.width: 1
              border.color: Util.alpha(root.accentBase, 0.55)
              Rectangle {
                visible: root.glassOn
                x: parent.radius * 0.7 + 1; y: 1
                width: parent.width - 2 * x; height: 1
                color: root.glassHighlight
              }
            }
            Column {
              id: updateCol
              x: 9; y: 7
              width: parent.width - 18
              spacing: 5
              Item {
                width: parent.width
                height: 18
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - updateBtns.width - 6
                  elide: Text.ElideRight
                  text: root.updateState === "working" ? "updating to v" + root.updateVersion + "…"
                      : root.updateState === "failed" ? "update failed · rolled back"
                      : "Update available  v" + (root.localVersion || "?") + " → v" + root.updateVersion
                  color: root.updateState === "failed" ? root.ink(root.pal.net) : root.accentInk
                  font.family: Style.font.family
                  font.pixelSize: root.fsSmall
                  font.bold: true
                }
                Row {
                  id: updateBtns
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 4
                  Chip {
                    label: root.updateState === "working" ? "working…" : (root.updateState === "failed" ? "retry" : "update now")
                    active: true
                    onActivated: if (root.updateState !== "working") root.runUpdate()
                  }
                  Chip {
                    visible: root.updateState !== "working"
                    label: "later"
                    onActivated: { root.updateState = ""; root.dismissUpdate() }
                  }
                }
              }
              Text {
                visible: text.length > 0
                width: parent.width
                text: root.updateState === "failed" ? root.updateError : root.updateNotes
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                color: root.fg
                opacity: root.dim(0.75)
                font.family: Style.font.family
                font.pixelSize: root.fsTiny
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

              // Section tabs
              Flow {
                width: parent.width
                spacing: 4
                bottomPadding: 3
                Repeater {
                  model: root.settingsTabs
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.settingsTab === modelData
                    onActivated: {
                      root.settingsTab = modelData
                      if (modelData === "colour") root.refreshPalette(false)
                      if (modelData === "presets") root.refreshPresets()
                    }
                  }
                }
              }

              // ── glass ──
              OptRow {
                tab: "glass"; label: "style"
                Repeater {
                  model: root.glassStyles
                  Chip {
                    required property string modelData
                    label: modelData
                    active: root.glassStyle === modelData
                    onActivated: root.setSetting("glassStyle", modelData)
                  }
                }
              }
              OptRow {
                tab: "glass"; label: ""
                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: root.glassStyleHint + (root.contrastBoosted ? "  ·  opacity raised for 4.5:1 text contrast" : "")
                  color: root.fg
                  opacity: root.dim(0.6)
                  font.family: Style.font.family
                  font.pixelSize: root.fsTiny
                }
              }
              OptRow {
                tab: "glass"; label: "blur bg"
                Chip { label: "off"; active: !root.hyprBlur; onActivated: root.setSetting("hyprBlur", false) }
                Chip { label: "on"; active: root.hyprBlur; onActivated: root.setSetting("hyprBlur", true) }
              }
              OptRow {
                tab: "glass"; label: "blur"
                visible: root.settingsTab === "glass" && root.hyprBlur && root.glassOn
                GlassSlider { key: "blur"; value: root.blurStrength; suffix: "%" }
              }
              OptRow {
                tab: "glass"; label: "glass"
                visible: root.settingsTab === "glass" && root.glassOn
                GlassSlider { key: "glassOpacity"; value: root.glassStrength; suffix: "%" }
              }
              OptRow {
                tab: "glass"; label: "tint"
                visible: root.settingsTab === "glass" && root.glassOn
                GlassSlider { key: "tint"; value: root.tintStrength; suffix: "%" }
              }
              OptRow {
                tab: "glass"; label: "corners"
                GlassSlider { key: "radius"; from: 0; to: 28; value: root.cornerRadius; suffix: "px" }
              }
              OptRow {
                tab: "glass"; label: "motion"
                Chip { label: "auto"; active: root.motionPref === "auto"; onActivated: root.setSetting("motion", "auto") }
                Chip { label: "full"; active: root.motionPref === "on"; onActivated: root.setSetting("motion", "on") }
                Chip { label: "reduced"; active: root.motionPref === "off"; onActivated: root.setSetting("motion", "off") }
              }
              OptRow {
                tab: "glass"; label: "bar pill"
                Chip { label: "glass"; active: root.barPill; onActivated: root.setSetting("barPill", true) }
                Chip { label: "icon only"; active: !root.barPill; onActivated: root.setSetting("barPill", false) }
              }
              OptRow {
                tab: "glass"; label: "meters"
                Chip { label: "flat"; active: !root.gradients; onActivated: root.setSetting("gradients", false) }
                Chip { label: "btop gradient"; active: root.gradients; onActivated: root.setSetting("gradients", true) }
              }

              // ── colour ──
              OptRow {
                tab: "colour"; label: "accent"
                Repeater {
                  model: root.accentPresets
                  Chip {
                    required property var modelData
                    label: modelData.name
                    swatch: modelData.hex ? modelData.hex : Commons.Color.accent
                    active: !root.accentFromWallpaper && root.accentSetting === modelData.name
                    onActivated: root.setSettings({ accent: modelData.name, accentWallpaper: false })
                  }
                }
              }
              OptRow {
                tab: "colour"; label: "custom"
                GlassField {
                  id: hexField
                  width: 84
                  maxLen: 7
                  placeholder: "#rrggbb"
                  text: root.isHex(root.accentSetting) ? root.accentSetting : ""
                  onCommitted: function(v) {
                    v = String(v).trim()
                    if (v.length > 0 && v[0] !== "#") v = "#" + v
                    if (root.isHex(v)) root.setSettings({ accent: v.toLowerCase(), accentWallpaper: false })
                    else if (v.length > 1) root.toast("use a 6-digit hex like #5e5ce6")
                  }
                }
                Chip {
                  visible: root.isHex(root.accentSetting)
                  label: root.accentSetting
                  swatch: root.isHex(root.accentSetting) ? root.accentSetting : "transparent"
                  active: !root.accentFromWallpaper
                  onActivated: root.setSetting("accentWallpaper", false)
                }
              }
              OptRow {
                tab: "colour"; label: "wallpaper"
                Chip {
                  label: root.accentFromWallpaper ? "from wallpaper ✓" : "from wallpaper"
                  active: root.accentFromWallpaper
                  onActivated: {
                    if (root.accentFromWallpaper) root.setSetting("accentWallpaper", false)
                    else { root.setSetting("accentWallpaper", true); root.refreshPalette(false) }
                  }
                }
                Repeater {
                  model: root.wallSwatches
                  Chip {
                    required property string modelData
                    required property int index
                    label: modelData
                    swatch: modelData
                    active: root.accentFromWallpaper && root.wallIndex === index
                    onActivated: root.setSettings({ accentWallpaper: true, accentWallpaperIndex: index })
                  }
                }
                Chip { label: "↻"; onActivated: root.refreshPalette(true) }
              }
              OptRow {
                tab: "colour"; label: ""
                visible: root.settingsTab === "colour" && root.wallSource !== ""
                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: root.wallSource === "theme" ? "swatches from your Omarchy theme (no image reader found for the wallpaper)"
                      : "swatches from your current wallpaper · picking a preset or hex turns this off"
                  color: root.fg
                  opacity: root.dim(0.6)
                  font.family: Style.font.family
                  font.pixelSize: root.fsTiny
                }
              }
              OptRow {
                tab: "colour"; label: "palette"
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
                tab: "colour"; label: "graph"
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

              // ── layout ──
              OptRow {
                tab: "layout"; label: "layout"
                Chip { label: "portrait"; active: !root.landscape; onActivated: root.setSetting("layout", "portrait") }
                Chip { label: "landscape"; active: root.landscape; onActivated: root.setSetting("layout", "landscape") }
              }
              OptRow {
                tab: "layout"; label: "popup"
                Chip { label: "under icon"; active: root.popupPos === "icon"; onActivated: root.setSetting("popupPos", "icon") }
                Chip { label: "centered"; active: root.popupPos === "center"; onActivated: root.setSetting("popupPos", "center") }
              }
              OptRow {
                tab: "layout"; label: "scale"
                GlassSlider { key: "scale"; from: 80; to: 130; stepSize: 5; value: root.uiScalePct; suffix: "%" }
              }
              OptRow {
                tab: "layout"; label: "density"
                Chip { label: "normal"; active: !root.compact; onActivated: root.setSetting("compact", false) }
                Chip { label: "compact"; active: root.compact; onActivated: root.setSetting("compact", true) }
              }
              OptRow {
                tab: "layout"; label: "boxes"
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
                tab: "layout"; label: "order"
                Repeater {
                  model: root.order
                  Chip {
                    required property string modelData
                    required property int index
                    label: (index > 0 ? "‹ " : "") + modelData
                    active: root.showBox(modelData)
                    // Click moves a box one place up; dragging titles still works.
                    onActivated: if (index > 0) root.swapBoxes(modelData, root.order[index - 1])
                  }
                }
                Chip { label: "reset"; onActivated: root.setSetting("order", root.boxNames) }
              }
              OptRow {
                tab: "layout"; label: "text"
                Chip { label: "normal"; active: root.textSize === "normal"; onActivated: root.setSetting("textSize", "normal") }
                Chip { label: "small"; active: root.textSize === "small"; onActivated: root.setSetting("textSize", "small") }
                Chip { label: "tiny"; active: root.textSize === "tiny"; onActivated: root.setSetting("textSize", "tiny") }
              }
              OptRow {
                tab: "layout"; label: "frames"
                Chip { label: "glass boxes"; active: !root.stroke; onActivated: root.setSetting("stroke", false) }
                Chip { label: "btop stroke"; active: root.stroke; onActivated: root.setSetting("stroke", true) }
              }
              OptRow {
                tab: "layout"; label: "line"
                visible: root.settingsTab === "layout" && root.stroke
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
                tab: "layout"; label: "fade"
                Chip { label: "on"; active: root.fade; onActivated: root.setSetting("fade", true) }
                Chip { label: "off"; active: !root.fade; onActivated: root.setSetting("fade", false) }
              }
              OptRow {
                tab: "layout"; label: "shadow"
                Chip { label: "shadow"; active: root.shadow; onActivated: root.setSetting("shadow", true) }
                Chip { label: "no shadow"; active: !root.shadow; onActivated: root.setSetting("shadow", false) }
              }

              // ── header ──
              OptRow {
                tab: "header"; label: "title"
                GlassField {
                  id: titleField
                  text: root.title
                  maxLen: 32
                  onCommitted: function(v) { if (v !== root.title) root.setSetting("title", v) }
                }
              }
              OptRow {
                tab: "header"; label: "title font"
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
                tab: "header"; label: "sys font"
                GlassField {
                  maxLen: 64
                  placeholder: "any installed font…"
                  text: root.builtinFonts.indexOf(root.titleFontKey.toLowerCase()) >= 0 ? "" : root.titleFontKey
                  onCommitted: function(v) { if (v.length > 0 && v !== root.titleFontKey) root.setSetting("titleFont", v) }
                }
              }
              OptRow {
                tab: "header"; label: "position"
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
                tab: "header"; label: "title size"
                GlassSlider { key: "titleSize"; from: 16; to: 46; value: root.titleSize; suffix: "px" }
              }
              OptRow {
                tab: "header"; label: "subtitle"
                GlassSlider { key: "subSize"; from: 7; to: 13; value: root.subSize; suffix: "px" }
              }
              OptRow {
                tab: "header"; label: "avatar"
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
                tab: "header"; label: "hero"
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
                tab: "header"; label: "hero pos"
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
                tab: "header"; label: "photo pos"
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

              // ── data ──
              OptRow {
                tab: "data"; label: "refresh"
                Repeater {
                  model: [1, 2, 3, 5, 10]
                  Chip {
                    required property int modelData
                    label: modelData + "s"
                    active: root.interval === modelData
                    onActivated: root.setSetting("interval", modelData)
                  }
                }
              }
              OptRow {
                tab: "data"; label: "procs"
                GlassSlider { key: "procCount"; from: 3; to: 15; value: root.procCount }
              }
              OptRow {
                tab: "data"; label: "network"
                Chip { label: "bytes  K/s"; active: root.netUnits === "bytes"; onActivated: root.setSetting("netUnits", "bytes") }
                Chip { label: "bits  Kb/s"; active: root.netUnits === "bits"; onActivated: root.setSetting("netUnits", "bits") }
              }
              OptRow {
                tab: "data"; label: "temp"
                Chip { label: "°C"; active: root.tempUnit === "c"; onActivated: root.setSetting("tempUnit", "c") }
                Chip { label: "°F"; active: root.tempUnit === "f"; onActivated: root.setSetting("tempUnit", "f") }
              }
              OptRow {
                tab: "data"; label: "updates"
                Chip { label: "check"; active: root.updateChecks; onActivated: root.setSetting("updateCheck", true) }
                Chip { label: "off"; active: !root.updateChecks; onActivated: root.setSetting("updateCheck", false) }
                Chip {
                  label: updateCheck.running ? "checking…" : "check now"
                  onActivated: { root.updateState = ""; root.setSetting("updateSeen", ""); root.checkForUpdate(true) }
                }
              }
              OptRow {
                tab: "data"; label: "version"
                Text {
                  width: parent.width
                  height: 18
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                  text: "v" + (root.localVersion || "?") + "  ·  " + root.updateStatusText
                  color: root.fg
                  opacity: root.dim(0.7)
                  font.family: Style.font.family
                  font.pixelSize: 9
                }
              }

              // ── presets ──
              OptRow {
                tab: "presets"; label: "saved"
                Repeater {
                  model: root.savedPresets
                  Chip {
                    required property string modelData
                    label: (root.presetDeleteMode ? "✕ " : "") + modelData
                    onActivated: root.presetDeleteMode ? root.deletePreset(modelData) : root.loadPreset(modelData)
                  }
                }
                Text {
                  visible: root.savedPresets.length === 0
                  height: 18
                  verticalAlignment: Text.AlignVCenter
                  text: "none yet"
                  color: root.fg
                  opacity: root.dim(0.6)
                  font.family: Style.font.family
                  font.pixelSize: 9
                }
              }
              OptRow {
                tab: "presets"; label: "save as"
                GlassField {
                  id: presetField
                  width: 110
                  maxLen: 32
                  placeholder: "preset name"
                }
                Chip { label: "save / export"; active: true; onActivated: root.savePreset(presetField.text) }
              }
              OptRow {
                tab: "presets"; label: "manage"
                Chip { label: "import file…"; onActivated: root.importPreset() }
                Chip {
                  visible: root.savedPresets.length > 0
                  label: root.presetDeleteMode ? "done" : "delete…"
                  active: root.presetDeleteMode
                  onActivated: root.presetDeleteMode = !root.presetDeleteMode
                }
              }
              OptRow {
                tab: "presets"; label: "reset"
                Chip {
                  label: root.resetArmed ? "tap again to reset everything" : "reset to defaults"
                  active: root.resetArmed
                  onActivated: {
                    if (root.resetArmed) { root.resetArmed = false; root.resetDefaults() }
                    else { root.resetArmed = true; resetDisarm.restart() }
                  }
                }
              }
              OptRow {
                tab: "presets"; label: ""
                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: "presets are JSON files in ~/.config/boxtop/presets: copy them to another machine, or import one here. Your photo and banner stay local."
                  color: root.fg
                  opacity: root.dim(0.6)
                  font.family: Style.font.family
                  font.pixelSize: root.fsTiny
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
                      color: root.fg; opacity: root.dim(0.6)
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
                      text: root.fmtTemp(root.stats.temp)
                      color: root.fg; opacity: root.dim(0.45)
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
                    color: root.fg; opacity: root.dim(0.85)
                    font.family: Style.font.family; font.pixelSize: root.fsSmall
                  }
                }
                Row {
                  spacing: 5
                  Text { text: "▲"; color: root.pal.up; font.pixelSize: root.fsTiny; anchors.verticalCenter: parent.verticalCenter }
                  Text {
                    text: root.stats ? root.fmtRate(root.netTxRate) : "…"
                    color: root.fg; opacity: root.dim(0.85)
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
                Text { text: "PID"; color: root.fg; opacity: root.dim(0.45); font.family: Style.font.family; font.pixelSize: root.fsTiny; width: 46 }
                Text { text: "PROGRAM"; color: root.fg; opacity: root.dim(0.45); font.family: Style.font.family; font.pixelSize: root.fsTiny; width: parent.width - 46 - 50 - 40 - 12 }
                Text { text: "MEM"; color: root.fg; opacity: root.dim(0.45); font.family: Style.font.family; font.pixelSize: root.fsTiny; width: 50; horizontalAlignment: Text.AlignRight }
                Text { text: "CPU%"; color: root.fg; opacity: root.dim(0.45); font.family: Style.font.family; font.pixelSize: root.fsTiny; width: 40; horizontalAlignment: Text.AlignRight }
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
                    // btop fade: rows dim toward the bottom, but never below
                    // the contrast floor (see root.dim).
                    readonly property real f: root.fade && procBoxItem.rows > 1 ? 1.0 - 0.6 * (index / (procBoxItem.rows - 1)) : 1.0
                    spacing: 4
                    Text {
                      text: procRow.p ? procRow.p.pid : ""
                      color: root.fg; opacity: root.dim(0.35 * procRow.f)
                      font.family: Style.font.family; font.pixelSize: root.fsSmall
                      width: 46
                    }
                    Text {
                      text: procRow.p ? procRow.p.name : ""
                      color: root.fg; opacity: root.dim(0.85 * procRow.f)
                      font.family: Style.font.family; font.pixelSize: root.fsSmall
                      elide: Text.ElideRight
                      width: parent.width - 46 - 50 - 40 - 12
                    }
                    Text {
                      text: procRow.p ? (procRow.p.mem_mb + "M") : ""
                      color: root.fg; opacity: root.dim(0.55 * procRow.f)
                      font.family: Style.font.family; font.pixelSize: root.fsSmall
                      width: 50; horizontalAlignment: Text.AlignRight
                    }
                    Text {
                      text: procRow.p ? procRow.p.cpu_pct.toFixed(1) : ""
                      color: procRow.p && procRow.p.cpu_pct > 1 ? root.ink(root.pal.proc) : root.fg
                      opacity: procRow.p && procRow.p.cpu_pct > 1 ? root.dim(procRow.f) : root.dim(0.4 * procRow.f)
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

      // Glass edge: 1 px hairline around the card and a flat 1 px specular
      // line along the top, drawn above the content (and the hero banner).
      Rectangle {
        visible: root.glassOn
        anchors.fill: parent
        anchors.margins: -panel.padding
        radius: root.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: root.glassBorder
      }
      Rectangle {
        visible: root.glassOn
        readonly property real inset: Math.max(root.cornerRadius * 0.85, 8)
        x: -panel.padding + inset
        y: -panel.padding + 1
        width: parent.width + 2 * panel.padding - 2 * inset
        height: 1
        color: root.glassHighlight
      }

      // Toast (preset saved, update result …)
      Rectangle {
        id: toastPill
        readonly property bool shown: root.toastText !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 4 + (shown ? 0 : 12)
        width: toastLabel.implicitWidth + 22
        height: 22
        radius: root.rounded ? height / 2 : 0
        opacity: shown ? 1 : 0
        visible: opacity > 0
        color: Util.alpha(root.glassComposite, 0.94)
        border.width: 1
        border.color: Util.alpha(root.accentBase, 0.7)
        Behavior on opacity { enabled: root.motion; NumberAnimation { duration: 160 } }
        Behavior on y { enabled: root.motion; SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.2 } }
        Text {
          id: toastLabel
          anchors.centerIn: parent
          text: root.toastText
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: 9
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
      ctx.fillStyle = root.gradients ? root.gradColor(stops, r / rows) : root.levelColor(stops, r / rows)
      ctx.fill()
    }
  }

  function paintBars(ctx, w, h, history, stops) {
    var pitch = root.barPitch
    var cols = Math.floor(w / pitch)
    var n = history.length
    if (root.gradients) {
      var grad = ctx.createLinearGradient(0, h, 0, 0)
      grad.addColorStop(0.0, stops[0])
      grad.addColorStop(0.5, stops[1])
      grad.addColorStop(1.0, stops[2])
      ctx.fillStyle = grad
      ctx.beginPath()
      for (var i = Math.max(0, n - cols); i < n; i++) {
        var c = cols - n + i
        var bh = Math.max(1, Math.round(Math.max(0, Math.min(1, history[i])) * h))
        ctx.rect(c * pitch, h - bh, pitch - 1, bh)
      }
      ctx.fill()
      return
    }
    // Flat: each bar takes the solid colour of its level; one fill per level.
    for (var band = 0; band < 3; band++) {
      ctx.beginPath()
      for (var j = Math.max(0, n - cols); j < n; j++) {
        var v = Math.max(0, Math.min(1, history[j]))
        var lv = v < 0.5 ? 0 : (v < 0.8 ? 1 : 2)
        if (lv !== band) continue
        var bh2 = Math.max(1, Math.round(v * h))
        ctx.rect((cols - n + j) * pitch, h - bh2, pitch - 1, bh2)
      }
      ctx.fillStyle = stops[band]
      ctx.fill()
    }
  }

  function paintLine(ctx, w, h, history, stops) {
    var n = history.length
    if (n < 2) return
    var step = w / (root.historyLen - 1)
    var x0 = w - (n - 1) * step
    function px(i) { return x0 + i * step }
    function py(i) { return h - 1 - Math.max(0, Math.min(1, history[i])) * (h - 2) }

    var fill
    if (root.gradients) {
      fill = ctx.createLinearGradient(0, h, 0, 0)
      fill.addColorStop(0.0, Util.alpha(Qt.lighter(stops[0], 1.0), 0.05))
      fill.addColorStop(1.0, Util.alpha(Qt.lighter(stops[2], 1.0), 0.35))
    } else {
      fill = Util.alpha(Qt.lighter(stops[0], 1.0), 0.16)
    }
    ctx.beginPath()
    ctx.moveTo(px(0), h)
    for (var i = 0; i < n; i++) ctx.lineTo(px(i), py(i))
    ctx.lineTo(px(n - 1), h)
    ctx.closePath()
    ctx.fillStyle = fill
    ctx.fill()

    var stroke = stops[0]
    if (root.gradients) {
      stroke = ctx.createLinearGradient(0, h, 0, 0)
      stroke.addColorStop(0.0, stops[0])
      stroke.addColorStop(0.5, stops[1])
      stroke.addColorStop(1.0, stops[2])
    }
    ctx.beginPath()
    ctx.moveTo(px(0), py(0))
    for (var j = 1; j < n; j++) ctx.lineTo(px(j), py(j))
    ctx.strokeStyle = stroke
    ctx.lineWidth = 1.5
    ctx.lineJoin = "round"
    ctx.stroke()
  }
}
