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

function composePackages(fileName) {
    const services = entry(source(fileName).replaceAll("\r\n", "\n"), "services").body;
    const names = keys(services);
    assert.ok(names.length, `${fileName}: expected image-bearing services`);
    return names.map((name) => entry(entry(services, name).body, "image").value
        .split("@")[0].replace(/:[^/]+$/, ""));
}

// This trusted repository config is a JavaScript-compatible JSON5 object.
// Evaluating it with Node's existing built-in VM avoids adding a parser dependency.
// This is NOT Renovate schema validation or resolution of the remote presets.
const renovate = JSON.parse(JSON.stringify(runInNewContext(
    `(${source("renovate.json5")})`,
    {},
    { timeout: 1_000, contextCodeGeneration: { strings: false, wasm: false } },
)));

function controlRules(packageName, field, fileName, rules = renovate.packageRules) {
    // Fail closed on ambiguous/global/pattern-based overrides rather than
    // pretending to implement Renovate's full matcher or ignoring later rules.
    // Only canonical literal paths/names: no globs, regexes, negations, empty
    // segments or dot traversal. Additional matcher shapes require review.
    const literal = /^[a-z0-9_-][a-z0-9._-]*(?:\/[a-z0-9_-][a-z0-9._-]*)*$/;
    assert.ok(typeof fileName === "string" && literal.test(fileName), `${field}: review literal file context`);
    assert.ok(typeof packageName === "string" && literal.test(packageName), `${field}: review literal package context`);
    return rules.filter((rule) => {
        if (!Object.hasOwn(rule, field)) return false;
        if (Object.hasOwn(rule, "matchFileNames")) {
            assert.ok(
                Array.isArray(rule.matchFileNames) && rule.matchFileNames.length > 0
                    && rule.matchFileNames.every((name) => typeof name === "string" && literal.test(name)),
                `${field}: review non-literal file matcher`,
            );
            // File and package selectors are conjunctive. Only a proven
            // different literal file can be excluded before checking packages.
            if (!rule.matchFileNames.includes(fileName)) return false;
        }
        if (!Object.hasOwn(rule, "matchPackageNames")) {
            assert.ok(Object.hasOwn(rule, "matchFileNames"), `${field}: review global override`);
            return true;
        }
        assert.ok(
            Array.isArray(rule.matchPackageNames) && rule.matchPackageNames.length > 0
                && rule.matchPackageNames.every((name) => typeof name === "string" && literal.test(name)),
            `${field}: review non-literal package matcher`,
        );
        return rule.matchPackageNames.includes(packageName);
    });
}

function controlRule(packageName, field, fileName, rules) {
    const matches = controlRules(packageName, field, fileName, rules);
    assert.equal(matches.length, 1, `expected exactly one ${field} rule for ${packageName} in ${fileName}`);
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
    const rule = controlRule(packageName, "allowedVersions", "services/dawarich/compose.yaml");
    // No enabled:false, update-type restriction or hidden matching condition
    // may make the compatibility guard dormant or only protect some updates.
    assert.deepEqual(rule, {
        description: rule.description,
        matchDatasources: ["docker"],
        matchPackageNames: [packageName],
        allowedVersions: rule.allowedVersions,
    });
    for (const app of ["open-archiver", "pocket-id"]) {
        assert.deepEqual(controlRule(packageName, "allowedVersions", `services/${app}/compose.yaml`), rule);
    }
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
    for (const app of ["karakeep", "open-archiver"]) {
        const fileName = `services/${app}/compose.yaml`;
        assert.equal(
            entry(service(app, `${app}-meilisearch`), "image").value.split("@")[0].replace(/:[^/]+$/, ""),
            packageName,
            `${fileName}: expected Meilisearch image`,
        );
        const rule = controlRule(packageName, "automerge", fileName);
        assert.deepEqual(rule, {
            description: rule.description,
            matchDatasources: ["docker"],
            matchPackageNames: [packageName],
            matchUpdateTypes: ["major", "minor", "patch"],
            automerge: false,
        });
    }
});

test("renovate_compatibility: every Pocket image is ungrouped and requires review for all update types", () => {
    const fileName = "services/pocket-id/compose.yaml";
    const packageNames = composePackages(fileName);
    assert.ok(packageNames.length >= 3, "expected Pocket app, init and backup images");
    for (const packageName of packageNames) {
        const rule = controlRule(packageName, "automerge", fileName);
        assert.strictEqual(controlRule(packageName, "groupName", fileName), rule);
        // Exact shape forbids package lists, update-type restrictions or hidden
        // conditions: new images in this file must also receive the opt-out.
        assert.deepEqual(rule, {
            description: rule.description,
            matchDatasources: ["docker"],
            matchFileNames: [fileName],
            automerge: false,
            groupName: null,
        });
    }
});

test("renovate_compatibility: the same Pocket packages in another file do not inherit its local opt-out", () => {
    for (const packageName of composePackages("services/pocket-id/compose.yaml")) {
        for (const field of ["automerge", "groupName"]) {
            // Evaluate the same identity in another real Compose file. This
            // asserts local rule scope, not remote presets or app deployment.
            assert.deepEqual(controlRules(packageName, field, "services/open-archiver/compose.yaml"), []);
        }
    }
});

test("renovate_compatibility: only provably unrelated literal files bypass fail-closed selector checks", () => {
    const fileName = "services/pocket-id/compose.yaml";
    const packageName = "docker.io/library/busybox";
    const fileRule = { matchFileNames: [fileName], automerge: false };
    assert.strictEqual(controlRule(packageName, "automerge", fileName, [
        {
            matchFileNames: ["services/open-archiver/compose.yaml"],
            matchPackageNames: ["*"],
            automerge: true,
        },
        fileRule,
    ]), fileRule);
    assert.deepEqual(controlRules(packageName, "automerge", fileName, [
        { ...fileRule, matchPackageNames: ["docker.io/getmeili/meilisearch"] },
    ]), []);

    for (const matchFileNames of [
        [], null, fileName, [""], [123],
        ["services/*/compose.yaml"], ["services/**/compose.yaml"],
        ["services/pocket-?d/compose.yaml"], ["services/{pocket-id,other}/compose.yaml"],
        ["services/[ab]/compose.yaml"], [`!${fileName}`], [`/${fileName}/`],
        [`./${fileName}`], ["services/../pocket-id/compose.yaml"],
        ["services/open-archiver/compose.yaml", `!${fileName}`],
    ]) {
        assert.throws(
            () => controlRules(packageName, "automerge", fileName, [{ ...fileRule, matchFileNames }]),
            /review non-literal file matcher/,
        );
    }
    for (const matchPackageNames of [[], null, packageName, ["*"], [`!${packageName}`], [`/${packageName}/`]]) {
        for (const scope of [{}, { matchFileNames: [fileName] }]) {
            assert.throws(
                () => controlRules(packageName, "automerge", fileName, [{ ...scope, matchPackageNames, automerge: false }]),
                /review non-literal package matcher/,
            );
        }
    }
    assert.throws(
        () => controlRules(packageName, "automerge", undefined, [fileRule]),
        /review literal file context/,
    );
    assert.throws(
        () => controlRule(packageName, "automerge", fileName, [{ matchDatasources: ["docker"], automerge: false }]),
        /review global override/,
    );
    assert.throws(
        () => controlRule(packageName, "automerge", fileName, [
            fileRule,
            { matchPackageNames: [packageName], automerge: true },
        ]),
        /expected exactly one automerge rule/,
    );
});
