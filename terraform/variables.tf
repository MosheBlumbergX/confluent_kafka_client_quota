# -----------------------------------------------------------------------------
# Where to run. Either let Terraform create a cluster, or point at yours.
# Client quotas need an Enterprise, Freight or Dedicated cluster (not Basic
# or Standard).
# -----------------------------------------------------------------------------
variable "create_cluster" {
  description = "true: create an environment and a 1-CKU public Dedicated cluster (billed per hour). false: use environment_id + kafka_cluster_id."
  type        = bool
  default     = false
}

variable "cloud" {
  description = "Cloud for the cluster Terraform creates (AWS, GCP or AZURE). Ignored when using an existing cluster."
  type        = string
  default     = "AWS"
}

variable "region" {
  description = "Region for the cluster Terraform creates. Pick one close to where you run the load tests."
  type        = string
  default     = "us-east-2"
}

variable "environment_id" {
  description = "Existing environment, for example env-abc123. Required when create_cluster = false."
  type        = string
  default     = null

  validation {
    condition     = var.create_cluster || can(regex("^env-[a-z0-9]+$", var.environment_id))
    error_message = "Set environment_id (looks like env-abc123), or set create_cluster = true."
  }
}

variable "kafka_cluster_id" {
  description = "Existing Enterprise, Freight or Dedicated cluster, for example lkc-abc123. Required when create_cluster = false."
  type        = string
  default     = null

  validation {
    condition     = var.create_cluster || can(regex("^lkc-[a-z0-9]+$", var.kafka_cluster_id))
    error_message = "Set kafka_cluster_id (looks like lkc-abc123), or set create_cluster = true."
  }
}

variable "data_plane_reachable" {
  description = "Override: can this machine reach the cluster's brokers and REST endpoint? null = detect (public endpoint = yes, Private Link/peering = no)."
  type        = bool
  default     = null
}

variable "prefix" {
  description = "Prefix for every resource this project creates, so it is obvious what belongs to the demo on a shared cluster."
  type        = string
  default     = "client-quota-demo"
}

variable "topic_partitions" {
  description = "Partitions for the demo topic. More partitions spread the load across more brokers."
  type        = number
  default     = 6
}

# -----------------------------------------------------------------------------
# The heart of the demo: who gets how much throughput.
#
# Values are in MB/s where 1 MB = 1,000,000 bytes (the unit Confluent Cloud
# uses). The minimum Confluent Cloud accepts is 1 MB/s.
#
# A tenant with quota = null gets NO quota of its own: it is unlimited unless
# a default quota is set (see default_quota below).
# -----------------------------------------------------------------------------
variable "tenants" {
  description = "Applications sharing the cluster. Each gets its own service account and API key."
  type = map(object({
    description = string
    quota = optional(object({
      ingress_mbps = number
      egress_mbps  = number
    }))
  }))

  default = {
    "payments-api" = {
      description = "Latency-sensitive, business-critical service. Generous quota."
      quota       = { ingress_mbps = 10, egress_mbps = 10 }
    }
    "nightly-etl" = {
      description = "Batch job that would happily eat the whole cluster. Tightly contained."
      quota       = { ingress_mbps = 1, egress_mbps = 1 }
    }
    "new-team" = {
      description = "A team that has just onboarded. Nobody has given it a quota yet."
      quota       = null
    }
  }

  validation {
    condition = alltrue([
      for t in values(var.tenants) :
      t.quota == null ? true : (t.quota.ingress_mbps >= 1 && t.quota.egress_mbps >= 1)
    ])
    error_message = "Confluent Cloud client quotas must be at least 1 MB/s for both ingress and egress."
  }

  validation {
    condition     = alltrue([for k in keys(var.tenants) : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Tenant names must be lower-case letters, digits and hyphens."
  }
}

# WARNING: the default quota applies to EVERY principal on the cluster that
# has no specific quota, not just the tenants of this demo. On a shared
# cluster that includes other teams' producers, consumers and connectors.
# Off by default for that reason; turn it on deliberately.
variable "default_quota" {
  description = "Cluster-wide default quota for every principal without a specific quota. null = no default."
  type = object({
    ingress_mbps = number
    egress_mbps  = number
  })
  default = null

  validation {
    condition     = var.default_quota == null ? true : (var.default_quota.ingress_mbps >= 1 && var.default_quota.egress_mbps >= 1)
    error_message = "The default quota must be at least 1 MB/s for both ingress and egress."
  }
}

variable "resource_labels" {
  description = <<-EOT
    Optional ownership labels (for example owner, cost centre, expiry date).
    Confluent Cloud resources do not support free-form tags, so these are
    written into the descriptions of the API keys and quotas.
  EOT
  type        = map(string)
  default     = {}
}
