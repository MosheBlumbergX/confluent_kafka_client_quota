#!/usr/bin/env bash
# Read the demo topic from the beginning as one tenant, flat out: the EGRESS
# side of the quota.
#
#   ./scripts/consume.sh <tenant> [duration_seconds]      (default 60)
#
# Run race.sh or produce.sh first so the topic has data to read.
source "$(dirname "$0")/common.sh"
run_near_brokers "$0" "$@"

TENANT="${1:?usage: $0 <tenant> [duration_seconds]}"
DURATION="${2:-60}"
require_tenant "${TENANT}"
QUOTA_MB=$(( $(quota_bytes "${TENANT}" EGRESS) / 1000000 ))

NAME="quota-demo-consume-${TENANT}-$$"
( sleep "${DURATION}"; ${DOCKER} stop -t 5 "${NAME}" >/dev/null 2>&1 || true ) &
WATCHDOG=$!
trap 'kill ${WATCHDOG} 2>/dev/null || true; ${DOCKER} stop -t 2 "${NAME}" >/dev/null 2>&1 || true' EXIT

# kafka-consumer-perf-test prints CSV in MiB/s; convert and add a verdict.
summarise() {
  if [[ "${RAW:-0}" == "1" ]]; then cat; return; fi
  awk -F', *' -v q="${QUOTA_MB}" "${VERDICT_AWK}"'
    $1 ~ /^[0-9][0-9][0-9][0-9]-/ && NF >= 4 {
      rate = $4 * 1.048576
      printf "%7.2f MB/s   quota %-9s  %s\n", rate, (q ? q " MB/s" : "none"), verdict(rate, q)
      fflush(); next
    }
    /ERROR|Exception/ { print; fflush() }'
}

# Consumer group names must start with the tenant name (see RBAC in tenants.tf).
${DOCKER} run --rm -e KAFKA_HEAP_OPTS="${KAFKA_HEAP_OPTS}" --name "${NAME}" \
  -v "${GENERATED}/${TENANT}.properties:/config/client.properties:ro" \
  "${KAFKA_IMAGE}" \
  kafka-consumer-perf-test \
    --bootstrap-server "${BOOTSTRAP}" \
    --topic "${TOPIC}" \
    --group "${TENANT}-perf-$$" \
    --messages 1000000000 \
    --consumer.config /config/client.properties \
    --timeout 60000 \
    --reporting-interval 5000 \
    --show-detailed-stats 2>&1 \
  | summarise | label "${TENANT}" || true
