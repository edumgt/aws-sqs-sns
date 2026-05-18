# AWS SQS & SNS 학습 정리

## 목차
- [SQS 개요](#sqs-개요)
- [S3 버킷 공개 정책 예시](#s3-버킷-공개-정책-예시)
- [SQS 큐 생성](#sqs-큐-생성)
- [메시지 송수신](#메시지-송수신)
- [Python(boto3) 테스트](#pythonboto3-테스트)
- [SNS 연동](#sns-연동)
- [마이크로서비스 간 메시지 전달](#마이크로서비스-간-메시지-전달)
- [민감정보 체크](#민감정보-체크)
- [ElastiCache Cache-Aside 예제 (DBMS + FE)](#elasticache-cache-aside-예제-dbms--fe)

---

## SQS 개요
**AWS SQS (Simple Queue Service)**는 메시지를 큐에 넣고 꺼내는 방식으로 시스템 간 **비동기 통신**을 가능하게 하는 서비스입니다.

### 주요 특징
- **비동기 처리**: 생산자(Producer)와 소비자(Consumer)의 처리 속도가 달라도 안정적으로 전달
- **완전관리형**: 서버 구축/유지보수 없이 사용
- **높은 내구성**: 메시지를 다중 복제 저장

### 큐 유형
- **Standard Queue**: 무제한 처리량, 최소 1회 전달 보장, 순서 보장 ❌
- **FIFO Queue**: 정확히 1회 처리, 순서 보장 ✅, 처리량 제한

### 활용 예시
- 주문/결제 처리 비동기화
- 이미지 업로드 후 썸네일 생성
- 마이크로서비스 간 메시지 전달 → [예제 보기](#마이크로서비스-간-메시지-전달)

---

## S3 버킷 공개 정책 예시
> ⚠️ 운영 환경에서는 버킷 공개 정책 적용 시 보안 리스크가 큽니다.

```bash
aws s3api put-bucket-policy \
  --bucket <bucket-name> \
  --policy file://s3-policy.json
```

---

## SQS 큐 생성
```bash
aws sqs create-queue --queue-name my-test-queue
```

### 권한 오류 예시
```text
An error occurred (AccessDenied) when calling the CreateQueue operation: \
User: arn:aws:iam::<account-id>:user/<user-name> is not authorized to perform: \
sqs:CreateQueue on resource: arn:aws:sqs:<region>:<account-id>:my-test-queue
```

### 콘솔 권한 부여 화면
![권한 부여](images/image.png)

### 생성 결과 예시
```json
{
  "QueueUrl": "https://sqs.<region>.amazonaws.com/<account-id>/my-test-queue"
}
```

### 콘솔 확인
![콘솔 확인](images/image-1.png)

---

## 메시지 송수신
### 메시지 보내기
```bash
aws sqs send-message \
  --queue-url https://sqs.<region>.amazonaws.com/<account-id>/my-test-queue \
  --message-body '안녕하세요! 이건 테스트 메시지입니다.'
```

```json
{
  "MD5OfMessageBody": "11b4b81379e4a214e981839eae5b94bd",
  "MessageId": "b48bb9d4-4a97-4394-915a-2c1cbfdc4f4c"
}
```

> **MD5OfMessageBody**는 복호화용이 아니라 **무결성 확인용**입니다.

### 메시지 수신
```bash
aws sqs receive-message \
  --queue-url https://sqs.<region>.amazonaws.com/<account-id>/my-test-queue
```

```json
{
  "Messages": [
    {
      "MessageId": "b48bb9d4-4a97-4394-915a-2c1cbfdc4f4c",
      "ReceiptHandle": "...",
      "MD5OfBody": "11b4b81379e4a214e981839eae5b94bd",
      "Body": "안녕하세요! 이건 테스트 메시지입니다."
    }
  ]
}
```

### 무결성 체크 (check.py)
`check.py`에서 `body = '안녕하세요! 이건 테스트 메시지입니다.'`를 변경해가며 확인 가능합니다.

```text
PS> python check.py
❌ 메시지가 손상되었거나 변조되었습니다.
PS> python check.py
✅ 메시지 무결성 확인됨!
```

---

## Python(boto3) 테스트
### boto3 설치
```bash
pip install boto3
```

### 테스트 실행
```bash
python sqs.py
```

### 결과 예시
```text
✅ 메시지 전송 완료
MessageId: b86cc94e-9858-4c87-8629-b9b18e5b37fa
MD5OfMessageBody: 40ca02b8b3f81347d8ceb1b0769de9e3

📩 메시지 수신
Body: {"message": "python으로 테스트 합니다."}
MD5 검증: ✅ 일치
🗑️ 메시지 삭제 완료
```

> 수신을 생략하려면 `sqs.py`의 수신 부분을 주석 처리합니다.

```python
# 2. 메시지 받기
# receive_message()
```

### 콘솔에서 대기 확인
![콘솔 대기 확인](images/image-2.png)

---

## SNS 연동
**Amazon SNS (Simple Notification Service)**는 이벤트를 여러 구독자에게 푸시(Push)하는 서비스입니다.
SQS, Lambda, Email, HTTP 엔드포인트 등이 구독자가 될 수 있습니다.

### SNS 생성
```bash
aws sns create-topic --name my-sns-topic
```

### 권한 오류 예시
```text
An error occurred (AuthorizationError) when calling the CreateTopic operation: \
User: arn:aws:iam::<account-id>:user/<user-name> is not authorized to perform: \
SNS:CreateTopic on resource: arn:aws:sns:<region>:<account-id>:my-sns-topic
```

### 권한 부여 화면
![SNS 권한 부여](images/image-3.png)

### ARN 생성 결과 예시
```json
{
  "TopicArn": "arn:aws:sns:<region>:<account-id>:my-sns-topic"
}
```

### SNS용 SQS 큐 생성
```bash
aws sqs create-queue --queue-name my-sns-queue
```

```json
{
  "QueueUrl": "https://sqs.<region>.amazonaws.com/<account-id>/my-sns-queue"
}
```

### 구독자 생성
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:<region>:<account-id>:my-sns-topic \
  --protocol sqs \
  --notification-endpoint arn:aws:sqs:<region>:<account-id>:my-sns-queue
```

```json
{
  "SubscriptionArn": "arn:aws:sns:<region>:<account-id>:my-sns-topic:<subscription-id>"
}
```

### 메시지 수신 허용 (SQS 정책 적용)
> JSON 문자열의 따옴표 이스케이프에 주의하세요.

1. `sqs-policy.json` 생성
2. 정책 적용

```bash
aws sqs set-queue-attributes --cli-input-json file://sqs-policy.json
```

3. 적용 확인

```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.<region>.amazonaws.com/<account-id>/my-sns-queue \
  --attribute-names Policy
```

```json
{
  "Attributes": {
    "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"SQS:SendMessage\",\"Resource\":\"arn:aws:sqs:<region>:<account-id>:my-sns-queue\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"arn:aws:sns:<region>:<account-id>:my-sns-topic\"}}}]}"
  }
}
```

### 메시지 발행
```bash
aws sns publish \
  --topic-arn arn:aws:sns:<region>:<account-id>:my-sns-topic \
  --message '안녕하세요! SNS에서 보내는 메시지입니다.'
```

### 콘솔 확인
![SNS 메시지 확인](images/image-4.png)

### sqs.py 수정 예시
```python
QUEUE_URL = 'https://sqs.<region>.amazonaws.com/<account-id>/my-sns-queue'
```

---

## 마이크로서비스 간 메시지 전달

SQS를 활용하면 **서비스 간 직접 호출 없이** 이벤트 기반으로 통신할 수 있습니다.

### 시나리오 구성

```
[주문 서비스 (producer.py)]
        ↓ ORDER_PLACED 이벤트 전송
    [SQS 큐: order-queue]
        ↓ 이벤트 수신
[재고 서비스 (consumer.py)]
        ↓ 재고 차감 처리
```

### SQS 큐 생성

```bash
aws sqs create-queue --queue-name order-queue
```

### 주문 서비스 — producer.py

`producer.py`는 주문 이벤트를 JSON 형태로 SQS에 전송합니다.

```python
order = {
    "event": "ORDER_PLACED",
    "order_id": "uuid...",
    "product_id": "PROD-001",
    "quantity": 2,
    "customer_id": "CUST-101",
    "timestamp": "2024-01-01T00:00:00"
}
sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(order))
```

실행:
```bash
python producer.py
```

```text
[주문 서비스] ✅ 주문 이벤트 전송 완료
  OrderId  : a1b2c3d4-...
  ProductId: PROD-001
  Quantity : 2
  MessageId: f9e8d7c6-...
```

### 재고 서비스 — consumer.py

`consumer.py`는 SQS에서 주문 이벤트를 폴링(Long Polling)하여 재고를 차감하고 메시지를 삭제합니다.
MD5 무결성 검증을 포함하여 손상된 메시지를 자동으로 건너뜁니다.

```python
response = sqs.receive_message(
    QueueUrl=QUEUE_URL,
    MaxNumberOfMessages=5,
    WaitTimeSeconds=5   # Long Polling
)
```

실행:
```bash
python consumer.py
```

```text
[재고 서비스] 📡 주문 이벤트 수신 대기 중...

[재고 서비스] ✅ 재고 차감 완료
  OrderId  : a1b2c3d4-...
  ProductId: PROD-001
  차감 수량 : 2  남은 재고: 8
  🗑️ 메시지 삭제 완료

[재고 서비스] 총 3건 처리 완료.
```

### 흐름 요약

| 단계 | 역할 | 파일 |
| --- | --- | --- |
| 1 | 주문 이벤트 생성 및 SQS 전송 | `producer.py` |
| 2 | SQS 폴링 → 이벤트 수신 | `consumer.py` |
| 3 | MD5 무결성 검증 | `consumer.py` |
| 4 | 재고 차감 비즈니스 로직 처리 | `consumer.py` |
| 5 | 처리 완료 메시지 삭제 | `consumer.py` |

> `producer.py`와 `consumer.py`의 `QUEUE_URL`을 실제 SQS URL로 변경 후 사용하세요.

---

## boto3 소개
boto3는 Python에서 AWS 서비스를 제어할 수 있게 해주는 공식 SDK입니다.

| 기능 구분 | 설명 |
| --- | --- |
| AWS 서비스 제어 | S3, EC2, DynamoDB, IAM, Lambda 등 제어 |
| 리소스 자동화 | 인스턴스 생성, 버킷 생성, 파일 업로드 등 |
| 클라이언트 & 리소스 | `client()`와 `resource()` API 제공 |
| 자격증명 연동 | IAM 사용자/역할, 환경 변수, `~/.aws/credentials` 등 |
| 오케스트레이션 | 예: EC2 생성 → 보안그룹 설정 → S3 설정파일 다운로드 → 시작 스크립트 실행 |

---

## 이메일 예제
`email1.py`, `email2.py`는 SNS 이용 이메일 발송/수신 예시입니다.
> 이메일 수신이 스팸 처리될 수 있으니 주의하세요.

---

# AWS ElastiCache 학습 정리

## 개요
**ElastiCache**는 AWS에서 제공하는 **인메모리 캐시 서비스**로, **Redis** 또는 **Memcached** 엔진을 사용할 수 있는 **완전관리형 캐시**입니다.

### 주요 특징
- **빠른 데이터 접근**: 메모리에 저장되어 DB보다 훨씬 빠름
- **부하 분산**: 자주 요청되는 데이터 캐싱으로 DB 부담 감소
- **지원 엔진**: Redis (주로 사용), Memcached
- **Auto Scaling & Cluster**: Redis는 샤딩/복제 구성 가능

### 활용 예시
- 로그인 세션/토큰 저장
- 인기 게시물/상품 리스트 캐싱
- API 응답 결과 캐싱
- 실시간 게임 랭킹 저장

---

## 콘솔 설정
![콘솔 설정](images/image-5.png)

---

## Valkey 소개 (Redis 오픈소스 대체)
**Valkey**는 Redis 7.2 코드를 기반으로 탄생한 **완전한 오픈소스 인메모리 키-값 저장소**입니다.

### 등장 배경
2024년 초 Redis Labs가 Redis 라이선스를 오픈소스(LGPL/BSD)에서 **상용 라이선스**로 변경했습니다.
이에 따라 AWS, Google Cloud, Oracle 등 클라우드 기업들이 **오픈소스 정신을 잇는 포크 프로젝트**를 시작했고, 그 결과가 **Valkey**입니다.

### 비교 표
| 항목 | Redis | Valkey |
| --- | --- | --- |
| 라이선스 | Redis Source Available (RSAL 등) | **Apache 2.0** |
| 기반 | Redis 7.2 포크 | Redis 7.2 기반에서 지속 발전 |
| 커뮤니티 | Redis Labs 주도 | Linux Foundation, AWS, GCP 등 주도 |
| 호환성 | Redis 클라이언트 사용 가능 | ✅ Redis 클라이언트 100% 호환 |
| 사용 방식 | Redis처럼 사용 | 동일 (포트 6379, CLI 등 동일) |

---

## 캐시(Cache)란?
캐시는 **자주 사용하는 데이터를 빠르게 꺼내기 위해 미리 저장해두는 공간**입니다.
쉽게 말해 **임시 저장소** 또는 **빠른 복사본**입니다.

![캐시 개념](images/image-6.png)

---

## 네트워크/서브넷 오류 대응
### 오류 화면
![서브넷 오류](images/image-7.png)

**원인**: 사용 중인 서브넷이 3개 미만

### 해결 절차
1. 사용자 설정으로 변경
2. 서브넷 3개 이상 생성 후 설정

![설정 변경](images/image-8.png)
![VPC 상태](images/image-9.png)
![서브넷 관리](images/image-10.png)

---

## VPC 서브넷 추가
![서브넷 추가](images/image-11.png)
![IP 대역 설정](images/image-12.png)

> IP 대역 설정 시 임의 값을 입력 후 하단 화살표로 조정

### 서브넷 3개 확인
![서브넷 확인](images/image-13.png)

---

## ElastiCache 설정 재시도
서브넷을 3개 모두 선택 후 설정합니다.

![서브넷 리프레시](images/image-14.png)

---

## 캐시 서버 생성
> 생성에 수 분 소요될 수 있습니다.

![생성 대기](images/image-15.png)
![생성 완료](images/image-16.png)

---

## 엔드포인트 복사
![엔드포인트](images/image-17.png)

---

## 연결 테스트 (redistest.py)
### 설치
```bash
pip install redis
```

### 오류 예시
```text
TimeoutError: [WinError 10060] 연결된 구성원으로부터 응답이 없어 연결하지 못했거나, 
호스트로부터 응답이 없어 연결이 끊어졌습니다
```

**해결**: 방화벽 포트 개방 필요

![방화벽 설정](images/image-18.png)

> 기존 서브넷 구성 문제로 신규 VPC/서브넷 구성 후 연결 필요할 수 있음

---

## Server 방식 설정
![Server 방식 1](images/image-19.png)
![Server 방식 2](images/image-20.png)
![Server 방식 3](images/image-21.png)

---

## 외부 퍼블릭 접속 관련 주의
**비추천 (테스트용만 가능)**

- EC2에 직접 Redis 설치
- 보안그룹에서 `0.0.0.0/0`에 TCP 6379 개방 (**매우 위험**)
- 퍼블릭 IP로 접근 가능

```bash
sudo yum install redis
sudo systemctl start redis
redis-cli -h <your-ec2-public-ip> -p 6379
```

---

## ElastiCache Cache-Aside 예제 (DBMS + FE)

ElastiCache(Valkey/Redis)를 **캐시 계층**, SQLite를 **원본 DBMS 계층**으로 두고,
Cache-Aside 패턴을 실습할 수 있는 백엔드+프론트엔드 예제를 추가했습니다.

### 예제 구성

| 경로 | 설명 |
| --- | --- |
| `elasticache_example/cache_aside_server.py` | API 서버 + Cache-Aside 로직 |
| `elasticache_example/frontend/index.html` | 브라우저 UI |
| `elasticache_example/frontend/app.js` | API 호출 스크립트 |
| `elasticache_example/frontend/styles.css` | UI 스타일 |

### 동작 흐름

1. 사용자가 `GET /api/products/<id>` 호출
2. Redis 키(`product:<id>`) 조회
3. 캐시 미스면 SQLite 조회 후 Redis TTL 캐시 저장
4. 응답에서 `cache_hit` 값으로 히트 여부 확인

### 실행 방법

1) 의존성 설치

```bash
pip install redis
```

2) (선택) 로컬 Redis 실행 또는 ElastiCache 엔드포인트 설정

```bash
export REDIS_HOST=localhost
export REDIS_PORT=6379
```

3) 서버 실행

```bash
python elasticache_example/cache_aside_server.py
```

4) 브라우저 접속

```text
http://127.0.0.1:8080
```

### API 요약

- `GET /api/health` : 캐시 모드 및 TTL 확인
- `GET /api/products` : 전체 상품 목록
- `GET /api/products/<id>` : 상품 단건 조회 (`cache_hit` 포함)
- `POST /api/cache/invalidate?id=<id>` : 캐시 무효화

