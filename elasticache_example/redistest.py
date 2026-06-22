import redis
import sys
import socket

# ElastiCache Redis 엔드포인트와 포트
# REDIS_HOST = "edumgt-redis-7c7abo.serverless.apn2.cache.amazonaws.com"
REDIS_HOST = "clustercfg.redis-server.7c7abo.apn2.cache.amazonaws.com"
REDIS_PORT = 6379

try:
    # Redis 클라이언트 생성
    client = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        decode_responses=True
    )

    # 연결 테스트 (ping 사용)
    if not client.ping():
        print("❌ Redis 서버 응답 없음. 종료합니다.")
        sys.exit(1)

    # 키-값 저장
    client.set("message", "안녕하세요, 엘라스티캐시!")

    # 키 값 가져오기
    value = client.get("message")
    print("✅ Redis에서 가져온 값:", value)

except (redis.exceptions.ConnectionError, redis.exceptions.TimeoutError, socket.gaierror) as e:
    print(f"❌ Redis 연결 오류: {e}")
    sys.exit(1)

except Exception as e:
    print(f"❌ 알 수 없는 오류 발생: {e}")
    sys.exit(1)
