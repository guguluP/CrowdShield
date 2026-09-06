"""
CrowdShield — Recommendations endpoint.

POST /venues/{venueId}/recommendations   — create a recommendation (Command group only)
GET  /venues/{venueId}/recommendations   — list recommendations (any authenticated user)
"""

from __future__ import annotations

import os

import boto3
from boto3.dynamodb.conditions import Key

from crowdshield_common import (
    error,
    new_id,
    now_iso,
    parse_body,
    path_param,
    require_command,
    response,
)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["RECOMMENDATIONS_TABLE"])


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    venue_id = path_param(event, "venueId")

    if not venue_id:
        return error(400, "venueId path parameter is required.")

    if method == "GET":
        return _list(venue_id)
    if method == "POST":
        return _create(event, venue_id)
    return error(405, f"Method {method} not allowed.")


def _list(venue_id: str):
    result = table.query(
        KeyConditionExpression=Key("venueId").eq(venue_id),
        ScanIndexForward=False,
        Limit=50,
    )
    return response(200, {"venueId": venue_id, "recommendations": result.get("Items", [])})


def _create(event, venue_id: str):
    forbidden = require_command(event)
    if forbidden:
        return forbidden

    body, err = parse_body(event)
    if err:
        return err

    if not body.get("action"):
        return error(400, "action is required (e.g. 'open_gate_c').")

    item = {
        "venueId": venue_id,
        "recommendationId": new_id(),
        "createdAt": now_iso(),
        "status": body.get("status", "pending"),
        "action": body["action"],
        "reason": body.get("reason"),
        "priority": body.get("priority", "medium"),
    }
    item = {k: v for k, v in item.items() if v is not None}

    table.put_item(Item=item)
    return response(201, item)
