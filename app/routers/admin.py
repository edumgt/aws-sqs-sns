import boto3
from fastapi import APIRouter

from app.services.sns import TOPIC_ARN
from app.services.sqs import CHAT_QUEUE_URL, ORDER_QUEUE_URL, SNS_QUEUE_URL

router = APIRouter()

_sqs = boto3.client('sqs', region_name='ap-northeast-2')
_sns = boto3.client('sns', region_name='ap-northeast-2')
_ses = boto3.client('ses', region_name='ap-northeast-2')

_QUEUES = [
    {"label": "채팅 (my-test-queue)",  "url": CHAT_QUEUE_URL},
    {"label": "SNS 연동 (my-sns-queue)", "url": SNS_QUEUE_URL},
    {"label": "주문 (order-queue)",      "url": ORDER_QUEUE_URL},
]

_ATTR_NAMES = [
    'ApproximateNumberOfMessages',
    'ApproximateNumberOfMessagesNotVisible',
    'MessageRetentionPeriod',
    'CreatedTimestamp',
]


@router.get("/sqs")
def sqs_status():
    result = []
    for q in _QUEUES:
        try:
            attrs = _sqs.get_queue_attributes(QueueUrl=q["url"], AttributeNames=_ATTR_NAMES)["Attributes"]
            result.append({
                "label": q["label"],
                "url": q["url"],
                "waiting":    int(attrs.get("ApproximateNumberOfMessages", 0)),
                "in_flight":  int(attrs.get("ApproximateNumberOfMessagesNotVisible", 0)),
                "retention_days": int(attrs.get("MessageRetentionPeriod", 0)) // 86400,
                "status": "ok",
            })
        except Exception as e:
            result.append({"label": q["label"], "url": q["url"], "status": "error", "error": str(e)})
    return {"queues": result}


@router.get("/sns")
def sns_status():
    try:
        attrs = _sns.get_topic_attributes(TopicArn=TOPIC_ARN)["Attributes"]
        subs = _sns.list_subscriptions_by_topic(TopicArn=TOPIC_ARN).get("Subscriptions", [])
        return {
            "status": "ok",
            "topic": {
                "arn": TOPIC_ARN,
                "confirmed": int(attrs.get("SubscriptionsConfirmed", 0)),
                "pending":   int(attrs.get("SubscriptionsPending", 0)),
                "deleted":   int(attrs.get("SubscriptionsDeleted", 0)),
            },
            "subscriptions": [
                {
                    "protocol": s["Protocol"],
                    "endpoint": s["Endpoint"][:64] + ("…" if len(s["Endpoint"]) > 64 else ""),
                    "confirmed": s["SubscriptionArn"] != "PendingConfirmation",
                }
                for s in subs
            ],
        }
    except Exception as e:
        return {"status": "error", "error": str(e)}


@router.get("/ses")
def ses_status():
    try:
        quota = _ses.get_send_quota()
        identities = _ses.list_identities(IdentityType="EmailAddress", MaxItems=20).get("Identities", [])
        verification = {}
        if identities:
            verification = _ses.get_identity_verification_attributes(
                Identities=identities
            ).get("VerificationAttributes", {})
        return {
            "status": "ok",
            "quota": {
                "max_24h":   int(quota["Max24HourSend"]),
                "max_rate":  quota["MaxSendRate"],
                "sent_24h":  int(quota["SentLast24Hours"]),
            },
            "identities": [
                {
                    "email":  email,
                    "verified": verification.get(email, {}).get("VerificationStatus") == "Success",
                }
                for email in identities
            ],
        }
    except Exception as e:
        return {"status": "error", "error": str(e)}
