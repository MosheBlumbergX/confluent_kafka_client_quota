#!/usr/bin/env bash
# Delete the demo topic. Run BEFORE terraform destroy (it needs the
# topic-admin key that Terraform deletes).
#
#   ./scripts/delete-topic.sh
#
# Only needed for private clusters: on a public cluster the topic is managed
# by Terraform and terraform destroy removes it.
source "$(dirname "$0")/common.sh"

if [[ "${TOPIC_MANAGED_BY_TERRAFORM:-false}" == "true" ]]; then
  echo "Topic ${TOPIC} is managed by Terraform: terraform destroy removes it."
  exit 0
fi
run_near_brokers "$0" "$@"

kafka_tool topic-admin \
  kafka-topics --bootstrap-server "${BOOTSTRAP}" \
    --command-config /config/client.properties \
    --delete --if-exists --topic "${TOPIC}"
echo "Topic ${TOPIC} deleted (if it existed)."
