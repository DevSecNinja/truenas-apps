import test from "node:test";
import assert from "node:assert/strict";
import { readdirSync } from "node:fs";
import { entry, fields, items, keys, scalar, source } from "./source-helpers.mjs";

const compose = source("services/open-archiver/compose.yaml");
const services = entry(compose, "services").body;
const app = entry(services, "open-archiver").body;
const workflow = source(".github/workflows/open-archiver-image.yml");
const jobs = entry(workflow, "jobs").body;
const image = entry(jobs, "image").body;
const publish = entry(jobs, "publish").body;

function labels(service) {
    if (!keys(service).includes("labels")) return {};
    const result = {};
    for (const item of items(entry(service, "labels").body)) {
        const label = scalar(item);
        const separator = label.indexOf("=");
        assert.ok(separator > 0, `expected key=value label: ${label}`);
        const key = label.slice(0, separator);
        assert.ok(!Object.hasOwn(result, key), `duplicate label: ${key}`);
        result[key] = label.slice(separator + 1);
    }
    return result;
}

function runCommand(step) {
    const run = entry(step, "run");
    return ["|", "|-"].includes(run.value) ? run.body : `${run.value} ${run.body}`;
}

function onlyStep(steps, predicate, description) {
    const matches = steps.filter(predicate);
    assert.equal(matches.length, 1, `expected exactly one ${description} step`);
    return matches[0];
}

function artifactProbe(step) {
    const command = runCommand(step).replace(/\\\r?\n\s*/g, " ").trim();
    const match = command.match(/^docker\s+run\s+([^\r\n]+?)\s+-e\s+'([^']+)'$/);
    assert.ok(match, "artifact check must be a single foreground docker run with a Node -e assertion");
    assert.doesNotMatch(match[1], /[;&|<>`]/, "artifact check must not mask failures with shell operators");
    const args = match[1].match(/"[^"]*"|\S+/g).map(scalar);
    assert.ok(!args.includes("--detach") && !args.includes("-d"), "wait for the artifact check to exit");
    return { args, code: match[2] };
}

test("access: one hostname-wide router protects setup APIs and alternate paths with both auth checks", () => {
    const routers = new Set();
    const exposed = [];
    for (const name of keys(services)) {
        const serviceLabels = labels(entry(services, name).body);
        if (serviceLabels["traefik.enable"] === "true") exposed.push(name);
        for (const key of Object.keys(serviceLabels)) {
            const router = key.match(/^traefik\.http\.routers\.([^.]+)\./);
            if (router) routers.add(router[1]);
        }
    }
    assert.deepEqual(exposed, ["open-archiver"]);
    assert.deepEqual([...routers], ["open-archiver-rtr"], "no alternate unguarded router");
    const config = labels(app);
    const router = "traefik.http.routers.open-archiver-rtr";
    assert.equal(
        config[`${router}.rule`], "Host(`open-archiver.${DOMAINNAME}`)",
        "the auth boundary must cover every path and method, not just the setup UI",
    );
    assert.deepEqual(config[`${router}.middlewares`].split(",").map((value) => value.trim()), [
        "chain-auth@file", "open-archiver-access",
    ]);
    assert.equal(config[`${router}.entrypoints`], "https");
    assert.equal(config[`${router}.service`], "open-archiver-svc");
    assert.equal(config["traefik.http.services.open-archiver-svc.loadbalancer.server.port"], "3000");
});

test("access: shared chain-auth still invokes the shared ForwardAuth middleware", () => {
    const http = entry(source("services/traefik/config/rules/middlewares-chains.yml"), "http").body;
    const middlewares = entry(http, "middlewares").body;
    const chain = entry(entry(middlewares, "chain-auth").body, "chain").body;
    assert.ok(
        items(entry(chain, "middlewares").body).map(scalar).includes("middlewares-forward-auth"),
        "chain-auth@file must retain its authentication layer alongside the dedicated role check",
    );
});

test("access: ForwardAuth decodes to exactly the required Entra role predicate", () => {
    const config = labels(app);
    const prefix = "traefik.http.middlewares.open-archiver-access.forwardauth";
    const address = new URL(config[`${prefix}.address`]);
    assert.equal(address.origin, "http://traefik-forward-auth:4181");
    assert.equal(address.pathname, "/portals/main");
    assert.equal(address.username, "");
    assert.equal(address.password, "");
    assert.equal(address.hash, "");
    assert.deepEqual([...address.searchParams], [["if", 'Role("open-archiver-access")']]);
    assert.equal(config[`${prefix}.trustForwardHeader`], "true");
    assert.equal(config[`${prefix}.maxResponseBodySize`], "1048576");
    assert.deepEqual(config[`${prefix}.authResponseHeaders`].split(","), [
        "X-Forwarded-User", "X-Forwarded-DisplayName",
    ]);
});

test("access: no service publishes host ports or bypasses private networks", () => {
    for (const name of keys(services)) {
        const service = entry(services, name).body;
        assert.ok(!keys(service).includes("ports"), `${name} must not publish ports`);
        if (keys(service).includes("network_mode")) {
            assert.equal(entry(service, "network_mode").value, "none", `${name} must not share host networking`);
        }
        if (keys(service).includes("networks")) {
            const networks = items(entry(service, "networks").body).map(scalar);
            assert.ok(networks.length > 0, `${name} needs explicit private networking`);
            const allowed = name === "open-archiver"
                ? ["open-archiver-frontend", "open-archiver-backend", "open-archiver-parser"]
                : ["open-archiver-backend", "open-archiver-parser"];
            for (const network of networks) assert.ok(allowed.includes(network), `${name}: unexpected ${network}`);
        } else {
            assert.equal(entry(service, "network_mode").value, "none", `${name} must not join the default network`);
        }
    }
    const networks = entry(compose, "networks").body;
    for (const name of ["open-archiver-backend", "open-archiver-parser"]) {
        assert.equal(entry(entry(networks, name).body, "internal").value, "true");
    }
});

test("activation: shared Traefik neither joins nor requires the unadopted candidate network", () => {
    const files = readdirSync(new URL("../../services/traefik/", import.meta.url))
        .filter((name) => /^compose.*\.yaml$/.test(name)).sort();
    assert.ok(files.includes("compose.yaml"), "the activation guard must include the base Compose file");
    for (const file of files) {
        const active = source(`services/traefik/${file}`).split("\n")
            .filter((line) => !line.trimStart().startsWith("#")).join("\n");
        assert.doesNotMatch(
            active, /\bopen-archiver-frontend\b/,
            `${file}: adding this external network requires a separate reviewed activation`,
        );
    }
});

test("activation: all eight candidate services require the explicit open-archiver profile", () => {
    assert.deepEqual(keys(services).sort(), [
        "open-archiver",
        "open-archiver-db",
        "open-archiver-db-backup",
        "open-archiver-init",
        "open-archiver-meilisearch",
        "open-archiver-migrate",
        "open-archiver-tika",
        "open-archiver-valkey",
    ]);
    for (const name of keys(services)) {
        const profiles = entry(entry(services, name).body, "profiles");
        assert.equal(profiles.value, "", `${name}: profiles must be an explicit list`);
        assert.deepEqual(
            items(profiles.body).map(scalar), ["open-archiver"],
            `${name}: no default or unrelated-profile activation, including one-shot services`,
        );
    }
});

test("activation: candidate dependencies cannot escape the open-archiver profile gate", () => {
    const names = keys(services);
    for (const name of names) {
        const service = entry(services, name).body;
        if (!keys(service).includes("depends_on")) continue;
        for (const dependency of keys(entry(service, "depends_on").body)) {
            assert.ok(names.includes(dependency), `${name}: dependency ${dependency} must be in the candidate stack`);
            assert.deepEqual(
                items(entry(entry(services, dependency).body, "profiles").body).map(scalar),
                ["open-archiver"],
                `${name}: dependency ${dependency} must not be ungated`,
            );
        }
    }
});

test("valkey: 192mb maxmemory leaves headroom below the independent 512m container cap without eviction", () => {
    const valkey = entry(services, "open-archiver-valkey").body;
    const command = items(entry(valkey, "command").body).map(scalar);
    assert.equal(command[0], "valkey-server");
    for (const [flag, value] of [
        ["--maxmemory", "${VALKEY_MAXMEMORY:-192mb}"],
        ["--maxmemory-policy", "noeviction"],
    ]) {
        assert.equal(command.filter((arg) => arg === flag).length, 1, `expected exactly one ${flag}`);
        assert.equal(command[command.indexOf(flag) + 1], value, flag);
    }
    assert.equal(entry(valkey, "mem_limit").value, "${VALKEY_MEM_LIMIT:-512m}");
});

test("workflow: only main pushes and ordinary pull requests trigger candidate image checks", () => {
    const events = entry(workflow, "on").body;
    assert.deepEqual(keys(events).sort(), ["pull_request", "push"]);
    const push = entry(events, "push").body;
    assert.deepEqual(keys(push).sort(), ["branches", "paths"], "no feature or tag publishing trigger");
    assert.deepEqual(items(entry(push, "branches").body).map(scalar), ["main"]);
    const publishPaths = [
        "services/open-archiver/image/**",
        "tests/open-archiver/**",
        ".github/workflows/open-archiver-image.yml",
    ];
    assert.deepEqual(
        items(entry(push, "paths").body).map(scalar).sort(), [...publishPaths].sort(),
        "proxy and Compose-only changes must not publish a new candidate image",
    );
    const pullRequest = entry(events, "pull_request").body;
    const paths = items(entry(pullRequest, "paths").body).map(scalar);
    for (const path of [
        ...publishPaths,
        "services/open-archiver/compose.yaml",
        "services/traefik/compose*.yaml",
        "services/traefik/config/rules/**",
    ]) assert.ok(paths.includes(path), `pull_request must validate changes to ${path}`);
});

test("workflow: only the main-gated publish job has package write permission after image checks", () => {
    assert.equal(entry(workflow, "permissions").value, "{}");
    assert.deepEqual(keys(jobs).sort(), ["image", "publish"]);
    assert.deepEqual(fields(entry(image, "permissions").body), { contents: "read" });
    assert.deepEqual(fields(entry(publish, "permissions").body), { contents: "read", packages: "write" });
    assert.equal(entry(publish, "needs").value, "image");
    assert.match(
        entry(publish, "if").value,
        /^github\.event_name\s*==\s*'push'\s*&&\s*github\.ref\s*==\s*'refs\/heads\/main'$/,
    );
    assert.ok(!keys(image).includes("if"), "PR image checks must not inherit the main-only publish guard");
});

test("workflow: read-only image job runs every Node regression test without a conditional skip", () => {
    const steps = items(entry(image, "steps").body);
    const checks = steps.filter((step) =>
        keys(step).includes("run") && entry(step, "run").value.includes("--test")
    );
    assert.equal(checks.length, 1, "expected the Node test runner in the image job");
    assert.match(
        entry(checks[0], "run").value,
        /^node\s+--experimental-vm-modules\s+--test\s+tests\/open-archiver\/\*\.test\.mjs$/,
    );
    assert.ok(!keys(checks[0]).includes("if"), "regression tests must always run");
    for (const target of [image, checks[0]]) {
        assert.ok(!keys(target).includes("continue-on-error"), "test failures must block publishing");
    }
    for (const step of steps) {
        if (!keys(step).includes("uses")) continue;
        const action = entry(step, "uses").value;
        assert.ok(!action.startsWith("docker/login-action@"), "read-only checks must not log in to GHCR");
        if (action.startsWith("docker/build-push-action@")) {
            const options = fields(entry(step, "with").body);
            assert.notEqual(options.push, "true", "the image job must not publish");
            assert.equal(options.load, "true", "the image job must load its disposable test image");
        }
    }
});

test("workflow: published digest passes the same runtime artifact check before recording its reference", () => {
    const steps = items(entry(publish, "steps").body);
    const pushed = onlyStep(steps, (step) =>
        keys(step).includes("uses")
        && entry(step, "uses").value.startsWith("docker/build-push-action@")
        && fields(entry(step, "with").body).push === "true",
    "candidate push");
    const isProbe = (step) => keys(step).includes("run") && /^\s*docker\s+run\b/.test(runCommand(step));
    const verified = onlyStep(steps, isProbe, "published runtime verification");
    const recorded = onlyStep(steps, (step) =>
        keys(step).includes("run") && /\$\{?GITHUB_STEP_SUMMARY\b/.test(runCommand(step)),
    "immutable reference summary");
    assert.ok(steps.indexOf(pushed) < steps.indexOf(verified), "verify only after publishing");
    assert.ok(steps.indexOf(verified) < steps.indexOf(recorded), "record only after verification succeeds");
    const built = onlyStep(items(entry(image, "steps").body), isProbe, "built runtime verification");
    for (const step of [pushed, verified, recorded, built]) {
        assert.ok(!keys(step).includes("if"), "artifact verification and reference recording must not be conditional");
        assert.ok(!keys(step).includes("continue-on-error"), "artifact failures must block the reference summary");
    }
    assert.ok(!keys(publish).includes("continue-on-error"), "publish must not hide failed artifact verification");
    const id = entry(pushed, "id").value;
    assert.match(id, /^[A-Za-z_][A-Za-z0-9_-]*$/);
    const digest = `\${{ steps.${id}.outputs.digest }}`;
    for (const step of [verified, recorded]) {
        assert.equal(
            fields(entry(step, "env").body).IMAGE_DIGEST, digest,
            "verify and record the digest returned by the actual push step",
        );
    }
    assert.match(runCommand(recorded), /\$\{IMAGE_DIGEST\}/);
    const probe = artifactProbe(verified);
    assert.equal(probe.args.at(-1), "ghcr.io/devsecninja/truenas-apps/open-archiver@${IMAGE_DIGEST}");
    assert.equal(probe.args.filter((arg) => arg === "--rm").length, 1);
    for (const [flag, value] of [
        ["--pull", "always"],
        ["--platform", "linux/amd64"],
        ["--network", "none"],
        ["--cap-drop", "ALL"],
        ["--security-opt", "no-new-privileges"],
        ["--entrypoint", "node"],
    ]) {
        assert.equal(probe.args.filter((arg) => arg === flag).length, 1, `expected one ${flag}`);
        assert.equal(probe.args[probe.args.indexOf(flag) + 1], value, flag);
    }
    assert.equal(probe.args.filter((arg) => arg === "--read-only").length, 1);
    assert.equal(
        probe.code, artifactProbe(built).code,
        "the pushed digest must pass the same UID, SQLite binding, and readable-artifact assertions as the build",
    );
});

test("image: SQLite binding check uses an absolute require without changing the /app working directory", () => {
    const instructions = source("services/open-archiver/image/Dockerfile")
        .replace(/\\\r?\n\s*/g, " ").split(/\r?\n/)
        .map((line) => line.trim()).filter((line) => line && !line.startsWith("#"));
    const workdirs = instructions.filter((line) => /^WORKDIR\s/i.test(line));
    assert.deepEqual(workdirs.map((line) => line.replace(/^WORKDIR\s+/i, "")), ["/app"]);
    const runs = instructions.filter((line) => /^RUN\s/i.test(line))
        .map((line) => line.replace(/^RUN\s+/i, ""));
    assert.equal(runs.filter((run) =>
        /require\(\s*['"]\/app\/packages\/backend\/node_modules\/sqlite3['"]\s*\)/.test(run)
    ).length, 1, "check the baked SQLite binding by its absolute module path");
    for (const run of runs) {
        assert.doesNotMatch(run, /(?:^|[;&|])\s*cd(?:\s|$)/, "RUN must not move subsequent commands out of /app");
    }
});
