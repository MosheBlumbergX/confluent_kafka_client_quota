#!/usr/bin/env bash
# Shared helpers for the demo scripts. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED="${REPO_ROOT}/generated"
KAFKA_IMAGE="${KAFKA_IMAGE:-confluentinc/cp-kafka:8.1.0}"
# Small heap: three load generators must fit on a small VM at the same time.
KAFKA_HEAP_OPTS="${KAFKA_HEAP_OPTS:--Xms128m -Xmx384m}"
REMOTE_DIR="${REMOTE_DIR:-client-quota-demo}"

die()  { echo "ERROR: $*" >&2; exit 1; }
note() { printf '\033[2m%s\033[0m\n' "$*"; }

[[ -f "${GENERATED}/demo.env" ]] || die "generated/demo.env not found. Run 'terraform apply' in terraform/ first."
# shellcheck disable=SC1091
source "${GENERATED}/demo.env"

require_tenant() {
  [[ -f "${GENERATED}/$1.properties" ]] || die "Unknown tenant '$1'. Known tenants: ${TENANTS}"
}

# Quota in bytes/s for a tenant: quota_bytes <tenant> INGRESS|EGRESS (0 = none).
quota_bytes() {
  local var
  var="$2_$(echo "$1" | tr 'a-z-' 'A-Z_')"
  echo "${!var:-0}"
}

# -----------------------------------------------------------------------------
# One run mode.
#
# Data-plane scripts (topic setup, produce, consume) must run on a machine
# that can reach the brokers. If VM_SSH_TARGET is set, they copy themselves
# and the client configs to that VM and run there; otherwise they run here.
# The command you type is the same either way.
# -----------------------------------------------------------------------------
ssh_opts() {
  local o=(-o ConnectTimeout=15 -o ServerAliveInterval=30)
  [[ -n "${VM_SSH_KEY:-}" ]] && o+=(-i "${VM_SSH_KEY}")
  printf '%s\n' "${o[@]}"
}

sync_to_vm() {
  local opts=(); while IFS= read -r l; do opts+=("$l"); done < <(ssh_opts)
  # tar over ssh: works with any rsync/scp flavour; permissions fixed after.
  COPYFILE_DISABLE=1 tar -C "${REPO_ROOT}" -czf - generated scripts \
    | ssh "${opts[@]}" "${VM_SSH_TARGET}" "umask 077 && rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR} \
        && tar -xzf - -C ${REMOTE_DIR} 2>/dev/null \
        && chmod 700 ${REMOTE_DIR} ${REMOTE_DIR}/generated ${REMOTE_DIR}/scripts \
        && chmod 600 ${REMOTE_DIR}/generated/* && chmod 700 ${REMOTE_DIR}/scripts/*"
}

run_near_brokers() {
  local script="$1"; shift
  if [[ -n "${VM_SSH_TARGET:-}" && "${QUOTA_DEMO_REMOTE:-0}" != "1" ]]; then
    local opts=(); while IFS= read -r l; do opts+=("$l"); done < <(ssh_opts)
    [[ -t 1 ]] && opts+=(-tt)   # line-by-line output and colours when interactive
    note "Running on ${VM_SSH_TARGET} (inside the cluster's network)..."
    sync_to_vm
    local args=""; for a in "$@"; do args+=" $(printf '%q' "$a")"; done
    exec ssh "${opts[@]}" "${VM_SSH_TARGET}" \
      "cd ${REMOTE_DIR} && QUOTA_DEMO_REMOTE=1 RAW=${RAW:-0} ./scripts/$(basename "${script}")${args}"
  fi
  check_reachable
  ensure_docker
}

# Fail early, with a useful hint, if the brokers cannot be resolved from here.
check_reachable() {
  local host="${BOOTSTRAP%%:*}"
  command -v python3 >/dev/null || return 0
  if ! python3 -c "import socket,sys; socket.gethostbyname(sys.argv[1])" "${host}" 2>/dev/null; then
    die "Cannot resolve ${host} from this machine.
       The cluster is probably private (Private Link / peering). Run the demo from a
       machine inside that network, for example:
         export VM_SSH_TARGET=user@vm-address  VM_SSH_KEY=/path/to/key.pem
       and run the same command again. See docs/private-clusters.md."
  fi
}

ensure_docker() {
  command -v docker >/dev/null || die "Docker is required (the Kafka CLI tools run in a container)."
  # Plain docker if this user may, otherwise passwordless sudo (common on
  # cloud VMs where the user is not in the docker group).
  if [[ -z "${DOCKER:-}" ]]; then
    if docker info >/dev/null 2>&1; then DOCKER="docker"
    elif sudo -n docker info >/dev/null 2>&1; then DOCKER="sudo -n docker"
    else die "Cannot talk to Docker. Add your user to the docker group or set DOCKER."; fi
  fi
}

# Run a Kafka CLI tool in a throw-away container, with an identity's client
# config mounted read-only. Nothing is installed on the machine.
kafka_tool() {
  local identity="$1"; shift
  ${DOCKER} run --rm -i -e KAFKA_HEAP_OPTS="${KAFKA_HEAP_OPTS}" \
    --name "quota-demo-${identity}-$$-${RANDOM}" \
    -v "${GENERATED}/${identity}.properties:/config/client.properties:ro" \
    "${KAFKA_IMAGE}" "$@"
}

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
colour_of() {
  case "$1" in
    payments-api) echo 32 ;;  # green
    nightly-etl)  echo 31 ;;  # red
    *)            echo 33 ;;  # yellow
  esac
}

# Prefix each line with a coloured tenant label.
label() {
  local tenant="$1" c; c=$(colour_of "$1")
  while IFS= read -r line; do
    printf '\033[%sm[%-12s]\033[0m %s\n' "${c}" "${tenant}" "${line}"
  done
}

# verdict(rate_MBps, quota_MBps), shared by live lines and end-of-run summary.
VERDICT_AWK='
function verdict(rate, q) {
  if (q == 0)          return "NO QUOTA: unlimited"
  if (rate > q * 1.15) return "above quota (warm-up burst)"
  if (rate < q * 0.85) return "below quota (not limited)"
  return "held at quota"
}'
