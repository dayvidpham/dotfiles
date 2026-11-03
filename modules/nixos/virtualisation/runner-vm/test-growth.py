#!/usr/bin/env python3
"""Exercise an evaluated preStart against its exclusively owned test image."""
import json
import os
from pathlib import Path
import subprocess
import sys

cases = json.loads((Path(__file__).parent / 'testdata/growth-cases.yaml').read_text())
required = {'absent', 'smaller', 'equal', 'larger', 'repeat', 'unwritable'}
assert {c['name'] for c in cases} == required
script, image = map(Path, sys.argv[1:])
assert image.name == 'runner-vm-1.img' and image.parent == script.parent
assert not image.exists() and not image.is_symlink()
for case in cases:
    if case['initialMiB'] is not None:
        with image.open('xb') as f:
            f.truncate(case['initialMiB'] * 1024 * 1024)
            f.write(b'runner-growth-marker')
        os.chmod(image, 0o400 if case.get('readonly') else 0o600)
    initial_stat = image.stat() if image.exists() else None
    result = subprocess.run(['bash', str(script)], capture_output=True, text=True)
    assert (result.returncode != 0) == bool(case.get('readonly')), (case, result.stderr)
    if case['expectedMiB'] is None:
        assert not image.exists()
    else:
        current = image.stat()
        assert current.st_size == case['expectedMiB'] * 1024 * 1024
        assert (current.st_ino, current.st_uid, current.st_gid, current.st_mode) == (initial_stat.st_ino, initial_stat.st_uid, initial_stat.st_gid, initial_stat.st_mode)
        with image.open('rb') as f:
            assert f.read(20) == b'runner-growth-marker'
        if case.get('repeat'):
            subprocess.run(['bash', str(script)], check=True)
            assert image.stat().st_size == current.st_size
        image.unlink()
    print('PASS', case['name'])
