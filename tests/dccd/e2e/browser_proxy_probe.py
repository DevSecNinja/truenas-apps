#!/usr/bin/env python
"""Public-image proxy probes and synthetic Chromium; never execute a real browser."""

import contextlib
import http.client
import http.server
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import re
import signal
import socket
import socketserver
import ssl
import subprocess
import sys
import threading
import time


def serve():
    class Canary(http.server.ThreadingHTTPServer):
        daemon_threads = True

        def get_request(self):
            connection, address = super().get_request()
            print(f"ACCEPT {self.server_port}", flush=True)
            return connection, address

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = b"controlled-private-canary"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    servers = [Canary(("0.0.0.0", port), Handler) for port in (80, 443, 8080)]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print("READY", flush=True)
    threading.Event().wait()


def wait_port(host, port):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=1):
                return
        except OSError:
            time.sleep(0.25)
    raise AssertionError(f"{host}:{port} did not become reachable within 45s")


def ready(private_ip):
    address = ipaddress.ip_address(private_ip)
    assert any(
        address in ipaddress.ip_network(network)
        for network in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
    ), f"Canary must have an RFC1918 address, got {address}"
    wait_port("policy-proxy", 3128)
    wait_port("private.fixture.test", 80)
    connection = http.client.HTTPConnection("private.fixture.test", 80, timeout=5)
    try:
        connection.request("GET", "/positive-control")
        response = connection.getresponse()
        assert response.status == 200
        assert response.read() == b"controlled-private-canary"
    finally:
        connection.close()
    print("proxy ready; controlled private endpoint reachable")


def deny(method, authority):
    connection = http.client.HTTPConnection("policy-proxy", 3128, timeout=8)
    target = authority if method == "CONNECT" else f"http://{authority}/denied"
    try:
        connection.request(method, target, headers={"Host": authority, "Connection": "close"})
        response = connection.getresponse()
        assert response.status == 403, (
            f"{method} {target}: expected 403, got {response.status} {response.reason}"
        )
        assert response.getheader("X-Squid-Error", "").startswith("ERR_ACCESS_DENIED"), (
            f"{method} {target}: 403 must originate from Squid's access policy"
        )
    finally:
        connection.close()


def denied_destinations(private_ip, method):
    # Only the canary, proxy-local loopback and isolated reserved literals.
    # These cases run with NO egress attachment, even if the policy regresses.
    hosts = (
        private_ip,
        "private.fixture.test",
        f"[::ffff:{private_ip}]",
        "192.0.2.1",
        "[::1]",
        "[fc00::1]",
        "[fe80::1]",
        "[2001:db8::1]",
    )
    port = 443 if method == "CONNECT" else 80
    for host in hosts:
        deny(method, f"{host}:{port}")
    print(f"{method if method == 'CONNECT' else 'HTTP'}: {len(hosts)} destinations denied with Squid 403")


def denied_ports():
    # A global literal isolates port ACLs from destination ACLs. This proxy
    # has no egress route, so even a regression cannot contact this address.
    for port in (22, 81, 3128, 8080, 8443):
        deny("GET", f"1.1.1.1:{port}")
    for port in (80, 8080, 8443):
        deny("CONNECT", f"1.1.1.1:{port}")
    print("ports: 8 requests denied with Squid 403")


def public():
    # Fixed public endpoint, no environment proxy settings or URL overrides.
    for secure in (False, True):
        if secure:
            connection = http.client.HTTPSConnection(
                "policy-proxy", 3128, timeout=25, context=ssl.create_default_context()
            )
            connection.set_tunnel("example.com", 443)
            target = "/"
        else:
            connection = http.client.HTTPConnection("policy-proxy", 3128, timeout=25)
            target = "http://example.com/"
        try:
            connection.request("GET", target, headers={"Host": "example.com"})
            response = connection.getresponse()
            assert response.status == 200, f"public {'HTTPS' if secure else 'HTTP'}: {response.status}"
            assert b"Example Domain" in response.read(65536), "Unexpected public response body"
        finally:
            connection.close()
        print("HTTPS example.com: 200 (verified TLS)" if secure else "HTTP example.com: 200")


def fake_chromium():
    """Only used by the executable fixture mounted at Chromium's fixed path."""
    if sys.argv[1:] == ["--version"]:
        print(os.environ["FAKE_CHROMIUM_VERSION"])
        raise SystemExit(int(os.environ.get("FAKE_VERSION_EXIT", "0")))

    print(f"FAKE_CHROMIUM_STARTED {os.getpid()}", flush=True)
    assert sys.argv[1:] == json.loads(os.environ["FAKE_EXPECTED_ARGS"]), sys.argv
    if "FAKE_CHILD_EXIT" in os.environ:
        raise SystemExit(int(os.environ["FAKE_CHILD_EXIT"]))

    def stop(signum, frame):
        print("FAKE_CHROMIUM_SIGTERM", flush=True)
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)

    class Echo(socketserver.BaseRequestHandler):
        def handle(self):
            with self.request.makefile("rb") as stream:
                for data in stream:
                    self.request.sendall(b"synthetic-cdp:" + data)

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    with Server(("127.0.0.1", 9223), Echo) as server:
        server.serve_forever()


def assert_cdp_closed():
    for port in (9222, 9223):
        try:
            connection = socket.create_connection(("127.0.0.1", port), timeout=1)
        except ConnectionRefusedError:
            continue
        connection.close()
        raise AssertionError(f"CDP port {port} is still open")


@contextlib.contextmanager
def launcher(version, args=(), **fake_environment):
    # Reuse only Playwright's bundled Node, not its browser API or installers.
    package = importlib.util.find_spec("playwright")
    assert package is not None and package.origin, "Public client image lacks Playwright"
    node = Path(package.origin).parent / "driver" / "node"
    assert node.is_file(), f"Bundled Node not found: {node}"
    assert_cdp_closed()
    environment = dict(os.environ)
    environment.update(
        FAKE_CHROMIUM_VERSION=version,
        FAKE_EXPECTED_ARGS=json.dumps([
            "--no-sandbox",
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=9223",
            *args,
        ]),
        **fake_environment,
    )
    process = subprocess.Popen(
        [str(node), "/opt/browser/launch.mjs", *args],
        env=environment, start_new_session=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        yield process
    finally:
        # Kill only this launcher's own process group on assertion/timeout.
        # The enclosing Docker container is also uniquely owned by this test.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate(timeout=5)


def assert_fake_reaped(output):
    match = re.search(r"FAKE_CHROMIUM_STARTED (\d+)", output)
    assert match, f"Fake Chromium was not executed:\n{output}"
    try:
        os.kill(int(match.group(1)), 0)
    except ProcessLookupError:
        return
    raise AssertionError(f"Fake Chromium survived its supervisor:\n{output}")


def launcher_reject():
    cases = (
        ("Chromium 153.0.8010.52", "9", "Unable to verify Chromium version", "failed version probe"),
        ("not a Chromium version", "0", "Unrecognized Chromium version", "malformed version"),
        ("Chromium 153.0.8010.47", "0", "below the security minimum 153.0.8010.52", "Chromium 153.0.8010.47"),
        ("Chromium 153.0.8010.51", "0", "below the security minimum 153.0.8010.52", "Chromium 153.0.8010.51"),
    )
    for version, exit_code, diagnostic, description in cases:
        with launcher(version, FAKE_VERSION_EXIT=exit_code) as process:
            output, _ = process.communicate(timeout=15)
            assert process.returncode == 1, output
            assert diagnostic in output, output
            assert "FAKE_CHROMIUM_STARTED" not in output, output
            assert_cdp_closed()
        print(f"launcher: {description} rejected before spawn")


def connect_synthetic_cdp(process):
    deadline = time.monotonic() + 10
    expected = b"synthetic-cdp:request\n"
    while time.monotonic() < deadline:
        if process.poll() is not None:
            output, _ = process.communicate(timeout=2)
            raise AssertionError(f"Launcher exited before CDP was ready:\n{output}")
        connection = None
        try:
            connection = socket.create_connection(("127.0.0.1", 9222), timeout=1)
            connection.sendall(b"request\n")
            received = b""
            while len(received) < len(expected):
                chunk = connection.recv(len(expected) - len(received))
                if not chunk:
                    break
                received += chunk
            if received == expected:
                return connection
        except OSError:
            pass
        if connection is not None:
            connection.close()
        time.sleep(0.1)
    raise AssertionError("Synthetic CDP relay did not become ready within 10s")


def launcher_minimum(args):
    with launcher("Chromium 153.0.8010.52", args) as process:
        with connect_synthetic_cdp(process) as connection:
            print("launcher: exact minimum accepted; source flags forwarded; CDP relay verified")
            process.send_signal(signal.SIGTERM)
            output, _ = process.communicate(timeout=12)
            assert process.returncode == 0, output
            assert "FAKE_CHROMIUM_SIGTERM" in output, output
            assert_fake_reaped(output)
            try:
                assert connection.recv(1) == b"", "CDP client socket survived SIGTERM"
            except ConnectionResetError:
                pass  # Reset, like EOF, proves the held relay socket was closed.
            assert_cdp_closed()
    print("launcher: SIGTERM reaped fake Chromium and closed CDP sockets")


def launcher_exit():
    for exit_code in (0, 7):
        with launcher("Chromium 153.0.8010.52", FAKE_CHILD_EXIT=str(exit_code)) as process:
            output, _ = process.communicate(timeout=15)
            assert process.returncode == (exit_code or 1), output
            assert f"Chromium exited unexpectedly: code={exit_code}" in output, output
            assert_fake_reaped(output)
            assert_cdp_closed()
        print(f"launcher: unexpected child exit {exit_code} failed closed")


if __name__ == "__main__":
    if Path(sys.argv[0]).name == "chromium-headless-shell":
        fake_chromium()
        raise SystemExit(0)
    mode = sys.argv[1]
    if mode == "serve":
        serve()
    elif mode == "ready":
        ready(sys.argv[2])
    elif mode == "deny-http":
        denied_destinations(sys.argv[2], "GET")
    elif mode == "deny-connect":
        denied_destinations(sys.argv[2], "CONNECT")
    elif mode == "deny-ports":
        denied_ports()
    elif mode == "public":
        public()
    elif mode == "launcher-reject":
        launcher_reject()
    elif mode == "launcher-minimum":
        launcher_minimum(sys.argv[2:])
    elif mode == "launcher-exit":
        launcher_exit()
    else:
        raise SystemExit(f"Unknown probe mode: {mode}")
