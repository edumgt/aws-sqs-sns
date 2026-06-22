import boto3
import hashlib
import json

# SQS 클라이언트 생성
sqs = boto3.client('sqs', region_name='ap-northeast-2')

# 사용 중인 SQS Queue URL
QUEUE_URL = 'https://sqs.ap-northeast-2.amazonaws.com/086015456585/my-test-queue'
# QUEUE_URL = 'https://sqs.ap-northeast-2.amazonaws.com/086015456585/my-sns-queue'

def send_message(message_body: dict):
    """메시지 전송 함수"""
    body_str = json.dumps(message_body)
    response = sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=body_str
    )
    print("✅ 메시지 전송 완료")
    print("MessageId:", response['MessageId'])
    print("MD5OfMessageBody:", response['MD5OfMessageBody'])

def receive_message():
    """메시지 수신 및 MD5 무결성 확인"""
    response = sqs.receive_message(
        QueueUrl=QUEUE_URL,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=5
    )

    messages = response.get('Messages', [])
    if not messages:
        print("📭 대기열에 메시지가 없습니다.")
        return

    for msg in messages:
        body = msg['Body']
        md5 = msg['MD5OfBody']

        # 무결성 검증
        local_md5 = hashlib.md5(body.encode()).hexdigest()
        is_valid = md5 == local_md5

        print("\n📩 메시지 수신")
        print("Body:", body)
        print("MD5 검증:", "✅ 일치" if is_valid else "❌ 불일치")

        # 메시지 삭제
        receipt_handle = msg['ReceiptHandle']
        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
        print("🗑️ 메시지 삭제 완료")

# 테스트 실행
if __name__ == "__main__":
    # 1. 메시지 보내기
    send_message({"message":"python 으로 테스트 합니다. !!!! @@@@ #### "})

    # 2. 메시지 받기
    receive_message()
