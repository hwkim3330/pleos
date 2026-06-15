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
MULTIMODE_ACTIVITY = "com.example.pleosmrmviewer/.MainActivity"
RECONFIG_ACTIVITY = "com.example.pleosreconfig/.MainActivity"
CBOR_ACTION = "com.pleos.SIMULATE_CBOR"

FAULTS = {
    "clear-lidar": {
        "label": "Clear LiDAR fault",
        "hex": "A266616374696F6E0062696403",
        "decoded": {"action": 0, "id": 3},
        "target": "FrontCenterLidar",
        "expected": "Remove front LiDAR warning",
    },
    "clear-mrm": {
        "label": "Clear MRM fault",
        "hex": "A266616374696F6E006269641833",
        "decoded": {"action": 0, "id": 51},
        "target": "FrontCenterCamera",
        "expected": "Remove MRM stop warning",
    },
    "front-lidar-degraded": {
        "label": "Front LiDAR degraded",
        "hex": "A566616374696F6E016269640364636F64651867667461726765747046726F6E7443656E7465724C6964617268736576657269747901",
        "decoded": {"action": 1, "id": 3, "code": 103, "target": "FrontCenterLidar", "severity": 1},
        "target": "FrontCenterLidar",
        "expected": "Autoware switches away from weak front LiDAR confidence",
    },
    "rear-zc-warning": {
        "label": "Rear TSN/ZC warning",
        "hex": "A566616374696F6E016269640164636F646518656674617267657466526561725A4368736576657269747902",
        "decoded": {"action": 1, "id": 1, "code": 101, "target": "RearZC", "severity": 2},
        "target": "RearZC",
        "expected": "Rear zonal/TSN degradation and reconfiguration",
    },
    "mrm-stop": {
        "label": "MRM safe stop",
        "hex": "A566616374696F6E01626964183364636F6465190132667461726765747146726F6E7443656E74657243616D65726168736576657269747903",
        "decoded": {"action": 1, "id": 51, "code": 306, "target": "FrontCenterCamera", "severity": 3},
        "target": "FrontCenterCamera",
        "expected": "Trigger Autoware MRM behavior and safe stop trajectory",
    },
}

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
route_thread = None


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


def open_activity(component):
    return adb("shell", "am", "start", "-n", component)


def send_cbor_fault(name):
    fault = FAULTS.get(name)
    if not fault:
        raise ValueError(f"unknown fault: {name}")
    return send_cbor_hex(fault["hex"])


def send_cbor_hex(hex_value):
    return adb(
        "shell",
        "am",
        "broadcast",
        "-a",
        CBOR_ACTION,
        "--es",
        "cbor_hex",
        hex_value,
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
    try:
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
                    if route_stop.is_set():
                        break
                    set_speed(speed_kph + math.sin(time.time()) * 3)
                    time.sleep(0.8)
            if route_stop.is_set():
                break
    finally:
        state["routeRunning"] = False


def stop_route():
    global route_thread
    route_stop.set()
    if route_thread and route_thread.is_alive():
        route_thread.join(timeout=2.0)
    state["routeRunning"] = False
    set_speed(0)
    set_drive("park")
    time.sleep(0.2)
    set_speed(0)
    return set_drive("park")


def html():
    faults_json = json.dumps(FAULTS, ensure_ascii=False)
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Pleos Vehicle Controller</title>
  <style>
    :root {{
      --bg:#f4f6f8; --panel:#ffffff; --panel2:#f8fafc; --line:#d9e0e8;
      --text:#172033; --muted:#667085; --blue:#2563eb; --green:#079455;
      --amber:#b54708; --red:#d92d20; --ink:#111827; --term:#101828;
    }}
    * {{ box-sizing:border-box; }}
    body {{
      margin:0; min-height:100vh; background:var(--bg); color:var(--text);
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
    }}
    main {{ padding:18px; max-width:1680px; margin:0 auto; }}
    header {{
      height:56px; display:flex; align-items:center; justify-content:space-between;
      border-bottom:1px solid var(--line); margin-bottom:14px;
    }}
    h1 {{ font-size:18px; margin:0; letter-spacing:0; }}
    h2 {{ font-size:12px; margin:0 0 10px; color:var(--muted); text-transform:uppercase; }}
    label {{ display:block; font-size:11px; font-weight:800; color:var(--muted); margin:10px 0 5px; }}
    input, textarea {{
      width:100%; border:1px solid var(--line); background:white; color:var(--text);
      border-radius:6px; padding:8px 10px; font:700 12px ui-monospace,SFMono-Regular,Menlo,monospace;
    }}
    textarea {{ min-height:108px; resize:vertical; line-height:1.45; }}
    button {{
      min-height:34px; border:1px solid #c8d1dc; border-radius:6px; background:#fff;
      color:var(--text); padding:0 10px; font-weight:800; cursor:pointer;
    }}
    button:hover {{ border-color:var(--blue); color:var(--blue); }}
    button.primary {{ background:var(--blue); border-color:var(--blue); color:white; }}
    button.green {{ background:var(--green); border-color:var(--green); color:white; }}
    button.red {{ background:var(--red); border-color:var(--red); color:white; }}
    button.ghost {{ background:var(--panel2); }}
    .status {{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; }}
    .chip {{
      border:1px solid var(--line); background:var(--panel); border-radius:999px;
      padding:7px 10px; font-size:12px; font-weight:900; color:var(--muted);
    }}
    .chip b {{ color:var(--ink); }}
    .layout {{ display:grid; grid-template-columns:320px minmax(460px,1fr) 420px; gap:12px; min-height:calc(100vh - 90px); }}
    .panel {{
      background:var(--panel); border:1px solid var(--line); border-radius:8px;
      overflow:hidden; box-shadow:0 8px 20px rgba(16,24,40,.05);
    }}
    .panel-inner {{ padding:12px; }}
    .section {{ border-top:1px solid var(--line); padding:12px; }}
    .section:first-child {{ border-top:0; }}
    .row {{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; }}
    .grid2 {{ display:grid; grid-template-columns:1fr 1fr; gap:8px; }}
    .speedline {{ display:grid; grid-template-columns:1fr 64px; gap:8px; align-items:center; }}
    input[type=range] {{ padding:0; }}
    .quick button {{ flex:1 1 80px; }}
    .terminal {{
      height:100%; display:flex; flex-direction:column; background:var(--term); color:#d0d5dd;
      font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
    }}
    .term-head {{
      display:flex; justify-content:space-between; align-items:center; padding:10px 12px;
      border-bottom:1px solid #344054; background:#182230;
    }}
    .term-log {{ flex:1; overflow:auto; padding:12px; white-space:pre-wrap; font-size:12px; line-height:1.5; }}
    .prompt {{ display:grid; grid-template-columns:56px 1fr 70px; gap:8px; padding:10px; border-top:1px solid #344054; background:#182230; }}
    .prompt input {{ background:#0b1220; border-color:#344054; color:#e4e7ec; }}
    .prompt span {{ align-self:center; color:#47cd89; font-weight:900; }}
    .fault-list {{ display:grid; gap:8px; }}
    .fault-card {{
      width:100%; min-height:58px; text-align:left; border:1px solid var(--line); background:var(--panel2);
      display:block; padding:8px 10px;
    }}
    .fault-card strong {{ display:block; font-size:12px; color:var(--text); }}
    .fault-card small {{ display:block; margin-top:3px; color:var(--muted); font-weight:700; }}
    .fault-card.active {{ border-color:var(--blue); box-shadow:0 0 0 2px rgba(37,99,235,.12); }}
    .kv {{ display:grid; grid-template-columns:92px 1fr; gap:6px 10px; font-size:12px; }}
    .kv div:nth-child(odd) {{ color:var(--muted); font-weight:900; }}
    .hexbox {{ word-break:break-all; background:#f2f4f7; border:1px solid var(--line); border-radius:6px; padding:10px; font:700 11px ui-monospace,SFMono-Regular,Menlo,monospace; }}
    .decoded {{ background:#101828; color:#d0d5dd; border-radius:6px; padding:10px; font:12px ui-monospace,SFMono-Regular,Menlo,monospace; white-space:pre-wrap; }}
    .hint {{ color:var(--muted); font-size:12px; line-height:1.45; margin:8px 0 0; }}
    @media (max-width:1180px) {{
      .layout {{ grid-template-columns:1fr; }}
      .terminal {{ min-height:460px; }}
    }}
  </style>
</head>
<body>
<main>
  <header>
    <div>
      <h1>PLEOS Control Terminal</h1>
      <div class="hint">ADB vehicle control, Autoware mode trigger, CBOR fault injection</div>
    </div>
    <div class="status">
      <div class="chip">lat <b id="lat">{state["lat"]:.5f}</b></div>
      <div class="chip">lon <b id="lon">{state["lon"]:.5f}</b></div>
      <div class="chip">speed <b id="speed">{state["speedKph"]:.0f}</b> km/h</div>
      <div class="chip">gear <b id="drive">{state["driveState"]}</b></div>
      <div class="chip">route <b id="route">idle</b></div>
    </div>
  </header>

  <div class="layout">
    <aside class="panel">
      <div class="section">
        <h2>Applications</h2>
        <div class="row">
          <button class="primary" onclick="openApp('drive')">Drive Pilot</button>
          <button onclick="openApp('reconfig')">Reconfig</button>
          <button onclick="openApp('multimode')">Multimode</button>
        </div>
      </div>
      <div class="section">
        <h2>Vehicle State</h2>
        <div class="speedline">
          <input id="ispeed" type="range" min="0" max="130" value="{state["speedKph"]}" oninput="sval.value=this.value">
          <input id="sval" value="{state["speedKph"]}" oninput="ispeed.value=this.value">
        </div>
        <div class="row" style="margin-top:8px">
          <button onclick="speed()">Set Speed</button>
          <button class="green" onclick="drive('drive')">Drive</button>
          <button onclick="drive('park')">Park</button>
          <button onclick="drive('reverse')">Reverse</button>
        </div>
      </div>
      <div class="section">
        <h2>Location</h2>
        <div class="grid2">
          <div><label>Latitude</label><input id="ilat" value="{state["lat"]:.7f}"></div>
          <div><label>Longitude</label><input id="ilon" value="{state["lon"]:.7f}"></div>
        </div>
        <div class="row" style="margin-top:8px">
          <button onclick="geo()">Set GPS</button>
          <button onclick="preset(37.40180,127.10895)">Start</button>
          <button onclick="preset(37.40636,127.11578)">Goal</button>
        </div>
      </div>
      <div class="section quick">
        <h2>Route / Quick Commands</h2>
        <div class="row">
          <button class="green" onclick="startRoute()">Route</button>
          <button class="red" onclick="stopRoute()">Stop</button>
          <button onclick="quick(30)">30</button>
          <button onclick="quick(80)">80</button>
          <button onclick="quick(0)">0</button>
        </div>
      </div>
    </aside>

    <section class="panel terminal">
      <div class="term-head">
        <strong>live command log</strong>
        <div class="row"><button class="ghost" onclick="clearLog()">Clear</button></div>
      </div>
      <div id="out" class="term-log"></div>
      <div class="prompt">
        <span>pleos&gt;</span>
        <input id="cmd" placeholder="try: open reconfig, speed 45, gear drive, fault mrm-stop, cbor A266..." onkeydown="if(event.key==='Enter') runPrompt()">
        <button class="primary" onclick="runPrompt()">Run</button>
      </div>
    </section>

    <aside class="panel">
      <div class="section">
        <h2>CBOR Fault Presets</h2>
        <div id="faults" class="fault-list"></div>
      </div>
      <div class="section">
        <h2>CBOR Inspector</h2>
        <div class="kv">
          <div>Name</div><div id="faultName">-</div>
          <div>Target</div><div id="faultTarget">-</div>
          <div>Expected</div><div id="faultExpected">-</div>
        </div>
        <label>Raw Hex</label>
        <div id="faultHex" class="hexbox">Select a fault preset or paste raw CBOR.</div>
        <label>Decoded Fields</label>
        <div id="faultDecoded" class="decoded">{{}}</div>
        <div class="row" style="margin-top:10px">
          <button class="red" onclick="sendSelectedFault()">Send Selected</button>
          <button onclick="copyHex()">Copy Hex</button>
        </div>
      </div>
      <div class="section">
        <h2>Raw CBOR</h2>
        <textarea id="rawHex" placeholder="Paste CBOR hex here"></textarea>
        <div class="row" style="margin-top:8px">
          <button class="primary" onclick="sendRawCbor()">Send Raw</button>
          <button onclick="inspectRaw()">Inspect Only</button>
        </div>
      </div>
    </aside>
  </div>
</main>
<script>
const FAULTS = {faults_json};
let selectedFault = 'front-lidar-degraded';
let lines = ['PLEOS control terminal ready.', 'Target ADB serial: {ADB_SERIAL}', ''];

function append(title, payload) {{
  const stamp = new Date().toLocaleTimeString();
  lines.push(`[${{stamp}}] ${{title}}`);
  if (payload) lines.push(payload.trim());
  lines.push('');
  out.textContent = lines.slice(-180).join('\\n');
  out.scrollTop = out.scrollHeight;
}}

async function call(path, label) {{
  const r = await fetch(path);
  const j = await r.json();
  append(label || path, j.last || JSON.stringify(j,null,2));
  refresh();
  return j;
}}
function geo() {{ call(`/api/geo?lat=${{ilat.value}}&lon=${{ilon.value}}`); }}
function preset(lat, lon) {{ ilat.value=lat; ilon.value=lon; geo(); }}
function speed() {{ call(`/api/speed?kph=${{ispeed.value}}`); }}
function quick(v) {{
  ispeed.value=v; sval.textContent=v;
  if (Number(v) === 0) {{ stopRoute(); return; }}
  speed();
}}
function drive(v) {{ call(`/api/drive?state=${{v}}`, `gear ${{v}}`); }}
function openApp(v) {{ call(`/api/open?app=${{v}}`, `open ${{v}}`); }}
function fault(v) {{ selectFault(v); call(`/api/fault?name=${{v}}`, `fault ${{v}}`); }}
function startRoute() {{ call(`/api/route/start?kph=${{ispeed.value || 45}}`, 'route start'); }}
function stopRoute() {{ call('/api/route/stop', 'route stop'); }}
function clearLog() {{ lines = ['log cleared']; out.textContent = lines.join('\\n'); }}

function renderFaults() {{
  faults.innerHTML = Object.entries(FAULTS).map(([key, fault]) => `
    <button class="fault-card" id="fault-${{key}}" onclick="selectFault('${{key}}')">
      <strong>${{fault.label}}</strong>
      <small>${{fault.target}} · ${{fault.expected}}</small>
    </button>
  `).join('');
  selectFault(selectedFault);
}}

function selectFault(key) {{
  selectedFault = key;
  const fault = FAULTS[key];
  document.querySelectorAll('.fault-card').forEach(el => el.classList.remove('active'));
  const active = document.getElementById(`fault-${{key}}`);
  if (active) active.classList.add('active');
  faultName.textContent = fault?.label || '-';
  faultTarget.textContent = fault?.target || '-';
  faultExpected.textContent = fault?.expected || '-';
  faultHex.textContent = fault?.hex || '';
  faultDecoded.textContent = JSON.stringify(fault?.decoded || {{}}, null, 2);
  rawHex.value = fault?.hex || '';
}}

function sendSelectedFault() {{ fault(selectedFault); }}
function sendRawCbor() {{
  const hex = rawHex.value.replace(/\\s/g, '');
  call(`/api/cbor?hex=${{encodeURIComponent(hex)}}`, 'cbor raw');
}}
function inspectRaw() {{
  faultName.textContent = 'Raw CBOR';
  faultTarget.textContent = 'manual';
  faultExpected.textContent = 'decode in Android native path when sent';
  faultHex.textContent = rawHex.value.replace(/\\s/g, '');
  faultDecoded.textContent = 'Raw hex only. Use app logcat/native CBOR decoder for authoritative fields.';
}}
async function copyHex() {{ await navigator.clipboard.writeText(faultHex.textContent); append('copy hex', 'copied selected CBOR hex'); }}

function runPrompt() {{
  const text = cmd.value.trim();
  if (!text) return;
  cmd.value = '';
  append(`pleos> ${{text}}`, '');
  const [head, ...rest] = text.split(/\\s+/);
  const arg = rest.join(' ');
  if (head === 'open') return openApp(arg || 'drive');
  if (head === 'speed') {{ ispeed.value = Number(arg || 0); sval.value = ispeed.value; return speed(); }}
  if (head === 'gear') return drive(arg || 'park');
  if (head === 'drive') return drive('drive');
  if (head === 'park') return drive('park');
  if (head === 'route') return arg === 'stop' ? stopRoute() : startRoute();
  if (head === 'fault') return fault(arg || selectedFault);
  if (head === 'cbor') {{ rawHex.value = arg; return sendRawCbor(); }}
  append('unknown command', 'open|speed|gear|route|fault|cbor');
}}

async function refresh() {{
  const r = await fetch('/api/status'); const j = await r.json();
  lat.textContent = Number(j.lat).toFixed(5); lon.textContent = Number(j.lon).toFixed(5);
  speed.textContent = Number(j.speedKph).toFixed(0); drive.textContent = j.driveState;
  route.textContent = j.routeRunning ? 'running' : 'idle';
}}
renderFaults();
append('status', 'controller loaded');
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
        global route_thread
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
            elif parsed.path == "/api/open":
                app = qs.get("app", ["drive"])[0]
                component = {
                    "drive": APP_ACTIVITY,
                    "multimode": MULTIMODE_ACTIVITY,
                    "reconfig": RECONFIG_ACTIVITY,
                }.get(app)
                if component is None:
                    raise ValueError(f"unknown app: {app}")
                open_activity(component)
                self.send_json(state)
            elif parsed.path == "/api/fault":
                send_cbor_fault(qs["name"][0])
                self.send_json(state)
            elif parsed.path == "/api/cbor":
                send_cbor_hex(qs["hex"][0])
                self.send_json(state)
            elif parsed.path == "/api/route/start":
                route_stop.set()
                if route_thread and route_thread.is_alive():
                    route_thread.join(timeout=2.0)
                route_thread = threading.Thread(
                    target=route_loop,
                    args=(float(qs.get("kph", ["45"])[0]),),
                    daemon=True,
                )
                route_thread.start()
                self.send_json(state)
            elif parsed.path == "/api/route/stop":
                stop_route()
                self.send_json(state)
            else:
                self.send_error(404)
        except Exception as exc:
            state["last"] = repr(exc)
            self.send_json(state)


if __name__ == "__main__":
    print(f"Pleos Vehicle Controller: http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
