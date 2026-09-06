"""
Shared helpers used by every CrowdShield Lambda.

Handles:
- Building consistent JSON API Gateway responses (with CORS headers)
- Reading the caller's Cognito group membership from the JWT authorizer context
- Small validation helpers so each handler stays short
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any


def response(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }


def error(status: int, message: str) -> dict[str, Any]:
    return response(status, {"error": message})


def caller_groups(event: dict[str, Any]) -> list[str]:
    """
    Pulls cognito:groups out of the JWT authorizer context that API Gateway
    HTTP API attaches to the event when a JwtAuthorizer is configured.
    """
    try:
        claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    except (KeyError, TypeError):
        return []

    groups = claims.get("cognito:groups", "")
    # API Gateway JWT authorizer flattens list claims into a comma/space
    # separated string in some configurations; handle both list and string.
    if isinstance(groups, list):
        return groups
    if isinstance(groups, str) and groups:
        # Groups can arrive as "[Command]" or "Command,Public"
        cleaned = groups.strip("[]")
        return [g.strip() for g in cleaned.replace(",", " ").split() if g.strip()]
    return []


def require_command(event: dict[str, Any]) -> dict[str, Any] | None:
    """Returns an error response if caller is not in the Command group, else None."""
    if "Command" not in caller_groups(event):
        return error(403, "Command role required for this action.")
    return None


def path_param(event: dict[str, Any], name: str) -> str | None:
    return (event.get("pathParameters") or {}).get(name)


def parse_body(event: dict[str, Any]) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    """Returns (body, None) on success or (None, error_response) on failure."""
    raw = event.get("body")
    if raw is None:
        return None, error(400, "Request body is required.")
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return None, error(400, "Request body must be valid JSON.")
    if not isinstance(parsed, dict):
        return None, error(400, "Request body must be a JSON object.")
    return parsed, None


def new_id() -> str:
    return uuid.uuid4().hex[:12]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ttl_epoch(hours: int = 48) -> int:
    """Default 48h TTL for telemetry-style items (alerts/incidents)."""
    return int((datetime.now(timezone.utc) + timedelta(hours=hours)).timestamp())


def to_dynamo_safe(value: Any) -> Any:
    """
    Recursively converts Python floats to Decimal, since boto3's DynamoDB
    resource layer raises TypeError on native floats. Safe to call on any
    JSON-parsed structure (dict/list/scalar) before a put_item/update_item.
    """
    if isinstance(value, float):
        # str() avoids binary-float imprecision leaking into the Decimal.
        return Decimal(str(value))
    if isinstance(value, dict):
        return {k: to_dynamo_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [to_dynamo_safe(v) for v in value]
    return value
