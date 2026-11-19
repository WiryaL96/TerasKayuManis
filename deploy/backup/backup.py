"""Private DB + Supabase Storage backup. Never print source errors/secrets.

Run from the root-owned systemd unit with a private EnvironmentFile. A manifest
is uploaded LAST: an incomplete run is never reported as a successful backup.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from urllib.parse import quote
from urllib.request import Request, urlopen


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    result = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def status(path, result, **values):
    path = Path(path)
    try:
        old = json.loads(path.read_text())
    except (OSError, ValueError):
        old = {}
    if result is not None:
        old.update(result=result, last_attempt=now())
    old.update(**values)
    temporary = path.with_suffix('.tmp')
    with open(temporary, 'w', encoding='utf8') as stream:
        os.chmod(temporary, 0o640)
        json.dump(old, stream)
    os.replace(temporary, path)


def pg_environment(dsn):
    from psycopg.conninfo import conninfo_to_dict
    values = conninfo_to_dict(dsn)
    env = os.environ.copy()
    # Never put DSN/password in pg_dump argv or diagnostic output.
    for key, value in values.items():
        env[{'dbname':'PGDATABASE','application_name':'PGAPPNAME'}.get(key, 'PG' + key.upper())] = str(value)
    return env


def command(args, env):
    subprocess.run(args, env=env, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=1800)


def storage_download(base, key, bucket, name, destination):
    url = base + '/storage/v1/object/authenticated/' + quote(bucket, safe='') + '/' + quote(name, safe='/')
    request = Request(url, headers={'Authorization': 'Bearer ' + key, 'apikey': key})
    with urlopen(request, timeout=120) as response, open(destination, 'wb') as output:
        for chunk in iter(lambda: response.read(1024 * 1024), b''):
            output.write(chunk)


def validate_bucket(s3, bucket, account):
    if not re.fullmatch(r'\d{12}', account):
        raise ValueError('AWS account required')
    args = dict(Bucket=bucket, ExpectedBucketOwner=account)
    # Each run has a unique prefix. Versioning would retain expired current
    # objects as noncurrent versions beyond the requested 30-day window.
    if s3.get_bucket_versioning(**args).get('Status') in ('Enabled', 'Suspended'):
        raise ValueError('Use a new unversioned backup bucket')
    block = s3.get_public_access_block(**args)['PublicAccessBlockConfiguration']
    if not all(block.get(k) for k in ('BlockPublicAcls', 'IgnorePublicAcls', 'BlockPublicPolicy', 'RestrictPublicBuckets')):
        raise ValueError('Bucket must be private')
    rules = s3.get_bucket_encryption(**args)['ServerSideEncryptionConfiguration']['Rules']
    if not any(r['ApplyServerSideEncryptionByDefault']['SSEAlgorithm'] == 'AES256' for r in rules):
        raise ValueError('SSE-S3 required')
    lifecycle = s3.get_bucket_lifecycle_configuration(**args)['Rules']
    if not any(r.get('Status') == 'Enabled' and r.get('Filter', {}).get('Prefix', r.get('Prefix')) == 'backups/' and r.get('Expiration', {}).get('Days') == 30 for r in lifecycle):
        raise ValueError('30 day lifecycle required')


def export_snapshot(folder):
    """Export one DB snapshot and its media, without choosing a cloud provider."""
    import psycopg
    folder = Path(folder)
    base = os.environ['SUPABASE_URL'].rstrip('/')
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    if not re.fullmatch(r'https://[a-z0-9]+\.supabase\.co', base):
        raise ValueError('Expected Supabase HTTPS URL')
    manifest = {'format': 1, 'created_at': now(), 'source_project': base.split('//')[1], 'files': [], 'counts': {}}
    revision = os.environ.get('BACKUP_APP_REVISION', '')
    if revision:
        if not re.fullmatch(r'[a-f0-9]{40}', revision):
            raise ValueError('Expected immutable application revision')
        manifest['app_revision'] = revision
    with psycopg.connect(os.environ['BACKUP_DATABASE_URL']) as conn:
        conn.execute('begin isolation level repeatable read read only')
        snapshot = conn.execute('select pg_export_snapshot()').fetchone()[0]
        manifest['restore_roles'] = sorted({role for (roles,) in conn.execute("select roles from pg_policies where schemaname in ('public','tkm','auth','storage')") for role in roles if role != 'public'})
        manifest['restore_extensions'] = [dict(name=name, schema=schema) for name, schema in conn.execute("select e.extname,n.nspname from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname in ('pgcrypto','uuid-ossp','citext')")]
        objects = conn.execute('select bucket_id,name,updated_at,metadata from storage.objects order by bucket_id,name').fetchall()
        manifest['storage_object_count'] = len(objects)
        if conn.execute("select to_regclass('auth.users')").fetchone()[0]:
            manifest['auth_user_count'] = conn.execute('select count(*) from auth.users').fetchone()[0]
        buckets = conn.execute('select id,name,public,file_size_limit,allowed_mime_types from storage.buckets order by id').fetchall()
        manifest['storage_buckets'] = [dict(zip(('id','name','public','file_size_limit','allowed_mime_types'), row)) for row in buckets]
        for table in ('orders', 'payments', 'order_items', 'profiles'):
            manifest['counts'][table] = conn.execute('select count(*) from public.' + table).fetchone()[0]
        manifest['ledger'] = [str(v) for v in conn.execute('select coalesce(sum(amount_rp),0),coalesce(sum(received_rp),0),coalesce(sum(change_rp),0) from public.payments').fetchone()]
        dump = folder / 'database.dump'
        command(['pg_dump', '--format=custom', '--no-owner', '--no-acl', '--schema=public', '--schema=tkm', '--schema=auth', '--schema=storage', '--snapshot=' + snapshot, '--file=' + str(dump)], pg_environment(os.environ['BACKUP_DATABASE_URL']))
        def record(path, relative, **metadata):
            manifest['files'].append(dict(key=relative, sha256=digest(path), bytes=path.stat().st_size, **metadata))
        record(dump, 'database.dump')
        (folder / 'media').mkdir(mode=0o700)
        for media_bucket, name, updated, metadata in objects:
            relative = 'media/' + hashlib.sha256((media_bucket + '/' + name).encode()).hexdigest()
            media = folder / relative
            storage_download(base, key, media_bucket, name, media)
            if metadata and metadata.get('size') is not None and int(metadata['size']) != media.stat().st_size:
                raise ValueError('Storage object changed')
            record(media, relative, bucket=media_bucket, name=name, updated_at=str(updated), content_type=(metadata or {}).get('mimetype', 'application/octet-stream'))
        with psycopg.connect(os.environ['BACKUP_DATABASE_URL']) as check:
            current = check.execute('select bucket_id,name,updated_at,metadata from storage.objects order by bucket_id,name').fetchall()
            if current != objects:
                raise ValueError('Storage changed during backup')
    (folder / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    return manifest


def run():
    import boto3
    import psycopg
    bucket, account = os.environ['BACKUP_BUCKET'], os.environ['BACKUP_AWS_ACCOUNT']
    base, key = os.environ['SUPABASE_URL'].rstrip('/'), os.environ['SUPABASE_SERVICE_ROLE_KEY']
    if not re.fullmatch(r'https://[a-z0-9]+\.supabase\.co', base):
        raise ValueError('Expected Supabase HTTPS URL')
    s3 = boto3.client('s3')  # EC2 instance profile, no static AWS secret required.
    validate_bucket(s3, bucket, account)
    prefix = 'backups/' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + os.urandom(4).hex() + '/'
    args = dict(Bucket=bucket, ExpectedBucketOwner=account, ServerSideEncryption='AES256')
    with tempfile.TemporaryDirectory(prefix='tkm-backup-') as folder:
        manifest = export_snapshot(folder)
        revision = Path('/opt/teraskayumanis/current/REVISION')
        if revision.exists() and 'app_revision' not in manifest:
            manifest['app_revision'] = revision.read_text(encoding='utf-8').strip()
        for item in manifest['files']:
            path = Path(folder) / item['key']
            with open(path, 'rb') as stream:
                s3.put_object(**args, Key=prefix + item['key'], Body=stream, Metadata={'sha256': item['sha256']})
        s3.put_object(**args, Key=prefix + 'manifest.json', Body=json.dumps(manifest).encode(), ContentType='application/json')
    return prefix


def main():
    path = os.environ.get('BACKUP_STATUS_PATH', '/var/lib/teraskayumanis-backups/status.json')
    try:
        status(path, 'Sedang berjalan')
        prefix = run()
        status(path, 'Berhasil', last_success=now(), backup_prefix=prefix)
        print('Backup completed (database and media). Restore verification is separate.')
        return 0
    except Exception:
        # Subprocess, SDK and HTTP exceptions can contain credentials or signed
        # URLs. Preserve a redacted status, never dump their text into journald.
        try:
            status(path, 'Gagal — periksa konfigurasi privat dan akses backup')
        except OSError:
            pass
        print('Backup failed; no successful manifest was recorded.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
