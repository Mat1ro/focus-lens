#!/usr/bin/env python3
"""Sign personal builds with a persistent, private local identity.

No Apple account, network access, system root trust, or privacy settings changes.
The dedicated keychain is not left in the user's global search list.
"""
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys


def run(args, sensitive=(), input_text=None):
    result = subprocess.run(args, capture_output=True, text=True, input=input_text)
    if result.returncode:
        message = result.stderr.strip() or result.stdout.strip()
        for value in sensitive:
            message = message.replace(value, "<redacted>")
        raise RuntimeError(f"{Path(args[0]).name} failed ({result.returncode}): {message}")
    return result.stdout.strip()


def sign(app, directory):
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    keychain = directory / "FocusLens.keychain-db"
    password_file = directory / "password"
    certificate = directory / "certificate.pem"
    if keychain.exists() and not (password_file.exists() and certificate.exists()):
        raise RuntimeError("Signing identity is incomplete. Restore its backup; do not silently generate a replacement.")
    if not password_file.exists():
        password_file.write_text(secrets.token_urlsafe(48) + "\n")
        password_file.chmod(0o600)
    password = password_file.read_text().strip()
    private_key = directory / "private-key.pem"
    p12 = directory / "identity.p12"
    if not certificate.exists():
        run(["openssl", "req", "-new", "-newkey", "rsa:3072", "-x509", "-sha256", "-days", "3650",
             "-subj", "/CN=Focus Lens Local Development/", "-keyout", str(private_key), "-out", str(certificate),
             "-passout", f"file:{password_file}", "-addext", "basicConstraints=critical,CA:FALSE",
             "-addext", "keyUsage=critical,digitalSignature", "-addext", "extendedKeyUsage=critical,codeSigning"])
        private_key.chmod(0o600)
    if not keychain.exists():
        run(["openssl", "pkcs12", "-export", "-inkey", str(private_key), "-in", str(certificate),
             "-out", str(p12), "-passin", f"file:{password_file}", "-passout", "stdin",
             "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1"],
            (password,), input_text=password + "\n")
        p12.chmod(0o600)
        original = shlex.split(run(["security", "list-keychains", "-d", "user"]))
        try:
            run(["security", "create-keychain", "-p", password, str(keychain)], (password,))
            run(["security", "import", str(p12), "-k", str(keychain), "-P", password,
                 "-x", "-T", "/usr/bin/codesign"], (password,))
            run(["security", "set-key-partition-list", "-S", "apple-tool:,codesign:", "-s", "-k", password,
                 str(keychain)], (password,))
        finally:
            run(["security", "list-keychains", "-d", "user", "-s", *original])
        # The key now lives only in the non-extractable keychain item.
        private_key.unlink(missing_ok=True)
        p12.unlink(missing_ok=True)
    run(["security", "unlock-keychain", "-p", password, str(keychain)], (password,))
    fingerprint = run(["openssl", "x509", "-in", str(certificate), "-noout", "-fingerprint", "-sha1"])
    fingerprint = fingerprint.split("=", 1)[1].replace(":", "").strip()
    requirement = f'designated => identifier "dev.local.FocusLens" and certificate leaf = H"{fingerprint}"'
    original = shlex.split(run(["security", "list-keychains", "-d", "user"]))
    try:
        # Security.framework must be able to pair the certificate with its key
        # while codesign resolves the identity. Restore the search list below.
        run(["security", "list-keychains", "-d", "user", "-s", *original, str(keychain)])
        run(["codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain),
             "--timestamp=none", "--requirements", "=" + requirement, str(app)])
        run(["codesign", "--verify", "--strict", str(app)])
    finally:
        run(["security", "list-keychains", "-d", "user", "-s", *original])
        run(["security", "lock-keychain", str(keychain)])
    print("Signed with persistent local certificate; identity preserved across rebuilds.")


if __name__ == "__main__":
    try:
        sign(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).expanduser().resolve())
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
