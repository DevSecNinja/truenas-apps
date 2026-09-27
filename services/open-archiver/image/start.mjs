import { spawn } from "node:child_process";

const children = new Set();
let stopping = false;
let exitCode = 0;
let deadline;

function stop(code) {
    if (stopping) return;
    stopping = true;
    exitCode = code;
    for (const child of children) child.kill("SIGTERM");
    if (children.size === 0) {
        process.exitCode = exitCode;
        return;
    }
    deadline = setTimeout(() => {
        console.error("Open Archiver shutdown exceeded 20 seconds");
        for (const child of children) child.kill("SIGKILL");
        exitCode = 1;
    }, 20_000);
}

process.on("SIGTERM", () => stop(0));
process.on("SIGINT", () => stop(0));

function run(name, args, cwd = "/app") {
    const child = spawn(process.execPath, args, { cwd, stdio: "inherit" });
    children.add(child);
    child.on("error", (error) => {
        console.error(`Cannot start ${name}: ${error.message}`);
        stop(1);
    });
    child.on("close", (code, signal) => {
        children.delete(child);
        if (!stopping) {
            console.error(`${name} exited unexpectedly (code=${code}, signal=${signal})`);
            stop(1);
        }
        if (children.size === 0) {
            clearTimeout(deadline);
            process.exitCode = exitCode;
        }
    });
}

const heap = process.env.INDEXING_WORKER_MAX_OLD_SPACE_MB || "1024";
if (!/^[1-9][0-9]*$/.test(heap)) {
    console.error("INDEXING_WORKER_MAX_OLD_SPACE_MB must be a positive integer");
    process.exitCode = 1;
} else {
    run("API", ["/app/apps/open-archiver/dist/index.js"]);
    run("frontend", ["/app/packages/frontend/build/index.js"], "/app/packages/frontend");
    run("ingestion worker", ["/app/packages/backend/dist/workers/ingestion.worker.js"]);
    run("indexing worker", [
        `--max-old-space-size=${heap}`,
        "/app/packages/backend/dist/workers/indexing.worker.js",
    ]);
    run("scheduler", ["/app/packages/backend/dist/jobs/schedulers/sync-scheduler.js"]);
}
