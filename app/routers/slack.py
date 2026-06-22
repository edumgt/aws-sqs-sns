import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone

from dotenv import load_dotenv
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.services.sns import publish

load_dotenv()

router = APIRouter()
SLACK_WEBHOOK_URL = os.environ.get('SLACK_WEBHOOK_URL', '')


class SlackRequest(BaseModel):
    subject: str
    message: str


@router.post("/send")
def send_to_slack(req: SlackRequest):
    if not SLACK_WEBHOOK_URL:
        raise HTTPException(status_code=500, detail="SLACK_WEBHOOK_URL이 설정되지 않았습니다.")

    message_id = publish(req.subject, req.message)

    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    payload = {
        "blocks": [
            {"type": "header", "text": {"type": "plain_text", "text": req.subject, "emoji": True}},
            {"type": "section", "text": {"type": "mrkdwn", "text": req.message}},
            {"type": "context", "elements": [
                {"type": "mrkdwn", "text": f"*AWS SNS* | {timestamp} | `{message_id}`"}
            ]},
        ]
    }
    data = json.dumps(payload, ensure_ascii=False).encode()
    http_req = urllib.request.Request(
        SLACK_WEBHOOK_URL, data=data,
        headers={'Content-Type': 'application/json'}, method='POST',
    )
    try:
        with urllib.request.urlopen(http_req, timeout=5):
            pass
    except urllib.error.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Slack 오류: {e.code} {e.read().decode()}")

    return {"ok": True, "messageId": message_id}
