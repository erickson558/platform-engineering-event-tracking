import json
import os
import uuid
from datetime import UTC, datetime
from typing import Any

import boto3


def _firehose_client():
    return boto3.client("firehose")


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def _parse_event_body(raw_body: str | None) -> list[dict[str, Any]]:
    if not raw_body:
        raise ValueError("Request body is required")

    parsed = json.loads(raw_body)
    if isinstance(parsed, dict):
        return [parsed]
    if isinstance(parsed, list):
        return parsed
    raise ValueError("Body must be a JSON object or array")


def _validate_event(event: dict[str, Any]) -> None:
    required = ["event_name", "event_timestamp", "source", "user_id", "payload"]
    missing = [k for k in required if k not in event]
    if missing:
        raise ValueError(f"Missing required fields: {', '.join(missing)}")


def _normalize_event(event: dict[str, Any], received_at: str) -> dict[str, Any]:
    _validate_event(event)
    return {
        "event_id": event.get("event_id", str(uuid.uuid4())),
        "event_name": event["event_name"],
        "event_timestamp": event["event_timestamp"],
        "source": event["source"],
        "user_id": event["user_id"],
        "version": str(event.get("version", "1")),
        "payload": event["payload"],
        "received_at": received_at,
    }


def _authorize(headers: dict[str, Any]) -> bool:
    expected = os.environ.get("AUTH_SHARED_SECRET", "")
    provided = headers.get("x-api-key") or headers.get("X-API-Key")
    return bool(expected) and provided == expected


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context

    headers = event.get("headers") or {}
    if not _authorize(headers):
        return _response(401, {"message": "Unauthorized"})

    try:
        max_batch_size = int(os.environ.get("MAX_BATCH_SIZE", "100"))
        stream_name = os.environ["FIREHOSE_STREAM_NAME"]
        received_at = datetime.now(UTC).isoformat()

        raw_events = _parse_event_body(event.get("body"))
        if len(raw_events) > max_batch_size:
            return _response(413, {"message": f"Max batch size is {max_batch_size}"})

        records = []
        for raw in raw_events:
            normalized = _normalize_event(raw, received_at)
            records.append(
                {
                    "Data": (json.dumps(normalized, separators=(",", ":")) + "\n").encode("utf-8")
                }
            )

        result = _firehose_client().put_record_batch(DeliveryStreamName=stream_name, Records=records)
        failed = result.get("FailedPutCount", 0)
        if failed > 0:
            return _response(
                503,
                {
                    "message": "Temporary ingestion failure",
                    "accepted": len(records) - failed,
                    "failed": failed,
                },
            )

        return _response(202, {"accepted": len(records), "failed": 0})
    except json.JSONDecodeError:
        return _response(400, {"message": "Malformed JSON payload"})
    except ValueError as err:
        return _response(400, {"message": str(err)})
    except Exception:
        return _response(500, {"message": "Unexpected server error"})
