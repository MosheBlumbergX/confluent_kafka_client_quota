#!/usr/bin/env bash
# Housekeeping for running the demo on a VM inside a private network.
#
# You normally do not need this script: when VM_SSH_TARGET is set, every
# data-plane script copies itself to the VM and runs there automatically.
#
#   ./scripts/vm.sh sync     # copy scripts + client configs to the VM now
#   ./scripts/vm.sh clean    # remove them (including secrets) from the VM
source "$(dirname "$0")/common.sh"
: "${VM_SSH_TARGET:?Set VM_SSH_TARGET, for example azureuser@203.0.113.10 (and VM_SSH_KEY if needed)}"

opts=(); while IFS= read -r l; do opts+=("$l"); done < <(ssh_opts)
case "${1:-}" in
  sync)  sync_to_vm && echo "Synced to ${VM_SSH_TARGET}:${REMOTE_DIR}" ;;
  clean) ssh "${opts[@]}" "${VM_SSH_TARGET}" "rm -rf ${REMOTE_DIR}" && echo "Removed ${REMOTE_DIR} from ${VM_SSH_TARGET}" ;;
  *)     sed -n '2,8p' "$0"; exit 1 ;;
esac
