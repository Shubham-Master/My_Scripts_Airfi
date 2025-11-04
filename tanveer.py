#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# y4_fleet_suite_v12i.py
# - Python 3.5 compatible, no external libs
# - Incremental: skips re-processing using size+mtime cache
# - Can reuse v12g outputs via --reuse-from (seeds CSVs + cache by log_file name)
# - Box State = Ready iff pending_files in the last cycle of the window == 0
# - Writes: per-cycle CSV, per-day CSV, per-box summary CSV, fleet HTML
#
from __future__ import print_function

import os, sys, re, io, csv, gzip, json, time, argparse
from datetime import datetime, timedelta

VERSION = "12i"

# ---------- utils ----------
def parse_utc(ts):
    try:
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        if len(ts) >= 6 and ts[-3] == ":" and (ts[-6] in ['+','-']):
            ts = ts[:-3] + ts[-2:]
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S.%f%z")
    except Exception:
        try:
            if ts.endswith("Z"):
                ts = ts[:-1] + "+0000"
            return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S%z")
        except Exception:
            try:
                return datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")
            except Exception:
                return None

def ensure_dir(p):
    if p and not os.path.isdir(p):
        os.makedirs(p)

def open_maybe_gz(path):
    # Safe gzip reader that gracefully handles corrupted .gz files
    if path.endswith(".gz"):
        try:
            with gzip.open(path, "rb") as f:
                data = f.read()
            return io.StringIO(data.decode("latin-1", "ignore"))
        except Exception as e:
            try:
                print("WARNING: corrupted gzip, reading as plain text →", path, file=sys.stderr)
                return io.open(path, "r", encoding="latin-1", errors="ignore")
            except Exception:
                print("ERROR: cannot open file →", path, file=sys.stderr)
                return io.StringIO("")

    # Non-gz file
    return io.open(path, "r", encoding="latin-1", errors="ignore")

def within_window(name_ts, start_dt, end_dt):
    return (name_ts is None) or (start_dt.date() <= name_ts.date() <= end_dt.date())

def round2(x):
    try:
        return float("{:.2f}".format(x))
    except Exception:
        return 0.0

# ---------- regex ----------
RE_PREFIX = re.compile(r'^(\d{4}-\d{2}-\d{2}T[0-9:\.]+(?:Z|\+\d{2}:\d{2}|\+\d{4}))\s+([0-9\-\.]+)\s+(.*)$')
RE_PPP_SENT_RECV = re.compile(r'pppd.*Sent\s+(\d+)\s+bytes,\s+received\s+(\d+)\s+bytes', re.I)
RE_PPP_CONNECT = re.compile(r'pppd.*Connect time\s+([0-9\.]+)\s+minutes', re.I)

RE_CD_PROGRESS = re.compile(r'\[(\d+(?:\.\d+)?)\s+of\s+(\d+(?:\.\d+)?)\s+MB\]\s+(\d+)%')
RE_FILE_HINT = re.compile(r'([A-Za-z0-9_\-\.]+\.zip)')

RE_CD_ATTEMPT1 = re.compile(r'Attempting to download manifest', re.I)
RE_CD_ATTEMPT2 = re.compile(r'Using azure to download', re.I)

RE_ADSB_JSON = re.compile(r'ADSB_WS: Sent data to socket:\s+(\{.*\})')
RE_FLC = re.compile(r'FLC created event.*"d":"([A-Z]{3})"')

RE_NAME_TS = re.compile(r'(\d{8})_(\d{6})-(\d{8})_(\d{6})')

# ---------- cache ----------
def cache_path(out_root, box):
    d = os.path.join(out_root, "cache"); ensure_dir(d)
    return os.path.join(d, "{}_index.json".format(box.replace(".","-")))

def load_cache(out_root, box):
    p = cache_path(out_root, box)
    if os.path.isfile(p):
        try:
            with io.open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def save_cache(out_root, box, idx):
    p = cache_path(out_root, box)
    with io.open(p, "w", encoding="utf-8") as f:
        json.dump(idx, f, indent=2, sort_keys=True)

def file_sig(path):
    try:
        st = os.stat(path)
        return {"size": st.st_size, "mtime": int(st.st_mtime)}
    except Exception:
        return None

def parse_name_ts(fn):
    m = RE_NAME_TS.search(fn)
    if not m: return (None, None)
    a,b,c,d = m.group(1),m.group(2),m.group(3),m.group(4)
    def to_dt(sdate, stime):
        try:
            return datetime.strptime(sdate+stime, "%Y%m%d%H%M%S")
        except Exception:
            return None
    return to_dt(a,b), to_dt(c,d)

# ---------- row builders ----------
def new_day_row(box, date_ymd):
    return {
        "date": date_ymd, "box_ip": box,
        "gsm_down_mb": 0.0, "gsm_up_mb": 0.0,
        "gsm_minutes": 0.0, "gsm_sessions": 0,
        "gsm_eff_mb_per_min": 0.0,
        "content_mb_processed": 0.0,
        "files_completed": 0,
        "avg_content_kBps": 0.0,
        "avg_step_MB_per_30s": 0.0,
        "tls_errors": 0, "http_4xx_5xx": 0,
        "dest_airport_last": "",
        "_content_seconds": 0.0,
        "_step_rate_sum": 0.0, "_step_count": 0,
        "pending_mb": 0.0
    }

def new_cycle_row(box, log_file, start_ts):
    return {
        "box_ip": box,
        "log_file": log_file,
        "date": start_ts.strftime("%Y-%m-%d") if start_ts else "",
        "gsm_down_mb": 0.0, "gsm_up_mb": 0.0,
        "gsm_minutes": 0.0, "gsm_sessions": 0,
        "content_mb_processed": 0.0,
        "files_completed": 0,
        "avg_content_kBps": 0.0,
        "any_content_attempted": 0,
        "dest_airport_last": "",
        "pending_mb_end": 0.0,
        "pending_files": 0,          # NEW: number of in-progress files at end of cycle
        "_content_seconds": 0.0,
        "_step_rate_sum": 0.0, "_step_count": 0
    }

# ---------- CSV helpers ----------
def merge_rows_unique(rows, key_fields):
    seen = {}
    for r in rows:
        key = tuple(r.get(k,"") for k in key_fields)
        seen[key] = r
    return list(seen.values())

def read_csv_if_exists(path):
    if not os.path.isfile(path): return []
    out = []
    with io.open(path, "r", encoding="utf-8") as f:
        rdr = csv.DictReader(f)
        for row in rdr: out.append(row)
    return out

def write_csv(path, fieldnames, rows):
    ensure_dir(os.path.dirname(path))
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fieldnames})

# ---------- analyzer ----------
def analyze_log_file(path, box):
    last_prog = {}    # {zip: {"mb":float,"total":float,"ts":datetime,"done":bool}}
    any_attempt = False
    tls_err = 0; http_err = 0
    dest_last = ""

    gsm_down = 0; gsm_up = 0
    gsm_minutes = 0.0; gsm_sessions = 0

    content_mb = 0.0; content_seconds = 0.0
    step_rate_sum = 0.0; step_count = 0
    files_completed = 0
    pending_mb_end = 0.0

    first_ts = None

    base = os.path.basename(path)
    fn_start, _ = parse_name_ts(base)

    f = open_maybe_gz(path)
    for raw in f:
        m = RE_PREFIX.match(raw)
        if not m: continue
        ts_s, ip, rest = m.group(1), m.group(2), m.group(3)
        ts = parse_utc(ts_s)
        if ts is None: continue
        if first_ts is None: first_ts = ts

        m1 = RE_PPP_SENT_RECV.search(rest)
        if m1:
            sent = int(m1.group(1)); recv = int(m1.group(2))
            gsm_up += sent; gsm_down += recv
            continue
        m2 = RE_PPP_CONNECT.search(rest)
        if m2:
            gsm_minutes += float(m2.group(1))
            gsm_sessions += 1
            continue

        if RE_CD_ATTEMPT1.search(rest) or RE_CD_ATTEMPT2.search(rest):
            any_attempt = True

        mp = RE_CD_PROGRESS.search(rest)
        if mp:
            cur_mb = float(mp.group(1))
            total_mb = float(mp.group(2))
            mz = RE_FILE_HINT.search(rest)
            key = mz.group(1) if mz else "_unknown_"
            prev = last_prog.get(key)
            if prev:
                dmb = cur_mb - prev["mb"]
                dt = 0.0
                try:
                    dt = (ts - prev["ts"]).total_seconds()
                except Exception:
                    dt = 0.0
                if dmb > 0 and dt > 0:
                    content_mb += dmb
                    content_seconds += dt
                    step_rate_sum += (dmb/dt)*30.0
                    step_count += 1
            done = False
            try:
                if total_mb > 0 and (cur_mb/total_mb) >= 0.99:
                    done = True
                    files_completed += 1
            except Exception:
                pass
            last_prog[key] = {"mb":cur_mb,"total":total_mb,"ts":ts,"done":done}
            # recompute pending MB across known files
            pending_mb_end = 0.0
            for k,v in last_prog.items():
                if v.get("total",0)>0:
                    diff = v["total"] - v["mb"]
                    if diff > 0.0 and not v.get("done",False):
                        pending_mb_end += diff
            continue

        if "tls" in rest.lower() and ("error" in rest.lower() or "fail" in rest.lower()):
            tls_err += 1
        if "http" in rest.lower():
            if " 4" in rest or " 5" in rest or " 40" in rest or " 50" in rest:
                if " 4" in rest or " 5" in rest:
                    http_err += 1

        mad = RE_ADSB_JSON.search(rest)
        if mad:
            try:
                obj = json.loads(mad.group(1))
                d = obj.get("destination","")
                if d: dest_last = d
            except Exception:
                pass
        mf = RE_FLC.search(rest)
        if mf: dest_last = mf.group(1)

    f.close()

    avg_kBps = 0.0
    if content_seconds > 0 and content_mb > 0:
        avg_kBps = (content_mb*1024.0)/content_seconds

    # count pending files at end of cycle (only files we saw progress for)
    pending_files = 0
    for k,v in last_prog.items():
        try:
            if v.get("total",0)>0 and (v["mb"]/v["total"]) < 0.99:
                pending_files += 1
        except Exception:
            pass

    row = new_cycle_row(box, base, first_ts or fn_start or datetime.utcnow())
    row["gsm_down_mb"] = round2(gsm_down/(1024.0*1024.0))
    row["gsm_up_mb"] = round2(gsm_up/(1024.0*1024.0))
    row["gsm_minutes"] = round2(gsm_minutes)
    row["gsm_sessions"] = gsm_sessions
    row["content_mb_processed"] = round2(content_mb)
    row["files_completed"] = files_completed
    row["avg_content_kBps"] = round2(avg_kBps)
    row["any_content_attempted"] = 1 if (any_attempt or content_mb>0 or files_completed>0) else 0
    row["dest_airport_last"] = dest_last
    row["pending_mb_end"] = round2(pending_mb_end)
    row["pending_files"] = pending_files
    row["_content_seconds"] = content_seconds
    row["_step_rate_sum"] = step_rate_sum
    row["_step_count"] = step_count
    return row

# ---------- processing ----------
def process_box(root, out_root, box, start_dt, end_dt, reuse_dir, progress, every):
    box_dir = os.path.join(root, box)
    if not os.path.isdir(box_dir):
        return {"box": box, "cycles": [], "days": {}, "summary": None}

    idx = load_cache(out_root, box) if CACHE_ENABLED else {}

    seeds_cycles = []
    if reuse_dir:
        c1 = os.path.join(reuse_dir, "boxes", box.replace(".","-"), "per_cycle.csv")
        seeds_cycles = read_csv_if_exists(c1)
        for r in seeds_cycles:
            lf = r.get("log_file","")
            if lf:
                idx.setdefault("by_name", {})[lf] = True

    cand = []
    for fn in sorted(os.listdir(box_dir)):
        if not fn.startswith("logfile-"): continue
        if not (fn.endswith(".gz") or fn.endswith(".log") or fn.endswith(".txt")): continue
        sdt, _ = parse_name_ts(fn)
        if sdt and not within_window(sdt, start_dt, end_dt): continue
        cand.append(os.path.join(box_dir, fn))

    cycles = []
    for r in seeds_cycles: cycles.append(r)

    last_tick = time.time()
    for i, path in enumerate(cand, 1):
        base = os.path.basename(path)
        sig = file_sig(path)
        if idx.get("by_name", {}).get(base, False):
            continue
        old = idx.get(path)
        if old and sig and old.get("size")==sig.get("size") and old.get("mtime")==sig.get("mtime"):
            continue

        c = analyze_log_file(path, box)
        cycles.append(c)
        if sig:
            idx[path] = sig
        idx.setdefault("by_name", {})[base] = True

        if progress and (time.time() - last_tick) >= every:
            content_tot = round2(sum(float(r.get("content_mb_processed",0.0)) for r in cycles))
            sessions = sum(int(r.get("gsm_sessions",0)) for r in cycles)
            print("[{}] {} files, sessions={}, contentMB={}".format(box, i, sessions, content_tot), file=sys.stderr)
            last_tick = time.time()

    if CACHE_ENABLED: save_cache(out_root, box, idx)

    # dedup cycles by (box_ip, log_file)
    cycles = merge_rows_unique(cycles, ["box_ip","log_file"])

    # build per day
    days = {}
    for c in cycles:
        date = c.get("date","")
        if not date: continue
        row = days.get(date)
        if not row:
            row = new_day_row(box, date); days[date] = row
        row["gsm_down_mb"] += float(c.get("gsm_down_mb",0.0))
        row["gsm_up_mb"]   += float(c.get("gsm_up_mb",0.0))
        row["gsm_minutes"] += float(c.get("gsm_minutes",0.0))
        row["gsm_sessions"]+= int(c.get("gsm_sessions",0))
        row["content_mb_processed"] += float(c.get("content_mb_processed",0.0))
        row["files_completed"] += int(c.get("files_completed",0))
        row["_content_seconds"] += float(c.get("_content_seconds",0.0))
        row["_step_rate_sum"]  += float(c.get("_step_rate_sum",0.0))
        row["_step_count"]     += int(c.get("_step_count",0))
        d = c.get("dest_airport_last","")
        if d: row["dest_airport_last"] = d
        pmb = float(c.get("pending_mb_end",0.0))
        if pmb>0: row["pending_mb"] = pmb

    for drow in days.values():
        drow["gsm_eff_mb_per_min"] = round2((drow["gsm_down_mb"]/drow["gsm_minutes"]) if drow["gsm_minutes"]>0 else 0.0)
        avg_kBps = 0.0
        if drow["_content_seconds"]>0 and drow["content_mb_processed"]>0:
            avg_kBps = (drow["content_mb_processed"]*1024.0)/drow["_content_seconds"]
        drow["avg_content_kBps"] = round2(avg_kBps)
        drow["avg_step_MB_per_30s"] = round2((drow["_step_rate_sum"]/max(1,drow["_step_count"])) if drow["_step_count"]>0 else 0.0)
        for k in ["gsm_down_mb","gsm_up_mb","gsm_minutes","content_mb_processed","pending_mb"]:
            drow[k] = round2(drow[k])

    # per-box summary
    total_cycles = len(cycles)
    acdc_cycles = sum(1 for c in cycles if int(c.get("any_content_attempted",0))==1)
    gsm_down_mb = round2(sum(float(c.get("gsm_down_mb",0.0)) for c in cycles))
    gsm_minutes = round2(sum(float(c.get("gsm_minutes",0.0)) for c in cycles))
    gsm_sessions = sum(int(c.get("gsm_sessions",0)) for c in cycles)
    content_mb   = round2(sum(float(c.get("content_mb_processed",0.0)) for c in cycles))
    files_completed = sum(int(c.get("files_completed",0)) for c in cycles)

    num=0.0; den=0.0
    for c in cycles:
        mb = float(c.get("content_mb_processed",0.0))
        sec= float(c.get("_content_seconds",0.0))
        if mb>0 and sec>0:
            num += mb*1024.0; den += sec
    avg_content_kBps = round2((num/den) if den>0 else 0.0)

    avg_gsm_down_per_session = round2((gsm_down_mb/gsm_sessions) if gsm_sessions>0 else 0.0)
    avg_gsm_minutes_per_session = round2((gsm_minutes/gsm_sessions) if gsm_sessions>0 else 0.0)
    avg_content_per_acdc_cycle = round2((content_mb/acdc_cycles) if acdc_cycles>0 else 0.0)

    # find last cycle in window (by date + name) and take its pending_files
    pending_files_window = 0
    last_dest = ""
    if cycles:
        last_sorted = sorted(cycles, key=lambda r: (r.get("date",""), r.get("log_file","")))
        last_row = last_sorted[-1]
        # new column in this version; if absent (from reuse), fallback to 1 if pending_mb_end>0 else 0
        pf = last_row.get("pending_files", "")
        if pf == "" or pf is None:
            try:
                pf = 1 if float(last_row.get("pending_mb_end",0.0))>0 else 0
            except Exception:
                pf = 0
        pending_files_window = int(pf)
        last_dest = last_row.get("dest_airport_last","")

    state = "Ready" if pending_files_window == 0 else "Not Ready"

    per_box_summary = {
        "box_ip": box,
        "cycles": total_cycles,
        "acdc_cycles": acdc_cycles,
        "gsm_down_mb": gsm_down_mb,
        "gsm_minutes": gsm_minutes,
        "gsm_eff_mb_per_min": round2((gsm_down_mb/gsm_minutes) if gsm_minutes>0 else 0.0),
        "content_mb": content_mb,
        "files_completed": files_completed,
        "avg_content_kBps": avg_content_kBps,
        "avg_gsm_down_per_session_mb": avg_gsm_down_per_session,
        "avg_gsm_minutes_per_session": avg_gsm_minutes_per_session,
        "avg_content_per_acdc_cycle_mb": avg_content_per_acdc_cycle,
        "pending_files_window": pending_files_window,   # NEW
        "state": state,
        "last_dest": last_dest
    }

    # write per-box CSVs
    box_out = os.path.join(out_root, "boxes", box.replace(".","-")); ensure_dir(box_out)

    cycle_fields = ["box_ip","log_file","date","gsm_down_mb","gsm_up_mb","gsm_minutes","gsm_sessions",
                    "content_mb_processed","files_completed","avg_content_kBps",
                    "any_content_attempted","dest_airport_last","pending_mb_end","pending_files"]
    existing_cycles = read_csv_if_exists(os.path.join(box_out, "per_cycle.csv"))
    merged_cycles = merge_rows_unique(existing_cycles + cycles, ["box_ip","log_file"])
    for r in merged_cycles:
        for k in ["gsm_down_mb","gsm_up_mb","gsm_minutes","content_mb_processed","avg_content_kBps","pending_mb_end"]:
            if k in r:
                try: r[k] = round2(float(r[k]))
                except Exception: r[k] = 0.0
        for k in ["gsm_sessions","files_completed","any_content_attempted","pending_files"]:
            if k in r:
                try: r[k] = int(float(r[k]))
                except Exception: r[k] = 0
    write_csv(os.path.join(box_out, "per_cycle.csv"), cycle_fields, merged_cycles)

    day_fields = ["date","box_ip","gsm_down_mb","gsm_up_mb","gsm_minutes","gsm_sessions",
                  "gsm_eff_mb_per_min","content_mb_processed","files_completed",
                  "avg_content_kBps","avg_step_MB_per_30s","tls_errors","http_4xx_5xx",
                  "dest_airport_last","pending_mb"]
    existing_days = read_csv_if_exists(os.path.join(box_out, "per_day.csv"))
    bydate = {}
    for r in existing_days:
        if r.get("box_ip")==box:
            bydate[r.get("date","")] = r
    for d, row in days.items():
        out = {k: row.get(k,"") for k in day_fields}
        bydate[d] = out
    merged_days = list(sorted(bydate.values(), key=lambda r: r.get("date","")))
    write_csv(os.path.join(box_out, "per_day.csv"), day_fields, merged_days)

    # fleet per_box_summary.csv (append/update)
    sum_fields = ["box_ip","cycles","acdc_cycles","gsm_down_mb","gsm_minutes","gsm_eff_mb_per_min",
                  "content_mb","files_completed","avg_content_kBps",
                  "avg_gsm_down_per_session_mb","avg_gsm_minutes_per_session",
                  "avg_content_per_acdc_cycle_mb","pending_files_window","state","last_dest"]
    fleet_box_sum = os.path.join(out_root, "per_box_summary.csv")
    rows = read_csv_if_exists(fleet_box_sum)
    rows = [r for r in rows if r.get("box_ip")!=box]
    rows.append(per_box_summary)
    write_csv(fleet_box_sum, sum_fields, rows)

    return {"box": box, "cycles": merged_cycles, "days": merged_days, "summary": per_box_summary}

# ---------- HTML ----------
def write_fleet_html(out_root, per_box_summary, start_str, end_str):
    ensure_dir(out_root)
    path = os.path.join(out_root, "fleet.html")

    boxes = sorted(per_box_summary.values(), key=lambda r: r["box_ip"])
    fleet = {
        "boxes_count": len(boxes),
        "included_cycles": sum(int(b["cycles"]) for b in boxes),
        "gsm_down_mb": round2(sum(float(b["gsm_down_mb"]) for b in boxes)),
        "gsm_minutes": round2(sum(float(b["gsm_minutes"]) for b in boxes)),
        "content_mb": round2(sum(float(b["content_mb"]) for b in boxes)),
        "files_completed": sum(int(b["files_completed"]) for b in boxes),
        "acdc_cycles": sum(int(b["acdc_cycles"]) for b in boxes),
    }
    fleet["avg_gsm_eff"] = round2((fleet["gsm_down_mb"]/fleet["gsm_minutes"]) if fleet["gsm_minutes"]>0 else 0.0)

    # approximate fleet avg content speed by MB-weighting per-box averages
    num=0.0; den=0.0
    for b in boxes:
        sp = float(b.get("avg_content_kBps",0.0))
        mb = float(b.get("content_mb",0.0))
        if sp>0 and mb>0:
            num += sp*mb; den += mb
    fleet["avg_content_kBps"] = round2((num/den) if den>0 else 0.0)
    fleet["avg_gsm_down_per_cycle"] = round2(fleet["gsm_down_mb"]/max(1,fleet["included_cycles"]))
    fleet["avg_content_per_acdc_cycle"] = round2(fleet["content_mb"]/max(1,fleet["acdc_cycles"]))

    header_cols = ["Box","Cycles","ACDC cycles","GSM Down (MB)","GSM Minutes","GSM Eff (MB/min)",
                   "Content (MB)","Files Completed","Avg Content Speed (kB/s)",
                   "Avg GSM Down / session (MB)","Avg GSM Minutes / session",
                   "Avg Content / ACDC (MB)","Pending Files","State","Last Dest"]

    rows_html = []
    for b in boxes:
        badge = "ready" if b["state"]=="Ready" else "notready"
        rows_html.append(
            "<tr>"
            "<td>{box_ip}</td><td>{cycles}</td><td>{acdc_cycles}</td>"
            "<td>{gsm_down_mb}</td><td>{gsm_minutes}</td><td>{gsm_eff_mb_per_min}</td>"
            "<td>{content_mb}</td><td>{files_completed}</td><td>{avg_content_kBps}</td>"
            "<td>{avg_gsm_down_per_session_mb}</td><td>{avg_gsm_minutes_per_session}</td>"
            "<td>{avg_content_per_acdc_cycle_mb}</td>"
            "<td>{pending_files_window}</td>"
            "<td><span class='badge {badge}'>{state}</span></td>"
            "<td>{last_dest}</td>"
            "</tr>".format(badge=badge, **b)
        )

    html = u"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<title>Y4 Fleet Report v{ver}</title>
<style>
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Inter,Helvetica,Arial,sans-serif;line-height:1.4;color:#111;padding:24px;background:#fafafa}}
h1,h2{{margin:0 0 12px}}
.card{{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;margin:12px 0;box-shadow:0 1px 2px rgba(0,0,0,.04)}}
.kv{{display:grid;grid-template-columns:220px 1fr;grid-row-gap:6px}}
table{{width:100%;border-collapse:collapse;margin:8px 0 16px}}
th,td{{border-bottom:1px solid #eee;padding:8px 10px;font-size:13px;text-align:left}}
th{{background:#f9fafb;font-weight:600}}
.badge{{display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px;border:1px solid #d1d5db}}
.badge.ready{{background:#ecfdf5;border-color:#10b981;color:#065f46}}
.badge.notready{{background:#fef2f2;border-color:#ef4444;color:#7f1d1d}}
.small{{font-size:12px;color:#6b7280}}
</style>
</head><body>
<h1>Y4 Fleet Report <span class="small">v{ver}</span></h1>

<div class="card">
  <h2>Fleet Summary</h2>
  <div class="kv">
    <div>Window</div><div>{start} → {end}</div>
    <div>Boxes</div><div>{boxes}</div>
    <div>Included cycles</div><div>{cycles}</div>
    <div>GSM Down (MB)</div><div>{gsm_down_mb}</div>
    <div>GSM Minutes</div><div>{gsm_minutes}</div>
    <div>Avg GSM Eff (MB/min)</div><div>{avg_gsm_eff}</div>
    <div>Content (MB)</div><div>{content_mb}</div>
    <div>Files Completed</div><div>{files_completed}</div>
    <div>Avg Content Speed (kB/s)</div><div>{avg_content_kBps}</div>
    <div>Avg GSM Down / cycle (MB)</div><div>{avg_gsm_down_per_cycle}</div>
    <div>Avg Content / ACDC cycle (MB)</div><div>{avg_content_per_acdc_cycle}</div>
  </div>
</div>

<div class="card">
  <h2>Per-box summaries</h2>
  <table>
    <thead><tr>{hdr}</tr></thead>
    <tbody>
      {rows}
    </tbody>
  </table>
</div>

<p class="small">Generated by y4_fleet_suite_v{ver}. Re-runs skip already-indexed logs; use --no-cache to force rescan.</p>
</body></html>
""".format(
        ver=VERSION,
        start=start_str, end=end_str,
        boxes=fleet["boxes_count"], cycles=fleet["included_cycles"],
        gsm_down_mb=fleet["gsm_down_mb"], gsm_minutes=fleet["gsm_minutes"],
        avg_gsm_eff=fleet["avg_gsm_eff"], content_mb=fleet["content_mb"],
        files_completed=fleet["files_completed"],
        avg_content_kBps=fleet["avg_content_kBps"],
        avg_gsm_down_per_cycle=fleet["avg_gsm_down_per_cycle"],
        avg_content_per_acdc_cycle=fleet["avg_content_per_acdc_cycle"],
        hdr="".join("<th>{}</th>".format(c) for c in header_cols),
        rows="\n".join(rows_html)
    )
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(html)

# ---------- args/main ----------
def parse_args():
    ap = argparse.ArgumentParser(description="Y4 fleet analyzer v{}".format(VERSION))
    ap.add_argument("--root", required=True, help="Root with /<box_ip>/logfile-*.gz")
    ap.add_argument("--boxes", nargs="*", help="Box IPs")
    ap.add_argument("--boxes-file", help="File with one box IP per line")
    ap.add_argument("--start", required=True, help="YYYY-MM-DD")
    ap.add_argument("--end", required=True, help="YYYY-MM-DD")
    ap.add_argument("--out", required=True, help="Output dir")
    ap.add_argument("--reuse-from", help="Reuse/seed from previous v12g (or later) outputs")
    ap.add_argument("--no-cache", action="store_true", help="Force rescan (ignore cache)")
    ap.add_argument("--progress", action="store_true")
    ap.add_argument("--progress-every", type=int, default=30)
    return ap.parse_args()

CACHE_ENABLED = True

def main():
    global CACHE_ENABLED
    args = parse_args()
    CACHE_ENABLED = (not args.no_cache)

    start_dt = datetime.strptime(args.start, "%Y-%m-%d")
    end_dt   = datetime.strptime(args.end, "%Y-%m-%d")

    boxes = []
    if args.boxes: boxes.extend(args.boxes)
    if args.boxes_file:
        with io.open(args.boxes_file, "r", encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if s: boxes.append(s)
    if not boxes:
        print("No boxes provided.", file=sys.stderr); sys.exit(2)
    boxes = sorted(set(boxes))

    per_box_summary = {}
    for b in boxes:
        if args.progress:
            print("[{}] scanning…".format(b), file=sys.stderr)
        res = process_box(args.root, args.out, b, start_dt, end_dt, args.reuse_from, args.progress, args.progress_every)
        per_box_summary[b] = res["summary"]

    write_fleet_html(args.out, per_box_summary, args.start, args.end)

    # also write/update fleet snapshot CSV
    fleet_sum_path = os.path.join(args.out, "per_box_summary.csv")
    exist = read_csv_if_exists(fleet_sum_path)
    exist = [r for r in exist if r.get("box_ip") not in per_box_summary]
    rows = exist + [per_box_summary[b] for b in sorted(per_box_summary)]
    sum_fields = ["box_ip","cycles","acdc_cycles","gsm_down_mb","gsm_minutes","gsm_eff_mb_per_min",
                  "content_mb","files_completed","avg_content_kBps",
                  "avg_gsm_down_per_session_mb","avg_gsm_minutes_per_session",
                  "avg_content_per_acdc_cycle_mb","pending_files_window","state","last_dest"]
    write_csv(fleet_sum_path, sum_fields, rows)

    print("Done. Output in: {}".format(args.out))

if __name__ == "__main__":
    main()
