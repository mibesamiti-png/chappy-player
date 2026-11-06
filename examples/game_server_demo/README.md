# Chappy Game Server — development echo room

This is a **small source-code example** for the user's long-term multiplayer-game goal. It is **not currently running on any server**, has no account login, and must not be mistaken for a secure production multiplayer service.

## Local server startup

On a PC with Python 3.10+:

```powershell
py -m pip install "websockets>=14,<17"
py examples/game_server_demo/server.py
```

It binds **127.0.0.1:8765 only**. The server recognizes these JSON text packets:
- `{"type":"ping"}` → `{"type":"pong"}`
- `{"type":"join","room":"test-room"}` → `{"type":"joined","room":"test-room", ...}`
- `{"type":"state","position":{"x":1.2,"y":3.4}}` → room members receive the state
- `{"type":"gravity","values":[1.2,2.3,9.8]}` → `{"type":"gravity_ack",...}`

The server assigns a temporary anonymous player ID, limits rooms to 8 connections, rate-limits to 15 messages/s per client, caps received frames at 2 KiB and relays only the specified message shapes. It does **not** execute commands or interpret arbitrary code from players. It does not persist player data.

## Connecting from Android

The new Game Server Lab client connects **only to WSS with trusted certificates** and a public DNS hostname, on TCP 443, 8443 or 9443. It deliberately refuses loopback and LAN/private IPs, unencrypted WS/HTTP, redirects and certificates that fail verification. Therefore the phone **cannot connect directly to the loopback Python example**.

To test with a phone, host a *separately secured* public development endpoint with a valid HTTPS certificate and a reverse proxy terminating WSS (for example a dedicated test domain forwarded to the Python service). The backend should remain listening on loopback behind that reverse proxy. Do not expose the Python service directly to the public internet.

**Security warning:** the reference room server is anonymous and does not implement account authentication, anti-abuse controls, matchmaking persistence, scalable state synchronization or cheat prevention. Its public exposure requires additional access control/authentication and monitoring. The Chappy app will ask before granting a mini-app access to a specific WSS/HTTPS host, but **that is not server-side authentication**.

## Roadmap

1. Device Lab: explicit sensor and haptic input on the phone.
2. Game Server Lab: text/JSON HTTPS GET/POST, WSS connect/send/receive/close, and manual gravity send.
3. This example: temporary multi-user rooms and a bounded position relay, for prototyping a small game only.
4. Future: server-authoritative game logic, per-player tokens, reconnection, timestamps, prediction/interpolation, host-side allowlists, and then private Wi-Fi/LAN pairing and SFTP file transfers.

The production Chappy Player and Stable mini-app catalog are deliberately unchanged by this source demo.
