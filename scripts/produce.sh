#!/usr/bin/env bash
# Produce to the demo topic as one tenant, flat out, for a fixed time.
#
#   ./scripts/produce.sh <tenant> [duration_seconds]      (default 60)
#
# The producer has NO client-side rate limit (--throughput -1): any ceiling
# you see comes from the broker enforcing the client quota.
#
# Output: one line per 5 s window, in MB/s (the unit quotas use), with a
# verdict. RAW=1 shows the original kafka-producer-perf-test lines instead.
source "$(dirname "$0")/common.sh"
run_near_brokers "$0" "$@"

TENANT="${1:?usage: $0 <tenant> [duration_seconds]}"
DURATION="${2:-60}"
RECORD_SIZE="${RECORD_SIZE:-1000}"
require_tenant "${TENANT}"
QUOTA_MB=$(( $(quota_bytes "${TENANT}" INGRESS) / 1000000 ))

NAME="quota-demo-produce-${TENANT}-$$"
# Time-boxed: effectively unlimited records, stopped after DURATION seconds.
( sleep "${DURATION}"; ${DOCKER} stop -t 5 "${NAME}" >/dev/null 2>&1 || true ) &
WATCHDOG=$!
trap 'kill ${WATCHDOG} 2>/dev/null || true; ${DOCKER} stop -t 2 "${NAME}" >/dev/null 2>&1 || true' EXIT

# kafka-producer-perf-test prints MiB/s; convert to MB/s and add a verdict.
summarise() {
  if [[ "${RAW:-0}" == "1" ]]; then cat; return; fi
  awk -v q="${QUOTA_MB}" -v out="${RESULTS_FILE:-}" -v t="${TENANT}" "${VERDICT_AWK}"'
    / records sent, / && /records\/sec \(/ {
      match($0, /\(([0-9.]+) MB\/sec\)/); mib = substr($0, RSTART + 1, RLENGTH - 9) + 0
      match($0, /, [0-9.]+ ms avg latency/); lat = substr($0, RSTART + 2, RLENGTH - 17) / 1000
      rate = mib * 1.048576
      printf "%7.2f MB/s   quota %-9s  avg latency %5.1f s   %s\n", rate, (q ? q " MB/s" : "none"), lat, verdict(rate, q)
      if (out != "") { print t, rate >> out; fflush(out) }
      fflush(); next
    }
    /ERROR|Exception/ { print; fflush() }'
}

${DOCKER} run --rm -e KAFKA_HEAP_OPTS="${KAFKA_HEAP_OPTS}" --name "${NAME}" \
  -v "${GENERATED}/${TENANT}.properties:/config/client.properties:ro" \
  "${KAFKA_IMAGE}" \
  kafka-producer-perf-test \
    --topic "${TOPIC}" \
    --num-records 1000000000 \
    --record-size "${RECORD_SIZE}" \
    --throughput -1 \
    --producer.config /config/client.properties \
    --producer-props acks=all linger.ms=20 batch.size=262144 compression.type=none client.id="${TENANT}" \
    2>&1 \
  | summarise | label "${TENANT}" || true
