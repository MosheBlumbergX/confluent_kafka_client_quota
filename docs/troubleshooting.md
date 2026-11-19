# Troubleshooting

[Back to README](../README.md)

| Symptom | Cause and fix |
|---|---|
| Verdict says `not settled yet: still bursting` | The quota had not been distributed to the brokers yet. Run longer: `./scripts/demo.sh 300`. Allow about a minute after any quota change. |
| A tenant shows `below quota (not limited)` | It is not hitting its ceiling, usually because the network or VM is the bottleneck. Expected for a generous quota on a small VM. |
| `Cannot resolve ... private.confluent.cloud` | Private cluster. Set `VM_SSH_TARGET` (see [private clusters](private-clusters.md)). |
| `Set environment_id ... or set create_cluster = true` | Pick an option in `terraform/terraform.tfvars`. |
| `Client quotas need an Enterprise, Freight or Dedicated cluster` | Your cluster is Basic or Standard. Use option A or another cluster. |
| `TOPIC_AUTHORIZATION_FAILED` right after apply | RBAC bindings take a minute to propagate. Wait and retry. |
| `permission denied ... docker.sock` | Add your user to the `docker` group (on VMs the scripts try `sudo -n docker`). |
| Option A apply takes a long time | Dedicated clusters can take 30+ minutes to provision. |
| Script header shows an old quota | Scripts read `generated/demo.env`; re-run `terraform apply` (it rewrites it). |
| `metrics.sh` returns nothing | Metrics arrive a few minutes late, or the API key lacks `MetricsViewer`. |
| Quota creation fails | Limits must be at least 1 MB/s; a principal can be in only one quota per cluster. |
| Raw perf-test output wanted | `RAW=1 ./scripts/produce.sh nightly-etl 60` |
