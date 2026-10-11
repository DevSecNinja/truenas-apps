#!/usr/bin/env bash
# PATH dispatcher for synthetic recovery fixtures, not a Docker/ZFS emulator.
# Unknown commands fail closed so a new production command cannot silently pass.
set -euo pipefail
command="${0##*/}"
printf '%s\n' "$*" >>"${MOCK_LOG}/${command}.calls"

event() { printf '%s\n' "$*" >>"${MOCK_LOG}/events"; }
unexpected() {
  printf 'Unexpected recovery mock call: %s %s\n' "${command}" "$*" >&2
  exit 97
}

case "${command}" in
sudo)
  [[ "$*" == -v ]] && exit 0
  case "$1" in
  docker | zfs) exec "$@" ;;
  *) unexpected "$@" ;;
  esac
  ;;
id)
  [[ "$*" == -u ]] && {
    printf '1000\n'
    exit 0
  }
  ;;
date)
  case "$*" in
  '-u +%Y%m%dT%H%M%SZ') printf '20261010T210000Z\n' ;;
  '+%s') printf '2000000000\n' ;;
  '--date=current +%s') printf '2000000000\n' ;;
  '--date=earlier +%s') printf '1999999999\n' ;;
  *) unexpected "$@" ;;
  esac
  exit 0
  ;;
git)
  case "$*" in
  "-C ${TEST_BASE_DIR} status --porcelain") exit 0 ;;
  "-C ${TEST_BASE_DIR} rev-parse HEAD")
    if [[ -f "${MOCK_LOG}/synced" ]]; then printf 'revision-target\n'; else printf 'revision-old\n'; fi
    exit 0
    ;;
  *) unexpected "$@" ;;
  esac
  ;;
dccd.sh)
  # Borrow the parent's real lock and validate its recovery identity, just as
  # the actual dccd main does. The rest of DCCD orchestration is intentionally
  # mocked here; actual main guard coverage lives in deployment_lock.bats.
  # shellcheck source=/dev/null
  source "${TEST_BASE_DIR}/scripts/lib/deployment-lock.sh"
  # shellcheck disable=SC2329 # Called by the dynamically sourced lock library.
  log_error() { printf '%s\n' "$*" >&2; }
  # shellcheck disable=SC2034 # Read by the dynamically sourced lock library.
  BASE_DIR="${TEST_BASE_DIR}"
  APP_FILTER=''
  for ((i = 1; i <= $#; i++)); do
    if [[ "${!i}" == -a ]]; then
      j=$((i + 1))
      # shellcheck disable=SC2034 # Read by the dynamically sourced lock library.
      APP_FILTER="${!j}"
    fi
  done
  inherited="${DCCD_LOCK_FD:?Recovery did not export its lock}"
  dccd_acquire_lock
  [[ "${DCCD_LOCK_FD}" == "${inherited}" ]] || exit 96
  dccd_check_maintenance
  case " $* " in
  *' -D '*)
    event sync
    [[ "${RECOVERY_FAIL_AT:-}" != sync ]] || exit 41
    touch "${MOCK_LOG}/synced"
    ;;
  *' -n -B '*)
    event deploy
    [[ "${RECOVERY_FAIL_AT:-}" != deploy ]] || exit 44
    touch "${MOCK_LOG}/deployed"
    ;;
  *) unexpected "$@" ;;
  esac
  exit 0
  ;;
zfs)
  case "$*" in
  'list -H -o name,mountpoint,mounted')
    printf 'tank/apps/widget\t%s/services/widget\t%s\n' "${TEST_BASE_DIR}" "${RECOVERY_MOUNTED:-yes}"
    if [[ "${RECOVERY_NESTED_DATASET:-0}" == 1 ]]; then
      printf 'tank/unrelated\t%s/services/widget/data\tyes\n' "${TEST_BASE_DIR}"
    fi
    ;;
  'list -H -t snapshot -o name -r tank/apps/widget')
    if [[ -f "${MOCK_LOG}/snapshot-name" ]]; then cat "${MOCK_LOG}/snapshot-name"; fi
    ;;
  'list -H -t snapshot -o name '*)
    [[ -f "${MOCK_LOG}/snapshot-name" ]] || exit 1
    cat "${MOCK_LOG}/snapshot-name"
    ;;
  'snapshot -r '*)
    event "snapshot ${*: -1}"
    [[ "${RECOVERY_FAIL_AT:-}" != snapshot ]] || exit 43
    printf '%s\n' "${*: -1}" >"${MOCK_LOG}/snapshot-name"
    ;;
  'get -H -o value org.truenas-apps:recovery-app '*)
    printf '%s\n' "${RECOVERY_STORED_OWNER:-widget}"
    ;;
  'get -H -o value org.truenas-apps:recovery-target-revision '*)
    if [[ -n "${RECOVERY_STORED_REVISION:-}" ]]; then
      printf '%s\n' "${RECOVERY_STORED_REVISION}"
    elif [[ -f "${MOCK_LOG}/target-revision" ]]; then
      cat "${MOCK_LOG}/target-revision"
    else
      printf '%s\n' '-'
    fi
    ;;
  'get -H -o value org.truenas-apps:recovery-target-images '*)
    if [[ -f "${MOCK_LOG}/target-images" ]]; then
      cat "${MOCK_LOG}/target-images"
    else
      jq -cn --arg image "${RECOVERY_IMAGE:-registry.invalid/widget:v2}" \
        '[{name:"web",image:$image,image_id:"sha256:target"},
          {name:"widget-db-backup",image:"registry.invalid/backup:v2",image_id:"sha256:backup"}]'
    fi
    ;;
  'set org.truenas-apps:recovery-target-revision='*)
    printf '%s\n' "${2#*=}" >"${MOCK_LOG}/target-revision"
    ;;
  'set org.truenas-apps:recovery-target-images='*)
    printf '%s\n' "${2#*=}" >"${MOCK_LOG}/target-images"
    ;;
  'get -H -o value org.truenas-apps:recovery-status '*)
    printf '%s\n' "${RECOVERY_STORED_STATUS:-pending}"
    ;;
  'set org.truenas-apps:recovery-status=complete '*)
    event "complete ${*: -1}"
    ;;
  'destroy -r '*)
    event "destroy ${*: -1}"
    rm "${MOCK_LOG}/snapshot-name"
    ;;
  *) unexpected "$@" ;;
  esac
  exit 0
  ;;
docker)
  case "$1" in
  compose)
    [[ "$2" == --project-name && "$3" == ix-widget && "$4" == --file ]] || unexpected "$@"
    shift 5
    case "$*" in
    'config --format json')
      jq -cn --arg source "${RECOVERY_MOUNT_SOURCE:-${TEST_BASE_DIR}/services/widget/data}" \
        --arg image "${RECOVERY_IMAGE:-registry.invalid/widget:v2}" \
        --arg type "${RECOVERY_MOUNT_TYPE:-bind}" \
        --argjson build "${RECOVERY_BUILD:-null}" \
        --argjson replicas "${RECOVERY_REPLICAS:-1}" '
        {services: {
          web: {image: $image, restart: "unless-stopped", build: $build,
                deploy: {replicas: $replicas},
                volumes: [{type: $type, source: $source, read_only: false}]},
          "widget-db-backup": {image: "registry.invalid/backup:v2", restart: "no"}
        }}'
      ;;
    pull)
      event pull
      [[ "${RECOVERY_FAIL_AT:-}" != pull ]] || exit 42
      ;;
    'ps --all --quiet '*)
      service="${*: -1}"
      if [[ "${RECOVERY_MISSING_SERVICE:-}" != "${service}" ]]; then
        if [[ "${service}" == web && "${RECOVERY_RETAIN_WEB:-0}" == 1 ]]; then
          printf 'live-web\n'
        else
          printf 'current-%s\n' "${service}"
        fi
      fi
      ;;
    *) unexpected "$@" ;;
    esac
    ;;
  ps)
    [[ "$*" == *'label=com.docker.compose.project=ix-widget'* ]] || unexpected "$@"
    case "$2" in
    -aq)
      printf 'live-web\nlive-retired\n'
      if [[ "${RECOVERY_BUSY_BACKUP:-0}" == 1 ]]; then printf 'live-backup\n'; fi
      ;;
    -q)
      for id in live-web live-retired; do
        if [[ ! -f "${MOCK_LOG}/stopped-${id}" ]]; then printf '%s\n' "${id}"; fi
      done
      if [[ "${RECOVERY_BUSY_BACKUP:-0}" == 1 ]]; then printf 'live-backup\n'; fi
      ;;
    --filter)
      if [[ "${RECOVERY_RUNNING_MEILI:-0}" == 1 ]]; then printf 'web\n'; fi
      ;;
    *) unexpected "$@" ;;
    esac
    ;;
  stop)
    [[ "$2" == --time && "$3" == 60 && "$4" == live-* ]] || unexpected "$@"
    event "stop $4"
    touch "${MOCK_LOG}/stopped-$4"
    ;;
  inspect)
    case "$3" in
    '{{json .Mounts}}')
      jq -cn --arg path "${RECOVERY_LIVE_MOUNT:-${TEST_BASE_DIR}/services/widget/data}" \
        '[{Type:"bind", Source:$path, RW:true}]'
      ;;
    '{"service":'*)
      image_id=sha256:old
      if [[ "$4" == live-web && "${RECOVERY_RETAIN_WEB:-0}" == 1 ]]; then image_id=sha256:target; fi
      printf '{"service":"%s","reference":"registry.invalid/old:v1","id":"%s"}\n' "$4" "${image_id}"
      ;;
    '{{index .Config.Labels "com.docker.compose.service"}}')
      if [[ "$4" == live-backup ]]; then printf 'widget-db-backup\n'; else printf 'web\n'; fi
      ;;
    '{{.State.Status}}')
      [[ "$4" == live-backup ]] || unexpected "$@"
      printf 'running\n'
      ;;
    '{{.State.Status}}|'*)
      if [[ "$4" == current-widget-db-backup ]]; then
        printf 'exited|%s|none|%s|sha256:backup\n' "${RECOVERY_BACKUP_EXIT:-0}" "${RECOVERY_BACKUP_STARTED:-current}"
      else
        image_id="${RECOVERY_ACTUAL_IMAGE:-sha256:target}"
        if [[ "${RECOVERY_RETAG_ON_DEPLOY:-0}" == 1 && -f "${MOCK_LOG}/deployed" ]]; then
          image_id=sha256:moved
        fi
        printf 'running|0|%s|current|%s\n' "${RECOVERY_HEALTH:-healthy}" "${image_id}"
      fi
      ;;
    *) unexpected "$@" ;;
    esac
    ;;
  image)
    [[ "$2 $3 $4" == 'inspect --format {{.Id}}' ]] || unexpected "$@"
    if [[ "$5" == registry.invalid/backup:v2 ]]; then
      printf 'sha256:backup\n'
    elif [[ "${RECOVERY_RETAG_ON_DEPLOY:-0}" == 1 && -f "${MOCK_LOG}/deployed" ]]; then
      printf 'sha256:moved\n'
    else
      printf 'sha256:target\n'
    fi
    ;;
  exec)
    event meili
    printf '%s\n' "${RECOVERY_MEILI_RESPONSE:-}"
    ;;
  *) unexpected "$@" ;;
  esac
  exit 0
  ;;
*) unexpected "$@" ;;
esac
unexpected "$@"
