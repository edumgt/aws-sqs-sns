import boto3
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone

SNS_TOPIC_ARN = 'arn:aws:sns:ap-northeast-2:086015456585:my-sns-topic'
SLACK_WEBHOOK_URL = 'https://hooks.slack.com/services/생략'

sns = boto3.client('sns', region_name='ap-northeast-2')


def publish_to_sns(subject: str, message: str) -> str:
    response = sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject,
        Message=message,
    )
    message_id = response['MessageId']
    print(f"✅ SNS 발행 완료 — MessageId: {message_id}")
    return message_id


def send_to_slack(subject: str, message: str, message_id: str) -> None:
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    payload = {
        "blocks": [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": subject, "emoji": True}
            },
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": message}
            },
            {
                "type": "context",
                "elements": [
                    {"type": "mrkdwn", "text": f"*AWS SNS* | {timestamp} | `{message_id}`"}
                ]
            }
        ]
    }

    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        SLACK_WEBHOOK_URL,
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"✅ Slack 전송 완료 — {resp.status}")
    except urllib.error.HTTPError as e:
        print(f"❌ Slack 전송 실패: {e.code} {e.read().decode()}")


if __name__ == "__main__":
    subject = "[알림] 서버 이벤트 발생"
    message = "SNS → Slack 연동 테스트 메시지입니다."

    message_id = publish_to_sns(subject, message)
    send_to_slack(subject, message, message_id)
