#!/usr/bin/env python3
"""Light tests for the Python side of Boxtop (no Qt, no network).

Run:  python3 -m unittest discover -s tests -v
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import boxtop  # noqa: E402
import boxtopctl  # noqa: E402
import updater  # noqa: E402


class SamplerTest(unittest.TestCase):
    def test_compiles(self):
        for name in ("boxtop.py", "boxtopctl.py", "updater.py"):
            with open(os.path.join(ROOT, name), encoding="utf-8") as f:
                compile(f.read(), name, "exec")

    def test_sample_shape_and_cost(self):
        s = boxtop.Sampler(8)
        time.sleep(0.2)
        t0 = time.process_time()
        for _ in range(5):
            d = s.sample()
        per_tick_ms = (time.process_time() - t0) / 5 * 1000
        for key in ("cpu", "cores", "ram_pct", "procs", "net_rx_bytes", "uptime"):
            self.assertIn(key, d)
        self.assertLessEqual(len(d["procs"]), 8)
        print("\n  sampler CPU per tick: %.1f ms" % per_tick_ms)
        self.assertLess(per_tick_ms, 60)  # generous bound for slow CI boxes


class CtlTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.patches = [
            mock.patch.object(boxtopctl, "PRESET_DIR", os.path.join(self.tmp, "presets")),
            mock.patch.object(boxtopctl, "SETTINGS_FILE", os.path.join(self.tmp, "settings.json")),
            mock.patch.object(boxtopctl, "HYPR_TOGGLE", os.path.join(self.tmp, "toggles/boxtop-glass.lua")),
            mock.patch.object(boxtopctl, "THEME_COLORS", os.path.join(self.tmp, "colors.toml")),
            mock.patch.object(boxtopctl, "WALLPAPER", os.path.join(self.tmp, "nowallpaper")),
            mock.patch.object(boxtopctl, "CACHE_DIR", os.path.join(self.tmp, "cache")),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_cmd(self, *argv):
        out = io.StringIO()
        with mock.patch("sys.stdout", out):
            rc = boxtopctl.main(list(argv))
        return rc, out.getvalue().strip()

    def test_presets_roundtrip_strip_local_keys(self):
        rc, _ = self.run_cmd("preset-save", "My look", "--json",
                             json.dumps({"id": "x", "glassStyle": "dark", "hero": "/a.png", "radius": 20}))
        self.assertEqual(rc, 0)
        rc, out = self.run_cmd("preset-list")
        self.assertEqual(json.loads(out), ["My look"])
        rc, out = self.run_cmd("preset-load", "My look")
        self.assertEqual(json.loads(out), {"glassStyle": "dark", "radius": 20})

    def test_bad_preset_name_rejected(self):
        with mock.patch("sys.stderr", io.StringIO()):
            rc, _ = self.run_cmd("preset-load", "../../etc/passwd")
        self.assertEqual(rc, 1)

    def test_mirror_restore(self):
        self.run_cmd("mirror", "--json", json.dumps({"id": "x", "accent": "#112233"}))
        rc, out = self.run_cmd("restore")
        self.assertEqual(json.loads(out), {"accent": "#112233"})

    def test_hypr_glass_only_reloads_on_change(self):
        with mock.patch("shutil.which", return_value=None):
            _, a = self.run_cmd("hypr-glass", "on", "70")
            _, b = self.run_cmd("hypr-glass", "on", "70")
            _, c = self.run_cmd("hypr-glass", "off")
        self.assertTrue(json.loads(a)["changed"])
        self.assertFalse(json.loads(b)["changed"])
        self.assertTrue(json.loads(c)["changed"])
        self.assertFalse(os.path.exists(boxtopctl.HYPR_TOGGLE))
        self.assertNotIn("gradient", boxtopctl.glass_lua(50))

    def test_palette_falls_back_to_theme(self):
        with open(boxtopctl.THEME_COLORS, "w") as f:
            f.write('accent = "#89b4fa"\nblue = "#89b4fa"\nmagenta = "#f5c2e7"\ngreen = "#a6e3a1"\n')
        rc, out = self.run_cmd("palette")
        d = json.loads(out)
        self.assertEqual(d["source"], "theme")
        self.assertEqual(d["colors"][:3], ["#89b4fa", "#f5c2e7", "#a6e3a1"])

    def test_swatches_distinct(self):
        hist = [(500, (30, 30, 46)), (300, (137, 180, 250)), (290, (140, 182, 248)), (200, (245, 194, 231)),
                (100, (166, 227, 161))]
        sw = boxtopctl.pick_swatches(hist, 5)
        self.assertGreaterEqual(len(sw), 3)
        self.assertEqual(len(sw), len(set(sw)))


def make_plugin(dirpath, version):
    os.makedirs(dirpath, exist_ok=True)
    with open(os.path.join(dirpath, "manifest.json"), "w") as f:
        json.dump({"id": "maftuuh.boxtop", "version": version}, f)
    with open(os.path.join(dirpath, "VERSION"), "w") as f:
        f.write(version + "\n")
    for name in ("Panel.qml", "boxtop.py"):
        with open(os.path.join(dirpath, name), "w") as f:
            f.write("# " + version + "\n")


class UpdaterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.inst = os.path.join(self.tmp, "maftuuh.boxtop")
        make_plugin(self.inst, "1.5.0")
        self.patches = [
            mock.patch.object(updater, "HERE", self.inst),
            mock.patch.object(updater, "CACHE_DIR", os.path.join(self.tmp, "cache")),
            mock.patch.object(updater, "CACHE_FILE", os.path.join(self.tmp, "cache/update.json")),
            mock.patch.object(updater, "BACKUP_DIR", os.path.join(self.tmp, "cache/backups")),
            mock.patch.object(updater, "notify", lambda *a: None),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_version_key(self):
        self.assertGreater(updater.version_key("v1.10.0"), updater.version_key("1.9.9"))
        self.assertEqual(updater.clean_version("v2"), "2.0.0")

    def test_check_release_newer_and_cached(self):
        calls = []

        def fake_rel():
            calls.append(1)
            return ("v1.6.0", "## v1.6.0\n- **glass** fix\n", "https://example/t.tar.gz")
        with mock.patch.object(updater, "latest_release", fake_rel):
            a = updater.do_check()
            b = updater.do_check()
        self.assertTrue(a["available"])
        self.assertEqual(a["latest"], "1.6.0")
        self.assertIn("glass fix", a["notes"])
        self.assertEqual(len(calls), 1, "second check must come from the cache")
        self.assertEqual(b["latest"], "1.6.0")

    def test_check_offline_is_quiet(self):
        def boom():
            raise OSError("offline")
        with mock.patch.object(updater, "latest_release", boom):
            d = updater.do_check(force=True)
        self.assertFalse(d["available"])
        self.assertEqual(d["error"], "OSError")

    def _tarball(self, version, broken=False):
        src = os.path.join(self.tmp, "src", "omarchy-boxtop-abc")
        make_plugin(src, version)
        if broken:
            os.unlink(os.path.join(src, "Panel.qml"))
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as tar:
            tar.add(src, arcname="omarchy-boxtop-abc")
        shutil.rmtree(os.path.join(self.tmp, "src"))
        return buf.getvalue()

    def test_apply_tarball_swaps_and_backs_up(self):
        data = self._tarball("1.6.0")
        with mock.patch.object(updater, "latest_release", lambda: ("v1.6.0", "", "https://x/t.tgz")), \
                mock.patch.object(updater, "http_get", lambda *a, **k: data), \
                mock.patch.object(updater, "is_git", lambda root=None: False):
            res = updater.do_apply()
        self.assertTrue(res["ok"], res)
        self.assertEqual(updater.local_version(self.inst), "1.6.0")
        self.assertEqual(len(os.listdir(updater.BACKUP_DIR)), 1)

    def test_apply_tarball_broken_keeps_old(self):
        data = self._tarball("1.6.0", broken=True)
        with mock.patch.object(updater, "latest_release", lambda: ("v1.6.0", "", "https://x/t.tgz")), \
                mock.patch.object(updater, "http_get", lambda *a, **k: data), \
                mock.patch.object(updater, "is_git", lambda root=None: False):
            res = updater.do_apply()
        self.assertFalse(res["ok"])
        self.assertEqual(updater.local_version(self.inst), "1.5.0")
        self.assertTrue(os.path.isfile(os.path.join(self.inst, "Panel.qml")))

    @unittest.skipUnless(shutil.which("git"), "git missing")
    def test_apply_git_fast_forward_and_rollback(self):
        origin = os.path.join(self.tmp, "origin")
        make_plugin(origin, "1.5.0")
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
                   GIT_COMMITTER_EMAIL="t@t")
        run = lambda *a, cwd=origin: subprocess.run(a, cwd=cwd, env=env, check=True, capture_output=True)
        run("git", "init", "-q", "-b", "main")
        run("git", "add", "-A")
        run("git", "commit", "-qm", "v1.5.0")
        shutil.rmtree(self.inst)
        run("git", "clone", "-q", origin, self.inst, cwd=self.tmp)
        make_plugin(origin, "1.6.0")
        run("git", "commit", "-qam", "v1.6.0")
        with mock.patch.object(updater, "latest_release", lambda: None), \
                mock.patch.object(updater, "remote_version_file", lambda: "1.6.0"):
            res = updater.do_apply()
        self.assertTrue(res["ok"], res)
        self.assertEqual(res["method"], "git")
        self.assertEqual(updater.local_version(self.inst), "1.6.0")

        # A broken upstream commit is rolled back.
        os.unlink(os.path.join(origin, "Panel.qml"))
        with open(os.path.join(origin, "VERSION"), "w") as f:
            f.write("1.7.0\n")
        run("git", "commit", "-qam", "broken")
        with mock.patch.object(updater, "latest_release", lambda: None), \
                mock.patch.object(updater, "remote_version_file", lambda: "1.7.0"):
            res = updater.do_apply()
        self.assertFalse(res["ok"])
        self.assertTrue(os.path.isfile(os.path.join(self.inst, "Panel.qml")))
        self.assertEqual(updater.local_version(self.inst), "1.6.0")


class QmlStaticTest(unittest.TestCase):
    """Cheap textual checks on Panel.qml (no Qt needed)."""

    def setUp(self):
        with open(os.path.join(ROOT, "Panel.qml"), encoding="utf-8") as f:
            self.qml = f.read()

    def test_braces_balanced(self):
        depth = 0
        for ch in self.qml:
            depth += ch == "{"
            depth -= ch == "}"
            self.assertGreaterEqual(depth, 0)
        self.assertEqual(depth, 0)

    def test_gradients_only_behind_classic_switch(self):
        # Every Gradient / createLinearGradient must sit behind root.gradients.
        lines = self.qml.splitlines()
        for i, line in enumerate(lines):
            if "createLinearGradient" in line or "gradient: Gradient" in line:
                window = "\n".join(lines[max(0, i - 6):i + 1])
                self.assertIn("root.gradients", window, "unguarded gradient at line %d" % (i + 1))


if __name__ == "__main__":
    unittest.main()
