#!/usr/bin/env bash
# Create the demo topic (idempotent) with the topic-admin identity, which can
# manage this one topic and nothing else.
#
#   ./scripts/setup-topic.sh
#
# Only needed for private clusters: on a public cluster Terraform creates the
# topic itself. demo.sh calls this for you when needed.
source "$(dirname "$0")/common.sh"

if [[ "${TOPIC_MANAGED_BY_TERRAFORM:-false}" == "true" ]]; then
  echo "Topic ${TOPIC} is managed by Terraform. Nothing to do."
  exit 0
fi
run_near_brokers "$0" "$@"

echo "Creating topic ${TOPIC} (${PARTITIONS} partitions) if it does not exist..."
kafka_tool topic-admin \
  kafka-topics --bootstrap-server "${BOOTSTRAP}" \
    --command-config /config/client.properties \
    --create --if-not-exists \
    --topic "${TOPIC}" \
    --partitions "${PARTITIONS}" \
    --config retention.ms=3600000
echo "Topic ready."
