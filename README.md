# Confluent Cloud Client Quotas: taming the noisy neighbour

Three applications share one Kafka cluster. They run **identical producers
with no client-side rate limit**, all at once. One has a 10 MB/s quota, one a
1 MB/s quota, one has none. One command, three minutes later:

```
  TENANT         QUOTA      FINAL MB/s     PEAK MB/s    VERDICT
  new-team       none       97.77          98.29        NO QUOTA: unlimited
  nightly-etl    1 MB/s     1.00           46.85        held at quota
  payments-api   10 MB/s    9.91           49.51        held at quota
```

Same code, same topic, same cluster: different ceilings. And no errors: the
throttled app simply waited (its latency climbed to ~34 s).

Everything is Terraform plus a few scripts. The quota itself is one resource:

```hcl
resource "confluent_kafka_client_quota" "tenant" {
  display_name = "client-quota-demo-nightly-etl"
  throughput {
    ingress_byte_rate = "1000000" # 1 MB/s
    egress_byte_rate  = "1000000"
  }
  principals = [confluent_service_account.tenant["nightly-etl"].id]
  kafka_cluster { id = local.cluster.id }
  environment   { id = local.environment_id }
}
```

## Quick start

You need a Confluent Cloud account, a **Cloud API key**
([how](https://docs.confluent.io/cloud/current/security/authenticate/workload-identities/service-accounts/api-keys/manage-api-keys.html)),
Terraform 1.9+, Docker, `jq` and `curl`.

```bash
# 1. Credentials (environment variables only, never committed)
cp .env.example .env              # fill in the two values
set -a; source .env; set +a

# 2. Choose where to run (edit terraform/terraform.tfvars, see below)
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 3. Deploy
cd terraform && terraform init && terraform apply && cd ..

# 4. Run the demo (about 3 minutes)
./scripts/demo.sh
```

**Step 2: pick one option** in `terraform/terraform.tfvars`:

| Option | Set | Good for | Cost |
|---|---|---|---|
| **A. Create a cluster** | `create_cluster = true` | You have no suitable cluster. Runs from your laptop. | A 1-CKU Dedicated cluster, billed per hour. Provisioning can take 30+ minutes. |
| **B. Use your cluster** | `environment_id` and `kafka_cluster_id` | You have an Enterprise, Freight or Dedicated cluster. | Only the traffic you generate. |

Client quotas need an Enterprise, Freight or Dedicated cluster. Option A uses
Dedicated because it is the only one of the three with a public endpoint.
If your cluster is **private** (Private Link, peering), the load generators
must run inside that network: set `VM_SSH_TARGET` and every script runs there
for you. See [docs/private-clusters.md](docs/private-clusters.md).

## Try it

```bash
./scripts/demo.sh                    # the race, with a verdict per tenant
./scripts/produce.sh nightly-etl 240 # one tenant; leave it running and...
```

...edit `nightly-etl` in `terraform/terraform.tfvars` to `3` MB/s, run
`terraform apply`, and watch the running producer move to ~3 MB/s within
about a minute. No restart, no code change.

```bash
./scripts/consume.sh nightly-etl 60  # egress quotas work the same way
./scripts/show-quotas.sh             # quotas as Confluent Cloud sees them
./scripts/metrics.sh 15              # bytes per app, measured by the brokers
```

Each line of output shows MB/s (the unit quotas use), the quota and a verdict:

```
[nightly-etl ]   40.42 MB/s   quota 1 MB/s   avg latency  0.0 s   above quota (warm-up burst)
[nightly-etl ]    0.93 MB/s   quota 1 MB/s   avg latency  7.6 s   held at quota
```

> **Why the burst?** Confluent Cloud distributes each quota across the
> brokers based on recent usage. A client starting from idle can run far
> above its quota until that happens: ~10 s to over 90 s in our runs. Quotas
> control sustained throughput, not every second. More in
> [docs/findings.md](docs/findings.md).

## Clean up

```bash
./scripts/delete-topic.sh            # private clusters only (no-op otherwise)
cd terraform && terraform destroy
./scripts/vm.sh clean                # if you used a VM
```

## Learn more

| Doc | What is in it |
|---|---|
| [Concepts](docs/concepts.md) | Why quotas, how they work, production advice |
| [Findings](docs/findings.md) | What we measured, the warm-up burst, detailed results |
| [Private clusters](docs/private-clusters.md) | Running from a VM inside a Private Link network |
| [Security](docs/security.md) | How this repo keeps secrets out of git, least privilege |
| [Troubleshooting](docs/troubleshooting.md) | Common errors and fixes |

What the Terraform creates: 4 service accounts (3 tenants + a topic admin),
their API keys, role bindings limited to the demo topic, 2 client quotas and
the topic `client-quota-demo-orders`, plus (option A) the environment and
cluster. On an existing cluster it changes nothing else, and the cluster-wide
default quota is **off** because it would apply to every app on the cluster.
