"""
CrowdShield — Incidents endpoint.

POST /venues/{venueId}/incidents   — log an incident (any authenticated user:
                                     Public citizens + Command operators)
GET  /venues/{venueId}/incidents   — list recent incidents (any authenticated user)

Auth: API Gateway JWT authorizer already requires a valid Cognito token.
Citizen reporting is a core product path — do NOT gate POST on Command group.
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
    response,
    ttl_epoch,
)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["INCIDENTS_TABLE"])


def _claims(event: dict) -> dict:
    return (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
        or {}
    )


def _groups(claims: dict) -> list[str]:
    raw = claims.get("cognito:groups") or ""
    if isinstance(raw, list):
        return [str(g) for g in raw]
    text = str(raw).strip()
    if not text:
        return []
    if text.startswith("["):
        return [g.strip(" \"'") for g in text.strip("[]").split(",") if g.strip()]
    return [g.strip() for g in text.replace(";", ",").split(",") if g.strip()]


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
    return response(200, {"venueId": venue_id, "incidents": result.get("Items", [])})


def _create(event, venue_id: str):
    # Any authenticated caller (Public or Command). Gateway JWT is the gate.
    body, err = parse_body(event)
    if err:
        return err

    if not body.get("description"):
        return error(400, "description is required.")

    claims = _claims(event)
    groups = _groups(claims)
    email = claims.get("email") or claims.get("username") or ""
    is_command = "Command" in groups
    source = "command" if is_command else "public"

    reported_by = body.get("reportedBy") or email or ("Command" if is_command else "Public citizen")

    item = {
        "venueId": venue_id,
        "incidentId": new_id(),
        "createdAt": now_iso(),
        "status": body.get("status", "open"),
        "category": body.get("category") or body.get("type") or "general",
        "description": body["description"],
        "location": body.get("location"),
        "reportedBy": reported_by,
        "source": source,
        "expiresAt": ttl_epoch(hours=body.get("ttlHours", 168)),
    }
    item = {k: v for k, v in item.items() if v is not None}

    table.put_item(Item=item)
    return response(201, item)
