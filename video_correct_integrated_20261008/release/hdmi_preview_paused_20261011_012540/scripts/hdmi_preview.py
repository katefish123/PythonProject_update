"""Local read-only preview for the latest captured HDMI frame."""

from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


PROJECT_ROOT = Path(__file__).resolve().parent.parent
FRAME_PATH = PROJECT_ROOT / "results" / "hardware_20261009" / "live_latest.jpg"
TARGET_PATH = PROJECT_ROOT / "results" / "ddr_fixture" / "source_640x480.png"
HOST = "127.0.0.1"
PORT = 8766

PAGE = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FPGA HDMI 画面</title>
<style>
body { margin: 0; padding: 24px; background: #111827; color: #f3f4f6;
  font: 16px system-ui, sans-serif; }
main { max-width: 1100px; margin: auto; }
h1 { font-size: 1.6rem; margin: 0 0 8px; }
p { color: #cbd5e1; }
#status { min-height: 1.5em; }
#frame { display: block; width: 100%; max-height: 78vh; object-fit: contain;
  background: #030712; border-radius: 8px; }
</style>
</head>
<body><main>
<h1>FPGA HDMI 画面</h1>
<p>画面来自 HDMI 采集卡。</p>
<p id="status" role="status">正在等待画面…</p>
<img id="frame" alt="FPGA HDMI 实时画面">
<script>
const frame = document.getElementById('frame');
const status = document.getElementById('status');
let currentUrl = null;
let lastUpdated = null;
async function refreshFrame() {
  try {
    const response = await fetch('/frame.jpg', { cache: 'no-store' });
    if (!response.ok) throw new Error('等待画面');
    const updated = response.headers.get('X-Frame-Updated') || '';
    lastUpdated = updated ? new Date(updated) : new Date();
    const blob = await response.blob();
    const nextUrl = URL.createObjectURL(blob);
    frame.onload = () => {
      if (currentUrl) URL.revokeObjectURL(currentUrl);
      currentUrl = nextUrl;
    };
    frame.src = nextUrl;
    showStatus();
  } catch (_) {
    status.textContent = '正在等待画面…';
  }
}
function showStatus() {
  if (!lastUpdated) return;
  const ageSeconds = (Date.now() - lastUpdated.getTime()) / 1000;
  status.textContent = ageSeconds > 5
    ? '采集已暂停，下面是最后一帧'
    : `图像更新时间：${lastUpdated.toLocaleString('zh-CN')}`;
}
refreshFrame();
setInterval(refreshFrame, 500);
setInterval(showStatus, 500);
</script>
</main></body></html>"""

TARGET_PAGE = """<!doctype html><html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>相机测试图</title><style>
html,body{margin:0;height:100%;background:#6e6e6e;color:white;font:16px system-ui,sans-serif}
body{display:flex;flex-direction:column;align-items:center}
nav{text-align:center;padding:12px}button{font:inherit;padding:7px 16px;background:#eee;color:#222;border:0;border-radius:4px}
img{display:block;min-height:0;max-width:100%;flex:1;object-fit:contain;width:100%}
:fullscreen nav{display:none}
</style></head><body><nav>
<p>将相机对准这张图，完整拍到四个彩色角标，并让测试图尽量占满相机画面。</p>
<button onclick="document.documentElement.requestFullscreen()">全屏显示测试图</button>
</nav><img src="/target.png" alt="四色角标相机测试图"></body></html>"""


class PreviewHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path in ("/", "/target"):
            body = (TARGET_PAGE if path == "/target" else PAGE).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/target.png":
            try:
                body = TARGET_PATH.read_bytes()
            except OSError:
                self.send_error(503, "Test target unavailable")
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/frame.jpg":
            try:
                frame = FRAME_PATH.read_bytes()
                modified = datetime.fromtimestamp(FRAME_PATH.stat().st_mtime).astimezone()
                timestamp = modified.isoformat(timespec="seconds")
            except (FileNotFoundError, PermissionError, IsADirectoryError):
                body = b"Frame not available yet."
                self.send_response(503)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(frame)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Frame-Updated", timestamp)
            self.end_headers()
            self.wfile.write(frame)
            return
        self.send_error(404)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), PreviewHandler)
    print(f"预览页面：http://{HOST}:{PORT}/")
    server.serve_forever()
