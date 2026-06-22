import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone

import boto3
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()
sns = boto3.client('sns', region_name='ap-northeast-2')
SNS_TOPIC_ARN = 'arn:aws:sns:ap-northeast-2:086015456585:my-sns-topic'
SLACK_WEBHOOK_URL = os.environ.get(
    'SLACK_WEBHOOK_URL',
    'https://hooks.slack.com/services/xxxxx',
)


class SlackRequest(BaseModel):
    subject: str
    message: str


@router.post("/send")
def send_to_slack(req: SlackRequest):
    resp = sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=req.subject, Message=req.message)
    message_id = resp['MessageId']

    if not SLACK_WEBHOOK_URL:
        raise HTTPException(status_code=500, detail="SLACK_WEBHOOK_URL이 설정되지 않았습니다.")

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
