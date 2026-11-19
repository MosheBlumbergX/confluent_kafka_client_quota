#!/usr/bin/env bash
# The noisy-neighbour race: every tenant floods the topic at the same time,
# with identical client code and no client-side throttling.
#
#   ./scripts/race.sh [duration_seconds]      (default 180)
#
# Ends with a summary: each tenant's throughput over the final third of the
# run (after warm-up) against its quota. Warm-up varies: in our runs from
# ~10 s to over 90 s, which is why the default is 3 minutes.
source "$(dirname "$0")/common.sh"
run_near_brokers "$0" "$@"

DURATION="${1:-180}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${REPO_ROOT}/logs"
export RESULTS_FILE="${REPO_ROOT}/logs/race-$(date +%Y%m%d-%H%M%S).txt"
: > "${RESULTS_FILE}"

echo "Racing ${TENANTS} for ${DURATION}s: identical producers, no client-side limits."
note "Warm-up: at first a tenant can burst far above its quota while Confluent Cloud"
note "distributes the quota to the brokers. In our runs this took ~10 s to over 90 s."
note "Watch each tenant settle. One line per tenant every 5 s:"
echo

pids=()
for t in ${TENANTS}; do
  "${SCRIPT_DIR}/produce.sh" "${t}" "${DURATION}" &
  pids+=($!)
done
trap 'kill "${pids[@]}" 2>/dev/null || true' INT TERM
wait "${pids[@]}" || true

# ---- Summary ----------------------------------------------------------------
echo
echo "Result over the final third of the run (after warm-up):"
echo
printf '  %-14s %-10s %-14s %-12s %s\n' TENANT QUOTA "FINAL MB/s" "PEAK MB/s" VERDICT
for t in ${TENANTS}; do
  q=$(( $(quota_bytes "${t}" INGRESS) / 1000000 ))
  awk -v t="${t}" -v q="${q}" -v c="$(colour_of "${t}")" "${VERDICT_AWK}"'
    $1 == t { r[++n] = $2; if ($2 > peak) peak = $2 }
    END {
      if (n == 0) { printf "  %-14s no data\n", t; exit }
      from = (n >= 3) ? n - int(n / 3) + 1 : 1
      for (i = from; i <= n; i++) { s += r[i]; k++ }
      steady = s / k
      v = verdict(steady, q)
      if (v ~ /^above/) v = "not settled yet: still bursting, run longer"
      printf "  \033[%sm%-14s\033[0m %-10s %-14.2f %-12.2f %s\n", c, t, (q ? q " MB/s" : "none"), steady, peak, v
    }' "${RESULTS_FILE}"
done
echo
note "Raw samples: ${RESULTS_FILE}"
