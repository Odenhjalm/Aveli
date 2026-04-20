import os
from pathlib import Path


PRODUCTION_ENV_VALUES = {"prod", "production", "live"}
CLOUD_RUNTIME_ENV_KEYS = ("FLY_APP_NAME", "K_SERVICE", "AWS_EXECUTION_ENV", "DYNO")


def parse_env_file(path: Path) -> dict:
    env = {}
    if not path.exists():
        return env

    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        env[key] = value

    return env


def cloud_runtime_active() -> bool:
    app_env = str(os.getenv("APP_ENV") or "").strip().lower()
    mcp_mode = str(os.getenv("MCP_MODE") or "").strip().lower()
    if app_env == "local" and mcp_mode == "local":
        return False
    return app_env in PRODUCTION_ENV_VALUES or any(os.getenv(key) for key in CLOUD_RUNTIME_ENV_KEYS)


def load_env():
    if os.getenv("AVELI_ENV_LOADED") == "1":
        return

    root = Path(__file__).resolve().parents[2]

    env_local = root / "backend" / ".env.local"
    env_default = root / "backend" / ".env"

    env_file = env_local if env_local.exists() else env_default

    if env_file.exists():
        env_vars = parse_env_file(env_file)
        env_source = str(env_file)

        # Load into process env ONLY if not already set
        for key, value in env_vars.items():
            if key not in os.environ:
                os.environ[key] = value
    else:
        env_source = "process environment"

    if cloud_runtime_active():
        if not os.getenv("APP_ENV"):
            raise RuntimeError("APP_ENV is missing in runtime environment")
        if not os.getenv("DATABASE_URL"):
            raise RuntimeError("DATABASE_URL is missing in runtime environment")
    else:
        required = {
            "APP_ENV": "local",
            "MCP_MODE": "local",
            "DATABASE_URL": "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local",
        }

        for key, expected in required.items():
            actual = os.getenv(key)
            if actual is None:
                raise RuntimeError(f"{key} is missing in environment")
            if key != "DATABASE_URL" and actual.lower() != expected:
                raise RuntimeError(f"{key} must be '{expected}', got '{actual}'")

    print(f"[AVELI ENV] Loaded from: {env_source}")
    print(f"[AVELI ENV] APP_ENV={os.getenv('APP_ENV')}")
    print(f"[AVELI ENV] MCP_MODE={os.getenv('MCP_MODE')}")

    os.environ["AVELI_ENV_LOADED"] = "1"
