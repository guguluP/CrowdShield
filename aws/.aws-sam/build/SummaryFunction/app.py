"""
CrowdShield — Bedrock incident summary endpoint (Stage 1).

POST /venues/{venueId}/summary   — generate a fresh AI summary (any authenticated user)

Mirrors FoundationModelsSummaryProvider's on-device prompt design (see the
iOS app's Services/FoundationModelsSummaryProvider.swift) so server-side
summaries are comparable quality to on-device ones — same instructions,
same three-field output shape (headline / body / recommendedNextStep).

Pulls venue-state (with per-zone risk detail — see venue_state Lambda's
`zones` field, added in Stage 1) and the most recent alerts directly from
DynamoDB rather than trusting client-submitted state, since a summary
endpoint that just echoes back whatever the caller claims is true offers no
real value over the on-device version.

Uses Bedrock's Converse API with a forced tool-use call to get reliable
structured output instead of parsing free-form prose — the model has no
choice but to call `emit_summary` with the three required fields.
"""

from __future__ import annotations

import json
import os
import time

import boto3
from botocore.exceptions import ClientError

from crowdshield_common import error, now_iso, path_param, response

dynamodb = boto3.resource("dynamodb")
venue_state_table = dynamodb.Table(os.environ["VENUE_STATE_TABLE"])
alerts_table = dynamodb.Table(os.environ["ALERTS_TABLE"])

bedrock = boto3.client("bedrock-runtime")

MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "global.anthropic.claude-sonnet-4-6")

SYSTEM_PROMPT = (
    "You are a crowd-safety operations assistant embedded in a command "
    "dashboard used by event safety officers. You will be given structured "
    "data about current crowd density, risk zones, flow issues, and recent "
    "alerts at a venue. Produce a concise, actionable situational summary "
    "for a human operator who needs to make a decision in the next few "
    "seconds — not a general report. Be specific about which zones and "
    "what actions, using the exact zone names given. Do not invent data "
    "that was not provided. If overall risk is low and nothing is "
    "actionable, say so plainly rather than manufacturing urgency."
)

TOOL_SPEC = {
    "toolSpec": {
        "name": "emit_summary",
        "description": "Return the structured incident summary for display on the command dashboard.",
        "inputSchema": {
            "json": {
                "type": "object",
                "properties": {
                    "headline": {
                        "type": "string",
                        "description": "One short sentence, the single most important thing for the operator to know right now.",
                    },
                    "body": {
                        "type": "string",
                        "description": "Two to four sentences of supporting detail — which zones, what's happening, why it matters.",
                    },
                    "recommendedNextStep": {
                        "type": "string",
                        "description": "One concrete, specific action the operator should consider taking next.",
                    },
                },
                "required": ["headline", "body", "recommendedNextStep"],
            }
        },
    }
}


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    venue_id = path_param(event, "venueId")

    if not venue_id:
        return error(400, "venueId path parameter is required.")
    if method != "POST":
        return error(405, f"Method {method} not allowed.")

    venue_state = venue_state_table.get_item(Key={"venueId": venue_id}).get("Item")
    if not venue_state:
        return error(404, f"No state recorded yet for venue '{venue_id}' — nothing to summarize.")

    recent_alerts = _recent_alerts(venue_id, limit=10)

    user_message = _build_prompt(venue_state, recent_alerts)

    try:
        summary = _call_bedrock(user_message)
    except ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "")
        # AccessDeniedException specifically means Bedrock model access
        # hasn't been granted for this account/region yet — a distinct,
        # actionable error from a generic failure, worth surfacing clearly
        # rather than a blanket 500.
        if error_code == "AccessDeniedException":
            return error(502, "Bedrock model access not enabled for this account/region.")
        return error(502, f"Bedrock request failed: {exc}")
    except (KeyError, ValueError, json.JSONDecodeError) as exc:
        return error(502, f"Unexpected Bedrock response shape: {exc}")

    summary["generatedAt"] = now_iso()
    summary["venueId"] = venue_id
    return response(200, summary)


def _recent_alerts(venue_id: str, limit: int) -> list[dict]:
    result = alerts_table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key("venueId").eq(venue_id),
        ScanIndexForward=False,
        Limit=limit,
    )
    return result.get("Items", [])


def _build_prompt(venue_state: dict, recent_alerts: list[dict]) -> str:
    zones = venue_state.get("zones", [])
    hotspots = venue_state.get("hotspots", [])

    lines = [
        f"Venue density (average): {venue_state.get('density', 'unknown')}",
        f"Venue movement speed (average): {venue_state.get('movementSpeed', 'unknown')}",
        f"Bottleneck zones: {', '.join(hotspots) if hotspots else 'none reported'}",
        f"State last updated: {venue_state.get('updatedAt', 'unknown')}",
        "",
        "Per-zone detail:",
    ]
    if zones:
        for zone in zones:
            lines.append(
                f"  - {zone.get('name', 'Unknown zone')}: "
                f"density={zone.get('density')}, "
                f"riskScore={zone.get('riskScore')}, "
                f"stampedeLikelihood={zone.get('stampedeLikelihood')}, "
                f"panicIntensity={zone.get('panicIntensity')}, "
                f"bottleneck={zone.get('isBottleneck')}"
            )
    else:
        lines.append("  (no per-zone detail available)")

    lines.append("")
    lines.append("Recent alerts (most recent first):")
    if recent_alerts:
        for alert in recent_alerts:
            lines.append(
                f"  - [{alert.get('severity', 'info')}] {alert.get('type', 'general')}: "
                f"{alert.get('message', '')} (at {alert.get('createdAt', 'unknown')})"
            )
    else:
        lines.append("  (no recent alerts)")

    return "\n".join(lines)


def _call_bedrock(user_message: str) -> dict:
    response_data = bedrock.converse(
        modelId=MODEL_ID,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": user_message}]}],
        toolConfig={
            "tools": [TOOL_SPEC],
            "toolChoice": {"tool": {"name": "emit_summary"}},
        },
        inferenceConfig={"maxTokens": 400, "temperature": 0.3},
    )

    output_message = response_data["output"]["message"]
    for content_block in output_message["content"]:
        if "toolUse" in content_block:
            tool_input = content_block["toolUse"]["input"]
            return {
                "headline": tool_input["headline"],
                "body": tool_input["body"],
                "recommendedNextStep": tool_input["recommendedNextStep"],
            }

    raise ValueError("Bedrock response contained no toolUse block.")
