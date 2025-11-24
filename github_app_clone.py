#!/usr/bin/env python3
import os, sys, time, subprocess, tempfile
from pathlib import Path

try:
    import requests, jwt
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "PyJWT"])
    import requests, jwt

def load_env(dotenv_path=".env"):
    if os.path.exists(dotenv_path):
        for raw in Path(dotenv_path).read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ[k.strip()] = v.strip().strip('"').strip("'")

def read_private_key():
    inline = os.getenv("GITHUB_PRIVATE_KEY_INLINE")
    path = os.getenv("GITHUB_PRIVATE_KEY_PATH")
    if inline:
        return inline.encode("utf-8")
    if path and os.path.exists(path):
        return Path(path).read_bytes()
    raise SystemExit("❌ Hittar ingen privatnyckel. Sätt GITHUB_PRIVATE_KEY_PATH eller GITHUB_PRIVATE_KEY_INLINE i .env")

def make_app_jwt(app_id:int, private_key_bytes:bytes)->str:
    now = int(time.time())
    payload = {"iat": now - 60, "exp": now + 9*60, "iss": app_id}
    t = jwt.encode(payload, private_key_bytes, algorithm="RS256")
    return t if isinstance(t, str) else t.decode("utf-8")

def get_installation_for_repo(app_jwt:str, owner:str, repo:str):
    url = f"https://api.github.com/repos/{owner}/{repo}/installation"
    headers = {"Authorization": f"Bearer {app_jwt}", "Accept":"application/vnd.github+json"}
    r = requests.get(url, headers=headers)
    if r.status_code == 404:
        raise SystemExit("❌ Appen är inte installerad på detta repo. Gå till din GitHub App → Install App → välj repot.")
    if r.status_code != 200:
        raise SystemExit(f"❌ Kunde inte hämta installation: {r.status_code} {r.text}")
    return r.json()

def get_installation_token(app_jwt:str, installation_id:int)->str:
    url = f"https://api.github.com/app/installations/{installation_id}/access_tokens"
    headers = {"Authorization": f"Bearer {app_jwt}", "Accept":"application/vnd.github+json"}
    r = requests.post(url, headers=headers)
    if r.status_code != 201:
        raise SystemExit(f"❌ Failed to get installation token: {r.status_code} {r.text}")
    return r.json()["token"]

def run(cmd, check=True, cwd=None, env=None):
    print("$ " + " ".join(cmd))
    return subprocess.run(cmd, check=check, cwd=cwd, env=env)

def main():
    import argparse, json
    p = argparse.ArgumentParser(description="GitHub App clone/push helper")
    p.add_argument("--repo", required=True, help="owner/repo, t.ex. Odenhjalm/andlig_app")
    p.add_argument("--branch", default="agent/work", help="feature-branch")
    p.add_argument("--dest", default="", help="målmapp (default: repo-namnet)")
    p.add_argument("--demo-commit", action="store_true", help="skapa tom commit och pusha")
    p.add_argument("--install-check", dest="install_check", action="store_true", help="visa installation-info och avsluta")
    args = p.parse_args()

    load_env()
    app_id = os.getenv("GITHUB_APP_ID")
    if not app_id or not app_id.isdigit():
        raise SystemExit("❌ GITHUB_APP_ID måste vara ett heltal i .env")
    pk = read_private_key()
    app_jwt = make_app_jwt(int(app_id), pk)

    owner, repo = args.repo.split("/", 1)

    install = get_installation_for_repo(app_jwt, owner, repo)
    installation_id = install["id"]

    if args.install_check:
        perms = install.get("permissions", {})
        print("✅ Installation hittad:")
        print(f"  installation_id: {installation_id}")
        print(f"  account: {install.get('account', {}).get('login')}")
        print(f"  permissions: {json.dumps(perms, indent=2)}")
        return

    inst_token = get_installation_token(app_jwt, installation_id)
    url_with_token = f"https://x-access-token:{inst_token}@github.com/{owner}/{repo}.git"

    dest = args.dest.strip() or repo
    run(["git", "clone", "--origin", "origin", url_with_token, dest])

    repo_dir = Path(dest)
    run(["git", "remote", "set-url", "origin", f"https://github.com/{owner}/{repo}.git"], cwd=repo_dir)
    run(["git", "checkout", "-b", args.branch], cwd=repo_dir)

    if args.demo_commit:
        (repo_dir/".agentmode.keep").write_text("agent touched\n", encoding="utf-8")
        run(["git", "add", ".agentmode.keep"], cwd=repo_dir)
        run(["git", "commit", "-m", "chore(agent): demo commit from agent"], cwd=repo_dir)

    env = os.environ.copy()
    askpass_script = "#!/usr/bin/env bash\necho x-access-token\n"
    with tempfile.TemporaryDirectory() as td:
        ap = Path(td)/"askpass.sh"
        ap.write_text(askpass_script)
        ap.chmod(0o755)
        env["GIT_ASKPASS"] = str(ap)
        env["GIT_TERMINAL_PROMPT"] = "0"
        run(["git", "push", f"https://x-access-token:{inst_token}@github.com/{owner}/{repo}.git", f"HEAD:{args.branch}"], cwd=repo_dir, env=env)

    print("✅ Klart.")

if __name__ == "__main__":
    main()
