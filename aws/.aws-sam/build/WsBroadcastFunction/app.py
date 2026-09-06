"""
CrowdShield — WebSocket broadcast handler (Phase 4).

Triggered by DynamoDB Streams (NEW_IMAGE) on VenueStateTable, AlertsTable,
IncidentsTable, and RecommendationsTable — one Lambda handles all four
sources so there's a single place that knows how to reach connected
clients, rather than duplicating the "look up connections, push, prune
stale ones" logic four times.

Each stream record's origin table is identified from its DynamoDB stream
ARN (passed in the event source mapping), which tells us both the
"resource" label to send to clients and where venueId lives in the image.
"""

from __future__ import annotations

import json
import os
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
connections_table = dynamodb.Table(os.environ["CONNECTIONS_TABLE"])

apigw_management = boto3.client(
    "apigatewaymanagementapi",
    endpoint_url=os.environ["WEBSOCKET_MANAGEMENT_ENDPOINT"],
)

# Maps each source table's env-configured name to the "resource" label sent
# to clients, so the app can dispatch on message.resource without needing to
# know DynamoDB table naming conventions.
RESOURCE_LABELS = {
    os.environ.get("VENUE_STATE_TABLE", ""): "venue_state",
    os.environ.get("ALERTS_TABLE", ""): "alert",
    os.environ.get("INCIDENTS_TABLE", ""): "incident",
    os.environ.get("RECOMMENDATIONS_TABLE", ""): "recommendation",
}


def _decimal_to_native(value):
    """Recursively converts DynamoDB Decimals to int/float for JSON output."""
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    if isinstance(value, dict):
        return {k: _decimal_to_native(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_decimal_to_native(v) for v in value]
    return value


def _table_name_from_stream_arn(stream_arn: str) -> str:
    # arn:aws:dynamodb:region:account:table/TABLE_NAME/stream/TIMESTAMP
    parts = stream_arn.split(":")
    table_part = parts[5]  # "table/TABLE_NAME/stream/TIMESTAMP"
    return table_part.split("/")[1]


def handler(event, context):
    for record in event.get("Records", []):
        if record.get("eventName") not in ("INSERT", "MODIFY"):
            continue

        stream_arn = record.get("eventSourceARN", "")
        table_name = _table_name_from_stream_arn(stream_arn)
        resource_label = RESOURCE_LABELS.get(table_name)
        if resource_label is None:
            continue

        new_image = record.get("dynamodb", {}).get("NewImage")
        if not new_image:
            continue

        item = _deserialize(new_image)
        venue_id = item.get("venueId")
        if not venue_id:
            continue

        _broadcast_to_venue(venue_id, resource_label, item)

    return {"statusCode": 200}


def _deserialize(dynamo_image: dict) -> dict:
    """Converts a raw DynamoDB Streams NewImage (typed AttributeValue dict)
    into a plain Python dict using boto3's deserializer, then normalizes
    Decimals to native numeric types for clean JSON output over the socket.
    """
    deserializer = boto3.dynamodb.types.TypeDeserializer()
    plain = {k: deserializer.deserialize(v) for k, v in dynamo_image.items()}
    return _decimal_to_native(plain)


def _broadcast_to_venue(venue_id: str, resource: str, item: dict) -> None:
    connections = connections_table.query(
        IndexName="byVenue",
        KeyConditionExpression=boto3.dynamodb.conditions.Key("venueId").eq(venue_id),
    ).get("Items", [])

    if not connections:
        return

    payload = json.dumps({"resource": resource, "item": item}, default=str).encode("utf-8")

    for connection in connections:
        connection_id = connection["connectionId"]
        try:
            apigw_management.post_to_connection(ConnectionId=connection_id, Data=payload)
        except ClientError as exc:
            error_code = exc.response.get("Error", {}).get("Code", "")
            # GoneException (410) means the client disconnected without
            # $disconnect firing cleanly — prune it so we stop wasting calls
            # on it. Any other error is logged but not treated as fatal for
            # the rest of the broadcast loop.
            if error_code == "GoneException" or exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode") == 410:
                connections_table.delete_item(Key={"connectionId": connection_id})
            else:
                print(f"Broadcast: failed to post to {connection_id}: {exc}")
