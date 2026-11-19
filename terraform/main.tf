locals {
  # Ownership labels rendered as text, appended to descriptions of API keys
  # and quotas. (Service account descriptions are capped at 128 characters,
  # so they only carry a short human-readable description.)
  label_suffix = length(var.resource_labels) == 0 ? "" : format(" [%s]", join(", ", [for k, v in var.resource_labels : "${k}=${v}"]))

  mb = 1000000 # Confluent Cloud quotas are in bytes/s; 1 MB = 10^6 bytes.

  # A new, clearly named topic so the demo never touches existing data.
  topic_name = "${var.prefix}-orders"
  topic_crn  = "${local.cluster.rbac_crn}/kafka=${local.cluster.id}/topic=${local.topic_name}"
}

# -----------------------------------------------------------------------------
# Topic admin identity. Least privilege: it can manage exactly one topic.
# -----------------------------------------------------------------------------
resource "confluent_service_account" "topic_admin" {
  display_name = "${var.prefix}-topic-admin"
  description  = "Creates the client quota demo topic. Manages that one topic only."
}

resource "confluent_role_binding" "topic_admin_manage" {
  principal   = "User:${confluent_service_account.topic_admin.id}"
  role_name   = "DeveloperManage"
  crn_pattern = local.topic_crn
}

resource "confluent_api_key" "topic_admin" {
  display_name = "${var.prefix}-topic-admin-kafka-key"
  description  = "Kafka API key for the demo topic admin.${local.label_suffix}"

  # The provider's readiness check calls the cluster's REST endpoint, which
  # cannot be reached from outside a private network.
  disable_wait_for_ready = !local.data_plane_reachable

  owner {
    id          = confluent_service_account.topic_admin.id
    api_version = confluent_service_account.topic_admin.api_version
    kind        = confluent_service_account.topic_admin.kind
  }

  managed_resource {
    id          = local.cluster.id
    api_version = local.cluster.api_version
    kind        = local.cluster.kind

    environment {
      id = local.environment_id
    }
  }

  depends_on = [confluent_role_binding.topic_admin_manage]
}

# -----------------------------------------------------------------------------
# The demo topic.
#
# Creating a topic is a data-plane call. If Terraform can reach the cluster
# (public endpoint), it manages the topic here. If the cluster is private,
# run scripts/setup-topic.sh from a machine inside the network instead
# (scripts/demo.sh does that for you).
# -----------------------------------------------------------------------------
resource "confluent_kafka_topic" "demo" {
  count = local.data_plane_reachable ? 1 : 0

  kafka_cluster {
    id = local.cluster.id
  }

  topic_name       = local.topic_name
  partitions_count = var.topic_partitions
  rest_endpoint    = local.cluster.rest_endpoint

  config = {
    # Short retention keeps storage (and cost) negligible for load tests.
    "retention.ms" = "3600000"
  }

  credentials {
    key    = confluent_api_key.topic_admin.id
    secret = confluent_api_key.topic_admin.secret
  }
}
