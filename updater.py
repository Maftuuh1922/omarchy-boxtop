#!/usr/bin/env python3
"""Boxtop built-in updater.

  updater.py check [--force]
      Print one JSON line describing whether a newer Boxtop exists:
        {"available": bool, "current": "1.5.0", "latest": "1.5.1",
         "kind": "release" | "version" | "commit", "notes": "...", "checked": ts}
      Order of sources: the latest GitHub release tag; when the repo has no
      releases, the VERSION file on main and, for git installs, whether main
      has commits the local checkout lacks. The answer is cached in
      ~/.cache/boxtop/update.json and reused for CHECK_EVERY seconds, so
      calling this often costs no network traffic. Offline or rate-limited:
      prints the cached answer (or "available": false) and exits 0.

  updater.py apply
      Update this install in place and print {"ok": bool, "from", "to",
      "method", "error"}:
        git clone -> fetch + fast-forward main (or the release tag), validate,
                     hard-reset back to the old commit on any failure
        otherwise -> download the release (or main) tarball, validate it,
                     back up the current folder to ~/.cache/boxtop/backups,
                     swap the new folder in, restore the backup on failure
      Sends a desktop notification with the result (it survives the shell
      reload that follows a successful update).
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

REPO = "Maftuuh1922/omarchy-boxtop"
BRANCH = "main"
PLUGIN_ID = "maftuuh.boxtop"
API = "https://api.github.com/repos/" + REPO
RAW = "https://raw.githubusercontent.com/%s/%s/" % (REPO, BRANCH)
CHECK_EVERY = 6 * 3600
TIMEOUT = 6

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "boxtop")
CACHE_FILE = os.path.join(CACHE_DIR, "update.json")
BACKUP_DIR = os.path.join(CACHE_DIR, "backups")
REQUIRED = ("manifest.json", "Panel.qml", "boxtop.py")


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def version_key(value):
    """'v1.4.0-beta' -> (1, 4, 0)"""
    parts = [int(n) for n in re.findall(r"\d+", str(value or ""))][:3]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def clean_version(value):
    return ".".join(str(n) for n in version_key(value))


def local_version(root=HERE):
    try:
        with open(os.path.join(root, "VERSION"), encoding="utf-8") as f:
            v = f.read().strip()
            if v:
                return clean_version(v)
    except OSError:
        pass
    try:
        with open(os.path.join(root, "manifest.json"), encoding="utf-8") as f:
            return clean_version(json.load(f).get("version", "0.0.0"))
    except (OSError, ValueError):
        return "0.0.0"


def http_get(url, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={
        "Accept": accept, "User-Agent": "boxtop-updater"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def http_json(url):
    return json.loads(http_get(url).decode("utf-8"))


def is_git(root=HERE):
    return os.path.isdir(os.path.join(root, ".git")) and shutil.which("git") is not None


def git(root, *args, check=True):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True,
                          timeout=60, check=check,
                          env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))


def snippet(text, lines=6, width=90):
    out = []
    for ln in str(text or "").splitlines():
        ln = re.sub(r"^[#>\s]+", "", ln.strip())
        ln = re.sub(r"[*_`]", "", ln)
        if not ln:
            continue
        out.append(ln[:width])
        if len(out) >= lines:
            break
    return "\n".join(out)


def read_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_cache(data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, CACHE_FILE)
    except OSError:
        pass


def latest_release():
    """(tag, notes, tarball_url) or None when the repo has no releases."""
    try:
        rel = http_json(API + "/releases/latest")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise
    tarball = rel.get("tarball_url")
    for asset in rel.get("assets") or []:
        if str(asset.get("name", "")).endswith(".tar.gz"):
            tarball = asset.get("browser_download_url") or tarball
            break
    return rel.get("tag_name") or "", rel.get("body") or rel.get("name") or "", tarball


def remote_version_file():
    try:
        return clean_version(http_get(RAW + "VERSION", accept="text/plain").decode().strip())
    except urllib.error.HTTPError:
        try:
            return clean_version(json.loads(http_get(RAW + "manifest.json", accept="application/json")).get("version"))
        except Exception:
            return ""


def commits_ahead(local_sha):
    """Commits on main that the local checkout lacks: (count, notes)."""
    cmp = http_json("%s/compare/%s...%s" % (API, local_sha, BRANCH))
    msgs = [c.get("commit", {}).get("message", "").splitlines()[0]
            for c in cmp.get("commits", [])][::-1]
    return int(cmp.get("ahead_by", 0)), "\n".join("• " + m[:86] for m in msgs[:5])


def do_check(force=False):
    now = int(time.time())
    current = local_version()
    cached = read_cache()
    if (not force and cached and cached.get("current") == current
            and now - int(cached.get("checked", 0)) < CHECK_EVERY):
        return cached

    result = {"available": False, "current": current, "latest": current,
              "kind": "", "notes": "", "checked": now}
    try:
        rel = latest_release()
        if rel is not None:
            tag, notes, tarball = rel
            result["latest"] = clean_version(tag)
            if version_key(tag) > version_key(current):
                result.update(available=True, kind="release", tag=tag,
                              notes=snippet(notes), tarball=tarball)
        else:
            remote = remote_version_file()
            if remote and version_key(remote) > version_key(current):
                result.update(available=True, kind="version", latest=remote,
                              notes="New version on " + BRANCH)
            elif is_git():
                sha = git(HERE, "rev-parse", "HEAD").stdout.strip()
                ahead, notes = commits_ahead(sha)
                if ahead > 0:
                    result.update(available=True, kind="commit",
                                  latest="%s+%d" % (current, ahead), notes=notes)
    except Exception as e:  # offline, rate limit, DNS ...
        if cached and cached.get("current") == current:
            cached["stale"] = True
            return cached
        result["error"] = type(e).__name__
        result["checked"] = now - CHECK_EVERY + 1800  # retry in 30 min, not 6 h
        write_cache(result)
        return result
    write_cache(result)
    return result


# ── apply ────────────────────────────────────────────────────────────────
def validate(root):
    for name in REQUIRED:
        if not os.path.isfile(os.path.join(root, name)):
            raise RuntimeError("missing " + name)
    with open(os.path.join(root, "manifest.json"), encoding="utf-8") as f:
        man = json.load(f)
    if man.get("id") != PLUGIN_ID:
        raise RuntimeError("manifest id mismatch")
    for py in ("boxtop.py", "updater.py", "boxtopctl.py"):
        p = os.path.join(root, py)
        if os.path.isfile(p):
            with open(p, encoding="utf-8") as f:
                compile(f.read(), p, "exec")
    if shutil.which("omarchy-plugin-validate"):
        r = subprocess.run(["omarchy-plugin-validate", root], capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            raise RuntimeError("omarchy-plugin-validate failed: " + (r.stderr or r.stdout).strip()[:200])


def apply_git(info):
    old = git(HERE, "rev-parse", "HEAD").stdout.strip()
    if git(HERE, "status", "--porcelain", "--untracked-files=no").stdout.strip():
        raise RuntimeError("local changes in " + HERE + "; commit or stash them first")
    try:
        git(HERE, "fetch", "--quiet", "--tags", "origin")
        target = "FETCH_HEAD"
        if info.get("kind") == "release" and info.get("tag"):
            target = "refs/tags/" + info["tag"]
            # Only fast-forward; a tag behind HEAD means we are already newer.
            git(HERE, "merge-base", "--is-ancestor", "HEAD", target)
        else:
            git(HERE, "fetch", "--quiet", "origin", BRANCH)
        git(HERE, "merge", "--ff-only", target)
        validate(HERE)
    except Exception as e:
        git(HERE, "reset", "--hard", old, check=False)
        if isinstance(e, subprocess.CalledProcessError):
            raise RuntimeError((e.stderr or e.stdout or str(e)).strip()[:200])
        raise
    return "git"


def find_plugin_root(top):
    for dirpath, _dirs, files in os.walk(top):
        if "manifest.json" in files and "Panel.qml" in files:
            return dirpath
    raise RuntimeError("archive has no plugin folder")


def prune_backups(keep=2):
    try:
        olds = sorted(os.listdir(BACKUP_DIR))
    except OSError:
        return
    for name in olds[:-keep]:
        shutil.rmtree(os.path.join(BACKUP_DIR, name), ignore_errors=True)


def apply_tarball(info):
    url = info.get("tarball") or "https://codeload.github.com/%s/tar.gz/refs/heads/%s" % (REPO, BRANCH)
    data = http_get(url, accept="application/octet-stream")
    work = tempfile.mkdtemp(prefix="boxtop-update-")
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
            base = os.path.realpath(work)
            for m in tar.getmembers():
                dest = os.path.realpath(os.path.join(work, m.name))
                if not dest.startswith(base + os.sep) or m.issym() or m.islnk():
                    raise RuntimeError("unsafe path in archive: " + m.name)
            if hasattr(tarfile, "data_filter"):
                tar.extractall(work, filter="data")
            else:
                tar.extractall(work)
        new_root = find_plugin_root(work)
        validate(new_root)

        os.makedirs(BACKUP_DIR, exist_ok=True)
        backup = os.path.join(BACKUP_DIR, "%s-%s" % (time.strftime("%Y%m%d-%H%M%S"), local_version()))
        shutil.copytree(HERE, backup, symlinks=True)
        try:
            # Swap contents in place so the folder (and anything that points at
            # it) stays the same path.
            for name in os.listdir(HERE):
                p = os.path.join(HERE, name)
                shutil.rmtree(p) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
            for name in os.listdir(new_root):
                s = os.path.join(new_root, name)
                d = os.path.join(HERE, name)
                shutil.copytree(s, d, symlinks=True) if os.path.isdir(s) else shutil.copy2(s, d)
            validate(HERE)
        except Exception:
            for name in os.listdir(HERE):
                p = os.path.join(HERE, name)
                shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
            for name in os.listdir(backup):
                s = os.path.join(backup, name)
                d = os.path.join(HERE, name)
                shutil.copytree(s, d, symlinks=True) if os.path.isdir(s) else shutil.copy2(s, d)
            raise
        prune_backups()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return "tarball"


def notify(title, body, ok):
    for cmd in (["omarchy-notification-send", "-g", "󰚰" if ok else "󰀦", title, body],
                ["notify-send", "-a", "Boxtop", title, body]):
        if shutil.which(cmd[0]):
            try:
                subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
                return
            except (OSError, subprocess.SubprocessError):
                continue


def do_apply():
    before = local_version()
    info = do_check(force=True)
    out = {"ok": False, "from": before, "to": info.get("latest", before), "method": "", "error": ""}
    if not info.get("available"):
        out["error"] = info.get("error") and "offline" or "already up to date"
        out["ok"] = not info.get("error")
        return out
    try:
        out["method"] = apply_git(info) if is_git() else apply_tarball(info)
        out["ok"] = True
        out["to"] = local_version() if info.get("kind") != "commit" else info.get("latest")
        try:
            os.unlink(CACHE_FILE)
        except OSError:
            pass
        notify("Boxtop updated", "v%s → v%s" % (before, out["to"]), True)
    except Exception as e:
        out["error"] = str(e)[:240] or type(e).__name__
        notify("Boxtop update failed", out["error"] + " (rolled back)", False)
    return out


def main(argv):
    cmd = argv[0] if argv else "check"
    if cmd == "check":
        emit(do_check(force="--force" in argv))
        return 0
    if cmd == "apply":
        res = do_apply()
        emit(res)
        return 0 if res["ok"] else 1
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
