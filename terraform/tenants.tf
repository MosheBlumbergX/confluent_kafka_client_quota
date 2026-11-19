# -----------------------------------------------------------------------------
# One service account per application ("tenant").
#
# Quotas are attached to PRINCIPALS (service accounts or identity pools),
# not to API keys, client IDs or topics. That is why every application needs
# its own identity: shared credentials mean a shared quota.
# -----------------------------------------------------------------------------
resource "confluent_service_account" "tenant" {
  for_each = var.tenants

  display_name = "${var.prefix}-${each.key}"
  description  = substr(each.value.description, 0, 128)
}

resource "confluent_api_key" "tenant" {
  for_each = var.tenants

  display_name = "${var.prefix}-${each.key}-kafka-key"
  description  = "Kafka API key for tenant ${each.key}.${local.label_suffix}"

  # The readiness check needs the cluster REST endpoint; skip it if private.
  disable_wait_for_ready = !local.data_plane_reachable

  owner {
    id          = confluent_service_account.tenant[each.key].id
    api_version = confluent_service_account.tenant[each.key].api_version
    kind        = confluent_service_account.tenant[each.key].kind
  }

  managed_resource {
    id          = local.cluster.id
    api_version = local.cluster.api_version
    kind        = local.cluster.kind

    environment {
      id = local.environment_id
    }
  }
}

# Least privilege: each tenant can write to and read from the demo topic,
# and use consumer groups that start with its own name. Nothing else.
resource "confluent_role_binding" "tenant_write" {
  for_each = var.tenants

  principal   = "User:${confluent_service_account.tenant[each.key].id}"
  role_name   = "DeveloperWrite"
  crn_pattern = local.topic_crn
}

resource "confluent_role_binding" "tenant_read_topic" {
  for_each = var.tenants

  principal   = "User:${confluent_service_account.tenant[each.key].id}"
  role_name   = "DeveloperRead"
  crn_pattern = local.topic_crn
}

resource "confluent_role_binding" "tenant_read_group" {
  for_each = var.tenants

  principal   = "User:${confluent_service_account.tenant[each.key].id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${local.cluster.rbac_crn}/kafka=${local.cluster.id}/group=${each.key}-*"
}
