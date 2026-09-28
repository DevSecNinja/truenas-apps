import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { entry, fields, items, scalar, source } from "./source-helpers.mjs";

const services = entry(source("services/open-archiver/compose.yaml"), "services").body;
const init = entry(services, "open-archiver-init").body;
const defaults = fields(entry(init, "environment").body);
const command = items(entry(init, "command").body);
assert.equal(command.length, 3, "expected sh, flags, and the literal init script");
assert.equal(scalar(command[0]), "sh");
assert.match(command[2], /^\|-\n/, "execute the actual literal Compose command");
// Compose turns $$ into a literal $ before passing this script to sh.
const script = command[2].slice(3).replaceAll("$$", "$");
const roots = ["/data/archive", "/data/scratch", "/data/postgres", "/data/valkey", "/data/meilisearch"];
const secrets = {
    DOMAINNAME: "archive.example.invalid",
    POSTGRES_ADMIN_PASSWORD: "synthetic-admin-only",
    POSTGRES_PASSWORD: "synthetic-database-only",
    REDIS_PASSWORD: "synthetic-valkey-only",
    MEILI_MASTER_KEY: "synthetic-search-only",
    JWT_SECRET: "synthetic-jwt-only",
    ENCRYPTION_KEY: "AB".repeat(32),
    STORAGE_ENCRYPTION_KEY: "cd".repeat(32),
    DB_ENC_PASSPHRASE: "synthetic-backup-only",
};

function harness(t) {
    const root = mkdtempSync(join(tmpdir(), "open-archiver-init-"));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const bin = join(root, "bin");
    const log = join(root, "calls");
    mkdirSync(bin);
    writeFileSync(log, "");
    for (const name of ["mkdir", "chown", "chmod"]) {
        writeFileSync(join(bin, name), `#!/bin/sh
{
    printf '%s\\000' '${name}' "$(umask)" "$#"
    printf '%s\\000' "$@"
} >> "$INIT_CALL_LOG"
if [ "\${INIT_FAIL_COMMAND:-}" = '${name}' ]; then
    exit 47
fi
`, { mode: 0o700 });
    }
    writeFileSync(join(bin, "printenv"), `#!/bin/sh
[ "$#" -eq 1 ] || exit 2
case "$1" in
${Object.keys(secrets).map((name) => `    ${name})
        [ "\${${name}+set}" = set ] || exit 1
        printf '%s\\n' "\${${name}}"
        ;;`).join("\n")}
    *) printf '%s\\n' 'unexpected printenv argument' >&2; exit 2 ;;
esac
`, { mode: 0o700 });

    return (overrides = {}, positional = []) => {
        // Do not inherit real secrets or a PATH that could reach filesystem tools.
        const env = {
            HOME: root, TMPDIR: root, PATH: bin, LC_ALL: "C", INIT_CALL_LOG: log,
            ...secrets, ...defaults, ...overrides,
        };
        for (const [name, value] of Object.entries(env)) {
            if (value === undefined) delete env[name];
        }
        writeFileSync(log, "");
        const result = spawnSync("/bin/sh", [
            scalar(command[1]), `umask 022\n${script}`, "open-archiver-init", ...positional,
        ], { cwd: root, env, encoding: "utf8", timeout: 5_000 });
        assert.ifError(result.error);
        assert.equal(result.signal, null, "init must exit, not time out or die from a signal");
        const tokens = readFileSync(log, "utf8").split("\0");
        assert.equal(tokens.pop(), "", "spy log must end on a record boundary");
        const calls = [];
        while (tokens.length) {
            const [name, mask, count] = tokens.splice(0, 3);
            const argc = Number(count);
            assert.ok(Number.isInteger(argc) && argc > 0 && argc <= tokens.length, "invalid spy record");
            calls.push({ name, mask: Number.parseInt(mask, 8), args: tokens.splice(0, argc) });
        }
        return { ...result, calls };
    };
}

function assertOperations(result, repair = false) {
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, "");
    const flags = repair ? ["-R"] : [];
    const expected = [
        ["mkdir", ["-p", ...roots]],
        ["chown", [...flags, "3132:3132", "/data/archive", "/data/scratch", "/data/meilisearch"]],
        ["chown", [...flags, "70:70", "/data/postgres"]],
        ["chown", [...flags, "999:1000", "/data/valkey"]],
        ["chmod", [...flags, "u=rwX,g=,o=", ...roots]],
        ["chmod", ["700", "/data"]],
    ];
    assert.deepEqual(result.calls, expected.map(([name, args]) => ({ name, mask: 0o077, args })));
}

function assertRejected(result, message) {
    assert.equal(result.status, 1, result.stderr);
    assert.ok(result.stderr.includes(message), `expected ${JSON.stringify(message)} in ${result.stderr}`);
    assert.deepEqual(result.calls, [], "invalid input must fail before mkdir, chown, or chmod");
}

test("init: Compose defaults permission repair to false", () => {
    assert.equal(defaults.OPEN_ARCHIVER_REPAIR_PERMISSIONS, "false");
});

test("init: regular and repeated starts only secure the five roots and /data, with umask 077", (t) => {
    const run = harness(t);
    assertOperations(run());
    assertOperations(run());
});

test("init: explicit repair recursively fixes only the correctly assigned service paths", (t) => {
    assertOperations(harness(t)({ OPEN_ARCHIVER_REPAIR_PERMISSIONS: "true" }), true);
});

for (const repair of ["false", "true"]) {
    test(`init: ${repair} repair mode discards inherited positional arguments`, (t) => {
        assertOperations(
            harness(t)({ OPEN_ARCHIVER_REPAIR_PERMISSIONS: repair }, ["-R", "/data/not-allowed"]),
            repair === "true",
        );
    });
}

for (const mode of [undefined, "", "TRUE", "FALSE", "1", "yes", " false ", "--recursive"]) {
    test(`init: invalid repair mode ${JSON.stringify(mode)} fails before filesystem mutation`, (t) => {
        assertRejected(
            harness(t)({ OPEN_ARCHIVER_REPAIR_PERMISSIONS: mode }),
            "ERROR: OPEN_ARCHIVER_REPAIR_PERMISSIONS must be true or false",
        );
    });
}

for (const name of Object.keys(secrets)) {
    for (const value of [undefined, "", "GENERATE", "CHANGE_ME"]) {
        test(`init: ${name}=${JSON.stringify(value)} fails before filesystem mutation`, (t) => {
            assertRejected(harness(t)({ [name]: value }), `ERROR: Open Archiver requires a populated ${name}`);
        });
    }
}

for (const name of ["ENCRYPTION_KEY", "STORAGE_ENCRYPTION_KEY"]) {
    for (const length of [63, 65]) {
        test(`init: ${name} with ${length} hex digits fails before filesystem mutation`, (t) => {
            assertRejected(
                harness(t)({ [name]: "a".repeat(length) }),
                "ERROR: Open Archiver encryption keys must contain 32 bytes",
            );
        });
    }
    test(`init: ${name} with non-hex digits fails before filesystem mutation`, (t) => {
        assertRejected(
            harness(t)({ [name]: "g".repeat(64) }),
            "ERROR: Open Archiver encryption keys must be hexadecimal",
        );
    });
}

for (const [name, calls] of [
    ["mkdir", ["mkdir"]],
    ["chown", ["mkdir", "chown"]],
    ["chmod", ["mkdir", "chown", "chown", "chown", "chmod"]],
]) {
    test(`init: a failed ${name} stops immediately and propagates the failure`, (t) => {
        const result = harness(t)({ INIT_FAIL_COMMAND: name });
        assert.equal(result.status, 47, result.stderr);
        assert.deepEqual(result.calls.map((call) => call.name), calls);
    });
}
