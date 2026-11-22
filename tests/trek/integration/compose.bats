#!/usr/bin/env bats
# Offline tracked configuration and synthetic env rendering only; no production secrets or daemon.
# shellcheck disable=SC2016

load '../helpers/common'

setup_file() {
	trek_setup_file || return 1
	yq --version || return 1
	command -v node || return 1
	TREK_COMPOSE_CLI="$(command -v docker-cli-plugin-docker-compose)" || return 1
	"${TREK_COMPOSE_CLI}" version || return 1
	export TREK_COMPOSE_CLI
	TREK_INIT_COMMAND="$(yq -r '.services."trek-init".command[2]' \
		"${TREK_REPO_ROOT}/services/trek/compose.yaml")" || return 1
	TREK_IDENTITY_COMMAND="$(yq -r '.services."trek-db-backup".environment.CONTAINER_INIT_PRE_COMMAND' \
		"${TREK_REPO_ROOT}/services/trek/compose.yaml")" || return 1
	export TREK_INIT_COMMAND TREK_IDENTITY_COMMAND
}

setup() {
	trek_setup
	# These stubs validate exact arguments but NEVER touch /data or /etc/group.
	trek_mock mkdir chown chmod grep id addgroup adduser
}

teardown() {
	trek_teardown
}

@test "compose: every candidate service requires the trek-candidate profile" {
	assert_compose_value '.services | keys | sort | join(",")' 'trek,trek-db-backup,trek-init'
	assert_compose_value '.services[] | .profiles | join(",")' \
		$'trek-candidate\ntrek-candidate\ntrek-candidate'
}

@test "compose: no candidate service publishes ports or uses host networking" {
	assert_compose_value \
		'[.services[] | select(has("ports") or (.network_mode == "host"))] | length' '0'
	assert_compose_value '.services."trek-init".network_mode' none
	assert_compose_value '.services."trek-db-backup".network_mode' none
}

@test "compose: the app joins only its nonexternal candidate network" {
	assert_compose_value '.services.trek.networks | join(",")' trek-frontend
	assert_compose_value '.networks | keys | join(",")' trek-frontend
	assert_compose_value '.networks."trek-frontend".name' trek-frontend
	assert_compose_value '.networks."trek-frontend".driver' bridge
	assert_compose_value '.networks."trek-frontend".external // false' false
}

@test "compose: upstream hosted services are off without a supplied services key" {
	assert_compose_value '.services.trek.environment.TREK_SERVICES' off
	assert_compose_value '.services.trek.environment | has("TREK_SERVICES_KEY")' false
}

@test "compose: native OIDC-only uses Pocket ID at id.DOMAINNAME without credential defaults" {
	assert_compose_value '.services.trek.environment.OIDC_ISSUER' 'https://id.${DOMAINNAME}'
	assert_compose_value '.services.trek.environment.OIDC_ONLY' true
	assert_compose_value '.services.trek.environment.OIDC_CLIENT_ID' '${OIDC_CLIENT_ID:-}'
	assert_compose_value '.services.trek.environment.OIDC_CLIENT_SECRET' '${OIDC_CLIENT_SECRET:-}'
	assert_compose_value '.services.trek.environment.OIDC_SCOPE' 'openid email profile'
	assert_compose_value '.services.trek.environment.OIDC_USERNAME_CLAIM' preferred_username
	assert_compose_value '.services.trek.environment.APP_URL' 'https://trek.${DOMAINNAME}'
	assert_compose_value '.services.trek.environment.ALLOWED_ORIGINS' 'https://trek.${DOMAINNAME}'
}

@test "compose: candidate routing does not reintroduce shared forward authentication" {
	assert_compose_value '.services.trek.labels[] |
    select(test("^traefik.http.routers.trek-rtr.middlewares="))' \
		'traefik.http.routers.trek-rtr.middlewares=chain-no-auth@file'
	assert_compose_value '[... | select(tag == "!!str") |
    select(test("traefik-forward-auth|chain-auth@file"))] | length' '0'
}

@test "compose: app identity is exactly 3134 and startup waits for the fail-closed init" {
	assert_compose_value '.services.trek.user' '3134:3134'
	assert_compose_value '.services.trek.depends_on."trek-init".condition' service_completed_successfully
	assert_compose_value '.services."trek-db-backup".depends_on.trek.condition' service_healthy
	assert_compose_value '.services."trek-init".command[0:2] | join(",")' 'sh,-ec'
}

@test "compose: backup invokes the verifier with required encryption and a read-only source" {
	assert_compose_value '.services."trek-db-backup".command | join(",")' 'bash,/trek-config/backup.sh'
	assert_compose_value '.services."trek-db-backup".environment.DEFAULT_ENCRYPT' TRUE
	assert_compose_value '.services."trek-db-backup".environment.DEFAULT_ENCRYPT_PASSPHRASE' '${DB_ENC_PASSPHRASE:-}'
	assert_compose_value '.services."trek-db-backup".environment.DEFAULT_CHECKSUM' SHA1
	assert_compose_value '.services."trek-db-backup".environment.DEFAULT_COMPRESSION' ZSTD
	assert_compose_value '.services."trek-db-backup".environment.MODE' MANUAL
	assert_compose_value '.services."trek-db-backup".environment.CONTAINER_ENABLE_SCHEDULING' FALSE
	assert_compose_value '.services."trek-db-backup".environment.DBBACKUP_USER' trekbackup
	assert_compose_value '.services."trek-db-backup".environment.DBBACKUP_GROUP' trekbackup
	assert_compose_value '.services."trek-db-backup".environment.DB01_HOST' /trek-data/travel.db
	assert_compose_value '.services."trek-db-backup".volumes | sort | join(",")' \
		'./backups/db-backup:/backup,./config:/trek-config:ro,./data/app:/trek-data:ro'
}

@test "compose: rendered backup receives only its explicit encryption secret, not the app env file" {
	local app_directory="${TEST_ROOT}/services/trek"
	local shared_directory="${TEST_ROOT}/services/shared/env"
	mkdir -p "${app_directory}" "${shared_directory}"
	# Copy only these tracked files, never a checkout .env or secret.sops.env.
	cp -- "${TREK_COMPOSE}" "${app_directory}/compose.yaml"
	cp -- "${TREK_REPO_ROOT}/services/shared/env/tz.env" "${shared_directory}/tz.env"
	assert_file_exists "${app_directory}/compose.yaml"
	assert_file_exists "${shared_directory}/tz.env"
	touch "${app_directory}/.env"
	# Existing yq dotenv writer: all fixture values are synthetic and distinct.
	run yq -i -p=yaml -o=props '{
		"DOMAINNAME": "synthetic-trek.invalid",
		"ENCRYPTION_KEY": "0000000000000000000000000000000000000000000000000000000000000000",
		"OIDC_CLIENT_ID": "synthetic-trek-client-id",
		"OIDC_CLIENT_SECRET": "synthetic-trek-client-secret",
		"JWT_SECRET": "synthetic-trek-jwt-secret",
		"DB_ENC_PASSPHRASE": "synthetic-trek-gpg-passphrase"
	}' "${app_directory}/.env"
	assert_success
	assert_file_exists "${app_directory}/.env"
	run yq -p=props -o=json '.' "${app_directory}/.env"
	assert_success
	local fixture="${output}"
	run yq -p=props -o=yaml -r '.TZ' "${shared_directory}/tz.env"
	assert_success
	local timezone="${output}"

	# Resolve env_file for real, from the isolated copy only. No inherited
	# credentials, COMPOSE_* selection, production working directory or daemon.
	cd "${app_directory}" || return 1
	run env -i PATH="${ORIGINAL_PATH}" HOME="${TEST_ROOT}" TMPDIR="${WORK_ROOT}" \
		LC_ALL=C COMPOSE_DISABLE_ENV_FILE=true "${TREK_COMPOSE_CLI}" \
		--ansi never --progress quiet \
		--project-directory "${app_directory}" \
		--project-name "trek-boundary-${BATS_TEST_NUMBER}-$$" \
		--env-file "${app_directory}/.env" \
		-f "${app_directory}/compose.yaml" --profile trek-candidate config --format json
	assert_success
	local document="${output}"
	run node -e '
		const assert = require("node:assert/strict");
		const fixture = JSON.parse(process.argv[1]);
		const { services } = JSON.parse(require("node:fs").readFileSync(0, "utf8"));
		// Positive control: init really loaded .env, including unrelated JWT.
		for (const [key, value] of Object.entries(fixture)) {
			assert.equal(services["trek-init"].environment[key], value, `init must load ${key}`);
		}
		const app = services.trek.environment;
		assert.equal(app.ENCRYPTION_KEY, fixture.ENCRYPTION_KEY);
		assert.equal(app.OIDC_CLIENT_SECRET, fixture.OIDC_CLIENT_SECRET);
		assert.equal(app.APP_URL, `https://trek.${fixture.DOMAINNAME}`);
		const backup = services["trek-db-backup"].environment;
		assert.equal(backup.TZ, process.argv[2]);
		assert.equal(backup.DEFAULT_ENCRYPT, "TRUE");
		assert.equal(backup.DEFAULT_ENCRYPT_PASSPHRASE, fixture.DB_ENC_PASSPHRASE);
		const { DEFAULT_ENCRYPT_PASSPHRASE, ...otherEnvironment } = backup;
		const remainder = JSON.stringify(otherEnvironment);
		for (const [key, value] of Object.entries(fixture)) {
			assert.equal(Object.hasOwn(backup, key), false, `backup must not inherit ${key}`);
			assert.equal(remainder.includes(value), false, `backup must not leak ${key} under another name`);
		}
		console.log("true");
	' "${fixture}" "${timezone}" <<<"${document}"
	assert_success
	assert_output true
	assert_dir_not_exists "${app_directory}/data"
	assert_dir_not_exists "${app_directory}/backups"
}

@test "compose_renovate: every Trek image update including digests requires ungrouped manual review" {
	# Reuse the built-in Node VM precedent in open-archiver/compatibility.test.mjs.
	# Local JSON5 policy only, not remote preset resolution or schema validation.
	run node -e '
		const assert = require("node:assert/strict");
		const source = require("node:fs").readFileSync(process.argv[1], "utf8");
		const config = JSON.parse(JSON.stringify(require("node:vm").runInNewContext(
			`(${source})`, {},
			{ timeout: 1000, contextCodeGeneration: { strings: false, wasm: false } }
		)));
		const rules = config.packageRules;
		const matches = rules.filter(rule =>
			rule.matchFileNames?.includes("services/trek/compose.yaml"));
		assert.equal(matches.length, 1, "expected exactly one Trek review rule");
		const rule = matches[0];
		assert.deepEqual(rule.matchFileNames, ["services/trek/compose.yaml"]);
		assert.deepEqual(rule.matchDatasources, ["docker"]);
		assert.equal(Object.hasOwn(rule, "matchUpdateTypes"), false, "digest updates must also require review");
		assert.deepEqual(Object.keys(rule).filter(key => key.startsWith("match")).sort(),
			["matchDatasources", "matchFileNames"], "must cover app, init and backup without additional selectors");
		assert.equal(rule.automerge, false, "every image update needs manual review");
		assert.equal(rule.groupName, null, "image updates must not inherit grouping");
		assert.equal(rules.indexOf(rule), rules.length - 1, "keep Trek review last to prevent local overrides");
		console.log("true");
	' "${TREK_REPO_ROOT}/renovate.json5"
	assert_success
	assert_output true
}

@test "trek_init: populated dummy inputs reach exact 3134 ownership and private permissions" {
	run_trek_init
	assert_success
	assert_output ""
	assert_called mkdir
	assert_called chown
	assert_called chmod
}

@test "trek_init: missing OIDC client ID fails before touching runtime paths" {
	run_trek_init OIDC_CLIENT_ID
	assert_failure 1
	assert_output 'ERROR: TREK requires a populated OIDC_CLIENT_ID'
	assert_init_untouched
}

@test "trek_init: missing OIDC client secret fails before touching runtime paths" {
	run_trek_init OIDC_CLIENT_SECRET
	assert_failure 1
	assert_output 'ERROR: TREK requires a populated OIDC_CLIENT_SECRET'
	assert_init_untouched
}

@test "trek_init: empty or placeholder OIDC client inputs fail closed" {
	local name value
	for name in OIDC_CLIENT_ID OIDC_CLIENT_SECRET; do
		for value in '' GENERATE CHANGE_ME; do
			run_trek_init "${name}" "${value}"
			assert_failure 1
			assert_output "ERROR: TREK requires a populated ${name}"
			assert_init_untouched
		done
	done
}

@test "trek_init: missing domain or encryption inputs also fail before filesystem changes" {
	local name
	for name in DOMAINNAME ENCRYPTION_KEY DB_ENC_PASSPHRASE; do
		run_trek_init "${name}"
		assert_failure 1
		assert_output "ERROR: TREK requires a populated ${name}"
		assert_init_untouched
	done
}

@test "backup_identity: accepts an existing exact 3134 user and group without recreating them" {
	run_backup_identity true 3134 3134
	assert_success
	assert_output ""
	assert_called id
	assert_not_called addgroup
	assert_not_called adduser
}

@test "backup_identity: creates a missing user and group with exactly 3134" {
	run_backup_identity false 3134 3134
	assert_success
	assert_output ""
	assert_called addgroup
	assert_called adduser
}

@test "backup_identity: rejects either a mismatched UID or a mismatched GID" {
	run_backup_identity true 3133 3134
	assert_failure 1
	assert_output 'ERROR: Invalid TREK backup identity'
	run_backup_identity true 3134 3133
	assert_failure 1
	assert_output 'ERROR: Invalid TREK backup identity'
}

@test "compose_activation: shared Traefik has no active candidate network or static route" {
	local file paths
	assert_file_exists "${TREK_REPO_ROOT}/services/traefik/compose.yaml"
	run "${REAL_FIND}" "${TREK_REPO_ROOT}/services/traefik" \
		-type f \( -name '*.yaml' -o -name '*.yml' \) ! -name 'compose.trek.yaml'
	assert_success
	refute_output ""
	paths="${output}"
	while IFS= read -r file; do
		assert_no_trek_yaml "${file}"
	done <<<"${paths}"
}

@test "compose_activation: tracked DNS configuration has no active TREK record" {
	local file paths
	assert_no_trek_yaml "${TREK_REPO_ROOT}/services/adguard/config/conf/AdGuardHome.yaml"
	assert_dir_exists "${TREK_REPO_ROOT}/services/adguard/config/unbound"
	run "${REAL_FIND}" "${TREK_REPO_ROOT}/services/adguard/config/unbound" \
		-type f -name '*.conf'
	assert_success
	refute_output ""
	paths="${output}"
	while IFS= read -r file; do
		assert_file_exists "${file}"
		run active_trek_conf "${file}"
		assert_failure 1
		assert_output ""
	done <<<"${paths}"
}

@test "compose_activation: deployment and host-account registries do not adopt the candidate" {
	run yq -r '.apps | has("trek")' "${TREK_REPO_ROOT}/truenas-apps.json"
	assert_success
	assert_output false
	run yq -r '.servers[].apps // [] | .[] | select(. == "trek")' "${TREK_REPO_ROOT}/servers.yaml"
	assert_success
	assert_output ""
}
