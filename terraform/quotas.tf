# -----------------------------------------------------------------------------
# Client quotas: the point of this demo.
#
# Rules worth remembering:
#   * A quota is a CEILING, not a guaranteed floor.
#   * Every principal listed in a quota gets the FULL amount (it is not shared
#     between the principals in the list).
#   * A principal can appear in at most ONE quota per cluster.
#   * The special principal "<default>" applies to EVERY principal on the
#     cluster without a more specific quota, including ones that have nothing
#     to do with this demo. That is why it is off by default here.
#   * Over-quota clients are not rejected. The broker tells them to back off
#     (throttle time) and briefly mutes the connection, so the application
#     sees higher latency, not errors.
#   * Changes reach running clients without a restart, typically within a
#     minute. Expect a burst above the quota while it is redistributed.
# -----------------------------------------------------------------------------

locals {
  tenants_with_quota = { for name, t in var.tenants : name => t if t.quota != null }
}

resource "confluent_kafka_client_quota" "tenant" {
  for_each = local.tenants_with_quota

  display_name = "${var.prefix}-${each.key}"
  description  = "${each.value.quota.ingress_mbps} MB/s in, ${each.value.quota.egress_mbps} MB/s out for ${each.key}.${local.label_suffix}"

  throughput {
    ingress_byte_rate = tostring(each.value.quota.ingress_mbps * local.mb)
    egress_byte_rate  = tostring(each.value.quota.egress_mbps * local.mb)
  }

  principals = [confluent_service_account.tenant[each.key].id]

  kafka_cluster {
    id = local.cluster.id
  }

  environment {
    id = local.environment_id
  }

  # In production, uncomment this so a typo in a plan cannot silently remove
  # the guard rail protecting your other tenants:
  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "confluent_kafka_client_quota" "default" {
  count = var.default_quota == null ? 0 : 1

  display_name = "${var.prefix}-default"
  description  = "Baseline for every principal without its own quota.${local.label_suffix}"

  throughput {
    ingress_byte_rate = tostring(var.default_quota.ingress_mbps * local.mb)
    egress_byte_rate  = tostring(var.default_quota.egress_mbps * local.mb)
  }

  principals = ["<default>"]

  kafka_cluster {
    id = local.cluster.id
  }

  environment {
    id = local.environment_id
  }
}
