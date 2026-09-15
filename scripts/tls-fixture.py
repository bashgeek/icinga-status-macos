"""Ephemeral loopback HTTPS fixture. Never modifies the system trust store."""

import base64
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def respond(self, code, body):
        encoded = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", f"https://localhost:{self.server.server_port}/ok")
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self.respond(200, {"ok": True})

    def do_POST(self):
        expected = "Basic " + base64.b64encode(b"fixture:password").decode()
        if self.headers.get("Authorization") != expected:
            self.respond(401, {})
            return
        if self.headers.get("X-HTTP-Method-Override") != "GET":
            self.respond(400, {})
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        if "attrs" not in body:
            self.respond(400, {})
            return
        service = self.path.endswith("/services")
        attrs = {
            "name": "disk" if service else "fixture-host",
            "display_name": "Disk" if service else "Fixture host",
            "state": 2.0 if service else 0.0,
            "state_type": 1.0,
            "acknowledgement": 0.0,
            "downtime_depth": 0.0,
            "last_check_result": {"output": "Fixture result"},
        }
        if service:
            attrs["host_name"] = "fixture-host"
        attrs = {key: value for key, value in attrs.items() if key in body["attrs"]}
        self.respond(200, {"results": [{
            "name": "fixture-host!disk" if service else "fixture-host", "attrs": attrs,
        }]})


def openssl(directory, *args):
    subprocess.run(["openssl", *args], cwd=directory, check=True, capture_output=True)


with tempfile.TemporaryDirectory(prefix="icinga-tls-") as temporary:
    directory = Path(temporary)
    (directory / "ca.cnf").write_text(
        "[req]\ndistinguished_name=dn\nx509_extensions=ca\nprompt=no\n"
        "[dn]\nCN=Icinga Status Test CA\n[ca]\nbasicConstraints=critical,CA:TRUE\n"
        "keyUsage=critical,keyCertSign,cRLSign\n"
    )
    (directory / "server.cnf").write_text(
        "[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=localhost\n"
        "[server]\nbasicConstraints=critical,CA:FALSE\n"
        "keyUsage=critical,digitalSignature,keyEncipherment\n"
        "extendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost\n"
    )
    openssl(directory, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-config", "ca.cnf", "-keyout", "ca.key", "-out", "ca.pem")
    openssl(directory, "req", "-new", "-newkey", "rsa:2048", "-nodes", "-config", "server.cnf",
            "-keyout", "server.key", "-out", "server.csr")
    openssl(directory, "x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key",
            "-CAcreateserial", "-out", "server.pem", "-days", "1", "-extfile", "server.cnf", "-extensions", "server")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(directory / "server.pem", directory / "server.key")
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    environment = dict(os.environ, ICINGA_TLS_TEST_URL=f"https://localhost:{server.server_port}",
                       ICINGA_TLS_TEST_CA=str(directory / "ca.pem"))
    try:
        result = subprocess.run(["swift", "test", "--filter", "TransportIntegrationTests"], env=environment)
    finally:
        server.shutdown()
        server.server_close()
    raise SystemExit(result.returncode)
