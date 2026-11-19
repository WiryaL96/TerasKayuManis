"""Migrations and Go integration against an owned disposable Docker database.

Never reads project .env or accesses an existing database/container.
"""
import os
from pathlib import Path
import secrets
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
NAME = 'tkm-mobile-test-' + uuid.uuid4().hex[:10]

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def sql(text):
    run(['docker', 'exec', '-i', '-w', '/workspace/tests', NAME, 'psql', '-U', 'postgres', '-d', 'tkm_mobile_test', '-X', '-v', 'ON_ERROR_STOP=1'], input=text, text=True, stdout=subprocess.DEVNULL)

def main():
    password = secrets.token_hex(16)
    started = False
    try:
        run(['docker', 'run', '--detach', '--name', NAME, '-v', str(ROOT/'backend') + ':/workspace:ro', '-e', 'POSTGRES_DB=tkm_mobile_test', '-e', 'POSTGRES_PASSWORD=' + password, '-p', '127.0.0.1::5432', 'postgres:17-alpine'], stdout=subprocess.DEVNULL)
        started = True
        for _ in range(45):
            if subprocess.run(['docker', 'exec', NAME, 'pg_isready', '-U', 'postgres'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                break
            time.sleep(1)
        else:
            raise RuntimeError('Disposable database did not start')
        sql((ROOT/'backend/tests/supabase_api_roles.sql').read_text())
        for migration in sorted((ROOT/'backend/migrations').glob('*.sql')):
            sql('begin;\n' + migration.read_text() + '\ncommit;')
            print('Applied', migration.name, flush=True)
            if migration.name.startswith('0003_'):
                sql((ROOT/'backend/tests/runtime_role.sql').read_text())
        sql("update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1;")
        for name in ['mobile_watch', 'pos_handoff', 'serverless_ops', 'order_flow']:
            sql((ROOT/f'backend/tests/{name}.sql').read_text())
            print('Passed SQL', name, flush=True)
        port = subprocess.check_output(['docker', 'port', NAME, '5432/tcp'], text=True).strip().split(':')[-1]
        env = {**os.environ, 'TEST_DATABASE_URL': f'postgres://postgres:{password}@127.0.0.1:{port}/tkm_mobile_test?sslmode=disable'}
        run(['go', 'test', './...'], cwd=ROOT/'backend', env=env)
        run(['go', 'vet', './...'], cwd=ROOT/'backend', env=env)
        print('PASS: migrations, SQL, Go integration, and vet',flush=True)
    finally:
        if started:
            run(['docker', 'rm', '--force', NAME], stdout=subprocess.DEVNULL)
            print('Disposable database removed',flush=True)

if __name__ == '__main__':
    main()
