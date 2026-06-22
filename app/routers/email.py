from botocore.exceptions import ClientError
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.services.ses import send_email as ses_send

router = APIRouter()


class EmailRequest(BaseModel):
    from_email: str
    to_email: str
    subject: str
    message: str


@router.post("/send")
def send_email(req: EmailRequest):
    try:
        ses_send(req.from_email, req.to_email, req.subject, req.message)
    except ClientError as e:
        raise HTTPException(status_code=500, detail=e.response['Error']['Message'])
    return {"ok": True}
