#!/usr/bin/env python3
import argparse
import json
import os
import re
import socketserver
import subprocess
import threading
import time


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--ctags", default="ctags")
    parser.add_argument("--ignore", action="append", default=[])
    parser.add_argument("--poll", type=float, default=5.0)
    parser.add_argument("--no-watch", action="store_true")
    return parser.parse_args()


def parse_tag_line(line):
    if not line or line.startswith("!"):
        return None
    parts = line.split("\t")
    if len(parts) < 3:
        return None
    name = parts[0]
    file_path = parts[1]
    if file_path.startswith("./"):
        file_path = file_path[2:]
    excmd = parts[2]
    line_no = None
    m = re.match(r"^(\d+)", excmd)
    if m:
        line_no = int(m.group(1))
    kind = ""
    scope = ""
    signature = ""
    for field in parts[3:]:
        if len(field) == 1:
            kind = field
            continue
        if field.startswith("kind:"):
            kind = field[5:]
        elif field.startswith("scope:"):
            scope = field[6:]
        elif field.startswith("class:"):
            scope = field[6:]
        elif field.startswith("struct:"):
            scope = field[7:]
        elif field.startswith("enum:"):
            scope = field[5:]
        elif field.startswith("signature:"):
            signature = field[10:]
        elif field.startswith("line:"):
            try:
                line_no = int(field[5:])
            except ValueError:
                pass
    return (name, file_path, line_no or 1, kind, scope, signature)


def build_search_text(tag):
    name, file_path, _, kind, scope, signature = tag
    return " ".join([name or "", kind or "", scope or "", signature or "", file_path or ""])


class Index:
    def __init__(self, root, ctags, ignore):
        self.root = root
        self.ctags = ctags
        self.ignore = set(ignore or [])
        self.lock = threading.RLock()
        self.ready = False
        self.indexing = False
        self.tags_by_file = {}
        self.tags = []
        self.file_mtimes = {}

    def _ctags_cmd(self, files=None):
        cmd = [self.ctags, "--fields=+n", "--excmd=number", "-f", "-"]
        if files:
            cmd += files
        else:
            for entry in sorted(self.ignore):
                cmd.append("--exclude=" + entry)
            cmd += ["-R", "."]
        return cmd

    def _run_ctags(self, files=None):
        cmd = self._ctags_cmd(files)
        proc = subprocess.Popen(
            cmd,
            cwd=self.root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="ignore",
        )
        for line in proc.stdout:
            line = line.rstrip("\n")
            tag = parse_tag_line(line)
            if tag:
                yield tag
        proc.stdout.close()
        proc.wait()

    def _scan_files(self):
        files = {}
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = [d for d in dirnames if d not in self.ignore]
            for filename in filenames:
                rel = os.path.relpath(os.path.join(dirpath, filename), self.root)
                try:
                    mtime = os.path.getmtime(os.path.join(self.root, rel))
                except OSError:
                    continue
                files[rel] = mtime
        return files

    def build_full(self):
        if self.indexing:
            return

        def worker():
            self.indexing = True
            tags_by_file = {}
            for tag in self._run_ctags():
                file_path = tag[1]
                tags_by_file.setdefault(file_path, []).append(tag)
            with self.lock:
                self.tags_by_file = tags_by_file
                self.tags = [t for lst in tags_by_file.values() for t in lst]
                self.file_mtimes = self._scan_files()
                self.ready = True
            self.indexing = False

        threading.Thread(target=worker, daemon=True).start()

    def update_files(self, changed, removed):
        if not changed and not removed:
            return
        tags_by_file = self.tags_by_file.copy()
        for rel in removed:
            tags_by_file.pop(rel, None)
        for rel in changed:
            tags = []
            for tag in self._run_ctags([rel]):
                tags.append(tag)
            if tags:
                tags_by_file[rel] = tags
            else:
                tags_by_file.pop(rel, None)
        with self.lock:
            self.tags_by_file = tags_by_file
            self.tags = [t for lst in tags_by_file.values() for t in lst]

    def watch_loop(self, interval, stop_event):
        while not stop_event.is_set():
            if self.indexing:
                time.sleep(interval)
                continue
            current = self._scan_files()
            changed = []
            removed = []
            for path, mtime in current.items():
                if path not in self.file_mtimes or self.file_mtimes[path] != mtime:
                    changed.append(path)
            for path in self.file_mtimes:
                if path not in current:
                    removed.append(path)
            if changed or removed:
                self.update_files(changed, removed)
                self.file_mtimes = current
            time.sleep(interval)

    def status(self):
        with self.lock:
            return {
                "ready": self.ready,
                "indexing": self.indexing,
                "tag_count": len(self.tags),
                "file_count": len(self.tags_by_file),
            }

    def search(self, req, session):
        query = req.get("query", "")
        mode = req.get("mode", "fuzzy")
        max_results = int(req.get("max", 2000))
        kinds = req.get("kinds")
        case_sensitive = bool(req.get("case_sensitive", False))
        kinds_set = set(kinds) if kinds else None

        if not self.ready:
            return {
                "ready": False,
                "indexing": self.indexing,
                "total": 0,
                "kinds": {},
                "matches": [],
                "limit_hit": False,
                "scanned": 0,
            }

        query_key = query if case_sensitive else query.lower()
        if mode == "regex":
            flags = 0 if case_sensitive else re.IGNORECASE
            regex = re.compile(query, flags)
            match_fn = lambda text: regex.search(text) is not None
        elif mode == "literal":
            match_fn = lambda text: query_key in text
        else:
            tokens = [t for t in query_key.split() if t]
            match_fn = lambda text: all(t in text for t in tokens) if tokens else True

        use_prev = (
            session.last_query
            and query_key.startswith(session.last_query)
            and session.last_mode == mode
            and session.last_kinds == kinds_set
            and not session.last_limit_hit
        )

        with self.lock:
            pool = session.last_results if use_prev else list(self.tags)

        matches = []
        kinds_count = {}
        limit_hit = False
        total = 0
        for tag in pool:
            text = build_search_text(tag)
            text_key = text if case_sensitive else text.lower()
            if match_fn(text_key):
                total += 1
                kind = tag[3] or "?"
                kinds_count[kind] = kinds_count.get(kind, 0) + 1
                if kinds_set is None or kind in kinds_set:
                    if len(matches) < max_results:
                        name, file_path, line_no, kind, scope, signature = tag
                        if not os.path.isabs(file_path):
                            file_path = os.path.join(self.root, file_path)
                        matches.append([name, file_path, line_no, kind, scope, signature])
                    else:
                        limit_hit = True
                        break

        session.last_query = query_key
        session.last_mode = mode
        session.last_kinds = kinds_set
        session.last_limit_hit = limit_hit
        session.last_results = matches if not limit_hit else None

        return {
            "ready": True,
            "indexing": self.indexing,
            "total": total,
            "kinds": kinds_count,
            "matches": matches,
            "limit_hit": limit_hit,
            "scanned": len(pool),
        }


class SessionState:
    def __init__(self):
        self.last_query = ""
        self.last_mode = ""
        self.last_kinds = None
        self.last_limit_hit = False
        self.last_results = None


class RequestHandler(socketserver.StreamRequestHandler):
    def setup(self):
        super().setup()
        self.session = SessionState()

    def handle(self):
        for raw in self.rfile:
            try:
                req = json.loads(raw.decode("utf-8").strip())
            except Exception:
                continue
            cmd = req.get("cmd", "search")
            if cmd == "search":
                resp = self.server.index.search(req, self.session)
                resp["cmd"] = "search"
                resp["seq"] = req.get("seq", 0)
            elif cmd == "status":
                resp = {"cmd": "status", "seq": req.get("seq", 0), "status": self.server.index.status()}
            elif cmd == "index":
                self.server.index.build_full()
                resp = {"cmd": "index", "seq": req.get("seq", 0)}
            elif cmd == "stop":
                resp = {"cmd": "stop", "seq": req.get("seq", 0)}
                self.wfile.write((json.dumps(resp) + "\n").encode("utf-8"))
                self.wfile.flush()
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return
            else:
                resp = {"cmd": "error", "seq": req.get("seq", 0), "error": "unknown cmd"}
            self.wfile.write((json.dumps(resp) + "\n").encode("utf-8"))
            self.wfile.flush()


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    args = parse_args()
    os.makedirs(os.path.dirname(args.socket), exist_ok=True)
    if os.path.exists(args.socket):
        os.remove(args.socket)
    index = Index(args.root, args.ctags, args.ignore)
    index.build_full()

    stop_event = threading.Event()
    if not args.no_watch:
        thread = threading.Thread(target=index.watch_loop, args=(args.poll, stop_event), daemon=True)
        thread.start()

    with Server(args.socket, RequestHandler) as server:
        server.index = index
        try:
            server.serve_forever()
        finally:
            stop_event.set()
            if os.path.exists(args.socket):
                os.remove(args.socket)


if __name__ == "__main__":
    main()
