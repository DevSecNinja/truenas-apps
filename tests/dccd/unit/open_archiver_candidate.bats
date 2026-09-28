#!/usr/bin/env bats
# Real, offline Compose rendering only: no daemon, pulls or container creation.
# Candidate refers to image approval, not a Compose service-selection gate.

load '../helpers/diagnostics'

setup_file() {
    diagnostics_require_helpers || return
    local tool
    for tool in yq jq; do
        command -v "${tool}" || return 1
    done
    if docker-compose version >/dev/null 2>&1; then
        export OPEN_ARCHIVER_COMPOSE_PROVIDER=docker-compose
    elif docker compose version >/dev/null 2>&1; then
        export OPEN_ARCHIVER_COMPOSE_PROVIDER=docker
    else
        printf 'Required working Compose provider missing: docker-compose or docker compose\n' >&2
        return 1
    fi
}

setup() {
    load '../helpers/common'
    # Like browser_task_limits.bats, retain real tools instead of common_setup's mocks.
    OPEN_ARCHIVER_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
    cd "${OPEN_ARCHIVER_TMPDIR}" || return
}

teardown() {
    if [[ -n "${OPEN_ARCHIVER_TMPDIR:-}" ]]; then
        local result=0
        assert_dir_not_exists "${OPEN_ARCHIVER_TMPDIR}/data" || result=1
        assert_dir_not_exists "${OPEN_ARCHIVER_TMPDIR}/backups" || result=1
        assert_file_not_exists "${OPEN_ARCHIVER_TMPDIR}/.env" || result=1
        rm -rf "${OPEN_ARCHIVER_TMPDIR}"
        return "${result}"
    fi
}

render_open_archiver_candidate() {
    local profile="$1" format="$2"
    shift 2
    local -a compose_command=("${OPEN_ARCHIVER_COMPOSE_PROVIDER}")
    local -a profile_args=() config_args=()
    if [[ "${OPEN_ARCHIVER_COMPOSE_PROVIDER}" == docker ]]; then
        compose_command+=(compose)
    fi
    if [[ -n "${profile}" ]]; then
        profile_args=(--profile "${profile}")
    fi
    case "${format}" in
    services) config_args=(--services) ;;
    json) config_args=(--format json) ;;
    *) return 1 ;;
    esac
    set -o pipefail
    # Removing env_file is the ONLY model transformation. Preserve all services,
    # dependencies, commands, resource limits, networks and bind mounts.
    # Stdin + a disposable project directory + --env-file /dev/null prevent
    # Compose from discovering the real service's ignored .env or shared env files.
    yq --yaml-fix-merge-anchor-to-spec=true -o=json 'del(.services[].env_file)' \
        "${REPO_ROOT}/services/open-archiver/compose.yaml" |
        env -i PATH="${PATH}" HOME="${OPEN_ARCHIVER_TMPDIR}" \
            DOMAINNAME=example.invalid \
            POSTGRES_ADMIN_PASSWORD=fixture-admin \
            POSTGRES_PASSWORD=fixture-postgres \
            REDIS_PASSWORD=fixture-redis \
            MEILI_MASTER_KEY=fixture-meili \
            JWT_SECRET=fixture-jwt \
            ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
            STORAGE_ENCRYPTION_KEY=abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789 \
            DB_ENC_PASSPHRASE=fixture-passphrase \
            "$@" "${compose_command[@]}" \
            --project-directory "${OPEN_ARCHIVER_TMPDIR}" \
            --project-name open-archiver-candidate --env-file /dev/null -f - \
            "${profile_args[@]}" config "${config_args[@]}"
}

assert_open_archiver_graph() {
    local document="$1"
    run jq -c '.services | keys' <<<"${document}"
    assert_success || return
    assert_output '["open-archiver","open-archiver-db","open-archiver-db-backup","open-archiver-init","open-archiver-meilisearch","open-archiver-migrate","open-archiver-tika","open-archiver-valkey"]' || return

    # Compare the complete dependency graph and readiness conditions, not just
    # a service count that could hide a missing init/migrate/backup dependency.
    run jq -e '
        (.services | all(.[]; (.profiles // []) == [])) and
        ((.services | with_entries(
            .value = ((.value.depends_on // {}) | with_entries(.value = .value.condition))
        )) == {
            "open-archiver": {
                "open-archiver-init": "service_completed_successfully",
                "open-archiver-migrate": "service_completed_successfully",
                "open-archiver-valkey": "service_healthy",
                "open-archiver-meilisearch": "service_healthy",
                "open-archiver-tika": "service_healthy"
            },
            "open-archiver-db": {"open-archiver-init": "service_completed_successfully"},
            "open-archiver-db-backup": {"open-archiver": "service_healthy"},
            "open-archiver-init": {},
            "open-archiver-meilisearch": {"open-archiver-init": "service_completed_successfully"},
            "open-archiver-migrate": {"open-archiver-db": "service_healthy"},
            "open-archiver-tika": {},
            "open-archiver-valkey": {"open-archiver-init": "service_completed_successfully"}
        })
    ' <<<"${document}"
    assert_success || return
    assert_output "true"
}

assert_open_archiver_valkey_limits() {
    local document="$1" maxmemory="$2" mem_limit="$3"
    run jq -c '.services["open-archiver-valkey"].command' <<<"${document}"
    assert_success || return
    assert_output "[\"valkey-server\",\"--requirepass\",\"fixture-redis\",\"--save\",\"300\",\"1\",\"--appendonly\",\"yes\",\"--appendfsync\",\"everysec\",\"--maxmemory\",\"${maxmemory}\",\"--maxmemory-policy\",\"noeviction\"]" || return

    # Compose serializes mem_limit as a byte-count STRING. Do not coerce it to a
    # number: assert both the normalized value and the actual output type.
    run jq -c '.services["open-archiver-valkey"].mem_limit' <<<"${document}"
    assert_success || return
    assert_output "\"${mem_limit}\""
}

@test "open_archiver_candidate: unset COMPOSE_PROFILES renders all eight services and their dependency graph" {
    # Keep coverage of the selection query used by generic dccd deployments.
    run render_open_archiver_candidate "" services
    assert_success
    local selected="${output}"

    run render_open_archiver_candidate "" json
    assert_success
    local document="${output}"
    assert_open_archiver_graph "${document}"

    run jq -e --arg selected "${selected}" \
        '(.services | keys) == ($selected | split("\n") | sort)' <<<"${document}"
    assert_success
    assert_output "true"
}

@test "open_archiver_candidate: empty COMPOSE_PROFILES renders all eight services and their dependency graph" {
    run render_open_archiver_candidate "" json COMPOSE_PROFILES=
    assert_success
    assert_open_archiver_graph "${output}"
}

@test "open_archiver_candidate: unrelated surveillance CLI and environment profiles retain the unprofiled stack" {
    run render_open_archiver_candidate surveillance json
    assert_success
    assert_open_archiver_graph "${output}"

    run render_open_archiver_candidate "" json COMPOSE_PROFILES=surveillance
    assert_success
    assert_open_archiver_graph "${output}"
}

@test "open_archiver_candidate: unprofiled Valkey defaults to 192mb with a 512m cap and noeviction" {
    run render_open_archiver_candidate "" json
    assert_success
    assert_open_archiver_valkey_limits "${output}" 192mb 536870912
}

@test "open_archiver_candidate: VALKEY_MAXMEMORY overrides the command independently of the container cap" {
    run render_open_archiver_candidate "" json VALKEY_MAXMEMORY=384mb
    assert_success
    assert_open_archiver_valkey_limits "${output}" 384mb 536870912
}

@test "open_archiver_candidate: VALKEY_MEM_LIMIT overrides the container cap independently of maxmemory" {
    run render_open_archiver_candidate "" json VALKEY_MEM_LIMIT=1024m
    assert_success
    assert_open_archiver_valkey_limits "${output}" 192mb 1073741824
}

@test "open_archiver_candidate: both explicit Valkey overrides are honored without enabling eviction" {
    run render_open_archiver_candidate "" json VALKEY_MAXMEMORY=384mb VALKEY_MEM_LIMIT=1024m
    assert_success
    assert_open_archiver_valkey_limits "${output}" 384mb 1073741824
}

@test "open_archiver_candidate: empty Valkey variables use colon-dash defaults independently" {
    run render_open_archiver_candidate "" json VALKEY_MAXMEMORY= VALKEY_MEM_LIMIT=
    assert_success
    assert_open_archiver_valkey_limits "${output}" 192mb 536870912

    run render_open_archiver_candidate "" json VALKEY_MAXMEMORY= VALKEY_MEM_LIMIT=1024m
    assert_success
    assert_open_archiver_valkey_limits "${output}" 192mb 1073741824

    run render_open_archiver_candidate "" json VALKEY_MAXMEMORY=384mb VALKEY_MEM_LIMIT=
    assert_success
    assert_open_archiver_valkey_limits "${output}" 384mb 536870912
}
