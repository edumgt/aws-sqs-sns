#!/usr/bin/env bash
# =============================================================================
# setup_ec2_tunnel.sh
# ElastiCache 접속용 EC2 점프호스트 생성 + SSH 터널 안내
#
# 구조:
#   [로컬 localhost:6379] ──SSH 터널──> [EC2 공개 IP] ──VPC 내부──> [ElastiCache]
#
# 사용법: bash setup_ec2_tunnel.sh
# =============================================================================
set -euo pipefail

ENV_FILE="elasticache_env.env"
KEY_FILE="elasticache-lab-key.pem"
REGION="ap-northeast-2"
INSTANCE_TYPE="t3.micro"
NAME="elasticache-lab"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
step() { echo -e "\n${CYAN}[$1]${NC} $2"; }

# ── env 로드 ──────────────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "❌  $ENV_FILE 없음 — setup_elasticache_env.sh 를 먼저 실행하세요."
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

echo "================================================"
echo "  ElastiCache 접속용 EC2 점프호스트 생성"
echo "================================================"

# ── 1. ElastiCache 엔드포인트 입력 ───────────────────────────────────────────
step "1/5" "ElastiCache 엔드포인트 확인"
echo ""
echo "  AWS 콘솔 → ElastiCache → 클러스터 → 엔드포인트 주소를 입력하세요."
echo "  (예: my-valkey.xxxxx.apn2.cache.amazonaws.com)"
echo ""
read -r -p "  ElastiCache 엔드포인트: " REDIS_HOST
read -r -p "  포트 [6379]: " REDIS_PORT
REDIS_PORT="${REDIS_PORT:-6379}"

# ── 2. 키페어 생성 ────────────────────────────────────────────────────────────
step "2/5" "키페어 생성: ${NAME}-key"
if [ -f "$KEY_FILE" ]; then
  warn "키 파일이 이미 있습니다: $KEY_FILE (재사용)"
else
  # 기존 키페어 삭제 후 재생성
  aws ec2 delete-key-pair --key-name "${NAME}-key" --region "$REGION" 2>/dev/null || true
  aws ec2 create-key-pair \
    --key-name "${NAME}-key" \
    --region "$REGION" \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  ok "키 파일 생성됨: $KEY_FILE"
fi

# ── 3. 최신 Amazon Linux 2023 AMI 조회 ───────────────────────────────────────
step "3/5" "Amazon Linux 2023 AMI 조회..."
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --region "$REGION" \
  --filters \
    "Name=name,Values=al2023-ami-*-x86_64" \
    "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)
ok "AMI: $AMI_ID"

# ── 4. EC2 인스턴스 시작 ──────────────────────────────────────────────────────
step "4/5" "EC2 인스턴스 시작 ($INSTANCE_TYPE)..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "${NAME}-key" \
  --subnet-id "$SUBNET_ID_1" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}-jump}]" \
  --region "$REGION" \
  --query 'Instances[0].InstanceId' --output text)
ok "인스턴스 ID: $INSTANCE_ID"

echo ""
echo "  인스턴스 running 상태 대기 중..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
ok "인스턴스 실행 중"

# 퍼블릭 IP 조회
EC2_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
ok "퍼블릭 IP: $EC2_IP"

# SSH 접속 준비 대기 (20초)
echo "  SSH 서비스 준비 대기 중 (20초)..."
sleep 20

# ── 5. 접속 정보 저장 및 출력 ─────────────────────────────────────────────────
step "5/5" "접속 정보 저장..."

# env 파일에 EC2·Redis 정보 추가
cat >> "$ENV_FILE" <<EOF
JUMP_INSTANCE_ID=${INSTANCE_ID}
JUMP_EC2_IP=${EC2_IP}
REDIS_HOST=${REDIS_HOST}
REDIS_PORT=${REDIS_PORT}
EOF
ok "elasticache_env.env 업데이트됨"

# 터널 스크립트 생성
TUNNEL_SCRIPT="start_tunnel.sh"
cat > "$TUNNEL_SCRIPT" <<SCRIPT
#!/usr/bin/env bash
# ElastiCache SSH 터널 — localhost:${REDIS_PORT} → ElastiCache
echo "SSH 터널 시작: localhost:${REDIS_PORT} → ${REDIS_HOST}:${REDIS_PORT}"
echo "종료: Ctrl+C"
ssh -i ${KEY_FILE} \\
    -L ${REDIS_PORT}:${REDIS_HOST}:${REDIS_PORT} \\
    -N -o StrictHostKeyChecking=no \\
    ec2-user@${EC2_IP}
SCRIPT
chmod +x "$TUNNEL_SCRIPT"
ok "터널 스크립트 생성됨: $TUNNEL_SCRIPT"

echo ""
echo "================================================"
echo -e "  ${GREEN}완료${NC}"
echo "================================================"
echo ""
echo "  EC2 점프호스트  : $EC2_IP"
echo "  ElastiCache    : $REDIS_HOST:$REDIS_PORT"
echo ""
echo "  ┌─ 사용 방법 ──────────────────────────────┐"
echo "  │                                          │"
echo "  │  1. 터널 시작 (별도 터미널)               │"
echo "  │     bash start_tunnel.sh                 │"
echo "  │                                          │"
echo "  │  2. redistest.py 설정 변경               │"
echo "  │     REDIS_HOST = 'localhost'             │"
echo "  │     REDIS_PORT = ${REDIS_PORT}                      │"
echo "  │                                          │"
echo "  │  3. 테스트 실행                           │"
echo "  │     python3 elasticache_example/redistest.py │"
echo "  │                                          │"
echo "  └──────────────────────────────────────────┘"
echo ""
echo "  EC2 직접 SSH:  ssh -i $KEY_FILE ec2-user@$EC2_IP"
echo "================================================"
