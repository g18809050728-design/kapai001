"""Build and run the local-only Godot Web admin preview."""

import argparse
import io
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import subprocess
import webbrowser


ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "dist" / "web-local-admin"
ADMIN_BRIDGE = ROOT / "tools" / "local_web_admin.js"
GODOT_VERSION = "4.7.2.stable"
HOST = "127.0.0.1"
DEFAULT_PORT = 8061
SHELL_ASSETS = (
    "game-shell.css", "game-shell.js", "game-shell.woff2", "account-campus.webp",
)
REQUIRED_EXPORTS = ("index.html", "index.js", "index.wasm", "index.pck")
STATIC_FILES = frozenset((*REQUIRED_EXPORTS, *SHELL_ASSETS, "OFL.txt",
    "index.png", "index.icon.png", "index.apple-touch-icon.png",
    "index.audio.worklet.js", "index.audio.position.worklet.js"))


def find_godot(option):
    configured = option or os.environ.get("GODOT_BIN")
    if configured:
        found = shutil.which(configured)
        if found:
            return Path(found).resolve()
        raise RuntimeError(f"找不到指定的 Godot：{configured}")
    local = Path(r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe")
    if local.is_file():
        return local
    for command in ("godot4", "godot"):
        if found := shutil.which(command):
            return Path(found).resolve()
    raise RuntimeError("找不到 Godot。请通过 --godot 或 GODOT_BIN 指定编辑器的可执行文件。")


def build_web(godot):
    result = subprocess.run([str(godot), "--version"], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8", errors="replace")
    version = result.stdout.strip()
    if result.returncode or (version != GODOT_VERSION and not version.startswith(GODOT_VERSION + ".")):
        raise RuntimeError(f"项目需要 Godot {GODOT_VERSION}；当前为 {version or '未知版本'}。")
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / ".gdignore").touch(exist_ok=True)
    print("正在导出本地 Web 管理员版……", flush=True)
    result = subprocess.run(
        [str(godot), "--headless", "--path", str(ROOT), "--export-release", "Web",
         str(BUILD / "index.html")], cwd=ROOT, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
    )
    if result.returncode:
        print("\n".join(result.stdout.splitlines()[-35:]), flush=True)
        raise RuntimeError("Web 导出失败。若缺少模板，请在 Godot 的「管理导出模板」安装同版本模板。")
    for name in REQUIRED_EXPORTS:
        if not (BUILD / name).is_file() or (BUILD / name).stat().st_size == 0:
            raise RuntimeError(f"Web 导出缺少 {name}，没有启动本地服务。")
    for name in SHELL_ASSETS:
        shutil.copyfile(ROOT / "web" / name, BUILD / name)
    shutil.copyfile(ROOT / "assets" / "fonts" / "OFL.txt", BUILD / "OFL.txt")


class LocalWebHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def send_head(self):
        if self.headers.get_all("Host") != [f"{HOST}:{self.server.server_port}"]:
            self.send_error(403, "Open this preview via its loopback address")
            return None
        path = self.path.partition("?")[0]
        if path == "/accounts.js":
            # Do not copy this adapter into the Godot output: only this server serves it.
            data = ADMIN_BRIDGE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            return io.BytesIO(data)
        name = "index.html" if path == "/" else path.removeprefix("/")
        if name not in STATIC_FILES:
            self.send_error(404)
            return None
        self.path = "/" + name
        return super().send_head()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Path to the Godot 4.7.2 executable")
    parser.add_argument("--no-browser", action="store_true", help="Do not open a browser tab")
    args = parser.parse_args()
    try:
        godot = find_godot(args.godot)
        if not ADMIN_BRIDGE.is_file():
            raise RuntimeError(f"本地管理员桥接脚本缺失：{ADMIN_BRIDGE}")
        handler = partial(LocalWebHandler, directory=str(BUILD))
        # Reserve the port first so a second launcher does not overwrite a running build.
        with ThreadingHTTPServer((HOST, DEFAULT_PORT), handler) as server:
            build_web(godot)
            url = f"http://{HOST}:{server.server_port}/"
            print(f"本地管理员版：{url}（Ctrl+C 停止；不连接正式站或云存档）", flush=True)
            if not args.no_browser:
                webbrowser.open(url)
            server.serve_forever()
    except KeyboardInterrupt:
        return 0
    except (OSError, RuntimeError) as error:
        print(f"启动失败：{error}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
