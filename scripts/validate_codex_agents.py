"""Validate this repository's minimal, documented Codex custom-agent schema.

Requires Python 3.11+. This is structural validation, not runtime discovery.
"""
from pathlib import Path
import tomllib

root = Path(__file__).resolve().parents[1]
expected = {"qa-web", "qa-mobile", "qa-api", "qa-lead"}
required = {"name", "description", "developer_instructions"}
files = sorted((root / ".codex" / "agents").glob("*.toml"))
seen = set()
for path in files:
    with path.open("rb") as stream:
        agent = tomllib.load(stream)
    if set(agent) != required:
        raise SystemExit(f"{path.name}: expected only {sorted(required)}")
    if any(not isinstance(agent[key], str) or not agent[key].strip() for key in required):
        raise SystemExit(f"{path.name}: required fields must be nonempty strings")
    if agent["name"] != path.stem or agent["name"] in seen:
        raise SystemExit(f"{path.name}: mismatched or duplicate name")
    seen.add(agent["name"])
if seen != expected:
    raise SystemExit(f"Expected {sorted(expected)}, found {sorted(seen)}")
print(f"PASS: {len(files)} TOML files; required string fields; unique matching names; minimal schema")
