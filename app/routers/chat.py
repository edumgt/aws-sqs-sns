import json
from datetime import datetime, timezone

from fastapi import APIRouter
from pydantic import BaseModel

from app.services.sqs import CHAT_QUEUE_URL, delete, receive, send

router = APIRouter()


class ChatMessage(BaseModel):
    username: str
    text: str


@router.post("/send")
def send_message(msg: ChatMessage):
    body = {"username": msg.username, "text": msg.text, "time": datetime.now(timezone.utc).strftime('%H:%M:%S')}
    send(CHAT_QUEUE_URL, body)
    return {"ok": True}


@router.get("/messages")
def receive_messages():
    messages = []
    for m in receive(CHAT_QUEUE_URL, max_messages=10, wait_seconds=2):
        try:
            messages.append(json.loads(m["Body"]))
        except json.JSONDecodeError:
            messages.append({"username": "?", "text": m["Body"], "time": ""})
        delete(CHAT_QUEUE_URL, m["ReceiptHandle"])
    return {"messages": messages}
