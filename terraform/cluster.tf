# -----------------------------------------------------------------------------
# Where the demo runs. Two options:
#
#   create_cluster = true   Terraform creates an environment and a small
#                           Dedicated cluster with a PUBLIC endpoint, so you
#                           can run everything from your laptop. Billed per
#                           CKU-hour while it exists: destroy it afterwards.
#
#   create_cluster = false  Use a cluster you already have (Enterprise,
#                           Freight or Dedicated). Read-only lookups: nothing
#                           here changes your cluster.
#
# Why Dedicated? Client quotas need Enterprise, Freight or Dedicated, and of
# those only Dedicated offers public networking. Enterprise and Freight are
# reachable over private networking only.
# -----------------------------------------------------------------------------

# --- Option A: create a cluster ----------------------------------------------
resource "confluent_environment" "demo" {
  count = var.create_cluster ? 1 : 0

  display_name = var.prefix

  stream_governance {
    package = "ESSENTIALS"
  }
}

resource "confluent_kafka_cluster" "demo" {
  count = var.create_cluster ? 1 : 0

  display_name = "${var.prefix}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = var.cloud
  region       = var.region

  dedicated {
    cku = 1 # the smallest Dedicated cluster
  }

  environment {
    id = confluent_environment.demo[0].id
  }
}

# --- Option B: use an existing cluster ---------------------------------------
data "confluent_environment" "target" {
  count = var.create_cluster ? 0 : 1

  id = var.environment_id
}

data "confluent_kafka_cluster" "target" {
  count = var.create_cluster ? 0 : 1

  id = var.kafka_cluster_id

  environment {
    id = var.environment_id
  }

  lifecycle {
    postcondition {
      condition     = try(length(self.enterprise), 0) + try(length(self.dedicated), 0) + try(length(self.freight), 0) > 0
      error_message = "Client quotas need an Enterprise, Freight or Dedicated cluster. ${var.kafka_cluster_id} is Basic or Standard."
    }
  }
}

# --- Whichever it is, the rest of the code only uses these -------------------
locals {
  environment_id = var.create_cluster ? confluent_environment.demo[0].id : data.confluent_environment.target[0].id

  cluster = var.create_cluster ? {
    id            = confluent_kafka_cluster.demo[0].id
    api_version   = confluent_kafka_cluster.demo[0].api_version
    kind          = confluent_kafka_cluster.demo[0].kind
    rbac_crn      = confluent_kafka_cluster.demo[0].rbac_crn
    bootstrap     = confluent_kafka_cluster.demo[0].bootstrap_endpoint
    rest_endpoint = confluent_kafka_cluster.demo[0].rest_endpoint
    } : {
    id            = data.confluent_kafka_cluster.target[0].id
    api_version   = data.confluent_kafka_cluster.target[0].api_version
    kind          = data.confluent_kafka_cluster.target[0].kind
    rbac_crn      = data.confluent_kafka_cluster.target[0].rbac_crn
    bootstrap     = data.confluent_kafka_cluster.target[0].bootstrap_endpoint
    rest_endpoint = data.confluent_kafka_cluster.target[0].rest_endpoint
  }

  # Can Terraform (on your laptop) reach the cluster's data plane? A cluster
  # we create is public. For an existing cluster, look at its endpoints:
  # Private Link / peering endpoints mean "no", unless you override it.
  existing_endpoint_types = var.create_cluster ? [] : [
    for e in try(data.confluent_kafka_cluster.target[0].endpoints, []) : e.connection_type
  ]
  existing_is_public = var.create_cluster ? true : (
    length(local.existing_endpoint_types) > 0
    ? contains(local.existing_endpoint_types, "PUBLIC")
    : !strcontains(data.confluent_kafka_cluster.target[0].bootstrap_endpoint, ".private.")
  )
  data_plane_reachable = coalesce(var.data_plane_reachable, local.existing_is_public)
}
