"""Offline tests for the optional, loopback-only example game server protocol."""
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
demo = ROOT / "examples/game_server_demo/server.py"
module = runpy.run_path(str(demo), run_name="game_server_contract_test")
parse = module["validated_packet"]
assert module["HOST"] == "127.0.0.1"
assert module["MAX_PLAYERS_PER_ROOM"] == 8
assert module["RATE_LIMIT_PER_SECOND"] <= 20
assert parse('{"type":"ping"}') == {"type": "ping"}
assert parse('{"type":"join","room":"test-room"}') == {
    "type": "join", "room": "test-room"}
assert parse('{"type":"gravity","values":[1.2,2.3,9.8]}') == {
    "type": "gravity", "values": [1.2, 2.3, 9.8]}
assert parse('{"type":"state","position":{"x":4,"y":-1.25}}') == {
    "type": "state", "position": {"x": 4.0, "y": -1.25}}
for bad in (
    '{}', '{"type":"exec","command":"rm -rf /"}',
    '{"type":"join","room":"../../private"}',
    '{"type":"join","room":"this_name_is_much_too_long_for_rooms"}',
    '{"type":"gravity","values":[1,2]}',
    '{"type":"gravity","values":[1,2,10000]}',
    '{"type":"state","position":{"x":0,"y":1e200}}',
    '{"type":"state","position":{"x":0,"y":true}}',
    '{"type":"state","position":{"x":0,"y":0,"z":5}}',
    'a' * 2049,
):
    rejected = False
    try:
        parse(bad)
    except (ValueError, TypeError, OverflowError):
        rejected = True
    assert rejected, f"Unsafe message accepted: {bad[:75]}"

server_text = demo.read_text(encoding="utf-8")
assert "max_size=2048" in server_text
assert "Rate limit" in server_text
assert "Only ping, join, gravity and state" in server_text
assert "await peer.send(message)" in server_text
assert "async with serve(handler, HOST, PORT" in server_text
print("Game server room protocol smoke test passed (no network access)")
