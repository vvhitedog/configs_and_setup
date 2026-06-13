#!/usr/bin/env python3
import argparse
import curses
import json
import os
import socket


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    return parser.parse_args()


class Client:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.file = self.sock.makefile("rwb", buffering=0)
        self.seq = 0

    def send(self, cmd, payload):
        self.seq += 1
        payload["cmd"] = cmd
        payload["seq"] = self.seq
        self.file.write((json.dumps(payload) + "\n").encode("utf-8"))
        self.file.flush()
        while True:
            line = self.file.readline()
            if not line:
                return None
            resp = json.loads(line.decode("utf-8"))
            if resp.get("cmd") == cmd and resp.get("seq") == self.seq:
                return resp


def render(stdscr, query, mode, matches, selected, kinds, status, preview, height, width):
    stdscr.erase()
    stdscr.addstr(0, 0, f"Query [{mode}]: {query}")
    stdscr.addstr(1, 0, status[: width - 1])

    list_height = height - 4
    list_width = width // 2
    for i in range(min(list_height, len(matches))):
        idx = i
        line = matches[idx]
        text = f"{line[0]} [{line[3]}] {line[1]}:{line[2]}"
        text = text[: list_width - 1]
        if idx == selected:
            stdscr.addstr(2 + i, 0, text, curses.A_REVERSE)
        else:
            stdscr.addstr(2 + i, 0, text)

    preview_x = list_width + 2
    for i, line in enumerate(preview[: list_height]):
        stdscr.addstr(2 + i, preview_x, line[: width - preview_x - 1])

    kinds_line = "Kinds: " + " ".join(sorted(kinds.keys()))
    stdscr.addstr(height - 1, 0, kinds_line[: width - 1])
    stdscr.refresh()


def build_preview(match, context=5):
    if not match:
        return []
    name, file_path, line_no = match[0], match[1], int(match[2])
    if not os.path.isfile(file_path):
        return ["(file missing)"]
    with open(file_path, "r", encoding="utf-8", errors="ignore") as fh:
        lines = fh.readlines()
    start = max(0, line_no - context - 1)
    end = min(len(lines), line_no + context)
    out = []
    for idx in range(start, end):
        text = lines[idx].rstrip("\n")
        prefix = f"{idx+1:6d} | "
        if name and name in text:
            text = text.replace(name, f"[{name}]")
        out.append(prefix + text)
    return out


def main(stdscr):
    args = parse_args()
    client = Client(args.socket)

    curses.curs_set(1)
    stdscr.nodelay(False)
    stdscr.keypad(True)

    query = ""
    mode = "fuzzy"
    matches = []
    selected = 0
    kinds = {}
    kinds_filter = set()
    status = ""
    preview = []

    def run_search():
        nonlocal matches, kinds, status, selected, preview
        nonlocal kinds_filter
        kinds_arg = sorted(kinds_filter) if kinds_filter else None
        resp = client.send(
            "search",
            {"query": query, "mode": mode, "max": 200, "kinds": kinds_arg, "case_sensitive": False},
        )
        if not resp:
            status = "No response from server"
            matches = []
            kinds = {}
            preview = []
            return
        if not resp.get("ready", True):
            status = "Indexing..."
            matches = []
            kinds = {}
            preview = []
            return
        matches = resp.get("matches", [])
        kinds = resp.get("kinds", {})
        total = resp.get("total", 0)
        filter_text = ",".join(sorted(kinds_filter)) if kinds_filter else "*"
        status = f"Matches: {len(matches)}/{total}  kinds:{filter_text}"
        selected = 0
        preview = build_preview(matches[0] if matches else None)

    run_search()
    while True:
        height, width = stdscr.getmaxyx()
        render(stdscr, query, mode, matches, selected, kinds, status, preview, height, width)
        ch = stdscr.getch()
        if ch in (27, ord("q")):
            break
        if ch in (curses.KEY_BACKSPACE, 127, 8):
            query = query[:-1]
            run_search()
            continue
        if ch in (curses.KEY_DOWN, ord("j")):
            if matches:
                selected = min(selected + 1, len(matches) - 1)
                preview = build_preview(matches[selected])
            continue
        if ch in (curses.KEY_UP, ord("k")):
            if matches:
                selected = max(selected - 1, 0)
                preview = build_preview(matches[selected])
            continue
        if ch in (ord("\n"), ord("\r")):
            if matches:
                name, file_path, line_no = matches[selected][0], matches[selected][1], matches[selected][2]
                curses.endwin()
                print(f"{file_path}:{line_no}:{name}")
                return
        if ch == ord("t"):
            curses.echo()
            stdscr.addstr(height - 2, 0, "Toggle kind (* for all): ")
            stdscr.clrtoeol()
            kind = stdscr.getstr(height - 2, 24, 8).decode("utf-8").strip()
            curses.noecho()
            if kind == "*" or kind == "":
                kinds_filter.clear()
            else:
                if kind in kinds_filter:
                    kinds_filter.remove(kind)
                else:
                    kinds_filter.add(kind)
            run_search()
            continue
        if ch in (ord("\t"),):
            continue
        if ch == 6:  # Ctrl-f
            mode = "fuzzy"
            run_search()
            continue
        if ch == 18:  # Ctrl-r
            mode = "regex"
            run_search()
            continue
        if ch == 12:  # Ctrl-l
            mode = "literal"
            run_search()
            continue
        if 32 <= ch <= 126:
            query += chr(ch)
            run_search()


if __name__ == "__main__":
    curses.wrapper(main)
