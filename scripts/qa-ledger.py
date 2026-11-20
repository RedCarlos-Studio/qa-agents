#!/usr/bin/env python3
"""Keep the per-client coverage ledger between QA runs.

save <run-dir> <client-dir>
    After a recognized verdict: copy <run-dir>/reports/coverage-ledger.md to
    <client-dir>/coverage-ledger.md. The previous ledger is kept in
    <client-dir>/coverage-history/ first. A missing or malformed new ledger
    leaves the client ledger untouched (warning, exit 0).

Exit 0 on success or a skipped save, 70 on an unsafe path.
"""
import os
import shutil
import sys
import time
from pathlib import Path


def warn(message):
    print('WARNING: ' + message, file=sys.stderr)


def save(run_dir, client_dir):
    src = run_dir / 'reports' / 'coverage-ledger.md'
    if not src.is_file() or src.is_symlink():
        warn('reports/coverage-ledger.md missing; client ledger unchanged')
        return 0
    try:
        text = src.read_text()
    except (OSError, UnicodeError):
        warn('reports/coverage-ledger.md unreadable; client ledger unchanged')
        return 0
    if not text.startswith('# Coverage ledger') or '| Module |' not in text:
        warn('coverage-ledger.md has an unexpected format; client ledger unchanged')
        return 0
    if not client_dir.is_dir() or client_dir.is_symlink():
        print('ERROR: client directory missing or a symlink', file=sys.stderr)
        return 70
    dst = client_dir / 'coverage-ledger.md'
    history = client_dir / 'coverage-history'
    if dst.is_symlink() or history.is_symlink():
        print('ERROR: client ledger path is a symlink', file=sys.stderr)
        return 70
    history.mkdir(mode=0o700, exist_ok=True)
    if dst.exists():
        stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
        shutil.copy2(dst, history / ('coverage-ledger-' + stamp + '.md'))
    tmp = client_dir / '.coverage-ledger.md.tmp'
    tmp.write_text(text)
    os.chmod(tmp, 0o600)
    os.replace(tmp, dst)
    print('Coverage ledger saved: ' + str(dst))
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] != 'save':
        print('Usage: qa-ledger.py save <run-dir> <client-dir>', file=sys.stderr)
        sys.exit(64)
    sys.exit(save(Path(sys.argv[2]), Path(sys.argv[3])))
