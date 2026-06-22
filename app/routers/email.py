import boto3
from botocore.exceptions import ClientError
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()
ses = boto3.client('ses', region_name='ap-northeast-2')


class EmailRequest(BaseModel):
    from_email: str
    to_email: str
    subject: str
    message: str


@router.post("/send")
def send_email(req: EmailRequest):
    try:
        ses.send_email(
            Source=req.from_email,
            Destination={'ToAddresses': [req.to_email]},
            Message={
                'Subject': {'Data': req.subject, 'Charset': 'UTF-8'},
                'Body': {'Text': {'Data': req.message, 'Charset': 'UTF-8'}},
            },
        )
    except ClientError as e:
        raise HTTPException(status_code=500, detail=e.response['Error']['Message'])
    return {"ok": True}
