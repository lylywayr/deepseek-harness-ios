#!/usr/bin/env python3
"""Regression tests for the native Harness wire contracts."""

from __future__ import annotations

import base64
import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

from protocol_contract import (  # noqa: E402
    ProtocolError,
    classify_http_status,
    directory_listing,
    event_result,
    image_block,
    mux_cancel,
    mux_open,
    rpc_envelope,
    validate_event_ready,
    validate_mux_server_frame,
    validate_rpc_response,
)


class ProtocolContractTests(unittest.TestCase):
    def test_json_rpc_envelope_and_empty_session_list_args(self) -> None:
        request = rpc_envelope("session/list", {}, "rpc-list-1")
        self.assertEqual(request["type"], "client-request")
        self.assertEqual(request["rpcId"], "rpc-list-1")
        self.assertEqual(request["method"], "session/list")
        self.assertEqual(request["payload"], {"args": {}})

    def test_json_rpc_correlation_is_required(self) -> None:
        response = {
            "type": "server-response",
            "rpcId": "rpc-other",
            "result": {"ok": True, "value": {"items": []}},
        }
        with self.assertRaisesRegex(ProtocolError, "correlation"):
            validate_rpc_response(response, "rpc-expected")

    def test_json_rpc_success_and_structured_remote_failure(self) -> None:
        response = {
            "type": "server-response",
            "rpcId": "rpc-1",
            "result": {"ok": True, "value": {"items": []}},
        }
        self.assertEqual(validate_rpc_response(response, "rpc-1"), {"items": []})
        failed = {
            "type": "server-response",
            "rpcId": "rpc-2",
            "result": {"ok": False, "error": {"code": "gateway/bad-request", "message": "bad"}},
        }
        with self.assertRaisesRegex(ProtocolError, "gateway/bad-request"):
            validate_rpc_response(failed, "rpc-2")

    def test_session_page_keeps_official_cursor_fields(self) -> None:
        request = rpc_envelope(
            "session/page",
            {
                "request": {
                    "address": {"kind": "session", "sessionId": "session-1"},
                    "throughSeq": 42,
                    "beforeSeq": 17,
                    "maxMessages": 30,
                }
            },
            "rpc-page-1",
        )
        page = request["payload"]["args"]["request"]
        self.assertEqual(page["address"], {"kind": "session", "sessionId": "session-1"})
        self.assertEqual(page["throughSeq"], 42)
        self.assertEqual(page["beforeSeq"], 17)
        self.assertEqual(page["maxMessages"], 30)

    def test_remote_mux_open_item_end_error_and_cancel(self) -> None:
        opened = mux_open("stream-1", "session/follow", {"args": {"request": {}}})
        self.assertEqual(opened["type"], "open")
        self.assertEqual(opened["endpoint"], "session/follow")
        self.assertEqual(validate_mux_server_frame({"type": "item", "streamId": "stream-1", "value": {"type": "snapshot"}})["type"], "item")
        self.assertEqual(validate_mux_server_frame({"type": "end", "streamId": "stream-1"})["type"], "end")
        error = {"type": "error", "streamId": "stream-1", "error": {"code": "gateway/internal", "message": "failed", "details": {}}}
        self.assertEqual(validate_mux_server_frame(error), error)
        self.assertEqual(mux_cancel("stream-1"), {"type": "cancel", "streamId": "stream-1"})

    def test_remote_event_ready_and_result_correlation(self) -> None:
        client_id, home = validate_event_ready({"type": "ready", "clientId": "client-1", "host": {"home": "/home/tester"}})
        self.assertEqual((client_id, home), ("client-1", "/home/tester"))
        result = event_result(client_id, "event-1", {"kind": "result", "value": "allowed-once"})
        self.assertEqual(result["clientId"], "client-1")
        self.assertEqual(result["eventId"], "event-1")
        self.assertEqual(result["outcome"]["kind"], "result")

    def test_workspace_baseline_and_increment_shapes(self) -> None:
        workspace = {
            "workspaceId": "workspace-1",
            "path": "/home/tester/project",
            "title": "Project",
            "sessionIds": ["session-1"],
            "createdAt": "2026-09-04T00:00:00Z",
            "updatedAt": "2026-09-04T00:00:00Z",
        }
        baseline = {"type": "baseline", "value": {"items": [workspace], "archivedSessionIds": []}}
        upsert = {"type": "upsert", "workspace": workspace}
        remove = {"type": "remove", "workspaceId": "workspace-1"}
        order = {"type": "order", "workspaceIds": ["workspace-2", "workspace-1"]}
        archived = {"type": "archived", "archivedSessionIds": ["session-1"]}
        self.assertEqual(baseline["value"]["items"][0]["workspaceId"], "workspace-1")
        self.assertEqual(upsert["workspace"], workspace)
        self.assertEqual(remove["workspaceId"], "workspace-1")
        self.assertEqual(order["workspaceIds"][0], "workspace-2")
        self.assertEqual(archived["archivedSessionIds"], ["session-1"])

    def test_directory_listing_uses_entries_and_crumbs(self) -> None:
        listing = directory_listing()
        self.assertEqual(set(listing), {"path", "home", "crumbs", "entries", "truncated"})
        self.assertEqual(listing["entries"][0]["path"], "/home/tester/project/Sources")
        self.assertTrue(listing["entries"][1]["hidden"])
        self.assertEqual(listing["crumbs"][-1]["path"], listing["path"])

    def test_image_prompt_is_base64_with_media_type(self) -> None:
        block = image_block(b"png-bytes", "image/png", "screen.png")
        self.assertEqual(block["type"], "image")
        self.assertEqual(block["mediaType"], "image/png")
        self.assertEqual(base64.b64decode(block["data"]), b"png-bytes")
        self.assertEqual(block["name"], "screen.png")

    def test_http_and_malformed_error_classification(self) -> None:
        self.assertEqual(classify_http_status(200), "ok")
        self.assertEqual(classify_http_status(401), "unauthorized")
        self.assertEqual(classify_http_status(503), "http-error")
        with self.assertRaises(ProtocolError):
            validate_mux_server_frame({"type": "item", "streamId": ""})
        with self.assertRaises(ProtocolError):
            validate_mux_server_frame({"type": "error", "streamId": "stream-1", "error": {"code": "x", "message": "bad"}})
        with self.assertRaises(ProtocolError):
            validate_event_ready({"type": "ready", "clientId": "", "host": {"home": "/home"}})
        with self.assertRaises(ProtocolError):
            validate_rpc_response({"type": "not-a-response"}, "rpc-1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
