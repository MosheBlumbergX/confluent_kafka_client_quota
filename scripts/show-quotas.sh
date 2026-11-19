#!/usr/bin/env bash
# List the client quotas on the demo cluster using the Client Quotas REST API.
# This is the same data Terraform manages, read back from Confluent Cloud.
#
#   ./scripts/show-quotas.sh
source "$(dirname "$0")/common.sh"
need_cloud_key
command -v jq >/dev/null || die "jq is required."

curl -sS --fail -u "${CONFLUENT_CLOUD_API_KEY}:${CONFLUENT_CLOUD_API_SECRET}" \
  "https://api.confluent.cloud/kafka-quotas/v1/client-quotas?spec.cluster=${CLUSTER_ID}&environment=${ENVIRONMENT_ID}" \
| jq -r '
    ["QUOTA", "NAME", "INGRESS MB/s", "EGRESS MB/s", "PRINCIPALS"],
    (.data[] | [
      .id,
      .spec.display_name,
      ((.spec.throughput.ingress_byte_rate | tonumber) / 1000000 | tostring),
      ((.spec.throughput.egress_byte_rate  | tonumber) / 1000000 | tostring),
      ([.spec.principals[].id] | join(","))
    ]) | @tsv' \
| column -t -s $'\t'
