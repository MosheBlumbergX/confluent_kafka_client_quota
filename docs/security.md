# Security

[Back to README](../README.md)

This repository is designed to be safe to publish and safe to run on a
shared cluster.

## Secrets

- **No secrets in code.** The Confluent Cloud API key comes from environment
  variables (`CONFLUENT_CLOUD_API_KEY` / `CONFLUENT_CLOUD_API_SECRET`), loaded
  from a git-ignored `.env`.
- **Generated secrets stay local.** Client configs are written to `generated/`
  with mode `0600` in a `0700` folder, and the folder is git-ignored. On a VM
  they live in `~/client-quota-demo` (also `0700`/`0600`); `vm.sh clean`
  removes them.
- **Terraform state is local and git-ignored.** It contains API key secrets.
  For team use, move it to an encrypted remote backend.
- **Watch provider error output.** If a `confluent_api_key` fails mid-create,
  the provider's error message can include the new key's secret. Do not paste
  raw `terraform apply` failures into issues or chats; delete and recreate any
  key whose secret was exposed.

`.gitignore` excludes `.env`, `*.tfvars` (only the `.example` is tracked),
`*.tfstate*`, `generated/`, `*.properties`, `logs/` and `comms/`.

Before you push:

```bash
git status --ignored            # generated/, .env, *.tfstate must be ignored
git grep -nE 'cflt[A-Za-z0-9+/]{20,}'
```

## Least privilege

| Identity | Can do |
|---|---|
| Each tenant | `DeveloperWrite` + `DeveloperRead` on the demo topic; `DeveloperRead` on consumer groups prefixed with its own name |
| Topic admin | `DeveloperManage` on the demo topic only |
| Your Cloud API key | Creates the above (and, in option A, the environment and cluster) |

Nothing in the demo gets cluster-admin rights.

## On a shared cluster

- Everything is prefixed `client-quota-demo-`, so it is obvious what belongs
  to the demo.
- Nothing existing is modified: the cluster is read with data sources only.
- The **default quota is off**: it would apply to every principal on the
  cluster, including other teams' workloads.
- The load tests push real traffic (the unlimited tenant reached ~98 MB/s in
  our runs). On elastic clusters that can scale capacity, and cost, up for a
  while. Keep runs short and tell the cluster's owners.
