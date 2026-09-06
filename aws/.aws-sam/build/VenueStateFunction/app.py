"""
CrowdShield — Venue State endpoint.

PUT /venues/{venueId}/state   — upsert current crowd-state snapshot
GET /venues/{venueId}/state   — fetch latest snapshot

Both require a valid Cognito JWT (any group). Write is intentionally open to
any authenticated caller in Phase 2 since sensor/ingestion sources are not
yet distinguished from dashboard users; tighten with a dedicated
"Ingestion" group later if needed.
"""

from __future__ import annotations

import os

import boto3

from crowdshield_common import error, now_iso, parse_body, path_param, response, to_dynamo_safe

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["VENUE_STATE_TABLE"])


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    venue_id = path_param(event, "venueId")

    if not venue_id:
        return error(400, "venueId path parameter is required.")

    if method == "GET":
        return _get(venue_id)
    if method == "PUT":
        return _put(event, venue_id)
    return error(405, f"Method {method} not allowed.")


def _get(venue_id: str):
    result = table.get_item(Key={"venueId": venue_id})
    item = result.get("Item")
    if not item:
        return error(404, f"No state recorded yet for venue '{venue_id}'.")
    return response(200, item)


def _put(event, venue_id: str):
    body, err = parse_body(event)
    if err:
        return err

    item = {
        "venueId": venue_id,
        "updatedAt": now_iso(),
        "density": body.get("density"),
        "movementSpeed": body.get("movementSpeed"),
        "hotspots": body.get("hotspots", []),
        "bottlenecks": body.get("bottlenecks", []),
        "flowDirections": body.get("flowDirections", []),
        "riskZones": body.get("riskZones", []),
        "zones": body.get("zones", []),
        "raw": body.get("raw"),
    }
    # Strip keys with None values so we don't overwrite with nulls unnecessarily.
    item = {k: v for k, v in item.items() if v is not None}

    table.put_item(Item=to_dynamo_safe(item))
    return response(200, item)
