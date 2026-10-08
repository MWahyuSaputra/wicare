import argparse
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import wicare_ascon as A

NAMA = {0: "KOSONG", 1: "ORANG DIAM", 2: "ORANG BERGERAK", 3: "GANGGUAN"}
TIMEOUT_S = 3.0

ap = argparse.ArgumentParser()
ap.add_argument("--key", default="key.hex")
ap.add_argument("--udp", type=int, default=5005)
ap.add_argument("--http", type=int, default=8080)
ap.add_argument("--tmot", type=int, default=250)
ap.add_argument("--tbr", type=int, default=100)
ap.add_argument("--allow-bench", action="store_true")
args = ap.parse_args()

KEY = bytes.fromhex(open(args.key).read().strip())
assert len(KEY) == 16, "key.hex harus berisi 32 karakter hex"

lock = threading.Lock()
rooms = {}
last_ctr = {}
events = []

def log(kind, room, text):
    with lock:
        events.insert(0, {"t": time.strftime("%H:%M:%S"), "kind": kind, "room": room, "text": text})
        del events[60:]
    print(f"[{kind}] room {room}: {text}", flush=True)

def handle(msg: dict, src):
    try:
        room, cnt, st = int(msg["room"]), int(msg["counter"]), int(msg["status"])
        mot, br, tmot, tbr = int(msg["mot"]), int(msg["br"]), int(msg["tmot"]), int(msg["tbr"])
        flags, session = int(msg["flags"]), int(msg["session"], 16)
        tag = bytes.fromhex(msg["tag"])
    except Exception:
        log("ALARM", "?", f"format laporan rusak dari {src[0]}")
        return

    calc = A.report_tag(KEY, session, room, cnt, st, mot, br, tmot, tbr, flags)
    if calc != tag:
        log("ALARM", room, f"tag tidak sah (laporan palsu/diubah) dari {src[0]}")
        return
    key = (room, session)
    if key in last_ctr and cnt <= last_ctr[key]:
        log("ALARM", room, f"replay terdeteksi: counter {cnt} <= {last_ctr[key]}")
        return
    if (flags & 1) and not args.allow_bench:
        log("ALARM", room, "CSI berasal dari HPS (mode benchmark) di mode produksi")
        return
    if (tmot, tbr) != (args.tmot, args.tbr):
        log("ALARM", room, f"ambang diubah: {tmot}/{tbr}, seharusnya {args.tmot}/{args.tbr}")
        return

    if not any(r == room for r, _ in last_ctr):
        log("INFO", room, f"room baru, session {session:016x}")
    elif key not in last_ctr:
        log("INFO", room, f"session baru {session:016x} (FPGA/daemon restart)")
    last_ctr[key] = cnt

    with lock:
        prev = rooms.get(room, {}).get("status")
        rooms[room] = {"status": st, "label": NAMA.get(st, "?"), "counter": cnt,
                       "mot": mot, "br": br, "t": time.time(), "alarm": ""}
    if prev != st:
        log("STATUS", room, f"{NAMA.get(prev, '-')} -> {NAMA.get(st, '?')}")

def udp_loop():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("0.0.0.0", args.udp))
    while True:
        data, src = s.recvfrom(2048)
        try:
            handle(json.loads(data), src)
        except json.JSONDecodeError:
            log("ALARM", "?", f"paket bukan JSON dari {src[0]}")

def watchdog():
    while True:
        time.sleep(0.5)
        now = time.time()
        with lock:
            items = list(rooms.items())
        for room, r in items:
            stale = now - r["t"] > TIMEOUT_S
            if stale and not r["alarm"]:
                r["alarm"] = "TIDAK ADA LAPORAN SAH"
                log("ALARM", room, f"tidak ada laporan sah > {TIMEOUT_S:.0f} detik (fail-secure)")
            elif not stale and r["alarm"]:
                r["alarm"] = ""

PAGE = """<!doctype html><html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wi-CARE Dashboard</title>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600&display=swap" rel="stylesheet">
<style>
body{font-family:'Plus Jakarta Sans',sans-serif;background:#fff;color:#1d1d1f;margin:0;padding:24px}
h1{font-size:20px;font-weight:600;margin:0 0 4px}.sub{color:#666;font-size:13px;margin-bottom:20px}
.rooms{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px;margin-bottom:24px}
.card{border:1px solid #ddd;border-radius:10px;padding:16px}
.card h2{font-size:14px;font-weight:600;margin:0 0 8px;color:#555}
.st{font-size:22px;font-weight:600}.s0{color:#2e7d32}.s1{color:#b26a00}.s2{color:#c62828}
.alarm{border-color:#c62828;background:#fdecea}.al{color:#c62828;font-weight:600;font-size:13px;margin-top:6px}
.meta{font-size:12px;color:#666;margin-top:8px}
table{border-collapse:collapse;width:100%;font-size:13px}td,th{text-align:left;padding:6px 8px;border-bottom:1px solid #eee}
th{color:#666;font-weight:600}.k-ALARM{color:#c62828;font-weight:600}
</style></head><body>
<h1>Wi-CARE</h1><div class="sub">Status ruang dari laporan bertanda Ascon-AEAD128</div>
<div class="rooms" id="rooms"></div>
<table><thead><tr><th>Waktu</th><th>Jenis</th><th>Ruang</th><th>Keterangan</th></tr></thead>
<tbody id="log"></tbody></table>
<script>
async function tick(){
 try{const d=await (await fetch('/api/state')).json();
  document.getElementById('rooms').innerHTML=Object.entries(d.rooms).map(([k,r])=>`
   <div class="card ${r.alarm?'alarm':''}"><h2>Ruang ${k}</h2>
   <div class="st s${r.status}">${r.label}</div>
   ${r.alarm?`<div class="al">${r.alarm}</div>`:''}
   <div class="meta">Laporan #${r.counter} &middot; gerak ${r.mot} &middot; napas ${r.br} &middot; ${r.age.toFixed(1)} s lalu</div></div>`).join('')||'<div class="sub">Belum ada laporan.</div>';
  document.getElementById('log').innerHTML=d.events.map(e=>`<tr><td>${e.t}</td>
   <td class="k-${e.kind}">${e.kind}</td><td>${e.room}</td><td>${e.text}</td></tr>`).join('');
 }catch(e){}
}
tick();setInterval(tick,1000);
</script></body></html>"""

class Web(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/api/state"):
            now = time.time()
            with lock:
                body = json.dumps({
                    "rooms": {str(k): {**v, "age": now - v["t"]} for k, v in rooms.items()},
                    "events": events[:30]}).encode()
            ctype = "application/json"
        else:
            body, ctype = PAGE.encode(), "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass

threading.Thread(target=udp_loop, daemon=True).start()
threading.Thread(target=watchdog, daemon=True).start()
print(f"Wi-CARE server: UDP {args.udp}, dashboard http://0.0.0.0:{args.http}", flush=True)
ThreadingHTTPServer(("0.0.0.0", args.http), Web).serve_forever()
