# Private clusters (Private Link, peering)

[Back to README](../README.md)

Enterprise and Freight clusters are reachable over private networking only,
and many Dedicated clusters are too. That splits the demo in two:

| Part | Where it runs | Why |
|---|---|---|
| Terraform (service accounts, keys, RBAC, **quotas**) | Your laptop | Control plane: public API |
| Topic creation, producers, consumers | A machine inside the network | Data plane: private endpoints only |

Terraform detects a private cluster from its endpoints and, instead of
creating the topic itself, leaves that to `scripts/setup-topic.sh`
(`demo.sh` runs it for you). Override detection with
`data_plane_reachable = true|false` if needed.

## Use a VM inside the network

You need a VM that can resolve and reach the cluster's private endpoint,
with Docker installed, and SSH access to it.

```bash
export VM_SSH_TARGET=azureuser@<vm-address>
export VM_SSH_KEY=/path/to/vm-key.pem      # if needed

./scripts/demo.sh                          # same commands as on a public cluster
```

When `VM_SSH_TARGET` is set, every data-plane script (`demo.sh`, `race.sh`,
`produce.sh`, `consume.sh`, `setup-topic.sh`, `delete-topic.sh`):

1. copies `scripts/` and `generated/` to `~/client-quota-demo` on the VM
   (directory `0700`, client configs `0600`), every time, so the VM always
   has your latest `terraform apply`;
2. runs itself there and streams the output back.

`show-quotas.sh` and `metrics.sh` always run locally: they only use the
public control-plane APIs.

If `azureuser` (or your user) is not in the VM's `docker` group, the scripts
use `sudo -n docker` automatically.

When you are done:

```bash
./scripts/delete-topic.sh     # before terraform destroy: it needs the topic-admin key
cd terraform && terraform destroy && cd ..
./scripts/vm.sh clean         # removes the copied configs (and secrets) from the VM
```

## Without `VM_SSH_TARGET`

If the brokers cannot be resolved from your machine, the scripts stop with a
hint instead of hanging:

```
ERROR: Cannot resolve lkc-xxxxx.<region>.azure.private.confluent.cloud from this machine.
       The cluster is probably private (Private Link / peering). ...
```

You can also clone the repo onto the VM and run everything there, as long as
Terraform's `generated/` folder is copied with it (or Terraform runs there too).
