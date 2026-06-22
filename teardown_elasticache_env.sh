#!/usr/bin/env bash
# =============================================================================
# teardown_elasticache_env.sh
# ElastiCache 캐시 서버 및 VPC 관련 리소스 전체 삭제
#
# 삭제 순서:
#   1. ElastiCache 클러스터 / 복제 그룹 (명시 지정 + 서브넷 그룹 연결 전체)
#      - edumgt-redis  (clustercfg.edumgt-redis.7c7abo.apn2.cache.amazonaws.com)
#   2. ElastiCache 서브넷 그룹
#   3. 보안 그룹
#   4. 라우팅 테이블 (연결 해제 → 삭제)
#   5. 서브넷 3개
#   6. 인터넷 게이트웨이 (분리 → 삭제)
#   7. VPC
#
# 사용법: bash teardown_elasticache_env.sh [env파일경로]
#         env파일 기본값: elasticache_env.env
# =============================================================================
set -uo pipefail   # -e 는 의도적으로 제외 — 일부 리소스 없어도 계속 진행

ENV_FILE="${1:-elasticache_env.env}"

# ── 색상 ──────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
fail() { echo -e "  ${RED}✘${NC}  $*"; }
step() { echo -e "\n${CYAN}[$1]${NC} $2"; }

# ── env 파일 로드 ─────────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  fail "env 파일을 찾을 수 없습니다: $ENV_FILE"
  echo "     setup_elasticache_env.sh 를 먼저 실행하거나 파일 경로를 지정하세요."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

echo "================================================"
echo "  ElastiCache 환경 전체 삭제"
echo "  Region : ${REGION}"
echo "  VPC    : ${VPC_ID}"
echo "================================================"
echo ""
read -r -p "  위 리소스를 모두 삭제합니다. 계속하시겠습니까? [y/N] " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
  echo "  취소됨."
  exit 0
fi

# ── 1. ElastiCache 클러스터 / 복제 그룹 삭제 ─────────────────────────────────
step "1/7" "ElastiCache 클러스터 및 복제 그룹 삭제..."

# ── 1-A. 명시 지정 클러스터 삭제 ─────────────────────────────────────────────
# 엔드포인트: clustercfg.edumgt-redis.7c7abo.apn2.cache.amazonaws.com
NAMED_CLUSTERS=("edumgt-redis")

for TARGET in "${NAMED_CLUSTERS[@]}"; do
  echo "  [명시] 복제 그룹 삭제 시도: $TARGET"

  # 복제 그룹으로 삭제 시도
  if aws elasticache describe-replication-groups \
      --replication-group-id "$TARGET" \
      --region "$REGION" > /dev/null 2>&1; then
    aws elasticache delete-replication-group \
      --replication-group-id "$TARGET" \
      --region "$REGION" > /dev/null 2>&1 \
      && ok "복제 그룹 삭제 요청: $TARGET" \
      || warn "삭제 실패: $TARGET"
  else
    # 단독 캐시 클러스터로 삭제 시도
    aws elasticache delete-cache-cluster \
      --cache-cluster-id "$TARGET" \
      --region "$REGION" > /dev/null 2>&1 \
      && ok "캐시 클러스터 삭제 요청: $TARGET" \
      || warn "없거나 이미 삭제됨: $TARGET"
  fi

  # 서버리스 캐시로도 삭제 시도
  aws elasticache delete-serverless-cache \
    --serverless-cache-name "$TARGET" \
    --region "$REGION" > /dev/null 2>&1 \
    && ok "서버리스 캐시 삭제 요청: $TARGET" \
    || true
done

# 명시 클러스터 삭제 완료 대기
echo "  명시 클러스터 삭제 완료 대기 중..."
WAIT_SEC=0
for TARGET in "${NAMED_CLUSTERS[@]}"; do
  while aws elasticache describe-replication-groups \
      --replication-group-id "$TARGET" \
      --region "$REGION" > /dev/null 2>&1; do
    if [ $WAIT_SEC -ge 600 ]; then
      warn "10분 초과 — $TARGET 아직 삭제 중"
      break
    fi
    echo -ne "\r  대기 중... ${WAIT_SEC}s  ($TARGET)"
    sleep 15
    WAIT_SEC=$((WAIT_SEC + 15))
  done
done
[ $WAIT_SEC -gt 0 ] && echo -e "\r  ${GREEN}✔${NC}  명시 클러스터 삭제 완료                    "

# ── 1-B. 서브넷 그룹 기준 나머지 클러스터 삭제 ───────────────────────────────
# 복제 그룹(Replication Group) 검색 — 서브넷 그룹 기준
RG_IDS=$(aws elasticache describe-replication-groups \
  --region "$REGION" \
  --query "ReplicationGroups[?contains(MemberClusters[0], '${ELASTICACHE_SUBNET_GROUP}') == \`false\`].ReplicationGroupId" \
  --output text 2>/dev/null || true)

# 서브넷 그룹으로 직접 필터링 (멤버 클러스터 경로)
ALL_CLUSTERS=$(aws elasticache describe-cache-clusters \
  --region "$REGION" \
  --query "CacheClusters[?CacheSubnetGroupName=='${ELASTICACHE_SUBNET_GROUP}'].[CacheClusterId,ReplicationGroupId]" \
  --output text 2>/dev/null || true)

DELETED_RGS=()
if [ -n "$ALL_CLUSTERS" ]; then
  while IFS=$'\t' read -r CLUSTER_ID RG_ID; do
    [ -z "$CLUSTER_ID" ] && continue

    if [ -n "$RG_ID" ] && [ "$RG_ID" != "None" ]; then
      # 복제 그룹 삭제 (이미 삭제했으면 스킵)
      if [[ ! " ${DELETED_RGS[*]} " =~ " ${RG_ID} " ]]; then
        echo "  복제 그룹 삭제: $RG_ID"
        aws elasticache delete-replication-group \
          --replication-group-id "$RG_ID" \
          --region "$REGION" > /dev/null 2>&1 && ok "삭제 요청: $RG_ID" || warn "삭제 실패 또는 이미 없음: $RG_ID"
        DELETED_RGS+=("$RG_ID")
      fi
    else
      # 단독 클러스터 삭제
      echo "  캐시 클러스터 삭제: $CLUSTER_ID"
      aws elasticache delete-cache-cluster \
        --cache-cluster-id "$CLUSTER_ID" \
        --region "$REGION" > /dev/null 2>&1 && ok "삭제 요청: $CLUSTER_ID" || warn "삭제 실패 또는 이미 없음: $CLUSTER_ID"
    fi
  done <<< "$ALL_CLUSTERS"
else
  warn "서브넷 그룹 '${ELASTICACHE_SUBNET_GROUP}'에 연결된 클러스터 없음 (이미 삭제됐거나 권한 부족)"
fi

# 클러스터 삭제 완료 대기
if [ -n "$ALL_CLUSTERS" ]; then
  echo ""
  echo "  클러스터 삭제 완료 대기 중 (최대 10분)..."
  WAIT_SEC=0
  while true; do
    REMAINING=$(aws elasticache describe-cache-clusters \
      --region "$REGION" \
      --query "CacheClusters[?CacheSubnetGroupName=='${ELASTICACHE_SUBNET_GROUP}'].CacheClusterId" \
      --output text 2>/dev/null | tr -s '[:space:]' | xargs)
    [ -z "$REMAINING" ] && break
    if [ $WAIT_SEC -ge 600 ]; then
      warn "10분 초과 — 클러스터가 아직 남아있습니다: $REMAINING"
      break
    fi
    echo -ne "  \r  대기 중... ${WAIT_SEC}s  남은 클러스터: $REMAINING"
    sleep 15
    WAIT_SEC=$((WAIT_SEC + 15))
  done
  echo -e "\r  ${GREEN}✔${NC}  클러스터 삭제 완료                              "
fi

# ── 2. ElastiCache 서브넷 그룹 삭제 ──────────────────────────────────────────
step "2/7" "ElastiCache 서브넷 그룹 삭제: ${ELASTICACHE_SUBNET_GROUP}"
aws elasticache delete-cache-subnet-group \
  --cache-subnet-group-name "${ELASTICACHE_SUBNET_GROUP}" \
  --region "$REGION" 2>/dev/null \
  && ok "서브넷 그룹 삭제됨" || warn "삭제 실패 또는 이미 없음 (권한 부족 가능)"

# ── 3. 보안 그룹 삭제 ─────────────────────────────────────────────────────────
step "3/7" "보안 그룹 삭제: ${SECURITY_GROUP_ID}"
# 인바운드 규칙 먼저 제거 (VPC 삭제 전 필요할 수 있음)
aws ec2 revoke-security-group-ingress \
  --group-id "${SECURITY_GROUP_ID}" \
  --region "$REGION" \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
  > /dev/null 2>&1 || true

aws ec2 delete-security-group \
  --group-id "${SECURITY_GROUP_ID}" \
  --region "$REGION" 2>/dev/null \
  && ok "보안 그룹 삭제됨" || warn "삭제 실패 또는 이미 없음"

# ── 4. 라우팅 테이블 삭제 ────────────────────────────────────────────────────
step "4/7" "라우팅 테이블 삭제: ${ROUTE_TABLE_ID}"

# 서브넷 연결 해제
ASSOC_IDS=$(aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --region "$REGION" \
  --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
  --output text 2>/dev/null || true)

for ASSOC_ID in $ASSOC_IDS; do
  [ -z "$ASSOC_ID" ] && continue
  aws ec2 disassociate-route-table --association-id "$ASSOC_ID" --region "$REGION" 2>/dev/null \
    && ok "연결 해제: $ASSOC_ID" || warn "이미 해제됨: $ASSOC_ID"
done

aws ec2 delete-route-table \
  --route-table-id "${ROUTE_TABLE_ID}" \
  --region "$REGION" 2>/dev/null \
  && ok "라우팅 테이블 삭제됨" || warn "삭제 실패 또는 이미 없음"

# ── 5. 서브넷 삭제 ────────────────────────────────────────────────────────────
step "5/7" "서브넷 3개 삭제..."
for SUBNET_VAR in SUBNET_ID_1 SUBNET_ID_2 SUBNET_ID_3; do
  SUBNET_ID="${!SUBNET_VAR}"
  [ -z "$SUBNET_ID" ] && continue
  aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$REGION" 2>/dev/null \
    && ok "삭제됨: $SUBNET_ID" || warn "삭제 실패 또는 이미 없음: $SUBNET_ID"
done

# ── 6. 인터넷 게이트웨이 분리 및 삭제 ────────────────────────────────────────
step "6/7" "인터넷 게이트웨이 삭제: ${IGW_ID}"
aws ec2 detach-internet-gateway \
  --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" \
  --region "$REGION" 2>/dev/null \
  && ok "VPC에서 분리됨" || warn "분리 실패 또는 이미 분리됨"

aws ec2 delete-internet-gateway \
  --internet-gateway-id "${IGW_ID}" \
  --region "$REGION" 2>/dev/null \
  && ok "인터넷 게이트웨이 삭제됨" || warn "삭제 실패 또는 이미 없음"

# ── 7. VPC 삭제 ───────────────────────────────────────────────────────────────
step "7/7" "VPC 삭제: ${VPC_ID}"

# VPC 내 잔여 네트워크 인터페이스 확인
ENI_COUNT=$(aws ec2 describe-network-interfaces \
  --filters Name=vpc-id,Values="${VPC_ID}" \
  --region "$REGION" \
  --query 'length(NetworkInterfaces)' \
  --output text 2>/dev/null || echo 0)

if [ "$ENI_COUNT" -gt 0 ]; then
  warn "VPC 내 네트워크 인터페이스 ${ENI_COUNT}개 잔존 — EC2 인스턴스가 남아있을 수 있습니다."
  warn "EC2 인스턴스를 먼저 종료한 후 다시 실행하세요."
fi

aws ec2 delete-vpc --vpc-id "${VPC_ID}" --region "$REGION" 2>/dev/null \
  && ok "VPC 삭제됨: ${VPC_ID}" || fail "VPC 삭제 실패 — 잔여 리소스가 있을 수 있습니다."

# ── 완료 ─────────────────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo -e "  ${GREEN}삭제 완료${NC}"
echo "================================================"
echo "  삭제된 리소스:"
echo "    ElastiCache (명시): edumgt-redis
    ElastiCache (서브넷 그룹 연결 전체)"
echo "    ElastiCache 서브넷 그룹 : ${ELASTICACHE_SUBNET_GROUP}"
echo "    보안 그룹               : ${SECURITY_GROUP_ID}"
echo "    라우팅 테이블           : ${ROUTE_TABLE_ID}"
echo "    서브넷 1~3              : ${SUBNET_ID_1} / ${SUBNET_ID_2} / ${SUBNET_ID_3}"
echo "    인터넷 게이트웨이       : ${IGW_ID}"
echo "    VPC                     : ${VPC_ID}"
echo ""

# env 파일 삭제 여부 확인
read -r -p "  env 파일($ENV_FILE)도 삭제할까요? [y/N] " DEL_ENV
if [[ "${DEL_ENV,,}" == "y" ]]; then
  rm -f "$ENV_FILE"
  ok "env 파일 삭제됨"
fi

echo "================================================"
