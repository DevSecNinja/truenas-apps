#!/usr/bin/env bats
# Unit tests for check_dhi_login() and auto_login_dhi()

setup() {
    load '../helpers/common'
    load '../helpers/mocks'
    common_setup

    # Create a services dir with a dummy app
    mkdir -p "${BASE_DIR}/services/myapp"
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# check_dhi_login — no dhi.io images in scope
# ---------------------------------------------------------------------------

@test "check_dhi_login: passes when no compose files exist" {
    run check_dhi_login
    assert_success
}

@test "check_dhi_login: passes when compose files have no dhi.io images" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: docker.io/library/nginx:alpine@sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
YAML
    run check_dhi_login
    assert_success
}

@test "check_dhi_login: passes when APP_FILTER excludes dhi.io app" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: dhi.io/nginx:1-debian13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    mkdir -p "${BASE_DIR}/services/otherapp"
    cat >"${BASE_DIR}/services/otherapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: docker.io/library/redis:alpine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    APP_FILTER="otherapp"
    run check_dhi_login
    assert_success
}

@test "check_dhi_login: passes in server mode when scoped app has no dhi.io image" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: docker.io/library/nginx:alpine@sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
YAML
    SERVER_APPS=("myapp")
    run check_dhi_login
    assert_success
}

# ---------------------------------------------------------------------------
# check_dhi_login — dhi.io images present, login status varies
# ---------------------------------------------------------------------------

@test "check_dhi_login: fails when dhi.io image in scope and not logged in" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: dhi.io/traefik:3.6-debian13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    # cat mock returns empty (no docker config)
    create_mock "cat" 0 ""
    run check_dhi_login
    assert_failure
    assert_output --partial "not logged in"
}

@test "check_dhi_login: fails when docker config exists but has no dhi.io entry" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: dhi.io/redis:8-debian13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    # docker config without dhi.io
    create_mock "cat" 0 '{"auths":{"index.docker.io":{"auth":"dummytoken"}}}'
    run check_dhi_login
    assert_failure
    assert_output --partial "not logged in"
}

@test "check_dhi_login: passes when dhi.io entry exists in docker config" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: dhi.io/traefik:3.6-debian13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    create_mock "cat" 0 '{"auths":{"dhi.io":{"auth":"dummytoken"},"index.docker.io":{}}}'
    run check_dhi_login
    assert_success
    assert_output --partial "dhi.io authentication verified"
}

@test "check_dhi_login: passes when dhi.io entry is in credHelpers section" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: dhi.io/traefik:3.6-debian13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    create_mock "cat" 0 '{"credHelpers":{"dhi.io":"desktop"}}'
    run check_dhi_login
    assert_success
    assert_output --partial "dhi.io authentication verified"
}

@test "check_dhi_login: error message mentions automated and manual options" {
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: dhi.io/traefik:3.6-debian13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    create_mock "cat" 0 ""
    run check_dhi_login
    assert_failure
    assert_output --partial "DOCKERHUB_USERNAME"
    assert_output --partial "DOCKERHUB_TOKEN"
    assert_output --partial "sudo docker login dhi.io"
    assert_output --partial "docs/INFRASTRUCTURE.md"
}

@test "check_dhi_login: server mode scans only assigned apps" {
    # myapp has a dhi.io image but is NOT in SERVER_APPS
    cat >"${BASE_DIR}/services/myapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: dhi.io/traefik:3.6-debian13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML
    mkdir -p "${BASE_DIR}/services/otherapp"
    cat >"${BASE_DIR}/services/otherapp/compose.yaml" <<'YAML'
---
services:
  app:
    image: docker.io/library/nginx:alpine@sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
YAML
    SERVER_APPS=("otherapp")
    run check_dhi_login
    assert_success
}

# ---------------------------------------------------------------------------
# auto_login_dhi
# ---------------------------------------------------------------------------

@test "auto_login_dhi: no-op when services/shared/env/.env does not exist" {
    run auto_login_dhi
    assert_success
    assert_output ""
}

@test "auto_login_dhi: no-op when shared .env has no DOCKERHUB_USERNAME" {
    mkdir -p "${BASE_DIR}/services/shared/env"
    echo "SOME_OTHER_VAR=value" >"${BASE_DIR}/services/shared/env/.env"
    run auto_login_dhi
    assert_success
    assert_output ""
}

@test "auto_login_dhi: no-op when shared .env has no DOCKERHUB_TOKEN" {
    mkdir -p "${BASE_DIR}/services/shared/env"
    echo "DOCKERHUB_USERNAME=myuser" >"${BASE_DIR}/services/shared/env/.env"
    run auto_login_dhi
    assert_success
    assert_output ""
}

@test "auto_login_dhi: logs in to dhi.io and docker.io when both credentials are present" {
    mkdir -p "${BASE_DIR}/services/shared/env"
    printf 'DOCKERHUB_USERNAME=myuser\nDOCKERHUB_TOKEN=mytoken\n' \
        >"${BASE_DIR}/services/shared/env/.env"
    # docker login succeeds
    create_mock "docker" 0 ""
    run auto_login_dhi
    assert_success
    assert_output --partial "Logging in to dhi.io as myuser"
    assert_output --partial "dhi.io login succeeded"
    assert_output --partial "Logging in to docker.io as myuser"
    assert_output --partial "docker.io login succeeded"
}

@test "auto_login_dhi: passes username to docker login" {
    mkdir -p "${BASE_DIR}/services/shared/env"
    printf 'DOCKERHUB_USERNAME=testuser\nDOCKERHUB_TOKEN=testtoken\n' \
        >"${BASE_DIR}/services/shared/env/.env"
    create_mock "docker" 0 ""
    auto_login_dhi
    assert_mock_called_with "docker" "--username testuser"
}

@test "auto_login_dhi: fails when docker login returns non-zero" {
    mkdir -p "${BASE_DIR}/services/shared/env"
    printf 'DOCKERHUB_USERNAME=baduser\nDOCKERHUB_TOKEN=badtoken\n' \
        >"${BASE_DIR}/services/shared/env/.env"
    create_mock "docker" 1 ""
    run auto_login_dhi
    assert_failure
    assert_output --partial "dhi.io login failed"
    assert_output --partial "services/shared/env/secret.sops.env"
}

# ---------------------------------------------------------------------------
# decrypt_sops_files — shared secrets included in server mode
# ---------------------------------------------------------------------------

@test "decrypt_sops_files: includes shared secret in server mode" {
    SOPS_AGE_KEY_FILE="${BASE_DIR}/age.key"
    touch "${SOPS_AGE_KEY_FILE}"

    mkdir -p "${SOPS_INSTALL_DIR}"
    SOPS_BIN="${SOPS_INSTALL_DIR}/sops-${SOPS_VERSION}"
    cat >"${SOPS_BIN}" <<'MOCK'
#!/bin/bash
if [ "$1" = "-d" ]; then
    echo "DOCKERHUB_USERNAME=testuser"
    exit 0
fi
exit 1
MOCK
    chmod +x "${SOPS_BIN}"

    mkdir -p "${BASE_DIR}/services/shared/env"
    touch "${BASE_DIR}/services/shared/env/secret.sops.env"

    SERVER_APPS=("otherapp")
    run decrypt_sops_files
    assert_success
    assert_file_exists "${BASE_DIR}/services/shared/env/.env"
}
