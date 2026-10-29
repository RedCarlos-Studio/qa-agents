#!/usr/bin/env bash
set -euo pipefail
umask 077

python3 - "${QA_ROOT:-/srv/qa}" "${QA_KEEP_RUNS:-3}" "$@" <<'PY'
import argparse
import fcntl
import os
import pwd
import re
import shutil
import sys
from pathlib import Path

parser = argparse.ArgumentParser(
    description='Clean old QA clones and sessions; preserve reports. Default: dry run.'
)
parser.add_argument('--keep', type=int, default=int(sys.argv[2]))
parser.add_argument('--apply', action='store_true')
args = parser.parse_args(sys.argv[3:])
if args.keep < 1:
    parser.error('--keep must be at least 1')

root = Path(sys.argv[1]).resolve()
if not root.is_dir():
    raise SystemExit('ERROR: QA_ROOT does not exist')

with (root / 'runner.lock').open('a') as lock:
    if os.geteuid() == 0:
        user = pwd.getpwnam('qa')
        os.fchown(lock.fileno(), user.pw_uid, user.pw_gid)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit('ERROR: another QA run or cleanup is active')

    runs = root / 'runs'
    if not runs.is_dir():
        raise SystemExit('No runs to clean.')

    for client in sorted(runs.iterdir()):
        if not client.is_dir() or client.is_symlink():
            continue
        ordered = sorted(
            (p for p in client.iterdir() if p.is_dir() and not p.is_symlink()),
            key=lambda p: p.name,
            reverse=True
        )
        for run in ordered[args.keep:]:
            reports = run / 'reports'
            summary = reports / 'summary.md'
            if reports.is_symlink() or summary.is_symlink() or not summary.is_file():
                print('SKIP incomplete run:', run)
                continue
            try:
                first = next(iter(summary.read_text().splitlines()), '')
            except (OSError, UnicodeError):
                print('SKIP unreadable summary:', run)
                continue
            first = first.replace('**', '').strip().lstrip('# ').strip()
            pattern = r'(?:Release verdict:\s*|Verdict:\s*)?(GO WITH KNOWN ISSUES|NO-GO|GO)(?=$|[\s:.,;—–-])'
            if not re.match(pattern, first, re.I):
                print('SKIP unrecognized verdict:', run)
                continue
            for name in ('repo', 'claude-home'):
                target = run / name
                if target.is_symlink():
                    print('SKIP symlink:', target)
                elif target.is_dir():
                    print('DELETE' if args.apply else 'WOULD DELETE', target)
                    if args.apply:
                        shutil.rmtree(target)

    if not args.apply:
        print('Dry run only. Pass --apply to delete the listed directories.')
PY
