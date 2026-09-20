#!/usr/bin/env bats
# Offline source-policy checks and daemonless task-limit rendering.

setup_file() {
    local library tool
    # common.bash otherwise auto-downloads missing libraries.
    for library in bats-support bats-assert bats-file; do
        if [[ ! -f "${BATS_TEST_DIRNAME}/../../libs/${library}/load.bash" ]]; then
            printf 'Required preinstalled BATS library missing: %s\n' "${library}" >&2
            return 1
        fi
    done
    for tool in yq docker-compose jq; do
        command -v "${tool}" || return 1
    done
}

setup() {
    load '../helpers/common'
    # Do not call common_setup: these checks need real tools, not mocks.
    BROWSER_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
    cd "${BROWSER_TMPDIR}"
    declare -gA EXPECTED_LIMITS=(
        [karakeep]='{"karakeep":100,"karakeep-browser-proxy":100,"karakeep-chrome":BROWSER_LIMIT,"karakeep-db-backup":100,"karakeep-init":50,"karakeep-meilisearch":100,"karakeep-workers":100}'
        [changedetection]='{"changedetection":100,"changedetection-browser-proxy":100,"changedetection-chrome":BROWSER_LIMIT,"changedetection-init":100}'
    )
}

teardown() {
    if [[ -n "${BROWSER_TMPDIR:-}" ]]; then
        rm -rf "${BROWSER_TMPDIR}"
    fi
}

render_browser_task_limits() {
    local app="$1"
    shift
    set -o pipefail
    # Extract only image/task-limit fields from every real service. No env_file,
    # secrets, dependencies or unrelated interpolation enter this render.
    yq --yaml-fix-merge-anchor-to-spec=true -o=json '
        .services[] |= {"image": .image, "pids_limit": .pids_limit} |
        {"services": .services}
    ' "${REPO_ROOT}/services/${app}/compose.yaml" |
        env -i PATH="${PATH}" HOME="${BROWSER_TMPDIR}" "$@" \
            docker-compose --project-directory "${BROWSER_TMPDIR}" \
            --project-name browser-task-limits --env-file /dev/null -f - \
            config --format json |
        jq -cS '.services | with_entries(.value = .value.pids_limit)'
}

@test "browser_task_limits: both browsers render 512 by default without changing non-browser limits" {
    local app
    for app in karakeep changedetection; do
        run render_browser_task_limits "${app}"
        assert_success
        assert_output "${EXPECTED_LIMITS[$app]//BROWSER_LIMIT/512}"
    done
}

@test "browser_task_limits: each app honors CHROME_PIDS_LIMIT=256 only for its browser" {
    local app
    for app in karakeep changedetection; do
        run render_browser_task_limits "${app}" CHROME_PIDS_LIMIT=256
        assert_success
        assert_output "${EXPECTED_LIMITS[$app]//BROWSER_LIMIT/256}"
    done
}

@test "browser_task_limits: source retains Node launcher, healthy proxy dependency and browser isolation" {
    local app document
    for app in karakeep changedetection; do
        run yq --yaml-fix-merge-anchor-to-spec=true -o=json 'explode(.)' \
            "${REPO_ROOT}/services/${app}/compose.yaml"
        assert_success
        document="${output}"
        run jq -e --arg app "${app}" '
            def network_names: if type == "array" then . else keys end;
            .services[$app + "-chrome"] as $browser |
            ($browser.pids_limit == "${CHROME_PIDS_LIMIT:-512}") and
            ($browser.image | startswith("dhi.io/playwright:")) and
            ($browser.entrypoint == ["node", "/opt/browser/launch.mjs"]) and
            ($browser.volumes == ["../shared/config/browser/launch.mjs:/opt/browser/launch.mjs:ro"]) and
            ($browser.depends_on[$app + "-browser-proxy"].condition == "service_healthy") and
            (($browser.networks | network_names) == [$app + "-browser"]) and
            ($browser.network_mode == null) and
            (($browser.ports // []) | length == 0) and
            (.networks[$app + "-browser"].internal == true)
        ' <<<"${document}"
        assert_success
        assert_output "true"
    done
}
