#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["websockets"]
# ///
"""3Dconnexion SpaceMouse WebSocket client — WAMP v1 over WSS."""
import sys
sys.stdout.reconfigure(line_buffering=True)
import asyncio
import json
import ssl
import time
import urllib.request

import websockets

HOST = "127.51.68.120"
HTTP_PORT = 8181

# WAMP v1 message types
WELCOME = 0
PREFIX = 1
CALL = 2
CALL_RESULT = 3
CALL_ERROR = 4
SUBSCRIBE = 5
EVENT = 8

call_counter = 0
pending: dict[str, asyncio.Future] = {}


def next_call_id() -> str:
    global call_counter
    call_counter += 1
    return f"call-{call_counter}"


async def send(ws, msg):
    await ws.send(json.dumps(msg))


async def rpc(ws, proc: str, *args):
    cid = next_call_id()
    msg = [CALL, cid, proc, *args]
    fut = asyncio.get_event_loop().create_future()
    pending[cid] = fut
    await send(ws, msg)
    return await asyncio.wait_for(fut, timeout=5.0)


def handle_read(prop: str):
    identity = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    table = {
        "view.affine": identity,
        "view.extents": [-1,-1,-10, 1,1,10],
        "view.fov": 1.0,
        "view.perspective": True,
        "view.frustum": [-1, 1, -1, 1, 0.1, 100],
        "view.target": [0,0,0],
        "view.rotatable": True,
        "view.constructionPlane": [0, 1, 0, 0],
        "model.extents": [-1,-1,-1, 1,1,1],
        "model.floorPlane": [0,1,0,0],
        "model.unitsToMeters": 1.0,
        "pivot.position": [0,0,0],
        "selection.empty": True,
        "selection.extents": [-1,-1,-1, 1,1,1],
        "selection.affine": identity,
        "pointer.position": [0,0,0],
        "coordinateSystem": identity,
        "views.front": identity,
        "hit.lookat": None,
        "frame.timingSource": 0,
        "frame.time": 0.0,
    }
    if prop in table:
        return (True, table[prop])
    return (False, None)


def handle_update(prop: str, value):
    match prop:
        case "motion":
            print("🎮 Motion START" if value else "🎮 Motion STOP")
        case "view.affine":
            if isinstance(value, list) and len(value) >= 16:
                print(f"📐 View  tx={value[12]:+.3f} ty={value[13]:+.3f} tz={value[14]:+.3f}")
        case "view.extents":
            pass  # noisy
        case "view.fov":
            print(f"🔭 FOV: {value:.3f}")
        case "pivot.position":
            if isinstance(value, list) and len(value) >= 3:
                print(f"📍 Pivot: {value[0]:+.3f} {value[1]:+.3f} {value[2]:+.3f}")
        case "pivot.visible":
            print(f"👁  Pivot visible: {value}")
        case "commands.activeCommand":
            print(f"⌨️  Command: {value}")
        case "events.keyPress":
            print(f"🔑 Key press: {value}")
        case "events.keyRelease":
            print(f"🔑 Key release: {value}")
        case "transaction":
            pass  # noisy
        case "settings.changed":
            print(f"⚙️  Settings changed")
        case "hit.selectionOnly" | "hit.lookfrom" | "hit.direction" | "hit.aperture":
            pass  # internal navlib stuff
        case _:
            print(f"   {prop} = {value}")


async def handle_event(ws, event):
    if not isinstance(event, list) or len(event) < 3 or event[0] != CALL:
        return

    cid, proc = event[1], event[2]

    if proc == "self:read" and len(event) >= 5:
        prop = event[4]
        known, result = handle_read(prop)
        if known:
            await send(ws, [CALL_RESULT, cid, result])
        else:
            await send(ws, [CALL_ERROR, cid, proc + "#generic", f"{prop} unknown"])

    elif proc == "self:update" and len(event) >= 6:
        prop, value = event[4], event[5]
        handle_update(prop, value)
        await send(ws, [CALL_RESULT, cid, None])

    else:
        await send(ws, [CALL_ERROR, cid, proc + "#generic", "unknown procedure"])


async def reader_task(ws):
    async for raw in ws:
        msg = json.loads(raw)
        t = msg[0]
        if t == CALL_RESULT and len(msg) >= 3:
            cid = msg[1]
            if cid in pending:
                pending.pop(cid).set_result(msg[2])
        elif t == CALL_ERROR and len(msg) >= 4:
            cid = msg[1]
            if cid in pending:
                pending.pop(cid).set_exception(RuntimeError(msg[3] if len(msg) > 3 else "RPC error"))
        elif t == EVENT and len(msg) >= 3:
            await handle_event(ws, msg[2])


async def main():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    url = f"https://{HOST}:{HTTP_PORT}/3dconnexion/nlproxy"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, context=ctx) as resp:
        info = json.loads(resp.read())
    port = info["port"]
    print(f"✓ Connected to 3DxNLServer v{info.get('version', '?')} on port {port}")

    ws_url = f"wss://{HOST}:{port}"
    async with websockets.connect(ws_url, ssl=ctx, subprotocols=["wamp"]) as ws:
        welcome = json.loads(await ws.recv())
        assert welcome[0] == WELCOME
        reader = asyncio.create_task(reader_task(ws))

        await send(ws, [PREFIX, "3dx_rpc", f"wss://{HOST}/3dconnexion#"])
        await send(ws, [PREFIX, "3dconnexion", f"wss://{HOST}/3dconnexion"])
        await send(ws, [PREFIX, "self", "spacemouse-py://local"])

        result = await rpc(ws, "3dx_rpc:create", "3dconnexion:3dmouse", "0.8.1")
        connexion = result["connexion"]

        controller_info = {"version": 0.8, "name": "SpaceMousePy", "rowMajorOrder": False}
        result = await rpc(ws, "3dx_rpc:create", "3dconnexion:3dcontroller", connexion, controller_info)
        instance = result["instance"]

        topic = f"3dconnexion:3dcontroller/{instance}"
        await send(ws, [SUBSCRIBE, topic])

        await rpc(ws, "3dx_rpc:update", f"3dconnexion:3dcontroller/{instance}", {"focus": True})

        await rpc(ws, "3dx_rpc:update", f"3dconnexion:3dcontroller/{instance}", {"frame": {"timingSource": 1}})

        print("🎮 Listening for SpaceMouse events... (Ctrl+C to quit)\n")

        async def animation_loop():
            ctrl = f"3dconnexion:3dcontroller/{instance}"
            while True:
                try:
                    await rpc(ws, "3dx_rpc:update", ctrl, {"frame": {"time": time.time() * 1000}})
                except Exception:
                    pass
                await asyncio.sleep(1/60)

        asyncio.create_task(animation_loop())
        await reader


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nBye!")
