import base64
import datetime
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID


spec = importlib.util.spec_from_file_location(
    "cert_sync", Path(__file__).with_name("cert_sync.py")
)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


def make_pair(hostname=sync.HOSTNAME, expired=False, future=False):
    key = ec.generate_private_key(ec.SECP256R1())
    now = datetime.datetime.now(datetime.timezone.utc)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, hostname)])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now + datetime.timedelta(days=1) if future else now - datetime.timedelta(days=2))
        .not_valid_after(now - datetime.timedelta(days=1) if expired else now + datetime.timedelta(days=2))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(hostname)]), critical=False)
        .sign(key, hashes.SHA256())
    )
    return (
        cert.public_bytes(serialization.Encoding.PEM),
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ),
    )


class CertificateSyncTests(unittest.TestCase):
    def test_valid_pair(self):
        sync.validate_pair(*make_pair())

    def test_invalid_pairs(self):
        cert, _ = make_pair()
        _, other_key = make_pair()
        for pair in (
            make_pair(hostname="wrong.example"),
            make_pair(expired=True),
            make_pair(future=True),
            (cert, other_key),
            (b"not a certificate", other_key),
        ):
            with self.subTest(), self.assertRaises(ValueError):
                sync.validate_pair(*pair)

    def test_install_renewal_and_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            pair = make_pair()
            self.assertTrue(sync.install_pair(*pair, destination))
            previous = (destination / "current").resolve()
            self.assertFalse(sync.install_pair(*pair, destination))
            renewed = make_pair()
            self.assertTrue(sync.install_pair(*renewed, destination))
            self.assertNotEqual(previous, (destination / "current").resolve())
            self.assertEqual((previous / "fullchain.pem").read_bytes(), pair[0])
            for name, data in zip(("fullchain.pem", "privkey.pem"), renewed):
                path = destination / "current" / name
                self.assertEqual(path.read_bytes(), data)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_failed_publish_preserves_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            original = make_pair()
            sync.install_pair(*original, destination)
            target = (destination / "current").readlink()
            with mock.patch.object(sync.os, "replace", side_effect=OSError):
                with self.assertRaises(OSError):
                    sync.install_pair(*make_pair(), destination)
            self.assertEqual((destination / "current").readlink(), target)
            self.assertEqual(len(list(destination.glob("generation-*"))), 1)
            self.assertFalse((destination / "next").exists())
            self.assertEqual((destination / "current" / "privkey.pem").read_bytes(), original[1])

    def test_invalid_chain_preserves_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            original = make_pair()
            sync.install_pair(*original, destination)
            target = (destination / "current").readlink()
            with self.assertRaises(sync.ssl.SSLError):
                sync.install_pair(b"invalid", original[1], destination)
            self.assertEqual((destination / "current").readlink(), target)

    def test_fetches_pair_in_one_verified_request(self):
        cert, key = make_pair()
        payload = json.dumps({
            "type": "kubernetes.io/tls",
            "data": {
                "tls.crt": base64.b64encode(cert).decode(),
                "tls.key": base64.b64encode(key).decode(),
            },
        }).encode()
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / "token"
            token_file.write_text("test-placeholder")
            config = {
                "api_url": "https://api.example:6443",
                "ca_file": "/example/ca.crt",
                "token_file": str(token_file),
            }
            with mock.patch.object(sync.ssl, "create_default_context") as context:
                with mock.patch.object(sync.urllib.request, "build_opener") as opener:
                    opener.return_value.open.return_value = io.BytesIO(payload)
                    self.assertEqual(sync.fetch_pair(config), (cert, key))
                    context.assert_called_once_with(cafile=config["ca_file"])
                    opener.return_value.open.assert_called_once()
                    request = opener.return_value.open.call_args.args[0]
                    self.assertEqual(request.full_url, config["api_url"] + sync.SECRET_PATH)
                    self.assertEqual(opener.return_value.open.call_args.kwargs["timeout"], 10)

    def test_rejects_insecure_or_ambiguous_api_urls(self):
        for url in (
            "http://api.example",
            "https://user@api.example",
            "https://api.example/path",
            "https://api.example?query=1",
            "https://api.example#fragment",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                sync.fetch_pair({"api_url": url})

    def test_rejects_redirects(self):
        with self.assertRaises(ValueError):
            sync.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.example")

    def test_fetch_failure_does_not_install(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(sync, "DESTINATION", Path(directory)):
                with mock.patch.object(sync.Path, "read_text", return_value="{}"):
                    with mock.patch.object(sync, "fetch_pair", side_effect=OSError):
                        with mock.patch.object(sync, "install_pair") as install:
                            with self.assertRaises(OSError):
                                sync.main()
                            install.assert_not_called()
        sync.signal.alarm(0)


if __name__ == "__main__":
    unittest.main()
