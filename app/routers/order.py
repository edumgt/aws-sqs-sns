from fastapi import APIRouter
from pydantic import BaseModel

from app.services.order import create_order, get_inventory, process_orders, send_order

router = APIRouter()


class OrderRequest(BaseModel):
    product_id: str
    quantity: int
    customer_id: str


@router.post("/place")
def place_order(req: OrderRequest):
    order = create_order(req.product_id, req.quantity, req.customer_id)
    message_id = send_order(order)
    return {"ok": True, "messageId": message_id, "orderId": order["order_id"]}


@router.post("/process")
def process():
    results = process_orders()
    return {"processed": len(results), "results": results}


@router.get("/inventory")
def inventory():
    return {"inventory": get_inventory()}
