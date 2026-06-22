"""SQS 공통 클라이언트 및 유틸리티 (sqs.py + check.py 통합)"""
import hashlib
import json

import boto3

client = boto3.client('sqs', region_name='ap-northeast-2')

CHAT_QUEUE_URL  = 'https://sqs.ap-northeast-2.amazonaws.com/086015456585/my-test-queue'
SNS_QUEUE_URL   = 'https://sqs.ap-northeast-2.amazonaws.com/086015456585/my-sns-queue'
ORDER_QUEUE_URL = 'https://sqs.ap-northeast-2.amazonaws.com/086015456585/order-queue'


def send(queue_url: str, body: dict) -> str:
    resp = client.send_message(QueueUrl=queue_url, MessageBody=json.dumps(body, ensure_ascii=False))
    return resp['MessageId']


def receive(queue_url: str, max_messages: int = 10, wait_seconds: int = 2) -> list:
    resp = client.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=max_messages, WaitTimeSeconds=wait_seconds)
    return resp.get('Messages', [])


def delete(queue_url: str, receipt_handle: str) -> None:
    client.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)


def verify_md5(body_str: str, expected_md5: str) -> bool:
    """메시지 무결성 검증 — 암호화 목적이 아닌 전송 오류 감지용"""
    return hashlib.md5(body_str.encode()).hexdigest() == expected_md5
