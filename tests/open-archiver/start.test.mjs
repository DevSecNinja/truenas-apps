import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import { createContext, SourceTextModule, SyntheticModule } from "node:vm";

const source = readFileSync(
    new URL("../../services/open-archiver/image/start.mjs", import.meta.url), "utf8",
);

async function launch(heap) {
    const proc = Object.assign(new EventEmitter(), {
        execPath: "/test/node",
        env: heap === undefined ? {} : { INDEXING_WORKER_MAX_OLD_SPACE_MB: heap },
    });
    const calls = [], children = [], errors = [], timers = new Set();
    const context = createContext({
        process: proc,
        console: { error: (...parts) => errors.push(parts.join(" ")) },
        setTimeout: (fn, ms) => {
            const timer = { fn, ms };
            timers.add(timer);
            return timer;
        },
        clearTimeout: (timer) => timers.delete(timer),
    });
    const mock = new SyntheticModule(["spawn"], function () {
        this.setExport("spawn", (command, args, options) => {
            const child = new EventEmitter();
            child.signals = [];
            child.kill = (signal) => { child.signals.push(signal); return true; };
            children.push(child);
            // Copy cross-realm values so strict assertions compare ordinary host objects.
            calls.push({ command, args: [...args], options: { ...options } });
            return child;
        });
    }, { context });
    const module = new SourceTextModule(source, { context, identifier: "start.mjs" });
    await module.link((specifier) => {
        assert.equal(specifier, "node:child_process", "unexpected launcher dependency");
        return mock;
    });
    await module.evaluate();
    return { proc, calls, children, errors, timers };
}

function assertSignals(children, ...signals) {
    assert.deepEqual(children.map((child) => child.signals), children.map(() => signals));
}

function closeAll(children, signal = "SIGTERM") {
    for (const child of children) child.emit("close", null, signal);
}

for (const heap of [undefined, "", "1", "2048"]) {
    test(`start: five direct Node commands with heap ${JSON.stringify(heap)}`, async () => {
        const h = await launch(heap);
        const expected = [
            ["/app/apps/open-archiver/dist/index.js"],
            ["/app/packages/frontend/build/index.js"],
            ["/app/packages/backend/dist/workers/ingestion.worker.js"],
            [`--max-old-space-size=${heap || "1024"}`,
                "/app/packages/backend/dist/workers/indexing.worker.js"],
            ["/app/packages/backend/dist/jobs/schedulers/sync-scheduler.js"],
        ];
        assert.deepEqual(h.calls, expected.map((args, index) => ({
            command: "/test/node", args,
            options: {
                cwd: index === 1 ? "/app/packages/frontend" : "/app",
                stdio: "inherit",
            },
        })));
        assert.deepEqual(h.errors, []);
        assert.equal(h.proc.exitCode, undefined);
        assert.equal(h.timers.size, 0);
        assertSignals(h.children);
    });
}

for (const heap of ["0", "-1", "1.5", "abc", " 1024", "1024 ", "1e3"]) {
    test(`start: invalid heap ${JSON.stringify(heap)} fails without spawning`, async () => {
        const h = await launch(heap);
        assert.equal(h.proc.exitCode, 1);
        assert.deepEqual(h.calls, []);
        assert.deepEqual(h.errors, ["INDEXING_WORKER_MAX_OLD_SPACE_MB must be a positive integer"]);
        assert.equal(h.timers.size, 0);
    });
}

for (const [code, signal] of [[0, null], [23, null], [null, "SIGKILL"]]) {
    test(`start: unexpected close (${code}, ${signal}) fatally stops all peers`, async () => {
        const h = await launch();
        h.children[0].emit("close", code, signal);
        assertSignals([h.children[0]]);
        assertSignals(h.children.slice(1), "SIGTERM");
        assert.deepEqual(h.errors, [`API exited unexpectedly (code=${code}, signal=${signal})`]);
        assert.equal(h.timers.size, 1);
        assert.equal(h.proc.exitCode, undefined, "wait for surviving children");
        h.proc.emit("SIGTERM"); // A later shutdown request must not erase the fatal status.
        closeAll(h.children.slice(1));
        assert.equal(h.proc.exitCode, 1);
        assert.equal(h.timers.size, 0);
        assert.equal(h.calls.length, 5, "no respawn");
    });
}

test("start: asynchronous spawn error stops children and waits for close", async () => {
    const h = await launch();
    h.children[0].emit("error", new Error("ENOENT"));
    assert.deepEqual(h.errors, ["Cannot start API: ENOENT"]);
    assertSignals(h.children, "SIGTERM");
    assert.equal(h.proc.exitCode, undefined);
    assert.equal(h.timers.size, 1);
    h.children[0].emit("close", -2, null);
    closeAll(h.children.slice(1));
    assert.equal(h.proc.exitCode, 1);
    assert.equal(h.timers.size, 0);
    assert.equal(h.calls.length, 5);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
    test(`start: ${signal} before spawn notifications forwards once and exits zero`, async () => {
        const h = await launch();
        // spawn() has returned; its asynchronous "spawn" and "close" events have not fired.
        h.proc.emit(signal);
        for (const child of h.children) child.emit("spawn");
        h.proc.emit("SIGTERM");
        h.proc.emit("SIGINT");
        assertSignals(h.children, "SIGTERM");
        assert.equal(h.timers.size, 1);
        closeAll(h.children.slice(0, -1));
        assert.equal(h.proc.exitCode, undefined, "wait for the last close");
        closeAll(h.children.slice(-1));
        h.proc.emit(signal); // Also safe after the final close.
        assertSignals(h.children, "SIGTERM");
        assert.equal(h.proc.exitCode, 0);
        assert.equal(h.timers.size, 0);
        assert.equal(h.calls.length, 5, "late spawn events must not respawn children");
        assert.deepEqual(h.errors, []);
    });
}

test("start: shutdown deadline kills only survivors and exits one", async () => {
    const h = await launch();
    h.proc.emit("SIGTERM");
    closeAll(h.children.slice(0, 1));
    const [timer] = h.timers;
    assert.equal(timer.ms, 20_000);
    h.timers.delete(timer);
    timer.fn();
    assertSignals(h.children.slice(0, 1), "SIGTERM");
    assertSignals(h.children.slice(1), "SIGTERM", "SIGKILL");
    assert.deepEqual(h.errors, ["Open Archiver shutdown exceeded 20 seconds"]);
    h.proc.emit("SIGTERM");
    closeAll(h.children.slice(1), "SIGKILL");
    assert.equal(h.proc.exitCode, 1);
    assert.equal(h.timers.size, 0);
    assert.equal(h.calls.length, 5);
});
