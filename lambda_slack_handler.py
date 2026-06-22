"""
AWS Lambda 함수 — SNS 메시지를 Slack으로 전달

배포 방법:
  1. 이 파일을 zip으로 압축
  2. Lambda 함수 생성 (Python 3.12, 핸들러: lambda_slack_handler.lambda_handler)
  3. 환경 변수 SLACK_WEBHOOK_URL 설정
  4. SNS 트리거 추가 (my-sns-topic)
"""

import json
import os
import urllib.request
import urllib.error

SLACK_WEBHOOK_URL = os.environ.get('SLACK_WEBHOOK_URL', '')


def send_to_slack(subject: str, message: str, timestamp: str) -> None:
    payload = {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": subject or "SNS 알림",
                    "emoji": True
                }
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": message
                }
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"*AWS SNS* | {timestamp}"
                    }
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
            print(f"Slack 응답: {resp.status} {resp.read().decode()}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Slack 전송 실패: {e.code} {e.read().decode()}") from e


def lambda_handler(event, context):
    if not SLACK_WEBHOOK_URL:
        raise EnvironmentError("환경 변수 SLACK_WEBHOOK_URL이 설정되지 않았습니다.")

    for record in event.get('Records', []):
        sns_payload = record.get('Sns', {})
        subject = sns_payload.get('Subject') or 'SNS 알림'
        message = sns_payload.get('Message', '')
        timestamp = sns_payload.get('Timestamp', '')

        print(f"수신된 SNS 메시지 — Subject: {subject}, Message: {message}")
        send_to_slack(subject, message, timestamp)

    return {'statusCode': 200, 'body': 'ok'}
