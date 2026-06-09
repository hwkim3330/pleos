#!/usr/bin/env python3
import json
import math
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ADB_SERIAL = "emulator-5554"
HOST = "127.0.0.1"
PORT = 8765
APP_ACTIVITY = "com.example.mrm_multimodal_demo/.MainActivity"
APP_RECEIVER = "com.example.mrm_multimodal_demo/.DrivePilotControlReceiver"

ROUTE = [
    (37.40180, 127.10895),
    (37.40238, 127.10974),
    (37.40294, 127.11104),
    (37.40350, 127.11242),
    (37.40432, 127.11328),
    (37.40512, 127.11378),
    (37.40592, 127.11464),
    (37.40636, 127.11578),
]

state = {
    "lat": ROUTE[0][0],
    "lon": ROUTE[0][1],
    "speedKph": 0,
    "driveState": "park",
    "routeRunning": False,
    "last": "",
}

route_stop = threading.Event()


def run(cmd):
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=12)
    out = (proc.stdout + proc.stderr).strip()
    state["last"] = "$ " + " ".join(cmd) + "\n" + out
    return proc.returncode, out


def adb(*args):
    return run(["adb", "-s", ADB_SERIAL, *args])


def send_app_control():
    args = [
        "shell",
        "am",
        "broadcast",
        "-n",
        APP_RECEIVER,
        "-a",
        "com.example.mrm_multimodal_demo.CONTROL",
        "--es",
        "drivepilot_source",
        "controller",
    ]
    args += [
        "--ef",
        "speedKph",
        f"{float(state['speedKph']):.3f}",
        "--ed",
        "lat",
        f"{float(state['lat']):.7f}",
        "--ed",
        "lon",
        f"{float(state['lon']):.7f}",
        "--es",
        "driveState",
        str(state["driveState"]),
    ]
    return adb(*args)


def open_drive_pilot():
    return adb(
        "shell",
        "am",
        "start",
        "-n",
        APP_ACTIVITY,
        "--es",
        "drivepilot_source",
        "controller",
        "--ef",
        "speedKph",
        f"{float(state['speedKph']):.3f}",
        "--ed",
        "lat",
        f"{float(state['lat']):.7f}",
        "--ed",
        "lon",
        f"{float(state['lon']):.7f}",
        "--es",
        "driveState",
        str(state["driveState"]),
    )


def set_geo(lat, lon):
    state["lat"] = lat
    state["lon"] = lon
    code, out = adb("emu", "geo", "fix", f"{lon:.7f}", f"{lat:.7f}", "5")
    _, app_out = send_app_control()
    state["last"] = out + "\n\nDrive Pilot override:\n" + app_out
    return code, state["last"]


def set_drive(value):
    state["driveState"] = value
    code, out = adb("shell", "cmd", "car_service", "emulate-driving-state", value)
    _, app_out = send_app_control()
    state["last"] = out + "\n\nDrive Pilot override:\n" + app_out
    return code, state["last"]


def set_speed(kph):
    state["speedKph"] = kph
    code, out = send_app_control()
    state["last"] = "Drive Pilot app speed override sent.\n" + out
    return code, state["last"]


def route_loop(speed_kph):
    route_stop.clear()
    state["routeRunning"] = True
    set_drive("drive")
    set_speed(speed_kph)
    while not route_stop.is_set():
        for start, end in zip(ROUTE, ROUTE[1:]):
            for i in range(24):
                if route_stop.is_set():
                    break
                t = i / 24
                lat = start[0] + (end[0] - start[0]) * t
                lon = start[1] + (end[1] - start[1]) * t
                set_geo(lat, lon)
                set_speed(speed_kph + math.sin(time.time()) * 3)
                time.sleep(0.8)
            if route_stop.is_set():
                break
        if route_stop.is_set():
            break
    state["routeRunning"] = False


def html():
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Pleos Vehicle Controller</title>
  <style>
    body {{ margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:#eef2f6; color:#111827; }}
    main {{ max-width: 980px; margin: 0 auto; padding: 28px; }}
    h1 {{ font-size: 28px; margin: 0 0 6px; }}
    .sub {{ color:#64748b; font-weight:700; margin-bottom:22px; }}
    .grid {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:14px; }}
    section {{ background:white; border-radius:12px; padding:18px; box-shadow:0 10px 26px rgba(15,23,42,.08); }}
    label {{ display:block; font-size:12px; font-weight:900; color:#64748b; margin:12px 0 6px; }}
    input, select {{ width:100%; box-sizing:border-box; height:40px; border:1px solid #d7dde7; border-radius:9px; padding:0 10px; font-weight:800; }}
    button {{ height:40px; border:0; border-radius:9px; padding:0 14px; font-weight:900; color:white; background:#2563eb; cursor:pointer; }}
    button.alt {{ background:#10b981; }}
    button.warn {{ background:#ef4444; }}
    .row {{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; }}
    pre {{ white-space:pre-wrap; background:#0f172a; color:#dbeafe; border-radius:10px; padding:14px; min-height:120px; }}
    .stat {{ display:grid; grid-template-columns:repeat(4,1fr); gap:10px; margin:16px 0; }}
    .pill {{ background:#eaf2ff; color:#2563eb; border-radius:10px; padding:10px; font-weight:900; }}
  </style>
</head>
<body>
<main>
  <h1>Pleos Vehicle Controller</h1>
  <div class="sub">Mac에서 ADB로 Pleos 에뮬레이터 위치/속도/주행상태를 테스트 주입</div>
  <div class="stat">
    <div class="pill">lat <span id="lat">{state["lat"]:.5f}</span></div>
    <div class="pill">lon <span id="lon">{state["lon"]:.5f}</span></div>
    <div class="pill">speed <span id="speed">{state["speedKph"]:.0f}</span> km/h</div>
    <div class="pill">state <span id="drive">{state["driveState"]}</span></div>
  </div>
  <div class="grid">
    <section>
      <h2>Location</h2>
      <label>Latitude</label><input id="ilat" value="{state["lat"]:.7f}">
      <label>Longitude</label><input id="ilon" value="{state["lon"]:.7f}">
      <p class="row">
        <button onclick="geo()">Set GPS</button>
        <button class="alt" onclick="preset(37.40180,127.10895)">Pangyo Start</button>
        <button class="alt" onclick="preset(37.40636,127.11578)">Destination</button>
      </p>
    </section>
    <section>
      <h2>Vehicle</h2>
      <label>Speed km/h</label><input id="ispeed" type="range" min="0" max="130" value="{state["speedKph"]}" oninput="sval.textContent=this.value">
      <div><b id="sval">{state["speedKph"]}</b> km/h</div>
      <p class="row">
        <button onclick="speed()">Set Speed</button>
        <button onclick="drive('drive')">Drive</button>
        <button onclick="drive('park')">Park</button>
        <button onclick="drive('reverse')">Reverse</button>
      </p>
    </section>
    <section>
      <h2>Demo Route</h2>
      <p class="row">
        <button class="alt" onclick="startRoute()">Start Route</button>
        <button class="warn" onclick="stopRoute()">Stop Route</button>
      </p>
    </section>
    <section>
      <h2>Quick Events</h2>
      <p class="row">
        <button onclick="quick(30)">Urban 30</button>
        <button onclick="quick(80)">Highway 80</button>
        <button class="warn" onclick="quick(0)">Stop</button>
      </p>
    </section>
  </div>
  <h2>ADB Output</h2>
  <pre id="out"></pre>
</main>
<script>
async function call(path) {{
  const r = await fetch(path); const j = await r.json();
  out.textContent = j.last || JSON.stringify(j,null,2); refresh();
}}
function geo() {{ call(`/api/geo?lat=${{ilat.value}}&lon=${{ilon.value}}`); }}
function preset(lat, lon) {{ ilat.value=lat; ilon.value=lon; geo(); }}
function speed() {{ call(`/api/speed?kph=${{ispeed.value}}`); }}
function quick(v) {{ ispeed.value=v; sval.textContent=v; speed(); }}
function drive(v) {{ call(`/api/drive?state=${{v}}`); }}
function startRoute() {{ call(`/api/route/start?kph=${{ispeed.value || 45}}`); }}
function stopRoute() {{ call('/api/route/stop'); }}
async function refresh() {{
  const r = await fetch('/api/status'); const j = await r.json();
  lat.textContent = Number(j.lat).toFixed(5); lon.textContent = Number(j.lon).toFixed(5);
  speed.textContent = Number(j.speedKph).toFixed(0); drive.textContent = j.driveState;
}}
setInterval(refresh, 1000); refresh();
</script>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def send_json(self, value):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        qs = parse_qs(parsed.query)
        try:
            if parsed.path == "/":
                body = html().encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif parsed.path == "/api/status":
                self.send_json(state)
            elif parsed.path == "/api/geo":
                set_geo(float(qs["lat"][0]), float(qs["lon"][0]))
                self.send_json(state)
            elif parsed.path == "/api/speed":
                set_speed(float(qs["kph"][0]))
                self.send_json(state)
            elif parsed.path == "/api/drive":
                set_drive(qs["state"][0])
                self.send_json(state)
            elif parsed.path == "/api/route/start":
                route_stop.set()
                time.sleep(0.2)
                threading.Thread(target=route_loop, args=(float(qs.get("kph", ["45"])[0]),), daemon=True).start()
                self.send_json(state)
            elif parsed.path == "/api/route/stop":
                route_stop.set()
                set_speed(0)
                set_drive("park")
                self.send_json(state)
            else:
                self.send_error(404)
        except Exception as exc:
            state["last"] = repr(exc)
            self.send_json(state)


if __name__ == "__main__":
    print(f"Pleos Vehicle Controller: http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
