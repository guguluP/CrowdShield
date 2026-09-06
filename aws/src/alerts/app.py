"""
CrowdShield — Alerts endpoint.

POST /venues/{venueId}/alerts   — create an alert (Command group only)
GET  /venues/{venueId}/alerts   — list recent alerts (any authenticated user)
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
    ttl_epoch,
)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["ALERTS_TABLE"])


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
    return response(200, {"venueId": venue_id, "alerts": result.get("Items", [])})


def _create(event, venue_id: str):
    forbidden = require_command(event)
    if forbidden:
        return forbidden

    body, err = parse_body(event)
    if err:
        return err

    severity = body.get("severity", "info")
    if severity not in {"info", "warning", "critical"}:
        return error(400, "severity must be one of: info, warning, critical.")

    item = {
        "venueId": venue_id,
        "alertId": new_id(),
        "createdAt": now_iso(),
        "severity": severity,
        "type": body.get("type", "general"),
        "message": body.get("message", ""),
        "location": body.get("location"),
        "expiresAt": ttl_epoch(hours=body.get("ttlHours", 48)),
    }
    item = {k: v for k, v in item.items() if v is not None}

    table.put_item(Item=item)
    return response(201, item)
