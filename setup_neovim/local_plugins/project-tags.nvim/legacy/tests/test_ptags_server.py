import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parents[1]
MODULE_DIR = PLUGIN_ROOT / "lua" / "project_tags"
sys.path.insert(0, str(MODULE_DIR))

import ptags_server as ps  # noqa: E402


class TestParseTagLine(unittest.TestCase):
    def test_parse_basic(self):
        line = "foo\t./src/main.c\t12;\"\tf"
        tag = ps.parse_tag_line(line)
        self.assertEqual(tag[0], "foo")
        self.assertEqual(tag[1], "src/main.c")
        self.assertEqual(tag[2], 12)
        self.assertEqual(tag[3], "f")

    def test_parse_fields(self):
        line = "Bar\tfile.cpp\t42;\"\tkind:c\tscope:Ns\tline:42"
        tag = ps.parse_tag_line(line)
        self.assertEqual(tag[0], "Bar")
        self.assertEqual(tag[2], 42)
        self.assertEqual(tag[3], "c")
        self.assertEqual(tag[4], "Ns")


class TestIndexSearch(unittest.TestCase):
    def _index_with_tags(self, root, tags):
        index = ps.Index(root, ctags="ctags", ignore=[])
        index.tags = tags
        index.ready = True
        index.indexing = False
        return index

    def test_search_prefix_narrowing(self):
        tags = [
            ("facebook", "src/a.c", 1, "f", "", "",),
            ("factory", "src/b.c", 2, "f", "", "",),
            ("beta", "src/c.c", 3, "v", "", "",),
        ]
        index = self._index_with_tags("/tmp", tags)
        session = ps.SessionState()

        r1 = index.search({"query": "f", "mode": "fuzzy", "max": 10, "kinds": None, "case_sensitive": False}, session)
        r2 = index.search({"query": "fa", "mode": "fuzzy", "max": 10, "kinds": None, "case_sensitive": False}, session)
        self.assertGreaterEqual(r1["total"], r2["total"])

    def test_search_limit_hit_resets_pool(self):
        tags = [
            ("foo", "a.c", 1, "f", "", ""),
            ("food", "b.c", 2, "f", "", ""),
            ("fool", "c.c", 3, "f", "", ""),
        ]
        index = self._index_with_tags("/tmp", tags)
        session = ps.SessionState()

        r1 = index.search({"query": "f", "mode": "fuzzy", "max": 1, "kinds": None, "case_sensitive": False}, session)
        self.assertTrue(r1["limit_hit"])
        r2 = index.search({"query": "fo", "mode": "fuzzy", "max": 10, "kinds": None, "case_sensitive": False}, session)
        self.assertEqual(r2["scanned"], len(tags))

    def test_search_returns_absolute_path(self):
        root = "/tmp/project"
        tags = [
            ("foo", "src/a.c", 1, "f", "", ""),
        ]
        index = self._index_with_tags(root, tags)
        session = ps.SessionState()

        r1 = index.search({"query": "foo", "mode": "literal", "max": 10, "kinds": None, "case_sensitive": True}, session)
        self.assertTrue(r1["matches"])
        match = r1["matches"][0]
        self.assertTrue(os.path.isabs(match[1]))


class TestServerProtocol(unittest.TestCase):
    def test_server_search_response(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            socket_path = os.path.join(tmpdir, "ptags.sock")
            index = ps.Index(tmpdir, ctags="ctags", ignore=[])
            index.tags = [
                ("facebook", "src/a.c", 1, "f", "", ""),
                ("beta", "src/b.c", 2, "v", "", ""),
            ]
            index.ready = True
            index.indexing = False

            server = ps.Server(socket_path, ps.RequestHandler)
            server.index = index

            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()

            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(socket_path)
            sock_file = sock.makefile("rwb", buffering=0)

            req = {"cmd": "search", "seq": 1, "query": "fa", "mode": "fuzzy", "max": 10, "kinds": None, "case_sensitive": False}
            sock_file.write((json.dumps(req) + "\n").encode("utf-8"))
            sock_file.flush()
            line = sock_file.readline()
            resp = json.loads(line.decode("utf-8"))
            self.assertEqual(resp["cmd"], "search")
            self.assertGreater(resp["total"], 0)

            sock_file.close()
            sock.shutdown(socket.SHUT_RDWR)
            sock.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=1)


if __name__ == "__main__":
    unittest.main()
import importlib.util
import json
import os
import socket
import subprocess
import tempfile
import time
import unittest


ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_PATH = os.path.join(ROOT_DIR, "lua", "project_tags", "ptags_server.py")


def load_server_module():
    spec = importlib.util.spec_from_file_location("ptags_server", SERVER_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ServerUnitTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_server_module()

    def test_parse_tag_line(self):
        line = "facebook\t./src/main.c\t123;\"\tf\tline:123\tkind:function\tscope:Foo"
        tag = self.mod.parse_tag_line(line)
        self.assertEqual(tag[0], "facebook")
        self.assertEqual(tag[1], "src/main.c")
        self.assertEqual(tag[2], 123)
        self.assertEqual(tag[3], "function")
        self.assertEqual(tag[4], "Foo")

    def test_build_search_text(self):
        tag = ("alpha", "src/a.c", 10, "f", "Cls", "sig()")
        text = self.mod.build_search_text(tag)
        self.assertIn("alpha", text)
        self.assertIn("src/a.c", text)
        self.assertIn("f", text)

    def test_index_search(self):
        index = self.mod.Index("/tmp", "ctags", [])
        index.tags = [
            ("facebook", "file1.c", 1, "f", "", ""),
            ("feature", "file2.c", 2, "v", "", ""),
            ("alpha", "file3.c", 3, "f", "", ""),
        ]
        index.ready = True
        session = self.mod.SessionState()
        resp = index.search({"query": "fa", "mode": "fuzzy", "max": 10, "kinds": None, "case_sensitive": False}, session)
        self.assertTrue(resp["ready"])
        self.assertGreaterEqual(resp["total"], 1)
        resp2 = index.search({"query": "fac", "mode": "fuzzy", "max": 10, "kinds": None, "case_sensitive": False}, session)
        self.assertGreaterEqual(resp2["total"], 1)
        resp3 = index.search({"query": "zz", "mode": "literal", "max": 10, "kinds": None, "case_sensitive": False}, session)
        self.assertEqual(resp3["total"], 0)


class ServerIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_server_module()

    def _fake_ctags(self, root):
        script = os.path.join(root, "fake_ctags.py")
        with open(script, "w", encoding="utf-8") as fh:
            fh.write(
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "print('facebook\\tfile1.c\\t1;\\\"\\tf')\n"
                "print('feature\\tfile2.c\\t2;\\\"\\tv')\n"
            )
        os.chmod(script, 0o755)
        return script

    def _wait_for_socket(self, path, timeout=5.0):
        start = time.time()
        while time.time() - start < timeout:
            if os.path.exists(path):
                return True
            time.sleep(0.05)
        return False

    def _send(self, sock, cmd, seq, payload):
        payload = dict(payload)
        payload["cmd"] = cmd
        payload["seq"] = seq
        sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        data = b""
        while b"\n" not in data:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
        line = data.split(b"\n", 1)[0]
        return json.loads(line.decode("utf-8"))

    def test_server_roundtrip(self):
        with tempfile.TemporaryDirectory() as root:
            with open(os.path.join(root, "file1.c"), "w", encoding="utf-8") as fh:
                fh.write("int facebook() { return 1; }\n")
            with open(os.path.join(root, "file2.c"), "w", encoding="utf-8") as fh:
                fh.write("int feature = 0;\n")

            fake_ctags = self._fake_ctags(root)
            sock_path = os.path.join(root, "ptags.sock")
            proc = subprocess.Popen(
                [os.getenv("PYTHON", "python3"), SERVER_PATH, "--root", root, "--socket", sock_path, "--ctags", fake_ctags, "--no-watch"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                self.assertTrue(self._wait_for_socket(sock_path))
                client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                client.connect(sock_path)
                seq = 1
                ready = False
                for _ in range(50):
                    status = self._send(client, "status", seq, {})
                    seq += 1
                    if status.get("status", {}).get("ready"):
                        ready = True
                        break
                    time.sleep(0.05)
                self.assertTrue(ready)
                resp = self._send(client, "search", seq, {"query": "fa", "mode": "fuzzy", "max": 10, "kinds": None, "case_sensitive": False})
                self.assertGreaterEqual(resp.get("total", 0), 1)
                seq += 1
                self._send(client, "stop", seq, {})
                client.close()
            finally:
                proc.terminate()
                proc.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
