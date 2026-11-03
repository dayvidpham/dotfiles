#!/usr/bin/env python3
"""Exercise an evaluated preStart against its exclusively owned test image."""
import json
import os
from pathlib import Path
import subprocess
import sys

cases = json.loads((Path(__file__).parent / 'testdata/growth-cases.yaml').read_text())
required = {'absent', 'smaller', 'equal', 'larger', 'repeat', 'unwritable',
            'existing-symlink', 'dangling-symlink', 'nonregular-directory', 'nonregular-fifo'}
assert {c['name'] for c in cases} == required
script, image = map(Path, sys.argv[1:])
assert image.name == 'runner-vm-1.img' and image.parent == script.parent
assert not image.exists() and not image.is_symlink()
for case in cases:
    kind = case.get('kind')
    if kind:
        target = image.parent / 'symlink-target'
        assert not target.exists() and not target.is_symlink()
        if kind == 'existing-symlink':
            target.write_bytes(b'unchanged-target')
            target.chmod(0o640)
            before = target.stat()
        if kind.endswith('symlink'):
            image.symlink_to(target)
        elif kind == 'directory':
            image.mkdir()
        elif kind == 'fifo':
            os.mkfifo(image)
        else:
            raise AssertionError('unknown fixture kind')
        original = image.lstat()
        result = subprocess.run(['bash', str(script)], capture_output=True, text=True, timeout=5)
        assert result.returncode != 0, (case, result.stdout, result.stderr)
        after = image.lstat()
        assert (after.st_ino, after.st_mode, after.st_uid, after.st_gid) == (original.st_ino, original.st_mode, original.st_uid, original.st_gid)
        if kind == 'existing-symlink':
            after_target = target.stat()
            assert (after_target.st_ino, after_target.st_mode, after_target.st_size, after_target.st_uid, after_target.st_gid) == (before.st_ino, before.st_mode, before.st_size, before.st_uid, before.st_gid)
            assert target.read_bytes() == b'unchanged-target'
            target.unlink()
        elif kind == 'dangling-symlink':
            assert not target.exists() and not target.is_symlink()
        if kind == 'directory':
            image.rmdir()
        else:
            image.unlink()
        print('PASS', case['name'])
        continue
    if case['initialMiB'] is not None:
        with image.open('xb') as f:
            f.truncate(case['initialMiB'] * 1024 * 1024)
            f.write(b'runner-growth-marker')
        os.chmod(image, 0o400 if case.get('readonly') else 0o600)
    initial_stat = image.stat() if image.exists() else None
    result = subprocess.run(['bash', str(script)], capture_output=True, text=True, timeout=5)
    assert (result.returncode != 0) == bool(case.get('failure')), (case, result.stderr)
    if case['expectedMiB'] is None:
        assert not image.exists()
    else:
        current = image.stat()
        assert current.st_size == case['expectedMiB'] * 1024 * 1024
        assert (current.st_ino, current.st_uid, current.st_gid, current.st_mode) == (initial_stat.st_ino, initial_stat.st_uid, initial_stat.st_gid, initial_stat.st_mode)
        with image.open('rb') as f:
            assert f.read(20) == b'runner-growth-marker'
        if case.get('repeat'):
            subprocess.run(['bash', str(script)], check=True, timeout=5)
            assert image.stat().st_size == current.st_size
        image.unlink()
    print('PASS', case['name'])
