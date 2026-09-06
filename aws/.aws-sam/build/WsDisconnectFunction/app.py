"""
CrowdShield — WebSocket $disconnect handler (Phase 4).

Removes the connection's row from ConnectionsTable so the broadcast Lambda
stops trying to push to it. Best-effort: if the row is already gone (e.g.
TTL beat us to it) this is still a success from API Gateway's perspective.
"""

from __future__ import annotations

import os

import boto3

from crowdshield_common import response

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["CONNECTIONS_TABLE"])


def handler(event, context):
    connection_id = event["requestContext"]["connectionId"]
    table.delete_item(Key={"connectionId": connection_id})
    return response(200, {"message": "Disconnected."})
