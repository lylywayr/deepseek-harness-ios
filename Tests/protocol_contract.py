"""Small, dependency-free wire helpers used by protocol regression tests.

These helpers intentionally model only the JSON contract. They do not connect to
Harness or contain credentials. Keeping the fixtures here makes the checks
runnable on Alpine, where Xcode and Swift are unavailable.
"""

from __future__ import annotations

import base64
from typing import Any


class ProtocolError(ValueError):
    """A malformed or incorrectly correlated wire value."""


def rpc_envelope(method: str, args: dict[str, Any], rpc_id: str) -> dict[str, Any]:
    if not method or not rpc_id:
        raise ProtocolError("method and rpc_id are required")
    return {
        "type": "client-request",
        "rpcId": rpc_id,
        "method": method,
        "payload": {"args": args},
    }


def validate_rpc_response(value: Any, expected_rpc_id: str) -> Any:
    if not isinstance(value, dict) or value.get("type") != "server-response":
        raise ProtocolError("invalid JSON-RPC response")
    if value.get("rpcId") != expected_rpc_id:
        raise ProtocolError("rpcId correlation failed")
    result = value.get("result")
    if not isinstance(result, dict) or not isinstance(result.get("ok"), bool):
        raise ProtocolError("invalid JSON-RPC result")
    if result["ok"]:
        return result.get("value")
    error = result.get("error")
    if not isinstance(error, dict):
        raise ProtocolError("missing structured remote error")
    raise ProtocolError(f"remote error: {error.get('code', 'unknown')}")


def mux_open(stream_id: str, endpoint: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {"type": "open", "streamId": stream_id, "endpoint": endpoint, "payload": payload}


def mux_cancel(stream_id: str) -> dict[str, Any]:
    return {"type": "cancel", "streamId": stream_id}


def validate_mux_server_frame(value: Any) -> Any:
    if not isinstance(value, dict) or not isinstance(value.get("streamId"), str) or not value.get("streamId"):
        raise ProtocolError("invalid Remote Mux frame")
    kind = value.get("type")
    if kind == "item":
        if set(value) - {"type", "streamId", "value"}:
            raise ProtocolError("invalid Remote Mux item")
        return value
    if kind == "end":
        return value
    if kind == "error":
        error = value.get("error")
        if not isinstance(error, dict) or not all(
            isinstance(error.get(key), str if key != "details" else dict)
            for key in ("code", "message", "details")
        ):
            raise ProtocolError("invalid Remote Mux error")
        return value
    raise ProtocolError("unknown Remote Mux frame")


def validate_event_ready(value: Any) -> tuple[str, str]:
    if not isinstance(value, dict) or value.get("type") != "ready":
        raise ProtocolError("missing event ready frame")
    client_id = value.get("clientId")
    host = value.get("host")
    if not isinstance(client_id, str) or not client_id:
        raise ProtocolError("missing event clientId")
    if not isinstance(host, dict) or not isinstance(host.get("home"), str):
        raise ProtocolError("missing event host")
    return client_id, host["home"]


def event_result(client_id: str, event_id: str, outcome: dict[str, Any]) -> dict[str, Any]:
    if not client_id or not event_id or not isinstance(outcome, dict):
        raise ProtocolError("invalid event result")
    return {"clientId": client_id, "eventId": event_id, "outcome": outcome}


def directory_listing() -> dict[str, Any]:
    return {
        "path": "/home/tester/project",
        "home": "/home/tester",
        "crumbs": [
            {"name": "/", "path": "/", "hidden": False},
            {"name": "tester", "path": "/home/tester", "hidden": False},
            {"name": "project", "path": "/home/tester/project", "hidden": False},
        ],
        "entries": [
            {"name": "Sources", "path": "/home/tester/project/Sources", "hidden": False},
            {"name": ".cache", "path": "/home/tester/project/.cache", "hidden": True},
        ],
        "truncated": False,
    }


def image_block(data: bytes, media_type: str, name: str) -> dict[str, str]:
    if not data or not media_type.startswith("image/") or not name:
        raise ProtocolError("invalid image block")
    return {
        "type": "image",
        "mediaType": media_type,
        "data": base64.b64encode(data).decode("ascii"),
        "name": name,
    }


def classify_http_status(status: int) -> str:
    if status in (401, 403):
        return "unauthorized"
    if status < 200 or status >= 300:
        return "http-error"
    return "ok"
