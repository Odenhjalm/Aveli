import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

KEYWORDS = [
    "enroll",
    "access",
    "course",
    "read",
    "user",
    "permission",
    "auth",
]

def extract_functions(file_path: str, snippet: str) -> str:
    path = ROOT / file_path

    if not path.exists():
        return ""

    try:
        source = path.read_text(errors="ignore")
    except Exception:
        return ""

    try:
        tree = ast.parse(source)
    except Exception:
        return source[:2000]

    snippet_lower = snippet.lower()

    matches = []

    for node in ast.walk(tree):

        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):

            try:
                func_source = ast.get_source_segment(source, node)
            except Exception:
                continue

            if not func_source:
                continue

            func_name = node.name.lower()

            # 🔥 1. matcha på funktionsnamn
            if any(k in func_name for k in KEYWORDS):
                matches.append(func_source)
                continue

            # 🔥 2. matcha snippet
            if snippet_lower[:50] in func_source.lower():
                matches.append(func_source)

    # dedup
    seen = set()
    unique = []

    for f in matches:
        if f not in seen:
            seen.add(f)
            unique.append(f)

    # 🔥 fallback: returnera största funktioner om inget matchar
    if not unique:
        all_funcs = [
            ast.get_source_segment(source, n)
            for n in ast.walk(tree)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
        ]
        return "\n\n".join(all_funcs[:5])

    return "\n\n".join(unique[:5])
