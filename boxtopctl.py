#!/usr/bin/env python3
"""Boxtop helper: wallpaper palette, Hyprland glass blur, settings files.

Every command is a short one-shot run started by the widget on a user action
(or once when the card opens), never on a timer, so the sampler budget is
untouched.

  boxtopctl.py palette [--count N] [--force]
      Print {"source", "path", "colors": [hex, ...]} with 3-5 dominant
      colours of the current Omarchy wallpaper. Uses Pillow when installed,
      then ImageMagick, then falls back to the active theme's colors.toml.
      Results are cached per wallpaper path + mtime in ~/.cache/boxtop.

  boxtopctl.py hypr-glass on BLUR | off
      Write (or remove) ~/.local/state/omarchy/toggles/hypr/boxtop-glass.lua,
      which Omarchy's Hyprland config loads automatically, then reload
      Hyprland only when the file actually changed. BLUR is 0-100.

  boxtopctl.py mirror [--json S] (or JSON on stdin) save ~/.config/boxtop/settings.json
  boxtopctl.py restore                            print it (or nothing)
  boxtopctl.py preset-save NAME [--json S]        save a look preset
  boxtopctl.py preset-list                        print ["name", ...]
  boxtopctl.py preset-load NAME                   print the preset JSON
  boxtopctl.py preset-import PATH                 copy a .json file in, print its name
  boxtopctl.py preset-delete NAME
"""
import colorsys
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HOME = os.path.expanduser("~")
STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local/state")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")

CONF_DIR = os.path.join(CONFIG, "boxtop")
PRESET_DIR = os.path.join(CONF_DIR, "presets")
SETTINGS_FILE = os.path.join(CONF_DIR, "settings.json")
CACHE_DIR = os.path.join(CACHE, "boxtop")
WALLPAPER = os.path.join(STATE, "omarchy/current/background")
THEME_COLORS = os.path.join(STATE, "omarchy/current/theme/colors.toml")
HYPR_TOGGLE = os.path.join(STATE, "omarchy/toggles/hypr/boxtop-glass.lua")

# Keys that describe the look and can travel between machines. Paths to
# uploaded images, the update bookkeeping and the box order stay local.
LOCAL_ONLY = {"id", "avatar", "hero", "updateSeen", "accentSwatches"}
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,31}$")
VIDEO_EXT = (".mp4", ".webm", ".mkv", ".mov", ".avi")


def atomic_write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")


# ── palette ──────────────────────────────────────────────────────────────
def hexc(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def from_hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def theme_colors():
    out = {}
    try:
        with open(THEME_COLORS, encoding="utf-8") as f:
            for line in f:
                m = re.match(r'\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"', line)
                if m:
                    out[m.group(1)] = m.group(2).lower()
    except OSError:
        pass
    return out


def pillow_histogram(path):
    try:
        from PIL import Image  # optional
    except ImportError:
        return None
    try:
        with Image.open(path) as im:
            im.draft("RGB", (128, 128))  # cheap JPEG decode at reduced size
            im = im.convert("RGB")
            im.thumbnail((64, 64))
            q = im.quantize(colors=10, method=Image.Quantize.FASTOCTREE)
            pal = q.getpalette()
            counts = q.getcolors() or []
        return [(n, tuple(pal[i * 3:i * 3 + 3])) for n, i in counts]
    except Exception:
        return None


def magick_histogram(path):
    exe = shutil.which("magick") or shutil.which("convert")
    if not exe:
        return None
    try:
        out = subprocess.run(
            [exe, path + "[0]", "-resize", "64x64", "-colors", "10", "-depth", "8",
             "-format", "%c", "histogram:info:-"],
            capture_output=True, text=True, timeout=8).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    hist = []
    for line in out.splitlines():
        m = re.match(r"\s*(\d+):.*?(#[0-9A-Fa-f]{6})", line)
        if m:
            hist.append((int(m.group(1)), from_hex(m.group(2))))
    return hist or None


def pick_swatches(hist, count):
    """Dominant, distinct, usable accent colours from a (count, rgb) histogram."""
    scored = []
    for n, rgb in hist:
        h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
        usable = s >= 0.18 and 0.12 <= l <= 0.9
        scored.append((n * (0.35 + s) * (1.0 if usable else 0.08), (h, l, s), rgb))
    scored.sort(key=lambda t: t[0], reverse=True)
    picked, hls = [], []
    for _, (h, l, s), rgb in scored:
        # Lift dull or very dark picks so they work as an accent on glass.
        if s < 0.35 or l < 0.35 or l > 0.8:
            s = max(s, 0.45)
            l = min(max(l, 0.45), 0.72)
            rgb = tuple(c * 255 for c in colorsys.hls_to_rgb(h, l, s))
        # Keep swatches visibly different: hue apart, or clearly lighter/darker.
        if any(min(abs(h - ph), 1 - abs(h - ph)) < 0.045 and abs(l - pl) < 0.16
               for ph, pl in hls):
            continue
        picked.append(rgb)
        hls.append((h, l))
        if len(picked) >= count:
            break
    return [hexc(c) for c in picked]


def cmd_palette(args):
    count = 5
    if "--count" in args:
        try:
            count = max(3, min(5, int(args[args.index("--count") + 1])))
        except (IndexError, ValueError):
            pass
    force = "--force" in args
    path = os.path.realpath(WALLPAPER) if os.path.exists(WALLPAPER) else ""
    key = ""
    if path:
        try:
            st = os.stat(path)
            key = f"{path}:{int(st.st_mtime)}:{st.st_size}:{count}"
        except OSError:
            path = ""
    cache_file = os.path.join(CACHE_DIR, "palette.json")
    if key and not force:
        try:
            with open(cache_file, encoding="utf-8") as f:
                cached = json.load(f)
            if cached.get("key") == key:
                emit(cached["result"])
                return 0
        except (OSError, ValueError, KeyError):
            pass

    colors, source, mean = [], "theme", ""
    if path and not path.lower().endswith(VIDEO_EXT):
        hist = pillow_histogram(path) or magick_histogram(path)
        if hist:
            colors = pick_swatches(hist, count)
            source = "wallpaper"
            total = float(sum(n for n, _ in hist)) or 1.0
            mean = hexc([sum(n * c[i] for n, c in hist) / total for i in range(3)])
    if len(colors) < 3:
        tc = theme_colors()
        seen = list(colors)
        for k in ("accent", "blue", "magenta", "cyan", "green", "orange", "red", "yellow"):
            v = tc.get(k)
            if v and v not in seen:
                seen.append(v)
        if len(seen) > len(colors):
            source = "theme" if not colors else "wallpaper+theme"
        colors = seen[:count]
    result = {"source": source, "path": path, "colors": colors, "mean": mean}
    if key:
        try:
            atomic_write(cache_file, json.dumps({"key": key, "result": result}))
        except OSError:
            pass
    emit(result)
    return 0


# ── Hyprland blur toggle ─────────────────────────────────────────────────
def glass_lua(blur):
    blur = max(0, min(100, int(blur)))
    size = 2 + round(blur * 0.12)          # 2..14
    passes = 1 + round(blur / 34)          # 1..4
    return (
        "-- Generated by the Boxtop plugin (maftuuh.boxtop): blur behind its glass card.\n"
        "-- Turn it off from the card (glass -> blur behind -> off) or delete this file.\n"
        "hl.config({ decoration = { blur = { enabled = true, size = %d, passes = %d,"
        " popups = true } } })\n"
        "hl.layer_rule({ match = { namespace = \"^(omarchy-keyboard-panel)$\" },"
        " blur = true, ignore_alpha = 0.05 })\n" % (size, passes)
    )


def cmd_hypr_glass(args):
    want = args[0] if args else "off"
    changed = False
    if want == "on":
        blur = args[1] if len(args) > 1 else "50"
        try:
            text = glass_lua(float(blur))
        except ValueError:
            text = glass_lua(50)
        try:
            with open(HYPR_TOGGLE, encoding="utf-8") as f:
                changed = f.read() != text
        except OSError:
            changed = True
        if changed:
            atomic_write(HYPR_TOGGLE, text)
    else:
        if os.path.exists(HYPR_TOGGLE):
            os.unlink(HYPR_TOGGLE)
            changed = True
    if changed and shutil.which("hyprctl"):
        subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=10)
    emit({"blur": want == "on", "changed": changed, "file": HYPR_TOGGLE})
    return 0


# ── settings mirror + presets ────────────────────────────────────────────
def read_stdin_json(args=()):
    args = list(args)
    raw = args[args.index("--json") + 1] if "--json" in args[:-1] else sys.stdin.read()
    data = json.loads(raw or "{}")
    if not isinstance(data, dict):
        raise ValueError("expected a JSON object")
    return data


def portable(data):
    return {k: v for k, v in data.items() if k not in LOCAL_ONLY}


def preset_path(name):
    if not NAME_RE.match(name or ""):
        raise ValueError("invalid preset name")
    return os.path.join(PRESET_DIR, name + ".json")


def cmd_mirror(args):
    data = read_stdin_json(args)
    data.pop("id", None)
    atomic_write(SETTINGS_FILE, json.dumps(data, indent=2, sort_keys=True) + "\n")
    return 0


def cmd_restore(_args):
    try:
        with open(SETTINGS_FILE, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            emit(data)
    except (OSError, ValueError):
        pass
    return 0


def cmd_preset_save(args):
    name = args[0] if args else ""
    data = portable(read_stdin_json(args[1:]))
    data["_boxtopPreset"] = 1
    atomic_write(preset_path(name), json.dumps(data, indent=2, sort_keys=True) + "\n")
    emit({"saved": name})
    return 0


def cmd_preset_list(_args):
    try:
        names = sorted(f[:-5] for f in os.listdir(PRESET_DIR)
                       if f.endswith(".json") and NAME_RE.match(f[:-5]))
    except OSError:
        names = []
    emit(names)
    return 0


def cmd_preset_load(args):
    with open(preset_path(args[0] if args else ""), encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("preset is not a JSON object")
    data.pop("_boxtopPreset", None)
    emit(portable(data))
    return 0


def cmd_preset_import(args):
    src = args[0] if args else ""
    with open(src, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("not a JSON object")
    base = re.sub(r"[^A-Za-z0-9 _.-]", "", os.path.splitext(os.path.basename(src))[0])[:32] or "imported"
    if not base[0].isalnum():
        base = "p" + base[:31]
    data = portable(data)
    data["_boxtopPreset"] = 1
    atomic_write(preset_path(base), json.dumps(data, indent=2, sort_keys=True) + "\n")
    emit({"imported": base})
    return 0


def cmd_preset_delete(args):
    p = preset_path(args[0] if args else "")
    if os.path.exists(p):
        os.unlink(p)
    return 0


COMMANDS = {
    "palette": cmd_palette,
    "hypr-glass": cmd_hypr_glass,
    "mirror": cmd_mirror,
    "restore": cmd_restore,
    "preset-save": cmd_preset_save,
    "preset-list": cmd_preset_list,
    "preset-load": cmd_preset_load,
    "preset-import": cmd_preset_import,
    "preset-delete": cmd_preset_delete,
}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        sys.stderr.write(__doc__)
        return 2
    try:
        return COMMANDS[argv[0]](argv[1:])
    except (OSError, ValueError) as e:
        sys.stderr.write(f"boxtopctl: {e}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
