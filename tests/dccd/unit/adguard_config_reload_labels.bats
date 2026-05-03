#!/usr/bin/env bats
# Unit tests for AdGuard/Unbound config reload labels.

setup() {
    load '../helpers/common'
}

_service_has_config_hash_label() {
    local service="$1"
    awk -v svc="  ${service}:" '
        BEGIN { found_service = 0; found_label = 0 }
        $0 == svc { found_service = 1; next }
        found_service && /^  [A-Za-z0-9_-]+:/ { exit found_label ? 0 : 1 }
        found_service && index($0, "config.sha256=${CONFIG_HASH:-}") { found_label = 1 }
        END { if (!found_service || !found_label) exit 1 }
    ' "${REPO_ROOT}/services/adguard/compose.yaml"
}

@test "adguard: Unbound services recreate when config hash changes" {
    run _service_has_config_hash_label "adguard-unbound-init"
    assert_success

    run _service_has_config_hash_label "adguard-unbound"
    assert_success

    run _service_has_config_hash_label "adguard-unbound-flush"
    assert_success
}
