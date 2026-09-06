"""
CrowdShield — WebSocket $connect handler (Phase 4).

Clients connect with an ID token and venueId as query string parameters,
e.g. wss://.../dev?token=<idToken>&venueId=technova-festival-grounds

Rejects the connection (403) if the token doesn't verify. On success,
stores the connectionId + venueId in ConnectionsTable so the broadcast
Lambda knows who to push updates to for that venue.
"""

from __future__ import annotations

import os
import time

import boto3

from crowdshield_common import error, response
from crowdshield_jwt import TokenInvalid, verify_id_token

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["CONNECTIONS_TABLE"])

# Connections expire after 24h of no explicit $disconnect (e.g. app killed
# without a clean close) — TTL cleanup on ConnectionsTable, not a hard
# session limit; a live connection just keeps getting used normally.
CONNECTION_TTL_SECONDS = 24 * 60 * 60


def handler(event, context):
    connection_id = event["requestContext"]["connectionId"]
    params = event.get("queryStringParameters") or {}

    token = params.get("token", "")
    venue_id = params.get("venueId", "")

    if not token or not venue_id:
        return error(400, "token and venueId query parameters are required.")

    try:
        claims = verify_id_token(token)
    except TokenInvalid as exc:
        return error(403, f"Unauthorized: {exc}")

    email = claims.get("email", "")

    table.put_item(
        Item={
            "connectionId": connection_id,
            "venueId": venue_id,
            "email": email,
            "connectedAt": int(time.time()),
            "expiresAt": int(time.time()) + CONNECTION_TTL_SECONDS,
        }
    )

    return response(200, {"message": "Connected."})
