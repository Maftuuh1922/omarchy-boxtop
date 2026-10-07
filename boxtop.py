#!/usr/bin/env python3
"""Boxtop: btop-style system data for the Omarchy bar.

Usage:
  boxtop.py [COUNT]                   print one JSON sample and exit
  boxtop.py --watch INTERVAL [COUNT]  print one JSON line every INTERVAL seconds

Watch mode keeps the previous sample in memory, so CPU usage (overall,
per-core and per-process) is a delta between ticks with no sleeping inside a
sample. The shell starts it when the card opens and stops it when it closes.
"""
import json
import os
import pwd
import shutil
import sys
import time

CLK_TCK = os.sysconf("SC_CLK_TCK")
PAGE_KB = os.sysconf("SC_PAGE_SIZE") // 1024


def read(path):
    with open(path, "rb") as f:
        return f.read()


# ── CPU ──
def cpu_times():
    """Return {name: (idle, total)} for 'cpu' and every 'cpuN' line."""
    out = {}
    for line in read("/proc/stat").split(b"\n"):
        if not line.startswith(b"cpu"):
            break
        p = line.split()
        v = [int(x) for x in p[1:]]
        idle = v[3] + (v[4] if len(v) > 4 else 0)
        out[p[0].decode()] = (idle, sum(v))
    return out


def pct(prev, cur):
    di = cur[0] - prev[0]
    dt = cur[1] - prev[1]
    if dt <= 0:
        return 0.0
    return max(0.0, min(100.0, 100.0 * (1.0 - di / dt)))


def cpu_freq():
    try:
        base = "/sys/devices/system/cpu"
        freqs = []
        for d in os.listdir(base):
            if d.startswith("cpu") and d[3:].isdigit():
                try:
                    freqs.append(int(read(f"{base}/{d}/cpufreq/scaling_cur_freq")) / 1000)
                except OSError:
                    pass
        return round(sum(freqs) / len(freqs)) if freqs else None
    except OSError:
        return None


def find_temp_path():
    base = "/sys/class/thermal"
    try:
        zones = sorted(z for z in os.listdir(base) if z.startswith("thermal_zone"))
    except OSError:
        return None
    types = {}
    for z in zones:
        try:
            types[read(f"{base}/{z}/type").decode().strip()] = f"{base}/{z}/temp"
        except OSError:
            pass
    for name in ("x86_pkg_temp", "TCPU", "INT3400 Thermal", "SEN1", "acpitz"):
        if name in types:
            return types[name]
    return f"{base}/{zones[0]}/temp" if zones else None


def cpu_temp(path):
    if not path:
        return None
    try:
        return int(read(path)) // 1000
    except (OSError, ValueError):
        return None


def cpu_model():
    try:
        for ln in read("/proc/cpuinfo").decode(errors="replace").splitlines():
            if ln.startswith("model name"):
                name = ln.split(":", 1)[1]
                for junk in ("(R)", "(TM)", "Intel ", "AMD ", "CPU ", " Processor", "Core "):
                    name = name.replace(junk, " ")
                return " ".join(name.split("@")[0].split())[:22]
    except OSError:
        pass
    return "cpu"


# ── MEM / DISK / NET / UPTIME ──
def meminfo():
    d = {}
    for line in read("/proc/meminfo").split(b"\n"):
        k, _, v = line.partition(b":")
        if v:
            d[k] = int(v.split()[0])
    total = d[b"MemTotal"]
    avail = d.get(b"MemAvailable", d[b"MemFree"])
    cached = max(0, d.get(b"Cached", 0) + d.get(b"SReclaimable", 0) - d.get(b"Shmem", 0))
    st = d.get(b"SwapTotal", 0)
    sf = d.get(b"SwapFree", 0)
    return {"used": total - avail, "total": total, "cached": cached,
            "swap_used": st - sf, "swap_total": st}


def net_bytes():
    rx = tx = 0
    try:
        for line in read("/proc/net/dev").split(b"\n")[2:]:
            p = line.split()
            if len(p) < 10 or p[0] == b"lo:":
                continue
            rx += int(p[1])
            tx += int(p[9])
    except OSError:
        pass
    return rx, tx


def human(b):
    if b < 1024:
        return f"{b}B"
    if b < 1048576:
        return f"{b / 1024:.0f}K"
    if b < 1073741824:
        return f"{b / 1048576:.1f}M"
    return f"{b / 1073741824:.2f}G"


def uptime_human():
    s = float(read("/proc/uptime").split()[0])
    d, r = divmod(int(s), 86400)
    h, r = divmod(r, 3600)
    m, _ = divmod(r, 60)
    return f"{d}d {h}h {m}m" if d else (f"{h}h {m}m" if h else f"{m}m")


# ── PROCS ──
_users = {}


def username(pid):
    try:
        uid = os.stat(f"/proc/{pid}").st_uid
    except OSError:
        return "?"
    name = _users.get(uid)
    if name is None:
        try:
            name = pwd.getpwuid(uid).pw_name
        except KeyError:
            name = str(uid)
        _users[uid] = name
    return name


def scan_procs():
    """Return {pid: (name, cpu_ticks, rss_kb)} reading only /proc/PID/stat."""
    out = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            st = read(f"/proc/{name}/stat")
        except OSError:
            continue
        lp = st.find(b"(")
        rp = st.rfind(b")")
        f = st[rp + 2:].split()
        try:
            out[int(name)] = (st[lp + 1:rp], int(f[11]) + int(f[12]), int(f[21]) * PAGE_KB)
        except (IndexError, ValueError):
            continue
    return out


class Sampler:
    def __init__(self, count):
        self.count = count
        self.model = cpu_model()
        self.temp_path = find_temp_path()
        self.prev_cpu = cpu_times()
        self.prev_procs = scan_procs()
        self.prev_time = time.monotonic()

    def sample(self):
        now = time.monotonic()
        dt = max(0.001, now - self.prev_time)

        cur_cpu = cpu_times()
        overall = pct(self.prev_cpu.get("cpu", (0, 0)), cur_cpu.get("cpu", (0, 0)))
        core_names = sorted((k for k in cur_cpu if k != "cpu"), key=lambda k: int(k[3:]))
        cores = [round(pct(self.prev_cpu.get(k, cur_cpu[k]), cur_cpu[k])) for k in core_names]

        procs = scan_procs()
        rows = []
        for pid, (comm, ticks, rss) in procs.items():
            old = self.prev_procs.get(pid)
            cpu_pct = 100.0 * max(0, ticks - old[1]) / CLK_TCK / dt if old else 0.0
            rows.append((cpu_pct, rss, pid, comm))
        active = sorted((r for r in rows if r[0] > 0.05), key=lambda r: r[0], reverse=True)
        idle = sorted((r for r in rows if r[0] <= 0.05), key=lambda r: r[1], reverse=True)
        top = (active + idle)[:self.count]

        mem = meminfo()
        total = mem["total"]
        disk = shutil.disk_usage("/")
        load = read("/proc/loadavg").split()[:3]
        rx, tx = net_bytes()

        self.prev_cpu = cur_cpu
        self.prev_procs = procs
        self.prev_time = now

        kb2g = lambda kb: round(kb / 1048576, 1)
        return {
            "cpu": round(overall), "cores": cores, "freq": cpu_freq(),
            "temp": cpu_temp(self.temp_path), "cpu_model": self.model,
            "ram_used": kb2g(mem["used"]), "ram_total": kb2g(total),
            "ram_pct": round(100 * mem["used"] / total) if total else 0,
            "cached": kb2g(mem["cached"]),
            "swap_used": kb2g(mem["swap_used"]), "swap_total": kb2g(mem["swap_total"]),
            "swap_pct": round(100 * mem["swap_used"] / mem["swap_total"]) if mem["swap_total"] else 0,
            "disk_used": round(disk.used / 2**30), "disk_total": round(disk.total / 2**30),
            "disk_pct": round(100 * disk.used / disk.total) if disk.total else 0,
            "load": load[0].decode(), "load5": load[1].decode(), "load15": load[2].decode(),
            "uptime": uptime_human(),
            "net_rx": human(rx), "net_tx": human(tx),
            "net_rx_bytes": rx, "net_tx_bytes": tx,
            "procs": [{
                "pid": pid,
                "name": comm.decode(errors="replace"),
                "user": username(pid),
                "mem_mb": round(rss / 1024),
                "mem_pct": round(100 * rss / total, 1) if total else 0,
                "cpu_pct": round(cpu_pct, 1),
            } for cpu_pct, rss, pid, comm in top],
        }


def clamp_int(v, lo, hi, default):
    try:
        return max(lo, min(hi, int(float(v))))
    except (TypeError, ValueError):
        return default


def main(argv):
    if argv and argv[0] == "--watch":
        interval = max(0.5, min(10.0, float(argv[1]) if len(argv) > 1 else 2.0))
        count = clamp_int(argv[2] if len(argv) > 2 else 8, 1, 20, 8)
        parent = os.getppid()
        sampler = Sampler(count)
        time.sleep(0.25)  # short warm-up so the first line already has real deltas
        nxt = time.monotonic()
        while True:
            # Exit if the shell went away and we were re-parented.
            if os.getppid() != parent:
                return
            try:
                sys.stdout.write(json.dumps(sampler.sample(), separators=(",", ":")) + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                return
            nxt += interval
            time.sleep(max(0.05, nxt - time.monotonic()))
    else:
        count = clamp_int(argv[0] if argv else 8, 1, 20, 8)
        sampler = Sampler(count)
        time.sleep(0.25)
        print(json.dumps(sampler.sample()))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except KeyboardInterrupt:
        pass
