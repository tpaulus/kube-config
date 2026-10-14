#!/usr/bin/env python3
"""Pull the cert-manager TLS Secret from within Home Assistant Core."""

import base64
import datetime
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import ssl
import sys
import tempfile
import urllib.parse
import urllib.request

from cryptography import x509
from cryptography.hazmat.primitives import serialization


SECRET_PATH = "/api/v1/namespaces/home-assistant/secrets/home-assistant-tls"
HOSTNAME = "home.paulus.family"
DESTINATION = Path("/config/cert-sync/tls")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Kubernetes API redirects are not permitted")


def fetch_pair(config):
    url = config["api_url"].rstrip("/")
    parsed = urllib.parse.urlsplit(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("api_url must be an HTTPS Kubernetes API origin")
    token = Path(config["token_file"]).read_text().strip()
    if not token:
        raise ValueError("Empty Kubernetes API token")
    context = ssl.create_default_context(cafile=config["ca_file"])
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=context),
        NoRedirect(),
    )
    request = urllib.request.Request(
        url + SECRET_PATH,
        headers={"Authorization": "Bearer " + token, "Accept": "application/json"},
    )
    with opener.open(request, timeout=10) as response:
        payload = response.read(1024 * 1024 + 1)
    if len(payload) > 1024 * 1024:
        raise ValueError("Oversized Kubernetes API response")
    secret = json.loads(payload)
    if secret["type"] != "kubernetes.io/tls":
        raise ValueError("Expected a Kubernetes TLS Secret")
    return tuple(
        base64.b64decode(secret["data"][name], validate=True)
        for name in ("tls.crt", "tls.key")
    )


def validate_pair(cert_pem, key_pem):
    cert = x509.load_pem_x509_certificate(cert_pem)
    key = serialization.load_pem_private_key(key_pem, None)
    encoding = serialization.Encoding.DER
    form = serialization.PublicFormat.SubjectPublicKeyInfo
    if cert.public_key().public_bytes(encoding, form) != key.public_key().public_bytes(encoding, form):
        raise ValueError("Certificate and private key do not match")
    now = datetime.datetime.now(datetime.timezone.utc)
    if hasattr(cert, "not_valid_before_utc"):
        not_before, not_after = cert.not_valid_before_utc, cert.not_valid_after_utc
    else:
        not_before = cert.not_valid_before.replace(tzinfo=datetime.timezone.utc)
        not_after = cert.not_valid_after.replace(tzinfo=datetime.timezone.utc)
    if not not_before <= now < not_after:
        raise ValueError("Certificate is not currently valid")
    names = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    if HOSTNAME not in names.get_values_for_type(x509.DNSName):
        raise ValueError("Certificate does not cover the Home Assistant hostname")


def install_pair(cert_pem, key_pem, destination=DESTINATION):
    current = destination / "current"
    if current.is_symlink():
        active = current.resolve(strict=True)
        if (active / "fullchain.pem").read_bytes() == cert_pem and (active / "privkey.pem").read_bytes() == key_pem:
            return False
    elif current.exists():
        raise ValueError("Certificate current path must be a symlink")

    staging = Path(tempfile.mkdtemp(prefix="generation-", dir=destination))
    link = destination / "next"
    try:
        for name, data in (("fullchain.pem", cert_pem), ("privkey.pem", key_pem)):
            with (staging / name).open("xb") as output:
                os.chmod(output.name, 0o600)
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
        # Check the full chain can be loaded by Core's TLS implementation.
        ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER).load_cert_chain(
            staging / "fullchain.pem", staging / "privkey.pem"
        )
        link.unlink(missing_ok=True)
        link.symlink_to(staging.name)
        # One atomic pointer switch publishes the certificate and key together.
        os.replace(link, current)
    except BaseException:
        link.unlink(missing_ok=True)
        shutil.rmtree(staging)
        raise
    return True


def deadline(signum, frame):
    raise TimeoutError("Certificate sync exceeded its 45-second budget")


def main():
    os.umask(0o077)
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(45)
    DESTINATION.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(DESTINATION, 0o700)
    with (DESTINATION / "sync.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        config = json.loads(Path("/config/cert-sync/config.json").read_text())
        cert_pem, key_pem = fetch_pair(config)
        validate_pair(cert_pem, key_pem)
        changed = install_pair(cert_pem, key_pem)
    signal.alarm(0)
    print("changed" if changed else "unchanged")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never emit API responses, tokens, or private key material to HA logs.
        print(f"Certificate sync failed ({type(error).__name__})", file=sys.stderr)
        sys.exit(1)
