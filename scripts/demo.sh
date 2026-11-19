#!/usr/bin/env bash
# The whole demo in one command.
#
#   ./scripts/demo.sh [race_duration_seconds]      (default 180)
#
# 1. Shows who gets which quota.
# 2. Makes sure the demo topic exists.
# 3. Runs the noisy-neighbour race and prints a verdict per tenant.
source "$(dirname "$0")/common.sh"

DURATION="${1:-180}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }

bold "Confluent Cloud client quotas: the noisy-neighbour demo"
echo "Cluster ${CLUSTER_ID} (environment ${ENVIRONMENT_ID}), topic ${TOPIC}"
[[ -n "${VM_SSH_TARGET:-}" ]] && echo "Load generators run on ${VM_SSH_TARGET}"

bold "1. Who gets what"
for t in ${TENANTS}; do
  q=$(( $(quota_bytes "${t}" INGRESS) / 1000000 ))
  printf '   \033[%sm%-14s\033[0m %s\n' "$(colour_of "${t}")" "${t}" \
    "$([[ ${q} -gt 0 ]] && echo "quota ${q} MB/s" || echo "no quota (unlimited)")"
done
note "   Quotas are set in terraform/terraform.tfvars and applied with terraform apply."

bold "2. Demo topic"
"${SCRIPT_DIR}/setup-topic.sh"

bold "3. The race: ${DURATION}s, all tenants flat out, no client-side limits"
"${SCRIPT_DIR}/race.sh" "${DURATION}"

bold "What next"
cat <<EOF
   * Change a quota live: edit terraform/terraform.tfvars, run terraform apply,
     and watch ./scripts/produce.sh nightly-etl 240 adjust (allow ~1 minute).
   * Egress:              ./scripts/consume.sh nightly-etl 60
   * Broker-side proof:   ./scripts/metrics.sh 15   (needs the Cloud API key)
   * Clean up:            cd terraform && terraform destroy
EOF
