"""
CrowdShield — Venues registry endpoint (Phase 6).

GET  /venues       — list all venues (any authenticated user)
POST /venues       — create a venue (Command group only)

venueId is derived from the submitted name: lowercased, non-alphanumeric
runs collapsed to a single hyphen, trimmed. This keeps venueId safe to use
both as a DynamoDB key and as a path segment in every other endpoint
(/venues/{venueId}/state, /alerts, etc.) without extra escaping there.
"""

from __future__ import annotations

import os
import re

import boto3

from crowdshield_common import error, now_iso, parse_body, require_command, response

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["VENUES_TABLE"])

_SLUG_STRIP_RE = re.compile(r"[^a-z0-9]+")


def slugify(name: str) -> str:
    slug = _SLUG_STRIP_RE.sub("-", name.strip().lower()).strip("-")
    return slug


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")

    if method == "GET":
        return _list()
    if method == "POST":
        return _create(event)
    return error(405, f"Method {method} not allowed.")


def _list():
    # Table is expected to stay small (tens to low hundreds of venues for
    # this prototype's scale) — a full scan is simpler than maintaining a
    # GSI for what is, at this scale, an infrequent read of a small table.
    result = table.scan()
    venues = sorted(result.get("Items", []), key=lambda v: v.get("name", ""))
    return response(200, {"venues": venues})


def _create(event):
    forbidden = require_command(event)
    if forbidden:
        return forbidden

    body, err = parse_body(event)
    if err:
        return err

    name = (body.get("name") or "").strip()
    if not name:
        return error(400, "name is required.")

    venue_id = slugify(name)
    if not venue_id:
        return error(400, "name must contain at least one letter or number.")

    existing = table.get_item(Key={"venueId": venue_id}).get("Item")
    if existing:
        return error(409, f"A venue with id '{venue_id}' already exists.")

    claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
    created_by = claims.get("email", "")

    item = {
        "venueId": venue_id,
        "name": name,
        "createdAt": now_iso(),
        "createdBy": created_by,
    }
    if body.get("description"):
        item["description"] = body["description"]

    table.put_item(Item=item)
    return response(201, item)
