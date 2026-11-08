"""TEST ONLY. One 127.0.0.1 HTTP exchange; no real PC permissions or keys.

Called by a Dart flutter test. The local-only session grant is synthesized
inside this fixture, solely to check binary-compatible request/response JSON.
"""
from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                       "examples" / "windows_companion"))
from offline_session_preview import OfflinePreviewSession  # noqa: E402

NOW = 1800000000


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args: object) -> None:
        pass  # No URLs, addresses, or request content in CI logs.

    def do_POST(self) -> None:
        if self.path != "/fixture" or self.headers.get("Content-Type") != "application/json":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 512:
                raise ValueError("Invalid bounded payload")
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError("Object required")
            session = OfflinePreviewSession(now_epoch_seconds=NOW, expires_at=NOW+60)
            assert session.verify(identity_verified=True, now_epoch_seconds=NOW)
            assert session.request_read_only(capability="pc.status.read",
                                             now_epoch_seconds=NOW)
            assert session.consent(side="pc", approved=True, now_epoch_seconds=NOW)
            assert session.consent(side="android", approved=True,
                                   now_epoch_seconds=NOW)
            response = session.accept_fixture_request(payload, now_epoch_seconds=NOW)
            if response is None:
                raise ValueError("Invalid offline status fixture")
            raw = json.dumps(response, sort_keys=True, separators=(",", ":")).encode()
            self.send_response(200)
        except (ValueError, TypeError, AssertionError, UnicodeError):
            raw = b'{"error":"SESSION-FORMAT"}'
            self.send_response(400)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def main() -> None:
    # Explicit loopback only: never bind 0.0.0.0 or LAN.
    with HTTPServer(("127.0.0.1", 0), FixtureHandler) as server:
        server.timeout = 12
        print(server.server_port, flush=True)
        server.handle_request()  # exactly one connection, no persistent daemon


if __name__ == "__main__":
    main()
