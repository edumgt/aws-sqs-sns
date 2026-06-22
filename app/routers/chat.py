from fastapi import APIRouter
from pydantic import BaseModel
import boto3
import json
from datetime import datetime, timezone

router = APIRouter()
sqs = boto3.client('sqs', region_name='ap-northeast-2')
QUEUE_URL = 'https://sqs.ap-northeast-2.amazonaws.com/086015456585/my-test-queue'


class ChatMessage(BaseModel):
    username: str
    text: str


@router.post("/send")
def send_message(msg: ChatMessage):
    body = {
        "username": msg.username,
        "text": msg.text,
        "time": datetime.now(timezone.utc).strftime('%H:%M:%S'),
    }
    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(body, ensure_ascii=False))
    return {"ok": True}


@router.get("/messages")
def receive_messages():
    resp = sqs.receive_message(
        QueueUrl=QUEUE_URL,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=2,
    )
    messages = []
    for m in resp.get('Messages', []):
        try:
            messages.append(json.loads(m['Body']))
        except json.JSONDecodeError:
            messages.append({"username": "?", "text": m['Body'], "time": ""})
        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=m['ReceiptHandle'])
    return {"messages": messages}
