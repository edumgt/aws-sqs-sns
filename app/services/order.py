"""주문/재고 서비스 (producer.py + consumer.py 통합)"""
import json
import uuid
from datetime import datetime

from app.services.sqs import ORDER_QUEUE_URL, client as sqs_client, delete, receive, verify_md5

_inventory: dict[str, int] = {
    "PROD-001": 10,
    "PROD-042": 3,
    "PROD-007": 20,
}


def create_order(product_id: str, quantity: int, customer_id: str) -> dict:
    return {
        "event": "ORDER_PLACED",
        "order_id": str(uuid.uuid4()),
        "product_id": product_id,
        "quantity": quantity,
        "customer_id": customer_id,
        "timestamp": datetime.utcnow().isoformat(),
    }


def send_order(order: dict) -> str:
    resp = sqs_client.send_message(
        QueueUrl=ORDER_QUEUE_URL,
        MessageBody=json.dumps(order, ensure_ascii=False),
        MessageAttributes={"event_type": {"StringValue": order["event"], "DataType": "String"}},
    )
    return resp["MessageId"]


def process_orders(max_messages: int = 10) -> list[dict]:
    results = []
    for msg in receive(ORDER_QUEUE_URL, max_messages=max_messages, wait_seconds=2):
        body_str = msg["Body"]
        if not verify_md5(body_str, msg["MD5OfBody"]):
            results.append({"status": "error", "reason": "MD5 불일치"})
            continue
        try:
            order = json.loads(body_str)
        except json.JSONDecodeError:
            results.append({"status": "error", "reason": "JSON 파싱 오류"})
            continue
        results.append(_apply_order(order))
        delete(ORDER_QUEUE_URL, msg["ReceiptHandle"])
    return results


def _apply_order(order: dict) -> dict:
    if order.get("event") != "ORDER_PLACED":
        return {"status": "skip", "reason": f"알 수 없는 이벤트: {order.get('event')}"}

    pid, qty = order["product_id"], order["quantity"]
    if pid not in _inventory:
        return {"status": "error", "order_id": order["order_id"], "reason": f"상품 없음: {pid}"}
    if _inventory[pid] < qty:
        return {"status": "error", "order_id": order["order_id"], "reason": f"재고 부족 (현재: {_inventory[pid]})"}

    _inventory[pid] -= qty
    return {"status": "ok", "order_id": order["order_id"], "product_id": pid, "quantity": qty, "remaining": _inventory[pid]}


def get_inventory() -> dict:
    return dict(_inventory)
