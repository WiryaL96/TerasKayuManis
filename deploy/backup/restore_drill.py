"""Restore only to an empty, local tkm_restore_* database and an isolated media
directory. No production restore path exists here. Credentials stay in env.

A successful drill validates the dump, ledger totals, row counts and EVERY media
checksum. It does not activate orders or change production data/Auth identities.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import urlsplit

from backup import command, digest, now, pg_environment, status


def validate_target(dsn):
    from psycopg.conninfo import conninfo_to_dict
    cfg = conninfo_to_dict(dsn)
    if cfg.get('host') not in ('127.0.0.1', 'localhost', '::1') or not re.fullmatch(r'tkm_restore_[a-z0-9_]+', cfg.get('dbname', '')):
        raise ValueError('Only an isolated localhost restore DB is allowed')


def run(bucket, account, prefix, project, media_dir, read_object=None):
    import psycopg
    dsn = os.environ['RESTORE_DATABASE_URL']
    validate_target(dsn)
    if not re.fullmatch(r'backups/[0-9TZ]+-[a-f0-9]{8}/', prefix) or not re.fullmatch(r'\d{12}', account):
        raise ValueError('Invalid backup identity')
    destination = Path(media_dir)
    destination.mkdir(mode=0o700, exist_ok=False)
    if read_object is None:
        import boto3
        s3 = boto3.client('s3')
        args = dict(Bucket=bucket, ExpectedBucketOwner=account)
        read_object = lambda key: s3.get_object(**args, Key=key)['Body']
    raw = read_object(prefix + 'manifest.json').read(10 * 1024 * 1024 + 1)
    if len(raw) > 10 * 1024 * 1024:
        raise ValueError('Manifest too large')
    manifest = json.loads(raw)
    if manifest['format'] != 1 or manifest['source_project'] != project + '.supabase.co':
        raise ValueError('Wrong source project')
    with psycopg.connect(dsn) as conn:
        if conn.execute("select count(*) from pg_tables where schemaname not in ('pg_catalog','information_schema')").fetchone()[0]:
            raise ValueError('Restore target must be empty')
        # Fresh PostgreSQL databases contain an empty public schema. The dump
        # recreates it. No CASCADE: any existing objects make this fail closed.
        conn.execute('drop schema if exists public')
        # RLS policies refer to these roles. They have no login/privileges.
        from psycopg import sql
        for role in set(('tkm_runtime', 'service_role', 'anon', 'authenticated') + tuple(manifest.get('restore_roles', []))):
            if not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_]{0,62}', role) or role.startswith('pg_'):
                raise ValueError('Invalid policy role')
            if not conn.execute('select 1 from pg_roles where rolname=%s', (role,)).fetchone():
                conn.execute(sql.SQL('create role {} nologin nosuperuser nocreaterole nocreatedb').format(sql.Identifier(role)))
        for extension in manifest.get('restore_extensions', []):
            if extension.get('name') not in ('pgcrypto', 'uuid-ossp', 'citext') or not re.fullmatch(r'[a-z_][a-z0-9_]*', extension.get('schema', '')):
                raise ValueError('Unsupported restore extension')
            conn.execute(sql.SQL('create schema if not exists {}').format(sql.Identifier(extension['schema'])))
            conn.execute(sql.SQL('create extension if not exists {} with schema {}').format(sql.Identifier(extension['name']), sql.Identifier(extension['schema'])))
    with tempfile.TemporaryDirectory(prefix='tkm-restore-') as folder:
        dump = None
        seen = set()
        for item in manifest['files']:
            key = item['key']
            if key in seen or not (key == 'database.dump' or re.fullmatch(r'media/[a-f0-9]{64}', key)):
                raise ValueError('Invalid manifest entry')
            seen.add(key)
            path = Path(folder) / 'download'
            obj = read_object(prefix + key)
            with open(path, 'wb') as stream:
                for chunk in iter(lambda: obj.read(1024 * 1024), b''):
                    stream.write(chunk)
            if path.stat().st_size != item['bytes'] or digest(path) != item['sha256']:
                raise ValueError('Checksum mismatch')
            if key == 'database.dump':
                dump = Path(folder) / 'database.dump'
                path.rename(dump)
            else:
                # Retain safe hashed filenames. Manifest maps hashes back to
                # original bucket/path for later recovery to an ISOLATED project.
                path.rename(destination / key.split('/')[1])
        if dump is None:
            raise ValueError('Database dump missing')
        from psycopg.conninfo import conninfo_to_dict
        command(['pg_restore', '--no-owner', '--no-privileges', '--exit-on-error', '--single-transaction', '--dbname=' + conninfo_to_dict(dsn)['dbname'], str(dump)], pg_environment(dsn))
    with psycopg.connect(dsn) as restored:
        for table, count in manifest['counts'].items():
            if table not in ('orders','payments','order_items','profiles') or restored.execute('select count(*) from public.' + table).fetchone()[0] != count:
                raise ValueError('Restored row count mismatch')
        ledger = [str(v) for v in restored.execute('select coalesce(sum(amount_rp),0),coalesce(sum(received_rp),0),coalesce(sum(change_rp),0) from public.payments').fetchone()]
        if ledger != manifest['ledger']:
            raise ValueError('Restored ledger mismatch')
        if 'auth_user_count' in manifest and restored.execute('select count(*) from auth.users').fetchone()[0] != manifest['auth_user_count']:
            raise ValueError('Restored Auth user count mismatch')
        if 'storage_object_count' in manifest and restored.execute('select count(*) from storage.objects').fetchone()[0] != manifest['storage_object_count']:
            raise ValueError('Restored Storage object count mismatch')
        if restored.execute("select count(*) from public.payments p join public.orders o on o.id=p.order_id where p.amount_rp<>o.total or p.received_rp-p.amount_rp<>p.change_rp or o.payment_status<>'paid'").fetchone()[0]:
            raise ValueError('Restored payment integrity failed')
        if restored.execute("select 1 from information_schema.columns where table_schema='public' and table_name='settings' and column_name='orders_enabled'").fetchone():
            restored.execute('update public.settings set orders_enabled=false where id=1')
        # Expired link/session credentials must never become live in a clone.
        if restored.execute("select to_regclass('public.staff_access_links')").fetchone()[0]:
            restored.execute('delete from public.staff_access_links')
        if restored.execute("select to_regclass('auth.sessions')").fetchone()[0]:
            restored.execute('delete from auth.sessions')
    (destination / 'manifest.json').write_text(json.dumps(manifest), encoding='utf8')
    os.chmod(destination / 'manifest.json', 0o600)
    if os.environ.get('RESTORE_STATUS_PATH'):
        status(os.environ['RESTORE_STATUS_PATH'], None, restore_verified_at=now())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--project', required=True)
    parser.add_argument('--media-dir', required=True)
    args = parser.parse_args()
    try:
        run(os.environ['BACKUP_BUCKET'], os.environ['BACKUP_AWS_ACCOUNT'], args.prefix, args.project, args.media_dir)
        print('Restore drill completed.')
        return 0
    except Exception:
        print('Restore drill failed. Target and backup remain isolated; no verification recorded.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
