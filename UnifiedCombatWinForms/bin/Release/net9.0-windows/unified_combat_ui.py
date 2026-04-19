#!/usr/bin/env python3
"""
Headless desktop hub for UnifiedCombat Windower addon.

- Listens on 127.0.0.1:27182 for TCP connections from game clients (NDJSON).
- Serves the WinForms UI channel on 127.0.0.1:27183 (mirror_snapshot / mirror_forward / mirror_error).

Run this process, then start UnifiedCombatWinForms.exe for the full UI.
Requires Python 3.8+ (asyncio). No Tkinter dependency.
"""

from __future__ import annotations

import asyncio
import json
from typing import Any, Dict, Optional, Set

HOST = "127.0.0.1"
PORT = 27182
# NDJSON control plane for UnifiedCombatWinForms (same payloads as game TCP).
# From hub: {"op":"mirror_snapshot","sessions":{...}}, {"op":"mirror_error",...}
# To hub:   {"op":"mirror_forward","sid":"<sid>","msg":{...}}
MIRROR_PORT = 27183
MIRROR_BROADCAST_COALESCE_S = 0.25


def parse_ndjson_line(line: bytes) -> Optional[dict]:
    line = line.strip()
    if not line:
        return None
    try:
        return json.loads(line.decode("utf-8", errors="replace"))
    except json.JSONDecodeError:
        return None


class UnifiedCombatHub:
    def __init__(self) -> None:
        self.sessions: Dict[str, Dict[str, Any]] = {}
        self.writers: Dict[str, asyncio.StreamWriter] = {}
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        self._server: Optional[asyncio.Server] = None
        self._mirror_server: Optional[asyncio.Server] = None
        self.mirror_clients: Set[asyncio.StreamWriter] = set()
        self._mirror_broadcast_handle: Optional[asyncio.TimerHandle] = None

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        sid = None
        hello_seen = False
        try:
            while True:
                raw = await reader.readline()
                if not raw:
                    break
                msg = parse_ndjson_line(raw)
                if not msg or not isinstance(msg, dict):
                    continue
                op = msg.get("op")
                if op == "hello":
                    proposed = str(msg.get("session") or id(writer))
                    sid = proposed
                    if sid in self.writers and self.writers[sid] is not writer:
                        sid = f"{proposed}::{id(writer)}"
                    self.writers[sid] = writer
                    self.sessions[sid] = {
                        "session": sid,
                        "char": msg.get("char", ""),
                        "job": msg.get("job", ""),
                        "engine": msg.get("engine", ""),
                    }
                    hello_seen = True
                    self.schedule_mirror_broadcast()
                elif op == "state" and msg.get("session"):
                    if hello_seen and sid and sid in self.sessions:
                        patched = dict(msg)
                        patched["session"] = sid
                        self.sessions[sid].update(patched)
                        self.schedule_mirror_broadcast()
        finally:
            if sid:
                self.writers.pop(sid, None)
                self.sessions.pop(sid, None)
            self.schedule_mirror_broadcast()
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _run_server(self) -> None:
        self._server = await asyncio.start_server(
            self._handle_client, HOST, PORT, reuse_address=True
        )
        async with self._server:
            await self._server.serve_forever()

    def send_to_session(self, sid: str, obj: dict) -> None:
        """Thread-safe send from non-async code (e.g. future tooling)."""
        w = self.writers.get(sid)
        if not w or not self.loop:
            return
        data = (json.dumps(obj, separators=(",", ":")) + "\n").encode("utf-8")

        async def _send() -> None:
            try:
                w.write(data)
                await w.drain()
            except Exception:
                pass

        try:
            asyncio.run_coroutine_threadsafe(_send(), self.loop)
        except Exception:
            pass

    async def send_to_session_async(self, sid: str, obj: dict) -> bool:
        w = self.writers.get(sid)
        if not w:
            return False
        data = (json.dumps(obj, separators=(",", ":")) + "\n").encode("utf-8")
        try:
            w.write(data)
            await w.drain()
            return True
        except Exception:
            return False

    async def _mirror_send_json(self, writer: asyncio.StreamWriter, obj: dict) -> None:
        line = json.dumps(obj, separators=(",", ":")) + "\n"
        writer.write(line.encode("utf-8"))
        await writer.drain()

    def schedule_mirror_broadcast(self) -> None:
        """Debounce full-session JSON push to WinForms (asyncio thread only)."""
        loop = asyncio.get_running_loop()

        def fire() -> None:
            self._mirror_broadcast_handle = None
            asyncio.create_task(self._broadcast_mirror_snapshot())

        h = self._mirror_broadcast_handle
        if h is not None:
            h.cancel()
            self._mirror_broadcast_handle = None
        self._mirror_broadcast_handle = loop.call_later(MIRROR_BROADCAST_COALESCE_S, fire)

    async def _push_mirror_snapshot(self, writer: asyncio.StreamWriter) -> None:
        line = json.dumps({"op": "mirror_snapshot", "sessions": self.sessions}, default=str) + "\n"
        writer.write(line.encode("utf-8"))
        await writer.drain()

    async def _broadcast_mirror_snapshot(self) -> None:
        if not self.mirror_clients:
            return
        try:
            payload = (
                json.dumps({"op": "mirror_snapshot", "sessions": self.sessions}, default=str) + "\n"
            ).encode("utf-8")
        except Exception:
            return
        dead: list[asyncio.StreamWriter] = []
        for w in list(self.mirror_clients):
            try:
                w.write(payload)
                await w.drain()
            except Exception:
                dead.append(w)
        for w in dead:
            self.mirror_clients.discard(w)

    async def _mirror_handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        self.mirror_clients.add(writer)
        try:
            await self._push_mirror_snapshot(writer)
            while True:
                raw = await reader.readline()
                if not raw:
                    break
                msg = parse_ndjson_line(raw)
                if not msg or not isinstance(msg, dict):
                    continue
                if msg.get("op") != "mirror_forward":
                    continue
                sid = msg.get("sid")
                inner = msg.get("msg")
                if not isinstance(sid, str) or not isinstance(inner, dict):
                    await self._mirror_send_json(
                        writer,
                        {"op": "mirror_error", "reason": "mirror_forward requires string sid and object msg"},
                    )
                    continue
                if sid not in self.sessions:
                    await self._mirror_send_json(
                        writer,
                        {"op": "mirror_error", "reason": "unknown_sid", "sid": sid},
                    )
                    continue
                ok = await self.send_to_session_async(sid, inner)
                if not ok:
                    await self._mirror_send_json(
                        writer,
                        {"op": "mirror_error", "reason": "send_failed", "sid": sid},
                    )
        finally:
            self.mirror_clients.discard(writer)
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _run_mirror_server(self) -> None:
        self._mirror_server = await asyncio.start_server(
            self._mirror_handle_client, HOST, MIRROR_PORT, reuse_address=True
        )
        async with self._mirror_server:
            await self._mirror_server.serve_forever()


async def _async_main(hub: UnifiedCombatHub) -> None:
    hub.loop = asyncio.get_running_loop()
    await asyncio.gather(
        hub._run_server(),
        hub._run_mirror_server(),
    )


def main() -> None:
    hub = UnifiedCombatHub()
    print(f"UnifiedCombat hub (headless): game {HOST}:{PORT}, UI {HOST}:{MIRROR_PORT}")
    print("Start UnifiedCombatWinForms to control sessions.")
    try:
        asyncio.run(_async_main(hub))
    except KeyboardInterrupt:
        print("Stopped.")


if __name__ == "__main__":
    main()
