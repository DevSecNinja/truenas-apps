import { execFileSync, spawn } from "node:child_process";
import { createServer, createConnection } from "node:net";

const binary = "/usr/lib/chromium/chromium-headless-shell";
const minimumVersion = [153, 0, 8010, 52];

let reportedVersion;
try {
  reportedVersion = execFileSync(binary, ["--version"], {
    encoding: "utf8",
    timeout: 10000,
    maxBuffer: 8192,
  }).trim();
} catch (error) {
  console.error(`Unable to verify Chromium version: ${error.message}`);
  process.exit(1);
}

const match = /^Chromium (\d+)\.(\d+)\.(\d+)\.(\d+)(?:\s|$)/.exec(reportedVersion);
if (!match) {
  console.error(`Unrecognized Chromium version: ${reportedVersion}`);
  process.exit(1);
}
const version = match.slice(1).map(Number);
const difference = version.findIndex((value, index) => value !== minimumVersion[index]);
if (difference !== -1 && version[difference] < minimumVersion[difference]) {
  console.error(
    `Browser disabled: ${reportedVersion} is below the security minimum ${minimumVersion.join(".")}. Update the DHI image before enabling browser features.`,
  );
  process.exit(1);
}

const sockets = new Set();
let stopping = false;
let exitCode = 0;
let killTimer;
const browser = spawn(binary, [
  "--no-sandbox",
  "--remote-debugging-address=127.0.0.1",
  "--remote-debugging-port=9223",
  ...process.argv.slice(2),
], { stdio: "inherit" });

// Keep the same stable CDP endpoint as the previous image without relying on
// Chromium accepting remote-debugging-address for a non-loopback listener.
const relay = createServer((client) => {
  const upstream = createConnection({ host: "127.0.0.1", port: 9223 });
  for (const socket of [client, upstream]) {
    sockets.add(socket);
    socket.on("error", (error) => {
      console.error(`CDP relay connection failed: ${error.message}`);
      client.destroy();
      upstream.destroy();
    });
    socket.on("close", () => {
      sockets.delete(socket);
      client.destroy();
      upstream.destroy();
    });
  }
  client.pipe(upstream);
  upstream.pipe(client);
});

function stop(code) {
  if (stopping) return;
  stopping = true;
  exitCode = code;
  relay.close();
  for (const socket of sockets) socket.destroy();
  browser.kill("SIGTERM");
  killTimer = setTimeout(() => browser.kill("SIGKILL"), 8000);
  killTimer.unref();
}

relay.on("error", (error) => {
  console.error(`Unable to start CDP relay: ${error.message}`);
  stop(1);
});
browser.once("error", (error) => {
  console.error(`Unable to start Chromium: ${error.message}`);
  stop(1);
  process.exit(1);
});
browser.once("exit", (code, signal) => {
  clearTimeout(killTimer);
  if (!stopping) {
    console.error(`Chromium exited unexpectedly: code=${code}, signal=${signal}`);
    exitCode = code || 1;
  }
  relay.close();
  for (const socket of sockets) socket.destroy();
  process.exit(exitCode);
});
process.once("SIGTERM", () => stop(0));
process.once("SIGINT", () => stop(0));
relay.listen(9222, "0.0.0.0");
