"""
CrowdShield Phase 1 — health endpoint.

Returns 200 with service metadata so you can verify the stack deployed.
Optionally pings DynamoDB (VenueState table) to confirm IAM + table wiring.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import BotoCoreError, ClientError

dynamodb = boto3.resource("dynamodb")


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }


def handler(event, context):
    env = os.environ.get("ENVIRONMENT", "dev")
    venue_default = os.environ.get("VENUE_ID_DEFAULT", "technova-festival-grounds")
    table_name = os.environ.get("VENUE_STATE_TABLE", "")

    db_ok = False
    db_error = None

    if table_name:
        try:
            table = dynamodb.Table(table_name)
            # Lightweight call — does not require an existing item
            table.load()
            db_ok = True
        except (ClientError, BotoCoreError) as exc:
            db_error = str(exc)

    payload = {
        "service": "CrowdShield",
        "phase": 1,
        "status": "ok" if db_ok or not table_name else "degraded",
        "environment": env,
        "region": os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION"),
        "defaultVenueId": venue_default,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "checks": {
            "api": True,
            "dynamodbVenueState": db_ok,
        },
    }
    if db_error:
        payload["checks"]["dynamodbError"] = db_error

    # Always 200 for API reachability; operators can inspect checks.dynamodbVenueState
    return _response(200, payload)
