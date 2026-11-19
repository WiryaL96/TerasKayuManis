"""Offsite backup for small installations: age encryption before private artifacts.

Only the public age recipient reaches the runner. Decryption keys stay offline.
Success is recorded separately, after GitHub acknowledges the artifact upload.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import time
from urllib.request import Request, urlopen

from backup import digest, export_snapshot


def checked(args, **kwargs):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=1800, **kwargs)


def retryable(error):
    if isinstance(error, (OSError, subprocess.CalledProcessError)):
        return True
    try:
        import psycopg
    except ImportError:
        return False
    return isinstance(error, psycopg.OperationalError)


def build(output):
    recipient = os.environ['BACKUP_AGE_RECIPIENT']
    if not re.fullmatch(r'age1[023456789acdefghjklmnpqrstuvwxyz]{58}', recipient):
        raise ValueError('An age X25519 public recipient is required')
    output = Path(output)
    if output.exists() or output.suffix != '.age':
        raise ValueError('Backup output must be a new .age file')
    maximum = int(os.environ.get('BACKUP_MAX_ARCHIVE_BYTES', str(2 * 1024 * 1024)))
    if not 1024 <= maximum <= 100 * 1024 * 1024:
        raise ValueError('Invalid archive budget')
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix='tkm-encrypted-backup-') as folder:
            raw = Path(folder) / 'snapshot'
            raw.mkdir(mode=0o700)
            manifest = export_snapshot(raw)
            archive = Path(folder) / 'snapshot.tar'
            with tarfile.open(archive, 'w') as tar:
                for name in ['manifest.json'] + [item['key'] for item in manifest['files']]:
                    tar.add(raw / name, arcname=name, recursive=False)
            checked([os.environ.get('AGE_BINARY', 'age'), '--encrypt', '--recipient', recipient, '--output', str(output), str(archive)])
        if output.stat().st_size > maximum:
            raise ValueError('Encrypted backup exceeds configured storage budget')
        os.chmod(output, 0o600)
        return {'encrypted_bytes': output.stat().st_size, 'sha256': digest(output), 'media_objects': sum(item['key'].startswith('media/') for item in manifest['files'])}
    except Exception:
        output.unlink(missing_ok=True)
        raise


def extract(archive, destination):
    """Accept exactly a manifest, a dump and hashed media; reject links/traversal."""
    destination = Path(destination)
    destination.mkdir(mode=0o700, exist_ok=False)
    total = 0
    seen = set()
    with tarfile.open(archive, 'r:') as tar:
        for member in tar:
            name = member.name
            if name in seen or not member.isfile() or not (name in ('manifest.json', 'database.dump') or re.fullmatch(r'media/[a-f0-9]{64}', name)):
                raise ValueError('Unsafe or duplicate archive member')
            total += member.size
            if total > int(os.environ.get('RESTORE_MAX_BYTES', str(512 * 1024 * 1024))):
                raise ValueError('Restore exceeds local size budget')
            target = destination / name
            target.parent.mkdir(mode=0o700, exist_ok=True)
            stream = tar.extractfile(member)
            if stream is None:
                raise ValueError('Missing archive content')
            with stream, target.open('xb') as out:
                os.chmod(target, 0o600)
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    out.write(block)
            seen.add(name)
    if not {'manifest.json', 'database.dump'} <= seen:
        raise ValueError('Incomplete archive')


def restore(encrypted, identity, project, media_dir):
    from restore_drill import run, validate_target
    validate_target(os.environ['RESTORE_DATABASE_URL'])
    with tempfile.TemporaryDirectory(prefix='tkm-restore-encrypted-') as folder:
        tar = Path(folder) / 'snapshot.tar'
        checked([os.environ.get('AGE_BINARY', 'age'), '--decrypt', '--identity', str(identity), '--output', str(tar), str(encrypted)])
        raw = Path(folder) / 'snapshot'
        extract(tar, raw)
        prefix = 'backups/19700101T000000Z-00000000/'
        def reader(key):
            if not key.startswith(prefix):
                raise ValueError('Unexpected backup path')
            relative = key[len(prefix):]
            if not (relative in ('manifest.json', 'database.dump') or re.fullmatch(r'media/[a-f0-9]{64}', relative)):
                raise ValueError('Unexpected backup file')
            return (raw / relative).open('rb')
        run('', '000000000000', prefix, project, media_dir, read_object=reader)


def record_result(result, restore_verified=False):
    if result not in ('success', 'failed'):
        raise ValueError('Invalid result')
    base = os.environ['SUPABASE_URL'].rstrip('/')
    if not re.fullmatch(r'https://[a-z0-9]+\.supabase\.co', base):
        raise ValueError('Expected Supabase HTTPS URL')
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    request = Request(base + '/rest/v1/rpc/record_backup_status',
                      data=json.dumps({'p_result': result, 'p_restore_verified': restore_verified}).encode(), method='POST',
                      headers={'Content-Type': 'application/json', 'apikey': key, 'Authorization': 'Bearer ' + key})
    with urlopen(request, timeout=20):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    package = commands.add_parser('build')
    package.add_argument('--output', required=True)
    status = commands.add_parser('status')
    status.add_argument('--result', choices=['success', 'failed'], required=True)
    drill = commands.add_parser('restore')
    drill.add_argument('--archive', required=True)
    drill.add_argument('--identity', required=True)
    drill.add_argument('--project', required=True)
    drill.add_argument('--media-dir', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'build':
            for attempt in range(3):
                try:
                    result = build(args.output)
                    break
                except Exception as error:
                    if attempt == 2 or not retryable(error):
                        raise
                    time.sleep(5 * 3 ** attempt)
            print(json.dumps(result))
        elif args.command == 'restore':
            restore(args.archive, args.identity, args.project, args.media_dir)
            print('Encrypted backup restore verified on isolated localhost database.')
        else:
            record_result(args.result)
        return 0
    except Exception:
        # Provider, DB and subprocess messages may include credentials or paths.
        print('Backup operation failed; no new success or restore proof was recorded.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
