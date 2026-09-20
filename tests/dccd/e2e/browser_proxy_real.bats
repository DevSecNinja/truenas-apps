#!/usr/bin/env bats
# Opt-in public-image proxy and synthetic launcher tests. Never pull DHI.

load '../helpers/common'

policy_e2e_enabled() {
    [[ "${GITHUB_ACTIONS:-}" == "true" || "${DCCD_E2E:-}" == "1" ]]
}

setup_file() {
    policy_e2e_enabled || return 0
    local tool image
    for tool in docker jq yq; do
        command -v "${tool}" || return 1
    done
    docker info || return 1

    # Read YAML directly: compose config could load real service .env files.
    export POLICY_COMPOSE="${REPO_ROOT}/services/changedetection/compose.yaml"
    export POLICY_CONFIG="${REPO_ROOT}/services/shared/config/browser/squid.conf"
    export POLICY_LAUNCHER="${REPO_ROOT}/services/shared/config/browser/launch.mjs"
    export POLICY_PROBE="${BATS_TEST_DIRNAME}/browser_proxy_probe.py"
    export POLICY_PROXY_IMAGE POLICY_CLIENT_IMAGE
    POLICY_PROXY_IMAGE="$(yq -r '.services."changedetection-browser-proxy".image' "${POLICY_COMPOSE}")"
    POLICY_CLIENT_IMAGE="$(yq -r '.services.changedetection.image' "${POLICY_COMPOSE}")"
    # CI deliberately does not inspect, pull or run the auth-protected DHI image.
    # Fail rather than accessing any other registry if these source refs change.
    for image in "${POLICY_PROXY_IMAGE}" "${POLICY_CLIENT_IMAGE}"; do
        case "${image}" in
        docker.io/ubuntu/squid:* | docker.io/dgtlmoon/changedetection.io:*) ;;
        *)
            printf 'Core E2E permits only the public proxy/client images: %s\n' "${image}" >&2
            return 1
            ;;
        esac
        if [[ ! "${image}" =~ @sha256:[a-f0-9]{64}$ ]]; then
            printf 'Expected source-pinned image, got: %s\n' "${image}" >&2
            return 1
        fi
        docker pull "${image}" || return 1
    done
}

setup() {
    POLICY_CONTAINERS=()
    POLICY_NETWORKS=()
    POLICY_TMPDIR=""
    policy_e2e_enabled || return 0
    POLICY_TMPDIR="$(mktemp -d "${BATS_TMPDIR}/dccd-test.XXXXXX")"
    POLICY_PREFIX="dccd-proxy-${POLICY_TMPDIR##*/}"
    POLICY_PREFIX="${POLICY_PREFIX,,}"
    POLICY_LABEL="io.truenas-apps.browser-proxy-test=${POLICY_PREFIX}"
}

teardown() {
    local id failed=0
    for id in "${POLICY_CONTAINERS[@]}"; do
        if [[ "${BATS_TEST_COMPLETED:-}" != "1" ]]; then
            docker logs --tail 40 "${id}" || true
        fi
        # IDs are recorded only after successful creation by this test.
        # Remove its anonymous image volumes too, never any shared volumes.
        docker rm --force --volumes "${id}" || failed=1
    done
    for id in "${POLICY_NETWORKS[@]}"; do
        docker network rm "${id}" || failed=1
    done
    if [[ -n "${POLICY_TMPDIR}" ]]; then
        rm -rf "${POLICY_TMPDIR}"
    fi
    run test "${failed}" -eq 0
    assert_success
}

policy_network() {
    local suffix="$1"
    shift
    run docker network create --label "${POLICY_LABEL}" "$@" "${POLICY_PREFIX}-${suffix}"
    assert_success
    POLICY_LAST_NETWORK="${output}"
    POLICY_NETWORKS+=("${POLICY_LAST_NETWORK}")
}

policy_container() {
    local suffix="$1"
    shift
    run docker create --name "${POLICY_PREFIX}-${suffix}" --label "${POLICY_LABEL}" \
        --read-only --cap-drop ALL --security-opt no-new-privileges=true \
        --user 65534:65534 --pids-limit 100 --tmpfs /tmp "$@"
    assert_success
    POLICY_LAST_CONTAINER="${output}"
    POLICY_CONTAINERS+=("${POLICY_LAST_CONTAINER}")
    run docker start "${POLICY_LAST_CONTAINER}"
    assert_success
}

start_policy_fixture() {
    local online="${1:-false}"
    assert_file_exists "${POLICY_CONFIG}"
    assert_file_exists "${POLICY_PROBE}"
    policy_network internal --internal --ipv6=false
    POLICY_INTERNAL="${POLICY_LAST_NETWORK}"

    policy_container canary --network "${POLICY_INTERNAL}" \
        --network-alias private.fixture.test --memory 128m \
        --sysctl net.ipv4.ip_unprivileged_port_start=0 \
        --mount "type=bind,src=${POLICY_PROBE},dst=/probe.py,readonly" \
        --entrypoint python "${POLICY_CLIENT_IMAGE}" -u /probe.py serve
    POLICY_CANARY="${POLICY_LAST_CONTAINER}"

    policy_container client --network "${POLICY_INTERNAL}" --memory 256m \
        --mount "type=bind,src=${POLICY_PROBE},dst=/probe.py,readonly" \
        --entrypoint python "${POLICY_CLIENT_IMAGE}" \
        -c 'import time; time.sleep(600)'
    POLICY_CLIENT="${POLICY_LAST_CONTAINER}"

    policy_container proxy --network "${POLICY_INTERNAL}" --memory 256m \
        --network-alias policy-proxy --network-alias changedetection-browser-proxy \
        --mount "type=bind,src=${POLICY_CONFIG},dst=/etc/squid/squid.conf,readonly" \
        --entrypoint /usr/sbin/squid-gnutls "${POLICY_PROXY_IMAGE}" \
        -N -f /etc/squid/squid.conf
    POLICY_PROXY="${POLICY_LAST_CONTAINER}"
    if [[ "${online}" == "true" ]]; then
        policy_network egress
        run docker network connect "${POLICY_LAST_NETWORK}" "${POLICY_PROXY}"
        assert_success
    fi

    run docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${POLICY_CANARY}"
    assert_success
    POLICY_PRIVATE_IP="${output}"
    run docker exec "${POLICY_CLIENT}" python /probe.py ready "${POLICY_PRIVATE_IP}"
    assert_success
    assert_output "proxy ready; controlled private endpoint reachable"
    run docker logs "${POLICY_CANARY}"
    assert_success
    POLICY_CANARY_BASELINE="${output}"
}

assert_canary_untouched() {
    # The server logs TCP acceptance, including connections without HTTP data.
    run docker logs "${POLICY_CANARY}"
    assert_success
    assert_output "${POLICY_CANARY_BASELINE}"
}

check_source_browser_policy() {
    local app="$1" document
    # Expand Karakeep's merged environment without reading any .env files.
    document="$(yq --yaml-fix-merge-anchor-to-spec=true -o=json 'explode(.)' "${REPO_ROOT}/services/${app}/compose.yaml")" || return 1
    printf '%s\n' "${document}" | jq -e --arg app "${app}" --arg image "${POLICY_PROXY_IMAGE}" '
      def networks: if type == "array" then . else keys end;
      .services[$app + "-chrome"] as $browser |
      .services[$app + "-browser-proxy"] as $proxy |
      (($browser.profiles // []) | length == 0) and
      (($proxy.profiles // []) | length == 0) and
      ((.services[$app].profiles // []) | length == 0) and
      (.services[$app].depends_on[$app + "-chrome"].condition == "service_healthy") and
      (if $app == "changedetection" then
        (.services.changedetection.environment.DEFAULT_FETCH_BACKEND == "html_webdriver") and
        (.services.changedetection.environment.PLAYWRIGHT_DRIVER_URL == "http://172.30.100.22:9222") and
        ($browser.networks."changedetection-browser".ipv4_address == "172.30.100.22") and
        (.services.changedetection.environment.PLAYWRIGHT_BROWSER_TYPE == "chromium") and
        (.services.changedetection.environment.FAST_PUPPETEER_CHROME_FETCHER == "false")
      else
        ((.services."karakeep-workers".profiles // []) | length == 0) and
        (.services."karakeep-workers".depends_on.karakeep.condition == "service_healthy") and
        (all((.services.karakeep, .services."karakeep-workers");
          (.environment.CRAWLER_HEADLESS_BROWSER == "true") and
          (.environment.BROWSER_WEB_URL == "http://karakeep-chrome:9222")))
      end) and
      ($browser.environment.BROWSER_ALLOW_UNPATCHED_VERSION == "153.0.8010.47") and
      ($browser.image | test("^dhi\\.io/playwright:[^@]+(@sha256:[a-f0-9]{64})?$")) and
      ($browser.user == "65532:65532") and
      ($browser.entrypoint == ["node", "/opt/browser/launch.mjs"]) and
      ($browser.volumes == ["../shared/config/browser/launch.mjs:/opt/browser/launch.mjs:ro"]) and
      ($browser.networks | networks) == [$app + "-browser"] and
      ($browser.network_mode == null) and
      (($browser.ports // []) | length == 0) and
      (.networks[$app + "-browser"].internal == true) and
      ((.networks[$app + "-browser-egress"].internal // false) == false) and
      ($proxy.networks | networks | sort) ==
        ([$app + "-browser", $app + "-browser-egress"] | sort) and
      ($browser.depends_on[$app + "-browser-proxy"].condition == "service_healthy") and
      ([$browser.command[] | select(startswith("--proxy-server"))] ==
        ["--proxy-server=http://" + $app + "-browser-proxy:3128"]) and
      ([$browser.command[] | select(startswith("--proxy-bypass-list"))] ==
        ["--proxy-bypass-list=<-loopback>"]) and
      ([$browser.command[] | select(startswith("--force-webrtc-ip-handling-policy"))] ==
        ["--force-webrtc-ip-handling-policy=disable_non_proxied_udp"]) and
      ($browser.command | index("--disable-quic") != null) and
      ([$browser.command[] | select(test("^--(no-proxy-server|proxy-auto-detect|proxy-pac-url|enable-quic)"))] | length == 0) and
      ($proxy.image == $image) and
      ($proxy.entrypoint == ["/usr/sbin/squid-gnutls"]) and
      ($proxy.command == ["-N", "-f", "/etc/squid/squid.conf"]) and
      ($proxy.volumes == ["../shared/config/browser/squid.conf:/etc/squid/squid.conf:ro"]) and
      ($proxy.read_only == true) and ($proxy.user == "65534:65534") and
      ($proxy.cap_drop == ["ALL"]) and
      ($proxy.security_opt | index("no-new-privileges=true") != null) and
      (($proxy.ports // []) | length == 0)
    '
}

@test "browser_proxy: both apps enable healthy DHI browsers with the exact exception and mandatory proxy isolation" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    local app
    for app in changedetection karakeep; do
        run check_source_browser_policy "${app}"
        assert_success
        assert_output "true"
    done
}

@test "browser_proxy: HTTP private literals, DNS names and non-global IPv6 receive Squid 403 before connection" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_policy_fixture
    run docker exec "${POLICY_CLIENT}" python /probe.py deny-http "${POLICY_PRIVATE_IP}"
    assert_success
    assert_output "HTTP: 8 destinations denied with Squid 403"
    assert_canary_untouched
}

@test "browser_proxy: CONNECT denies private DNS, literals and IPv4-mapped IPv6 before connection" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_policy_fixture
    run docker exec "${POLICY_CLIENT}" python /probe.py deny-connect "${POLICY_PRIVATE_IP}"
    assert_success
    assert_output "CONNECT: 8 destinations denied with Squid 403"
    assert_canary_untouched
}

@test "browser_proxy: non-web ports and CONNECT outside 443 receive Squid 403" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_policy_fixture
    run docker exec "${POLICY_CLIENT}" python /probe.py deny-ports
    assert_success
    assert_output "ports: 8 requests denied with Squid 403"
    assert_canary_untouched
}

@test "browser_proxy: public HTTP and certificate-verified HTTPS are allowed" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_policy_fixture true
    run docker exec "${POLICY_CLIENT}" python /probe.py public
    assert_success
    assert_line "HTTP example.com: 200"
    assert_line "HTTPS example.com: 200 (verified TLS)"
    assert_canary_untouched
}

start_launcher_fixture() {
    assert_file_exists "${POLICY_LAUNCHER}"
    assert_file_exists "${POLICY_PROBE}"
    # Mount an executable copy of this test's Python fixture at the fixed
    # Chromium path. Normalize its shebang only in the disposable copy.
    cp "${POLICY_PROBE}" "${POLICY_TMPDIR}/chromium-headless-shell"
    sed -i 's/\r$//' "${POLICY_TMPDIR}/chromium-headless-shell"
    chmod 0755 "${POLICY_TMPDIR}/chromium-headless-shell"
    policy_container launcher --network none --memory 256m --user 65532:65532 \
        --mount "type=bind,src=${POLICY_PROBE},dst=/probe.py,readonly" \
        --mount "type=bind,src=${POLICY_LAUNCHER},dst=/opt/browser/launch.mjs,readonly" \
        --mount "type=bind,src=${POLICY_TMPDIR}/chromium-headless-shell,dst=/usr/lib/chromium/chromium-headless-shell,readonly" \
        --entrypoint python "${POLICY_CLIENT_IMAGE}" \
        -c 'import time; time.sleep(600)'
    POLICY_LAUNCHER_CLIENT="${POLICY_LAST_CONTAINER}"
}

@test "browser_launcher: failed, malformed and below-minimum versions fail closed by default" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_launcher_fixture
    run docker exec "${POLICY_LAUNCHER_CLIENT}" python /probe.py launcher-reject
    assert_success
    assert_line "launcher: failed version probe rejected before spawn"
    assert_line "launcher: malformed version rejected before spawn"
    assert_line "launcher: Chromium 153.0.8010.47 rejected before spawn"
    assert_line "launcher: Chromium 153.0.8010.51 rejected before spawn"
}

@test "browser_launcher: mismatched and unsupported overrides cannot bypass the version floor" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_launcher_fixture
    run docker exec "${POLICY_LAUNCHER_CLIENT}" python /probe.py launcher-reject-override
    assert_success
    assert_output "launcher: 7 mismatched or unsupported overrides rejected before spawn"
}

@test "browser_launcher: only the exact 153.0.8010.47 exception warns and relays until supervised SIGTERM" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_launcher_fixture
    local -a browser_args
    run yq -r '.services."changedetection-chrome".command[]' "${POLICY_COMPOSE}"
    assert_success
    mapfile -t browser_args <<<"${output}"
    run docker exec "${POLICY_LAUNCHER_CLIENT}" python /probe.py launcher-exception "${browser_args[@]}"
    assert_success
    assert_line "launcher: exact 153.0.8010.47 exception warned before spawn and relayed CDP"
    assert_line "launcher: SIGTERM reaped fake Chromium and closed CDP sockets"
}

@test "browser_launcher: patched versions relay without warnings even with the stale exception" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_launcher_fixture
    local -a browser_args
    run yq -r '.services."changedetection-chrome".command[]' "${POLICY_COMPOSE}"
    assert_success
    mapfile -t browser_args <<<"${output}"
    run docker exec "${POLICY_LAUNCHER_CLIENT}" python /probe.py launcher-patched "${browser_args[@]}"
    assert_success
    assert_line "launcher: Chromium 153.0.8010.52 relayed without warning (exception unset)"
    assert_line "launcher: Chromium 153.0.8010.52 relayed without warning (stale exception set)"
    assert_line "launcher: Chromium 153.0.8010.53 relayed without warning (stale exception set)"
    assert_line "launcher: Chromium 154.0.0.0 relayed without warning (stale exception set)"
    assert_line "launcher: SIGTERM reaped fake Chromium and closed CDP sockets"
}

@test "browser_launcher: unexpected clean or failed Chromium exit closes the relay and fails the supervisor" {
    policy_e2e_enabled || skip "E2E tests require DCCD_E2E=1"
    start_launcher_fixture
    run docker exec "${POLICY_LAUNCHER_CLIENT}" python /probe.py launcher-exit
    assert_success
    assert_line "launcher: unexpected child exit 0 failed closed"
    assert_line "launcher: unexpected child exit 7 failed closed"
}
