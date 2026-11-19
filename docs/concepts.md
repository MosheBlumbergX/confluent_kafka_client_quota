# Concepts: why and how client quotas work

[Back to README](../README.md)

## The problem: noisy neighbours

Sharing one Kafka cluster between many teams is cheaper and simpler than a
cluster per team. The catch: one application (a backfill, a nightly ETL, a
retry loop gone wrong) suddenly pushes far more data than usual, and everyone
else on the cluster pays for it.

Client quotas let a platform team say, per application:

> "You may produce at most X MB/s and consume at most Y MB/s on this cluster."

| Use case | How quotas help |
|---|---|
| **Protect critical workloads** | A batch job cannot starve a latency-sensitive service. |
| **Contain batch and backfill jobs** | Big jobs still finish, at a predictable pace. |
| **Tiers of service** | Gold, silver and bronze tenants, each with its own ceiling. |
| **A safe baseline** | A *default* quota catches every new or forgotten application. |
| **Capacity planning** | The sum of your quotas bounds sustained worst-case load. |
| **Chargeback conversations** | "You need more throughput? Here is what that tier costs." |

## The rules

1. **Quotas attach to principals**: service accounts or identity pools. Not to
   API keys, client IDs or topics. Shared credentials mean a shared identity,
   so give every application its own service account.
2. **A quota is a ceiling, not a floor.** It caps throughput; it does not
   reserve capacity.
3. **Every principal in a quota gets the full amount.** A 10 MB/s quota listing
   two service accounts lets *each* of them do 10 MB/s. It is not shared.
4. **One quota per principal per cluster**, plus an optional **default quota**
   (principal `<default>`) for every principal without its own quota.
5. **Over-quota clients are slowed, not rejected.** The broker returns a
   *throttle time* and briefly mutes the connection. The application sees
   extra latency, not errors: there is no retry logic to write.

Also:

- Available on **Enterprise, Freight and Dedicated** clusters (not Basic or
  Standard). Of those, only Dedicated offers public networking.
- Limits are in **bytes per second**; minimum **1 MB/s** (1,000,000 B/s) for
  ingress and for egress.
- Quotas are **cluster level**: Confluent Cloud distributes slices of each
  quota to the brokers where that principal's traffic lands.
- Quotas live in the **control plane**, so Terraform can manage them from
  anywhere, even for a cluster reachable only over Private Link.

## How this repo is laid out

| File | What it does |
|---|---|
| [`terraform/cluster.tf`](../terraform/cluster.tf) | Option A: create an environment + Dedicated cluster. Option B: look up yours (read-only). |
| [`terraform/tenants.tf`](../terraform/tenants.tf) | One service account + API key per tenant, least-privilege RBAC |
| [`terraform/quotas.tf`](../terraform/quotas.tf) | **The client quotas** (per tenant, optional default) |
| [`terraform/main.tf`](../terraform/main.tf) | The demo topic and the identity that manages it |
| [`terraform/variables.tf`](../terraform/variables.tf) | Options, tenants and their limits in MB/s, with validation |
| [`terraform/outputs.tf`](../terraform/outputs.tf) | Writes client configs to `generated/` (git-ignored, mode 0600) |

| Script | What it does |
|---|---|
| `demo.sh [secs]` | The guided demo: quotas, topic, race, verdict |
| `race.sh [secs]` | All tenants flat out at once, then a summary table |
| `produce.sh <tenant> [secs]` | One tenant producing flat out (ingress) |
| `consume.sh <tenant> [secs]` | One tenant reading flat out (egress) |
| `show-quotas.sh` | Quotas as Confluent Cloud sees them (REST API) |
| `metrics.sh [mins]` | Bytes per principal, measured by the brokers (Metrics API) |
| `setup-topic.sh`, `delete-topic.sh` | Topic lifecycle for private clusters |
| `vm.sh sync\|clean` | Copy to / remove from a VM (normally automatic) |

The load generator is the standard `kafka-producer-perf-test` /
`kafka-consumer-perf-test`, run in Docker with `--throughput -1` (no
client-side limit), 1 KB records, `acks=all`, no compression.

## The default quota

`<default>` applies to **every** principal on the cluster without its own
quota: other teams' producers, consumers, connectors. That makes it the best
guard rail on a cluster you own, and a risky change on a cluster you share.
This repo leaves it off (`default_quota = null`). To try it:

```hcl
default_quota = { ingress_mbps = 2, egress_mbps = 2 }
```

Then `new-team`, which has no quota of its own, is held to 2 MB/s.

## Taking it to production

- **One identity per application.** Quotas follow principals; shared service
  accounts mean shared limits and no per-app visibility.
- **Set a default quota** on clusters you own.
- **Identity pools work too** for OAuth/OIDC applications (`pool-xxxx`).
- **Quota by tier, not by app**, once you have many applications: one quota
  per tier listing many principals (each still gets the full amount).
- **Leave headroom for bursts.** Quotas govern sustained throughput; expect
  bursts above them after idle periods and right after changes
  ([findings](findings.md)).
- **Protect quotas from accidental deletion** with
  `lifecycle { prevent_destroy = true }` (commented out in `quotas.tf` so the
  demo can be destroyed).
- **Monitor throttling.** Alert on client metrics `produce-throttle-time-avg`
  and `fetch-throttle-time-avg`; chart Metrics API `request_bytes` and
  `response_bytes` by `principal_id`.
- **Make quota changes reviewable.** Keep them in Terraform, change them
  through pull requests.

## Further reading

- [Get started with client quotas](https://docs.confluent.io/cloud/current/clusters/client-quotas-quickstart.html)
- [Multi-tenancy and client quotas](https://docs.confluent.io/cloud/current/clusters/client-quotas.html)
- [Terraform: `confluent_kafka_client_quota`](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_client_quota)
- [Cluster types](https://docs.confluent.io/cloud/current/clusters/cluster-types.html)
- [Metrics API](https://api.telemetry.confluent.cloud/docs/descriptors/datasets/cloud)
