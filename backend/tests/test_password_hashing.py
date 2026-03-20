from passlib.context import CryptContext

from app.auth import hash_password, verify_password


def test_hash_password_uses_bcrypt_sha256_for_long_passwords():
    password = ("prefix-" * 12) + "tail-A"
    other_password = ("prefix-" * 12) + "tail-B"

    hashed = hash_password(password)

    assert hashed.startswith("$bcrypt-sha256$")
    assert verify_password(password, hashed) is True
    assert verify_password(other_password, hashed) is False


def test_verify_password_accepts_legacy_bcrypt_hashes():
    legacy_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    legacy_context.handler("bcrypt").set_backend("os_crypt")

    password = "Secret123!"
    legacy_hash = legacy_context.hash(password)

    assert verify_password(password, legacy_hash) is True
    assert verify_password("Secret123!wrong", legacy_hash) is False


def test_verify_password_does_not_crash_for_long_password_against_legacy_bcrypt():
    legacy_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    legacy_context.handler("bcrypt").set_backend("os_crypt")

    legacy_hash = legacy_context.hash("short-password")
    long_password = "x" * 100

    assert verify_password(long_password, legacy_hash) is False
