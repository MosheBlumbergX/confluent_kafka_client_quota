# -----------------------------------------------------------------------------
# Client configuration for the scripts.
#
# Written to ../generated/ (git-ignored) with 0600 permissions. These files
# contain API secrets: do not share or commit them.
# -----------------------------------------------------------------------------
locals {
  generated_dir = abspath("${path.module}/../generated")
  bootstrap     = replace(local.cluster.bootstrap, "SASL_SSL://", "")

  client_identities = merge(
    { for name, key in confluent_api_key.tenant : name => { sa = confluent_service_account.tenant[name].id, key = key } },
    { "topic-admin" = { sa = confluent_service_account.topic_admin.id, key = confluent_api_key.topic_admin } },
  )

  # Bytes/s that actually apply to each tenant (own quota, else default, else 0 = unlimited).
  effective_quota = {
    for name, t in var.tenants : name => (
      t.quota != null ? { ingress = t.quota.ingress_mbps * local.mb, egress = t.quota.egress_mbps * local.mb } :
      var.default_quota != null ? { ingress = var.default_quota.ingress_mbps * local.mb, egress = var.default_quota.egress_mbps * local.mb } :
      { ingress = 0, egress = 0 }
    )
  }
}

resource "local_sensitive_file" "client_properties" {
  for_each = local.client_identities

  filename             = "${local.generated_dir}/${each.key}.properties"
  file_permission      = "0600"
  directory_permission = "0700"

  content = <<-EOT
    # Identity: ${each.key} (service account ${each.value.sa})
    bootstrap.servers=${local.bootstrap}
    security.protocol=SASL_SSL
    sasl.mechanism=PLAIN
    sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${each.value.key.id}" password="${each.value.key.secret}";
    client.dns.lookup=use_all_dns_ips
    session.timeout.ms=45000
    request.timeout.ms=60000
  EOT

  # RBAC needs the bindings in place before the keys are handed out.
  depends_on = [
    confluent_kafka_topic.demo,
    confluent_role_binding.tenant_write,
    confluent_role_binding.tenant_read_topic,
    confluent_role_binding.tenant_read_group,
    confluent_role_binding.topic_admin_manage,
  ]
}

# Non-secret metadata the scripts need (IDs, names and limits only).
resource "local_file" "demo_env" {
  filename             = "${local.generated_dir}/demo.env"
  file_permission      = "0644"
  directory_permission = "0700"

  content = <<-EOT
    ENVIRONMENT_ID=${local.environment_id}
    CLUSTER_ID=${local.cluster.id}
    BOOTSTRAP=${local.bootstrap}
    TOPIC=${local.topic_name}
    PARTITIONS=${var.topic_partitions}
    TOPIC_MANAGED_BY_TERRAFORM=${local.data_plane_reachable}
    TENANTS="${join(" ", keys(var.tenants))}"
    %{for name, sa in confluent_service_account.tenant~}
    SA_${upper(replace(name, "-", "_"))}=${sa.id}
    INGRESS_${upper(replace(name, "-", "_"))}=${local.effective_quota[name].ingress}
    EGRESS_${upper(replace(name, "-", "_"))}=${local.effective_quota[name].egress}
    %{endfor~}
  EOT
}

output "environment_id" {
  value = local.environment_id
}

output "cluster_id" {
  value = local.cluster.id
}

output "bootstrap_endpoint" {
  value = local.bootstrap
}

output "topic" {
  value = local.topic_name
}

output "tenants" {
  description = "Each tenant, its service account and the quota that applies to it."
  value = {
    for name, t in var.tenants : name => {
      service_account = confluent_service_account.tenant[name].id
      quota_id        = t.quota != null ? confluent_kafka_client_quota.tenant[name].id : (var.default_quota != null ? confluent_kafka_client_quota.default[0].id : "none")
      applies = (
        t.quota != null ? "own: ${t.quota.ingress_mbps} MB/s in, ${t.quota.egress_mbps} MB/s out" :
        var.default_quota != null ? "default: ${var.default_quota.ingress_mbps} MB/s in, ${var.default_quota.egress_mbps} MB/s out" :
        "UNLIMITED (no quota, no default)"
      )
    }
  }
}

output "console_url" {
  description = "Open this, then Settings > Client quotas, to see the quotas in the UI."
  value       = "https://confluent.cloud/environments/${local.environment_id}/clusters/${local.cluster.id}/settings/kafka"
}
