import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { entry, items, scalar, source } from "./source-helpers.mjs";

const services = entry(source("services/open-archiver/compose.yaml"), "services").body;
const backup = entry(services, "open-archiver-db-backup").body;
const command = items(entry(backup, "command").body);
assert.equal(command.length, 3, "expected bash, flags, and the literal backup script");
assert.equal(scalar(command[0]), "bash");
assert.equal(scalar(command[1]), "-c");
assert.match(command[2], /^\|-\n/, "execute the actual literal Compose command");
// Compose unescapes $$ before passing the command to bash.
const script = command[2].slice(3).replaceAll("$$", "$");
const jobs = ["01", "02"];

function launch(t, codes) {
    const root = mkdtempSync(join(tmpdir(), "open-archiver-backup-"));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const bin = join(root, "bin");
    mkdirSync(bin);
    jobs.forEach((job, index) => {
        // null means the helper really is missing from the isolated PATH.
        if (codes[index] === null) return;
        writeFileSync(join(bin, `backup${job}-now`), `#!/bin/bash
printf '%s\\000' 'backup${job}-now' "$#" "$@"
exit ${codes[index]}
`, { mode: 0o700 });
    });

    const result = spawnSync("/bin/bash", [scalar(command[1]), script], {
        cwd: root,
        // No inherited credentials, BASH_ENV, shell options, or real backup helpers.
        env: { HOME: root, TMPDIR: root, PATH: bin, LC_ALL: "C" },
        encoding: "utf8",
        timeout: 5_000,
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null, "backup wrapper must exit, not time out or die from a signal");
    // Helpers emit only synthetic invocation metadata, never database contents.
    const tokens = result.stdout.split("\0");
    assert.equal(tokens.pop(), "", "spy output must end on a record boundary");
    const calls = [];
    while (tokens.length) {
        const [name, count] = tokens.splice(0, 2);
        const argc = Number(count);
        assert.ok(Number.isInteger(argc) && argc >= 0 && argc <= tokens.length, "invalid spy record");
        calls.push({ name, args: tokens.splice(0, argc) });
    }
    return { ...result, calls };
}

test("backup: Compose declares exactly the two expected completion IDs", () => {
    const labels = items(entry(backup, "labels").body).map(scalar);
    assert.deepEqual(
        labels.filter((label) => label.startsWith("dccd.backup-jobs=")),
        ["dccd.backup-jobs=01,02"],
    );
});

for (const [description, codes] of [
    ["both jobs succeed", [0, 0]],
    ["first job fails and second succeeds", [23, 0]],
    ["first job succeeds and second fails", [0, 47]],
    ["both jobs fail", [23, 47]],
    ["first helper is missing and second succeeds", [null, 0]],
    ["second helper is missing after first succeeds", [0, null]],
    ["first job returns signal-like status 143 and second succeeds", [143, 0]],
    ["second job returns signal-like status 143 after first succeeds", [0, 143]],
]) {
    test(`backup: ${description} attempts each helper once and preserves failures`, (t) => {
        const result = launch(t, codes);
        const failedJobs = jobs.filter((job, index) => codes[index] !== 0);
        assert.equal(result.status, failedJobs.length ? 1 : 0, result.stderr);
        assert.deepEqual(
            result.calls,
            jobs.filter((job, index) => codes[index] !== null).map((job) => ({
                name: `backup${job}-now`, args: ["now"],
            })),
            "every available helper must run exactly once, in order, with only the now argument",
        );
        assert.deepEqual(
            result.stderr.split("\n").filter((line) => line.startsWith("ERROR:")),
            jobs.flatMap((job, index) => codes[index] === 0 ? [] : [
                `ERROR: Backup ${job} failed with exit code ${codes[index] ?? 127}`,
            ]),
            "report every failed helper without allowing a later success to mask it",
        );
        jobs.forEach((job, index) => {
            if (codes[index] === null) {
                assert.equal(
                    result.stderr.match(new RegExp(`backup${job}-now: command not found`, "g"))?.length,
                    1,
                    "a missing helper must be attempted exactly once",
                );
            }
        });
        if (!failedJobs.length) assert.equal(result.stderr, "");
    });
}
