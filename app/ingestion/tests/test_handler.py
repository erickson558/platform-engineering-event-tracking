import json
import os
from unittest.mock import patch

import handler


def _event(payload, api_key="secret"):
    return {
        "headers": {"x-api-key": api_key},
        "body": json.dumps(payload),
    }


def test_unauthorized():
    os.environ["AUTH_SHARED_SECRET"] = "secret"
    result = handler.lambda_handler(_event({}, api_key="wrong"), None)
    assert result["statusCode"] == 401


@patch("handler._firehose_client")
def test_accepts_single_event(mock_client):
    os.environ["AUTH_SHARED_SECRET"] = "secret"
    os.environ["FIREHOSE_STREAM_NAME"] = "stream"
    mock_client.return_value.put_record_batch.return_value = {"FailedPutCount": 0}

    payload = {
        "event_name": "sign_in",
        "event_timestamp": "2026-04-29T17:00:00Z",
        "source": "web",
        "user_id": "u-1",
        "payload": {"method": "oauth"},
    }

    result = handler.lambda_handler(_event(payload), None)
    assert result["statusCode"] == 202
    body = json.loads(result["body"])
    assert body["accepted"] == 1


def test_rejects_invalid_payload():
    os.environ["AUTH_SHARED_SECRET"] = "secret"
    os.environ["FIREHOSE_STREAM_NAME"] = "stream"

    payload = {
        "event_name": "sign_in",
        "source": "web",
        "user_id": "u-1",
        "payload": {"method": "oauth"},
    }

    result = handler.lambda_handler(_event(payload), None)
    assert result["statusCode"] == 400
