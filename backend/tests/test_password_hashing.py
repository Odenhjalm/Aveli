import bcrypt

from app.auth import hash_password, verify_password


def test_hash_password_uses_bcrypt_sha256_for_long_passwords():
    password = ("prefix-" * 12) + "tail-A"
    other_password = ("prefix-" * 12) + "tail-B"

    hashed = hash_password(password)

    assert hashed.startswith("$bcrypt-sha256$")
    assert verify_password(password, hashed) is True
    assert verify_password(other_password, hashed) is False


def test_verify_password_accepts_legacy_bcrypt_hashes():
    password = "Secret123!"
    legacy_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode(
        "ascii"
    )

    assert verify_password(password, legacy_hash) is True
    assert verify_password("Secret123!wrong", legacy_hash) is False


def test_verify_password_does_not_crash_for_long_password_against_legacy_bcrypt():
    legacy_hash = bcrypt.hashpw(b"short-password", bcrypt.gensalt()).decode("ascii")
    long_password = "x" * 100

    assert verify_password(long_password, legacy_hash) is False


def test_verify_password_returns_false_for_malformed_hashes():
    assert verify_password("Secret123!", "") is False
    assert verify_password("Secret123!", "$bcrypt-sha256$broken") is False
    assert verify_password("Secret123!", "$2b$12$broken") is False
