#!/usr/bin/env bash
# Server-side proof: bytes produced per principal per minute, from the
# Confluent Cloud Metrics API. This is what the BROKER saw, independent of
# what any client reports.
#
#   ./scripts/metrics.sh [minutes_back]
#
# Metrics land with a delay of a few minutes. Needs a Cloud API key whose
# owner has the MetricsViewer role (OrganizationAdmin includes it).
source "$(dirname "$0")/common.sh"
need_cloud_key
command -v jq >/dev/null || die "jq is required."

MINUTES="${1:-15}"

# Map service account IDs back to tenant names for readable output.
names='{}'
for t in ${TENANTS}; do
  var="SA_$(echo "${t}" | tr 'a-z-' 'A-Z_')"
  names=$(jq -c --arg k "${!var}" --arg v "${t}" '. + {($k): $v}' <<<"${names}")
done

query=$(jq -n --arg c "${CLUSTER_ID}" --arg i "now-${MINUTES}m|m/now|m" '{
  aggregations: [{metric: "io.confluent.kafka.server/request_bytes"}],
  filter: {op: "AND", filters: [
    {field: "resource.kafka.id", op: "EQ", value: $c},
    {field: "metric.type",       op: "EQ", value: "Produce"}
  ]},
  granularity: "PT1M",
  intervals: [$i],
  group_by: ["metric.principal_id"],
  limit: 1000
}')

curl -sS --fail -u "${CONFLUENT_CLOUD_API_KEY}:${CONFLUENT_CLOUD_API_SECRET}" \
  -H 'Content-Type: application/json' \
  -d "${query}" \
  https://api.telemetry.confluent.cloud/v2/metrics/cloud/query \
| jq -r --argjson names "${names}" '
    ["MINUTE (UTC)", "TENANT", "PRINCIPAL", "PRODUCED MB/s (avg over minute)"],
    (.data | sort_by(.timestamp, .["metric.principal_id"]) | .[] | [
      (.timestamp | sub(":00Z$"; "Z")),
      ($names[.["metric.principal_id"]] // "(other)"),
      .["metric.principal_id"],
      ((.value / 60 / 1000000) * 100 | round / 100 | tostring)
    ]) | @tsv' \
| column -t -s $'\t'
