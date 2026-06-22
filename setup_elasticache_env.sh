#!/usr/bin/env bash
# =============================================================================
# setup_elasticache_env.sh
# ElastiCache 테스트용 VPC 환경 자동 구성
#
# 생성 리소스:
#   - VPC (10.0.0.0/16)
#   - 서브넷 3개 (서로 다른 AZ)
#   - 인터넷 게이트웨이 + 라우팅 테이블
#   - 보안 그룹 (인바운드 전체 개방 — 테스트 전용)
#   - ElastiCache 서브넷 그룹 (ElastiCache 권한 있을 경우)
#
# 필요 권한: EC2 Full Access (+ ElastiCache 권한 시 서브넷 그룹 자동 생성)
# 사용법   : bash setup_elasticache_env.sh
# =============================================================================
set -euo pipefail

# ── 설정 ─────────────────────────────────────────────────────────────────────
REGION="ap-northeast-2"
NAME="elasticache-lab"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDRS=("10.0.1.0/24" "10.0.2.0/24" "10.0.3.0/24")
OUTPUT_FILE="elasticache_env.env"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
fail() { echo -e "  ${RED}✘${NC}  $*"; }

echo "================================================"
echo "  ElastiCache 테스트 VPC 환경 구성"
echo "  Region: $REGION"
echo "================================================"
echo ""

# ── 1. 가용 영역 조회 ─────────────────────────────────────────────────────────
echo "[1/7] 가용 영역 조회..."
AZ1=$(aws ec2 describe-availability-zones --region "$REGION" \
  --query 'AvailabilityZones[0].ZoneName' --output text)
AZ2=$(aws ec2 describe-availability-zones --region "$REGION" \
  --query 'AvailabilityZones[1].ZoneName' --output text)
AZ3=$(aws ec2 describe-availability-zones --region "$REGION" \
  --query 'AvailabilityZones[2].ZoneName' --output text)
ok "AZ: $AZ1 / $AZ2 / $AZ3"

# ── 2. VPC 생성 ───────────────────────────────────────────────────────────────
echo ""
echo "[2/7] VPC 생성 ($VPC_CIDR)..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --region "$REGION" \
  --query 'Vpc.VpcId' --output text)

aws ec2 create-tags --resources "$VPC_ID" \
  --tags Key=Name,Value="${NAME}-vpc" --region "$REGION"

# DNS 호스트네임 활성화 (ElastiCache 엔드포인트 접근에 필요)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" \
  --enable-dns-hostnames "{\"Value\":true}" --region "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" \
  --enable-dns-support "{\"Value\":true}" --region "$REGION"

ok "VPC ID: $VPC_ID"

# ── 3. 인터넷 게이트웨이 ──────────────────────────────────────────────────────
echo ""
echo "[3/7] 인터넷 게이트웨이 생성 및 연결..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$REGION" \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"

aws ec2 create-tags --resources "$IGW_ID" \
  --tags Key=Name,Value="${NAME}-igw" --region "$REGION"

ok "IGW ID: $IGW_ID"

# ── 4. 서브넷 3개 생성 ────────────────────────────────────────────────────────
echo ""
echo "[4/7] 서브넷 3개 생성 (AZ별)..."
AZS=("$AZ1" "$AZ2" "$AZ3")
SUBNET_IDS=()

for i in 0 1 2; do
  AZ="${AZS[$i]}"
  CIDR="${SUBNET_CIDRS[$i]}"
  IDX=$((i + 1))

  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$CIDR" \
    --availability-zone "$AZ" \
    --region "$REGION" \
    --query 'Subnet.SubnetId' --output text)

  aws ec2 create-tags --resources "$SUBNET_ID" \
    --tags Key=Name,Value="${NAME}-subnet-${IDX}" --region "$REGION"

  # 퍼블릭 IP 자동 할당 (EC2 연결 테스트용)
  aws ec2 modify-subnet-attribute \
    --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$REGION"

  SUBNET_IDS+=("$SUBNET_ID")
  ok "Subnet $IDX: $SUBNET_ID  ($AZ, $CIDR)"
done

# ── 5. 라우팅 테이블 ──────────────────────────────────────────────────────────
echo ""
echo "[5/7] 라우팅 테이블 생성 및 서브넷 연결..."
RT_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-tags --resources "$RT_ID" \
  --tags Key=Name,Value="${NAME}-rt" --region "$REGION"

aws ec2 create-route \
  --route-table-id "$RT_ID" \
  --destination-cidr-block "0.0.0.0/0" \
  --gateway-id "$IGW_ID" \
  --region "$REGION" > /dev/null

for SUBNET_ID in "${SUBNET_IDS[@]}"; do
  aws ec2 associate-route-table \
    --route-table-id "$RT_ID" --subnet-id "$SUBNET_ID" \
    --region "$REGION" > /dev/null
done

ok "Route Table ID: $RT_ID  (0.0.0.0/0 → IGW)"

# ── 6. 보안 그룹 — 전체 개방 ─────────────────────────────────────────────────
echo ""
echo "[6/7] 보안 그룹 생성 (All traffic open — 테스트 전용)..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "${NAME}-sg" \
  --description "${NAME}: all traffic open for testing" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' --output text)

aws ec2 create-tags --resources "$SG_ID" \
  --tags Key=Name,Value="${NAME}-sg" --region "$REGION"

# 인바운드: 모든 프로토콜, 모든 포트, 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --region "$REGION" \
  --ip-permissions '[
    {
      "IpProtocol": "-1",
      "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "All traffic (test only)"}]
    }
  ]' > /dev/null

# 아웃바운드: 기본값이 이미 0.0.0.0/0 전체 허용
ok "Security Group ID: $SG_ID  (inbound ALL / outbound ALL)"
warn "운영 환경에서는 반드시 포트를 제한하세요 (Redis: 6379)"

# ── 7. ElastiCache 서브넷 그룹 생성 (권한 있을 경우) ─────────────────────────
echo ""
echo "[7/7] ElastiCache 서브넷 그룹 생성 시도..."
SUBNET_GROUP_NAME="${NAME}-subnet-group"

if aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name "$SUBNET_GROUP_NAME" \
  --cache-subnet-group-description "${NAME} subnet group" \
  --subnet-ids "${SUBNET_IDS[@]}" \
  --region "$REGION" > /dev/null 2>&1; then
  ok "ElastiCache 서브넷 그룹: $SUBNET_GROUP_NAME"
else
  warn "ElastiCache 서브넷 그룹 생성 실패 (권한 부족)"
  warn "콘솔 → ElastiCache → 서브넷 그룹에서 아래 서브넷 ID로 직접 생성하세요."
fi

# ── 결과 저장 ─────────────────────────────────────────────────────────────────
cat > "$OUTPUT_FILE" <<EOF
# ElastiCache 테스트 환경 변수 — $(date '+%Y-%m-%d %H:%M:%S')
REGION=$REGION
VPC_ID=$VPC_ID
IGW_ID=$IGW_ID
ROUTE_TABLE_ID=$RT_ID
SUBNET_ID_1=${SUBNET_IDS[0]}
SUBNET_ID_2=${SUBNET_IDS[1]}
SUBNET_ID_3=${SUBNET_IDS[2]}
SECURITY_GROUP_ID=$SG_ID
ELASTICACHE_SUBNET_GROUP=${SUBNET_GROUP_NAME}
EOF

# ── 완료 요약 ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo -e "  ${GREEN}구성 완료${NC}"
echo "================================================"
echo "  VPC              : $VPC_ID  ($VPC_CIDR)"
echo "  서브넷 1         : ${SUBNET_IDS[0]}  ($AZ1)"
echo "  서브넷 2         : ${SUBNET_IDS[1]}  ($AZ2)"
echo "  서브넷 3         : ${SUBNET_IDS[2]}  ($AZ3)"
echo "  보안 그룹        : $SG_ID"
echo "  서브넷 그룹      : $SUBNET_GROUP_NAME"
echo ""
echo "  설정값 저장됨    : $OUTPUT_FILE"
echo ""
echo "  다음 단계:"
echo "  1. AWS 콘솔 → ElastiCache → 클러스터 생성"
echo "  2. VPC: $VPC_ID 선택"
echo "  3. 서브넷 그룹: $SUBNET_GROUP_NAME 선택"
echo "  4. 보안 그룹: $SG_ID 선택"
echo "  5. 엔드포인트를 elasticache_example/ 의 REDIS_HOST 에 설정"
echo "================================================"
