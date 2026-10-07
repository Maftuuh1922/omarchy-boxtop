#!/usr/bin/env python3
"""btop-style system data for Omarchy bar plugin."""
import json, pathlib, time, shutil, os

P = pathlib.Path

# ── CPU ──
def cpu_overall():
    def sample():
        p = P("/proc/stat").read_text().splitlines()[0].split()[1:]
        v = [int(x) for x in p]
        idle = v[3] + (v[4] if len(v) > 4 else 0)
        return idle, sum(v)
    i1, t1 = sample(); time.sleep(0.15); i2, t2 = sample()
    dt = t2 - t1
    return 0.0 if dt <= 0 else max(0, min(100, 100.0 * (1.0 - (i2 - i1) / dt)))

def cpu_per_core():
    def sample():
        cores = {}
        for line in P("/proc/stat").read_text().splitlines():
            if line.startswith("cpu") and not line.startswith("cpu "):
                p = line.split(); v = [int(x) for x in p[1:]]
                idle = v[3] + (v[4] if len(v) > 4 else 0)
                cores[p[0]] = (idle, sum(v))
        return cores
    c1 = sample(); time.sleep(0.15); c2 = sample()
    out = []
    for k in sorted(c1):
        if k not in c2: continue
        i1, t1 = c1[k]; i2, t2 = c2[k]; dt = t2 - t1
        out.append(round(max(0, min(100, 100.0 * (1.0 - (i2 - i1) / dt))) if dt > 0 else 0))
    return out

def cpu_freq():
    try:
        freqs = []
        for f in sorted(P("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_cur_freq")):
            freqs.append(int(f.read_text().strip()) / 1000)  # MHz
        return round(sum(freqs) / len(freqs)) if freqs else None
    except: return None

def cpu_temp():
    roots = list(P("/sys/class/thermal").glob("thermal_zone*"))
    pref = {}
    for z in roots:
        try: pref[(z / "type").read_text().strip()] = z
        except: pass
    for n in ["x86_pkg_temp", "TCPU", "INT3400 Thermal", "SEN1", "acpitz"]:
        z = pref.get(n)
        if z:
            try: return int((z / "temp").read_text().strip()) // 1000
            except: pass
    for z in roots:
        try: return int((z / "temp").read_text().strip()) // 1000
        except: continue
    return None

# ── MEM ──
def meminfo():
    d = {}
    for line in P("/proc/meminfo").read_text().splitlines():
        k, _, v = line.partition(":"); d[k] = int(v.strip().split()[0])
    total = d["MemTotal"]; avail = d.get("MemAvailable", d["MemFree"])
    cached = d.get("Cached", 0) + d.get("SReclaimable", 0) - d.get("Shmem", 0)
    cached = max(0, cached)
    st = d.get("SwapTotal", 0); sf = d.get("SwapFree", 0)
    return {
        "used": total - avail, "total": total,
        "cached": cached,
        "swap_used": st - sf, "swap_total": st,
    }

# ── DISK ──
def diskinfo():
    d = shutil.disk_usage("/")
    return {"used": d.used, "total": d.total}

# ── NET ──
def net_bytes():
    try:
        rx = tx = 0
        for line in P("/proc/net/dev").read_text().splitlines()[2:]:
            p = line.split(); iface = p[0].rstrip(":")
            if iface == "lo": continue
            rx += int(p[1]); tx += int(p[9])
        return rx, tx
    except: return 0, 0

def human(b):
    if b < 1024: return f"{b}B"
    if b < 1048576: return f"{b/1024:.0f}K"
    if b < 1073741824: return f"{b/1048576:.1f}M"
    return f"{b/1073741824:.2f}G"

# ── PROCS ──
import pwd

STATE = P(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "omarchy-sysmon-procs.json"

def top_procs(n=9):
    hz = os.sysconf("SC_CLK_TCK")
    now = time.time()
    prev = {}
    prev_time = None
    try:
        data = json.loads(STATE.read_text())
        prev = {int(k): v for k, v in data.get("ticks", {}).items()}
        prev_time = data.get("time")
    except Exception:
        pass

    total_ticks = 0
    for line in P("/proc/stat").read_text().splitlines():
        if line.startswith("cpu "):
            total_ticks = sum(int(x) for x in line.split()[1:])
            break

    procs = []
    seen = {}
    for pid_dir in P("/proc").iterdir():
        if not pid_dir.name.isdigit(): continue
        try:
            st = (pid_dir / "stat").read_text()
            # comm may contain spaces/parens; split around the last ')'
            rp = st.rindex(")")
            comm = st[st.index("(") + 1:rp]
            fields = st[rp + 2:].split()
            utime = int(fields[11]); stime = int(fields[12])
            rss_kb = int(fields[21]) * 4
            uid = (pid_dir / "status").read_text()
            user = "?"
            for ln in uid.splitlines():
                if ln.startswith("Uid:"):
                    user = pwd.getpwuid(int(ln.split()[1])).pw_name
                    break
            ticks = utime + stime
            seen[int(pid_dir.name)] = ticks
            procs.append({"pid": int(pid_dir.name), "name": comm, "ticks": ticks, "mem_kb": rss_kb, "user": user})
        except Exception:
            continue

    cpu_pct = {}
    if prev_time and prev:
        dt = max(0.001, now - prev_time)
        for p in procs:
            old = prev.get(p["pid"], 0)
            delta = max(0, p["ticks"] - old)
            cpu_pct[p["pid"]] = round(100.0 * delta / hz / dt, 1)

    try:
        STATE.write_text(json.dumps({"time": now, "ticks": seen}))
    except Exception:
        pass

    total_mem = int(P("/proc/meminfo").read_text().splitlines()[0].split()[1])

    # prefer recently-active processes, like btop's "cpu lazy" sort
    procs.sort(key=lambda p: (p["ticks"], p["mem_kb"]), reverse=True)
    active = [p for p in procs if cpu_pct.get(p["pid"], 0) > 0.05]
    active.sort(key=lambda p: cpu_pct.get(p["pid"], 0), reverse=True)
    rest = [p for p in procs if cpu_pct.get(p["pid"], 0) <= 0.05]
    rest.sort(key=lambda p: p["mem_kb"], reverse=True)
    ordered = (active + rest)[:n]

    out = []
    for p in ordered:
        out.append({
            "pid": p["pid"],
            "name": p["name"],
            "user": p["user"],
            "mem_mb": round(p["mem_kb"] / 1024),
            "mem_pct": round(100 * p["mem_kb"] / total_mem, 1) if total_mem else 0,
            "cpu_pct": cpu_pct.get(p["pid"], 0.0),
        })
    return out

# ── UPTIME ──
def uptime_human():
    s = float(P("/proc/uptime").read_text().split()[0])
    d, r = divmod(int(s), 86400); h, r = divmod(r, 3600); m, _ = divmod(r, 60)
    return f"{d}d {h}h {m}m" if d else (f"{h}h {m}m" if h else f"{m}m")

cpu = cpu_overall()
cores = cpu_per_core()
freq = cpu_freq()
temp = cpu_temp()
mem = meminfo()
disk = diskinfo()
load1, load5, load15 = P("/proc/loadavg").read_text().split()[:3]
rx, tx = net_bytes()
procs = top_procs(8)
uptime = uptime_human()

def cpu_model():
    try:
        for ln in P("/proc/cpuinfo").read_text().splitlines():
            if ln.startswith("model name"):
                name = ln.split(":", 1)[1].strip()
                for junk in ("(R)", "(TM)", "Intel ", "AMD ", "CPU ", " Processor", "Core "):
                    name = name.replace(junk, " ")
                name = name.split("@")[0]
                return " ".join(name.split())[:22]
    except Exception:
        pass
    return "cpu"

kb2g = lambda kb: round(kb / 2**20, 1)

print(json.dumps({
    "cpu": round(cpu), "cores": cores, "freq": freq, "temp": temp,
    "ram_used": kb2g(mem["used"]), "ram_total": kb2g(mem["total"]), "ram_pct": round(100*mem["used"]/mem["total"]),
    "cached": kb2g(mem["cached"]),
    "swap_used": kb2g(mem["swap_used"]), "swap_total": kb2g(mem["swap_total"]),
    "swap_pct": round(100*mem["swap_used"]/mem["swap_total"]) if mem["swap_total"] > 0 else 0,
    "disk_used": round(disk["used"]/2**30), "disk_total": round(disk["total"]/2**30),
    "disk_pct": round(100*disk["used"]/disk["total"]),
    "load": load1, "load5": load5, "load15": load15,
    "uptime": uptime, "cpu_model": cpu_model(),
    "net_rx": human(rx), "net_tx": human(tx),
    "net_rx_bytes": rx, "net_tx_bytes": tx,
    "procs": procs,
}))
