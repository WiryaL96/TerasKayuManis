#!/usr/bin/env python3
"""Root-owned installer; the Actions user may only submit a release and its hashes."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

ROOT = Path('/opt/teraskayumanis')
RELEASES = ROOT / 'releases'
INCOMING = Path('/var/lib/tkm-deploy/incoming/release.tar.gz')
MAX_ARCHIVE_BYTES = 150 * 1024 * 1024
MAX_EXTRACTED_BYTES = 600 * 1024 * 1024

def validate_archive(archive, sha):
    members = archive.getmembers()
    if not members or len(members) > 30000:
        raise ValueError('Invalid release file count')
    if sum(member.size for member in members) > MAX_EXTRACTED_BYTES:
        raise ValueError('Release exceeds extraction limit')
    names = set()
    for member in members:
        parts = Path(member.name).parts
        if not parts or parts[0] not in ('server', 'web', 'REVISION') or '..' in parts:
            raise ValueError('Unexpected release path')
        if member.name in names or member.isdev() or member.isfifo():
            raise ValueError('Duplicate or special release entry')
        names.add(member.name)
        # data_filter also rejects paths/links escaping the destination, devices
        # and FIFOs, and ignores archive owners and unsafe permission bits.
    revision = archive.extractfile('REVISION')
    if revision is None or revision.read(80).decode().strip() != sha:
        raise ValueError('Release revision mismatch')
    server = archive.getmember('server')
    entry = archive.getmember('web/server/index.mjs')
    if not server.isfile() or not entry.isfile():
        raise ValueError('Required application files missing')

def restart():
    # Stop the current dispatcher before starting the next version.
    for name in ('tkm-web', 'tkm-api'):
        subprocess.run(['systemctl', 'stop', name], check=True)
    subprocess.run(['systemctl', 'reset-failed', 'tkm-api', 'tkm-web'], check=True)
    for name in ('tkm-api', 'tkm-web'):
        subprocess.run(['systemctl', 'start', name], check=True)

def healthy():
    for _ in range(30):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8080/ready', timeout=2) as response:
                if response.status != 200:
                    raise ValueError('API not ready')
            request = urllib.request.Request('http://127.0.0.1/api/core/menu', headers={'Host':'16.79.69.36'})
            with urllib.request.urlopen(request, timeout=3) as response:
                if response.status == 200:
                    return True
        except (OSError, ValueError):
            pass
        time.sleep(1)
    return False

def activate(path):
    link = ROOT / '.current-next'
    link.unlink(missing_ok=True)
    link.symlink_to(path, target_is_directory=True)
    os.replace(link, ROOT / 'current')

def current_release():
    previous = (ROOT / 'current').resolve(strict=True)
    if previous.parent != RELEASES or not previous.is_dir():
        raise ValueError('Unexpected current release')
    return previous

def snapshot_upload(destination, checksum):
    fd = os.open(INCOMING, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as source, destination.open('wb') as output:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_ARCHIVE_BYTES:
            raise ValueError('Invalid release upload')
        digest = hashlib.sha256()
        copied = 0
        while chunk := source.read(1024 * 1024):
            copied += len(chunk)
            if copied > MAX_ARCHIVE_BYTES:
                raise ValueError('Release exceeds upload limit')
            digest.update(chunk)
            output.write(chunk)
        if digest.hexdigest() != checksum:
            raise ValueError('Release checksum mismatch')

def deploy(sha, checksum):
    if not re.fullmatch('[0-9a-f]{40}', sha) or not re.fullmatch('[0-9a-f]{64}', checksum):
        raise ValueError('Invalid deployment hashes')
    if INCOMING.is_symlink() or not INCOMING.is_file() or INCOMING.stat().st_size > MAX_ARCHIVE_BYTES:
        raise ValueError('Invalid release upload')
    previous = current_release()
    destination = RELEASES / ('ci-' + sha + '-' + checksum[:12])
    with tempfile.TemporaryDirectory(prefix='.ci-staging-', dir=RELEASES) as staging:
        staging = Path(staging)
        # Snapshot an unprivileged upload before validating/extracting it.
        snapshot = staging / 'release.tar.gz'
        snapshot_upload(snapshot, checksum)
        content = staging / 'content'
        content.mkdir()
        with tarfile.open(snapshot, 'r:gz') as archive:
            validate_archive(archive, sha)
            archive.extractall(content, filter='data')
        for directory, dirs, files in os.walk(content, followlinks=False):
            os.chmod(directory, 0o755)
            for name in files:
                path = Path(directory) / name
                if not path.is_symlink():
                    os.chmod(path, 0o644)
        os.chmod(content / 'server', 0o755)
        if destination.exists():
            if destination.is_symlink() or (destination / '.archive-sha256').read_text().strip() != checksum:
                raise ValueError('Existing release differs from this artifact')
        else:
            (content / '.archive-sha256').write_text(checksum + '\n')
            os.chmod(content / '.archive-sha256', 0o644)
            os.rename(content, destination)
    if destination == previous and healthy():
        print('Release already active:', sha, flush=True)
        return
    try:
        activate(destination)
        restart()
        if not healthy():
            raise RuntimeError('New release health check failed')
    except Exception:
        activate(previous)
        restart()
        if not healthy():
            raise RuntimeError('Deployment failed; previous release also failed health checks') from None
        raise RuntimeError('Deployment failed; previous release restored') from None
    print('DEPLOYED', sha, 'Previous release:', previous.name, flush=True)
    # Only CI-owned release directories are eligible for retention cleanup.
    retained = {destination, previous}
    managed = sorted([p for p in RELEASES.iterdir() if re.fullmatch('ci-[0-9a-f]{40}-[0-9a-f]{12}', p.name) and p.is_dir() and not p.is_symlink()], key=lambda p:p.stat().st_mtime, reverse=True)
    retained.update(managed[:3])
    for old in managed:
        if old not in retained and old.resolve().parent == RELEASES:
            shutil.rmtree(old)

def main():
    import fcntl
    if os.geteuid() != 0 or len(sys.argv) != 3:
        raise ValueError('Run the root-owned installer with revision and checksum')
    with open('/run/lock/tkm-deploy.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        deploy(sys.argv[1], sys.argv[2])

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Deployment error:', str(error), file=sys.stderr)
        sys.exit(1)
