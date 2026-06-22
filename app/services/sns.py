"""SNS 공통 클라이언트 (sns_publish.py + email1.py + email2.py 통합)"""
import boto3

client = boto3.client('sns', region_name='ap-northeast-2')
TOPIC_ARN = 'arn:aws:sns:ap-northeast-2:086015456585:my-sns-topic'


def publish(subject: str, message: str) -> str:
    resp = client.publish(TopicArn=TOPIC_ARN, Subject=subject, Message=message)
    return resp['MessageId']


def subscribe_email(email: str) -> str:
    """이메일 구독 추가 — 수신자가 확인 메일에서 승인해야 활성화됨"""
    resp = client.subscribe(TopicArn=TOPIC_ARN, Protocol='email', Endpoint=email)
    return resp['SubscriptionArn']
