#!/usr/bin/env python3
"""Static checks for agents/: frontmatter, unique names per install set,
qa-rules references, symlinks and the Docker copy list. No network, no Docker.

Usage: python3 scripts/qa-check-agents.py
Exit 0 when all checks pass, 1 otherwise.
"""
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit('ERROR: PyYAML is required (pip install pyyaml)')

ROOT = Path(__file__).resolve().parent.parent
AGENTS = ROOT / 'agents'
RULES = AGENTS / 'qa-rules.md'

# Which agent files form each install set. Names must be unique inside a set.
LOCAL_SET = ['qa-lead.md', 'qa-runner.md', 'qa-api.md', 'qa-web.md', 'qa-mobile.md']
IMAGE_SET = ['qa-lead.md', 'qa-runner.md', 'qa-api.md', 'qa-web-server.md']
REQUIRED = {'name', 'description', 'tools', 'model'}
DASHES = re.compile('[–—←→⇒↔]')

errors = []


def fail(msg):
    errors.append(msg)


def frontmatter(path):
    text = path.read_text()
    if not text.startswith('---\n'):
        fail(f'{path.name}: no frontmatter')
        return None, text
    end = text.find('\n---\n', 4)
    if end < 0:
        fail(f'{path.name}: frontmatter not closed')
        return None, text
    try:
        data = yaml.safe_load(text[4:end])
    except yaml.YAMLError as exc:
        fail(f'{path.name}: YAML error: {exc}')
        return None, text
    if not isinstance(data, dict):
        fail(f'{path.name}: frontmatter is not a mapping')
        return None, text
    return data, text[end + 5:]


rule_sections = set(re.findall(r'^## (\d+)\. ', RULES.read_text(), re.M))
if not rule_sections:
    fail('qa-rules.md: no numbered sections found')

meta = {}
for path in sorted(AGENTS.glob('*.md')):
    if path.name == 'qa-rules.md':
        continue
    data, body = frontmatter(path)
    if data is None:
        continue
    meta[path.name] = data
    missing = REQUIRED - set(data)
    if missing:
        fail(f'{path.name}: missing keys {sorted(missing)}')
    tools = [t.strip() for t in str(data.get('tools', '')).split(',') if t.strip()]
    for tool in tools:
        if tool.startswith('mcp__claude-in-chrome') and tool != 'mcp__claude-in-chrome__*':
            fail(f'{path.name}: use mcp__claude-in-chrome__* (documented form), not {tool}')
    if path.name != 'qa-lead.md' and not {'Write', 'Edit'} <= set(tools):
        fail(f'{path.name}: specialists and qa-runner need Write and Edit in tools')
    refs = re.findall(r'qa-rules §(\d+)', body)
    for ref in refs:
        if ref not in rule_sections:
            fail(f'{path.name}: qa-rules §{ref} does not exist')
    if 'qa-rules' not in body and path.name != 'qa-runner.md':
        fail(f'{path.name}: does not reference qa-rules.md')

for label, members in (('local', LOCAL_SET), ('image', IMAGE_SET)):
    names = {}
    for member in members:
        if member not in meta:
            fail(f'{label} set: {member} missing or unparsable')
            continue
        name = meta[member].get('name')
        if name in names:
            fail(f'{label} set: name {name!r} used by {names[name]} and {member}')
        names[name] = member

for path in list(AGENTS.glob('*.md')):
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if DASHES.search(line):
            fail(f'{path.name}:{n}: em/en dash or arrow character')

claude_agents = ROOT / '.claude' / 'agents'
for member in LOCAL_SET:
    link = claude_agents / member
    if not link.is_symlink() or link.resolve() != (AGENTS / member).resolve():
        fail(f'.claude/agents/{member} must be a symlink to agents/{member}')
rules_link = ROOT / '.claude' / 'qa-rules.md'
if not rules_link.is_symlink() or rules_link.resolve() != RULES.resolve():
    fail('.claude/qa-rules.md must be a symlink to agents/qa-rules.md')

dockerfile = (ROOT / 'docker' / 'Dockerfile').read_text()
dockerignore = (ROOT / '.dockerignore').read_text()
for member in IMAGE_SET + ['qa-rules.md']:
    if f'agents/{member}' not in dockerfile:
        fail(f'Dockerfile does not copy agents/{member}')
    if f'!agents/{member}' not in dockerignore:
        fail(f'.dockerignore does not allow agents/{member}')
for member in ('qa-mobile.md', 'qa-web.md '):
    if f'agents/{member}' in dockerfile:
        fail(f'Dockerfile must not ship agents/{member.strip()}')

if errors:
    print('\n'.join('FAIL ' + e for e in errors))
    sys.exit(1)
print(f'OK: {len(meta)} agents, rules sections {sorted(rule_sections, key=int)}')
