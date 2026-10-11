import test from "node:test";
import assert from "node:assert/strict";
import { runInNewContext } from "node:vm";
import { entry, fields, items, keys, scalar, source } from "./source-helpers.mjs";

// Source-policy tests only: neither container execution nor restore evidence.
// Reuse the existing restricted YAML reader; real Compose validation is separate.
function service(app, name) {
    const compose = source(`services/${app}/compose.yaml`).replaceAll("\r\n", "\n");
    return entry(entry(compose, "services").body, name).body;
}

function environment(serviceBody) {
    const body = entry(serviceBody, "environment").body;
    if (!body.trimStart().startsWith("- ")) return fields(body);
    const result = {};
    for (const item of items(body).map(scalar)) {
        const separator = item.indexOf("=");
        assert.ok(separator > 0, `expected explicit key=value environment: ${item}`);
        const key = item.slice(0, separator);
        assert.ok(!Object.hasOwn(result, key), `duplicate environment key: ${key}`);
        result[key] = item.slice(separator + 1);
    }
    return result;
}

// This trusted repository config is a JavaScript-compatible JSON5 object.
// Evaluating it with Node's existing built-in VM avoids adding a parser dependency.
// This is NOT Renovate schema validation or resolution of the remote presets.
const renovate = JSON.parse(JSON.stringify(runInNewContext(
    `(${source("renovate.json5")})`,
    {},
    { timeout: 1_000, contextCodeGeneration: { strings: false, wasm: false } },
)));

function controlRule(packageName, field) {
    // Fail closed on ambiguous/global/pattern-based overrides rather than
    // pretending to implement Renovate's full matcher or ignoring later rules.
    const matches = renovate.packageRules.filter((rule) => {
        if (!Object.hasOwn(rule, field)) return false;
        assert.ok(rule.matchPackageNames?.length, `${field}: review global override`);
        for (const name of rule.matchPackageNames) {
            assert.match(name, /^[a-z0-9./_-]+$/, `${field}: review non-literal package matcher`);
        }
        return rule.matchPackageNames.includes(packageName);
    });
    assert.equal(matches.length, 1, `expected exactly one ${field} rule for ${packageName}`);
    return matches[0];
}

test("source_reader: quoted identities allow trailing comments without stripping literal hashes", () => {
    assert.equal(scalar('"3130:3130" # svc-app-karakeep'), "3130:3130");
    assert.equal(scalar('"literal # value" # trailing comment'), "literal # value");
    assert.equal(scalar('"escaped \\"quote\\"" # trailing comment'), 'escaped "quote"');
    assert.throws(() => scalar('"3130:3130" unexpected'), /unsupported YAML double-quoted scalar/);
    assert.throws(() => scalar('"unterminated'), /unsupported YAML double-quoted scalar/);
});

test("karakeep_meilisearch: enables startup migration on digest-pinned v1.51 or newer within v1", () => {
    const meili = service("karakeep", "karakeep-meilisearch");
    const version = entry(meili, "image").value.match(
        /^docker\.io\/getmeili\/meilisearch:v1\.(0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)@sha256:[0-9a-f]{64}$/,
    );
    assert.ok(version, "Meilisearch must use a digest-pinned stable v1 image");
    assert.ok(Number(version[1]) >= 51, "MEILI_UPGRADE_DB requires Meilisearch v1.51 or newer");
    assert.equal(environment(meili).MEILI_UPGRADE_DB, "true");
    assert.equal(environment(meili).MEILI_ENV, "production");
    assert.equal(environment(meili).MEILI_MASTER_KEY, "${KARAKEEP_MEILI_MASTER_KEY}");
});

test("karakeep_meilisearch: migration retains identity, hardening, limits and readiness dependencies", () => {
    const meili = service("karakeep", "karakeep-meilisearch");
    assert.equal(entry(meili, "user").value, "3130:3130");
    assert.equal(entry(meili, "read_only").value, "true");
    assert.deepEqual(items(entry(meili, "cap_drop").body).map(scalar), ["ALL"]);
    assert.ok(!keys(meili).includes("cap_add"), "migration must not add capabilities");
    assert.deepEqual(items(entry(meili, "security_opt").body).map(scalar), ["no-new-privileges=true"]);
    assert.equal(entry(meili, "mem_limit").value, "${MEILI_MEM_LIMIT:-1024m}");
    assert.equal(entry(meili, "pids_limit").value, "100");
    assert.deepEqual(items(entry(meili, "volumes").body).map(scalar), ["./data/meilisearch:/meili_data"]);
    assert.deepEqual(items(entry(meili, "tmpfs").body).map(scalar), ["/tmp"]);
    assert.deepEqual(items(entry(meili, "networks").body).map(scalar), ["karakeep-backend"]);
    assert.ok(!keys(meili).includes("ports"), "Meilisearch must not publish host ports");
    const dependencies = entry(meili, "depends_on").body;
    assert.equal(entry(entry(dependencies, "karakeep-init").body, "condition").value, "service_completed_successfully");
    const webDependencies = entry(service("karakeep", "karakeep"), "depends_on").body;
    assert.equal(entry(entry(webDependencies, "karakeep-meilisearch").body, "condition").value, "service_healthy");
});

for (const app of ["dawarich", "open-archiver"]) {
    test(`backup_compatibility: ${app} uses a digest-pinned v4 compatibility image`, () => {
        assert.match(
            entry(service(app, `${app}-db-backup`), "image").value,
            /^docker\.io\/nfrastack\/db-backup:4\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)@sha256:[0-9a-f]{64}$/,
            "Allow v4 maintenance updates without accepting v5 or an unpinned image",
        );
    });

    test(`backup_compatibility: ${app} retains one-shot encrypted ZSTD and SHA1 settings`, () => {
        const backup = service(app, `${app}-db-backup`);
        const env = environment(backup);
        for (const [key, value] of Object.entries({
            MODE: "MANUAL",
            MANUAL_RUN_FOREVER: "FALSE",
            CONTAINER_ENABLE_SCHEDULING: "FALSE",
            ENABLE_NOTIFICATIONS: "FALSE",
            DEFAULT_ENCRYPT: "TRUE",
            DEFAULT_ENCRYPT_PASSPHRASE: "${DB_ENC_PASSPHRASE}",
            DEFAULT_COMPRESSION: "ZSTD",
            DEFAULT_CHECKSUM: "SHA1",
            DEFAULT_CLEANUP_TIME: "2880",
            DB01_TYPE: "pgsql",
            DB01_HOST: `${app}-db`,
        })) assert.equal(env[key], value, `${app}: ${key}`);
        assert.equal(entry(backup, "restart").value, "no");
        assert.deepEqual(items(entry(backup, "volumes").body).map(scalar), ["./backups/db-backup:/backup"]);
        if (app === "dawarich") {
            assert.deepEqual(items(entry(backup, "command").body).map(scalar), ["backup-now"]);
        } else {
            assert.equal(env.DB02_TYPE, "redis");
            assert.equal(env.DB02_HOST, "open-archiver-valkey");
            // backup.test.mjs executes the real two-job wrapper with success,
            // failure and missing-helper mocks; do not replace that with grep.
            assert.deepEqual(items(entry(backup, "labels").body).map(scalar), ["dccd.backup-jobs=01,02"]);
        }
    });
}

test("renovate_compatibility: actual allowedVersions accepts v4 and rejects v5 and boundary lookalikes", () => {
    const packageName = "docker.io/nfrastack/db-backup";
    const rule = controlRule(packageName, "allowedVersions");
    // No enabled:false, update-type restriction or hidden matching condition
    // may make the compatibility guard dormant or only protect some updates.
    assert.deepEqual(rule, {
        description: rule.description,
        matchDatasources: ["docker"],
        matchPackageNames: [packageName],
        allowedVersions: rule.allowedVersions,
    });
    assert.equal(typeof rule.allowedVersions, "string");
    assert.match(rule.allowedVersions, /^\/.+\/$/, "Docker versioning requires a regex guard");
    const allowed = new RegExp(rule.allowedVersions.slice(1, -1));
    for (const version of ["4.0.0", "4.9.2", "4.10.0", "4.99.99"]) {
        assert.ok(allowed.test(version), `${version} must remain eligible`);
    }
    for (const version of ["3.9.2", "5.0.0", "5.0.4", "5.99.99", "14.9.2", "latest", "x4.9.2", "4x9.2"]) {
        assert.ok(!allowed.test(version), `${version} must be rejected`);
    }
});

test("renovate_compatibility: Meilisearch major, minor and patch updates explicitly disable automerge", () => {
    const packageName = "docker.io/getmeili/meilisearch";
    const rule = controlRule(packageName, "automerge");
    assert.deepEqual(rule, {
        description: rule.description,
        matchDatasources: ["docker"],
        matchPackageNames: [packageName],
        matchUpdateTypes: ["major", "minor", "patch"],
        automerge: false,
    });
});
