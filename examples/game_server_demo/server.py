"""Minimal, deliberately loopback-only game room WebSocket example.

Install websockets>=14.0 then run:
    python server.py
Expose WSS only through a trusted TLS reverse proxy if you understand the
authentication and abuse risks. This is NOT a production multiplayer backend.
"""
import asyncio
import json
import re
import time
import uuid
from collections import defaultdict, deque

HOST = "127.0.0.1"
PORT = 8765
MAX_PLAYERS_PER_ROOM = 8
ROOMS = defaultdict(set)
RATE_LIMIT_PER_SECOND = 15


def validated_packet(raw):
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > 2048:
        raise ValueError("Text packets must be <= 2KiB")
    packet = json.loads(raw)
    if not isinstance(packet, dict):
        raise ValueError("Expected JSON object")
    kind = packet.get("type")
    if kind == "ping":
        return {"type": "ping"}
    if kind == "join":
        room = packet.get("room", "")
        if not isinstance(room, str) or not re.fullmatch(r"[a-z0-9_-]{1,20}", room):
            raise ValueError("Room must be 1-20 simple characters")
        return {"type": "join", "room": room}
    if kind == "state":
        axes = packet.get("position")
        if not isinstance(axes, dict) or set(axes) != {"x", "y"}:
            raise ValueError("State requires an x/y position")
        normalized = {}
        for axis in ("x", "y"):
            value = axes[axis]
            if (isinstance(value, bool) or not isinstance(value, (int, float)) or
                    not -1000 <= value <= 1000):
                raise ValueError("Position must be bounded numbers")
            normalized[axis] = round(float(value), 3)
        return {"type": "state", "position": normalized}
    raise ValueError("Only ping, join and state messages are supported")


async def handler(socket):
    player = uuid.uuid4().hex[:12]
    room = None
    recent = deque()
    await socket.send(json.dumps({"type": "ready", "player": player}))
    try:
        async for raw in socket:
            now = time.monotonic()
            while recent and now - recent[0] > 1:
                recent.popleft()
            recent.append(now)
            if len(recent) > RATE_LIMIT_PER_SECOND:
                await socket.close(code=1008, reason="Rate limit")
                break
            try:
                packet = validated_packet(raw)
            except (ValueError, TypeError, json.JSONDecodeError):
                await socket.send(json.dumps({"type": "error", "detail": "Invalid packet"}))
                continue
            if packet["type"] == "ping":
                await socket.send(json.dumps({"type": "pong"}))
            elif packet["type"] == "join":
                new_room = packet["room"]
                members = ROOMS[new_room]
                if socket not in members and len(members) >= MAX_PLAYERS_PER_ROOM:
                    await socket.send(json.dumps({"type": "error", "detail": "Room full"}))
                    continue
                if room:
                    ROOMS[room].discard(socket)
                room = new_room
                members.add(socket)
                await socket.send(json.dumps({
                    "type": "joined", "room": room,
                    "player": player, "players": len(members)
                }))
            elif packet["type"] == "state":
                if not room:
                    await socket.send(json.dumps({"type": "error", "detail": "Join first"}))
                    continue
                message = json.dumps({
                    "type": "state", "player": player,
                    "position": packet["position"]
                })
                for peer in tuple(ROOMS[room]):
                    if peer is not socket:
                        try:
                            await peer.send(message)
                        except Exception:
                            ROOMS[room].discard(peer)
    finally:
        if room:
            ROOMS[room].discard(socket)
            if not ROOMS[room]:
                ROOMS.pop(room, None)


async def main():
    try:
        from websockets.asyncio.server import serve
    except ImportError as error:
        raise SystemExit("Install dependency: python -m pip install 'websockets>=14,<17'") from error
    async with serve(handler, HOST, PORT, max_size=2048,
                     max_queue=16, ping_interval=20):
        print("Development game room server listening on loopback", HOST, PORT)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
