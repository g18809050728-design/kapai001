"""Contract checks for the loopback-only preview server (no Godot required)."""

from functools import partial
from http.client import HTTPConnection
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
import unittest

from start_local_web import ADMIN_BRIDGE, HOST, LocalWebHandler, ThreadingHTTPServer


class LocalWebLauncherTests(unittest.TestCase):
    def setUp(self):
        work = TemporaryDirectory()
        self.addCleanup(work.cleanup)
        root = Path(work.name)
        (root / "index.html").write_bytes(b"local preview")
        (root / "index.wasm").write_bytes(b"dummy wasm")
        (root / "private.txt").write_bytes(b"not a game asset")
        handler = partial(LocalWebHandler, directory=str(root))
        self.server = ThreadingHTTPServer((HOST, 0), handler)
        self.addCleanup(self.server.server_close)
        thread = Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(self.server.shutdown)

    def request(self, method, path, **headers):
        conn = HTTPConnection(HOST, self.server.server_port, timeout=5)
        try:
            conn.request(method, path, headers=headers)
            response = conn.getresponse()
            return response.status, {key.lower(): value for key, value in response.getheaders()}, response.read()
        finally:
            conn.close()

    def test_main_page_and_wasm(self):
        status, headers, body = self.request("GET", "/")
        self.assertEqual((status, body), (200, b"local preview"))
        self.assertEqual(headers["cache-control"], "no-store")
        status, headers, body = self.request("HEAD", "/index.wasm")
        self.assertEqual((status, headers["content-type"], body), (200, "application/wasm", b""))

    def test_serves_local_bridge_without_copying_into_build(self):
        status, headers, body = self.request("GET", "/accounts.js")
        self.assertEqual((status, body), (200, ADMIN_BRIDGE.read_bytes()))
        self.assertEqual(headers["content-type"], "text/javascript; charset=utf-8")
        self.assertNotIn("access-control-allow-origin", headers)

    def test_rejects_non_loopback_host_and_has_no_account_api(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        self.assertEqual(self.request("GET", "/accounts.js", Host="non-loopback.test")[0], 403)
        for path in ("/api/v1/auth/session", "/private.txt", "/%2e%2e/project.godot"):
            with self.subTest(path=path):
                self.assertEqual(self.request("GET", path)[0], 404)
