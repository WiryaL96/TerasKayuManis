"""Windows/native PostgreSQL integration audit using NEW disposable data only.

Requires PostgreSQL binaries at .cache/postgres-17-tools/pgsql/bin, Go, and
deploy/backup/requirements.txt (or the cached .cache/operations-python modules).
Never reads application .env files or connects to the restaurant database.
"""
from pathlib import Path
import argparse
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--rush-seconds', type=int, default=0)
args = parser.parse_args()
if args.rush_seconds and not 30 <= args.rush_seconds <= 1800:
    raise SystemExit('Rush duration must be 30..1800 seconds')
BIN = ROOT / '.cache/postgres-17-tools/pgsql/bin'
if not (BIN / 'initdb.exe').is_file():
    raise SystemExit('Install native PostgreSQL test tools first; see module docstring')
RUN = Path(tempfile.mkdtemp(prefix='audit-db-', dir=ROOT / '.cache'))
password = secrets.token_hex(24)
pwfile = RUN / 'init-password'
pwfile.write_text(password)
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
env = dict(os.environ, PGHOST='127.0.0.1', PGPORT=str(port), PGUSER='test_runner',
           PGPASSWORD=password, PGDATABASE='teraskayumanis_test')
dsn = f'postgresql://test_runner:{password}@127.0.0.1:{port}/teraskayumanis_test?sslmode=disable'
env.update(TEST_DATABASE_URL=dsn, BACKUP_TEST_DATABASE_URL=dsn)
env['PATH'] = str(BIN) + os.pathsep + env['PATH']
env['PYTHONPATH'] = str(ROOT / '.cache/operations-python') + os.pathsep + env.get('PYTHONPATH', '')
result = {'sql_steps': [], 'logs': RUN.name, 'database': 'disposable loopback only', 'go_race_detector': False}


def run(label, command, cwd=ROOT, timeout=180):
    with (RUN / (label + '.log')).open('wb') as output:
        process = subprocess.run([str(v) for v in command], cwd=cwd, env=env, stdout=output,
                                 stderr=subprocess.STDOUT, timeout=timeout,
                                 creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    if process.returncode:
        raise RuntimeError(f'{label} failed: see .cache/{RUN.name}/{label}.log (credentials withheld)')
    print(label + ': passed', flush=True)


started = False
try:
    run('init', [BIN / 'initdb.exe', '-D', RUN / 'data', '-U', 'test_runner', '--pwfile', pwfile,
                 '--auth-host=scram-sha-256', '--auth-local=trust'])
    pwfile.unlink()
    run('start', [BIN / 'pg_ctl.exe', '-D', RUN / 'data', '-l', RUN / 'postgres.log', '-o',
                  f'-h 127.0.0.1 -p {port} -c wal_level=logical', '-w', 'start'])
    started = True
    run('createdb', [BIN / 'createdb.exe', 'teraskayumanis_test'])
    workflow = (ROOT / '.github/workflows/ci.yml').read_text().split('  backend:', 1)[1].split('  staff-integration:', 1)[0]
    for line in workflow.splitlines():
        match = re.search(r'- run: psql .*? -f (\S+)', line)
        if not match:
            continue
        file = match[1]
        if file == 'tests/cash_lifecycle.sql':
            run('enable-fixture', [BIN / 'psql.exe', '-v', 'ON_ERROR_STOP=1', '-c',
                                  'update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1'])
        run(Path(file).stem, [BIN / 'psql.exe', '-v', 'ON_ERROR_STOP=1', *(['-1'] if ' -1 ' in line else []), '-f', ROOT / 'backend' / file], ROOT / 'backend')
        result['sql_steps'].append(file)
    run('go-tests', ['go', 'test', '-json', '-count=1', '-timeout', '180s', './...'], ROOT / 'backend', 240)
    events = [json.loads(line) for line in (RUN / 'go-tests.log').read_text().splitlines() if line.startswith('{')]
    result['go'] = {action: sum(e.get('Action') == action and 'Test' in e for e in events) for action in ['pass', 'skip', 'fail']}
    run('go-vet', ['go', 'vet', './...'], ROOT / 'backend')
    result['go_vet'] = True
    run('restore-drill', [sys.executable, '-m', 'unittest', 'deploy.backup.test_restore_integration'])
    result['restore_drill'] = True
    if args.rush_seconds:
        env.update(TKM_RUSH_SECONDS=str(args.rush_seconds), TKM_RUSH_REPORT=str(ROOT / '.cache/audit-rush-result.json'))
        run('rush', ['go', 'test', '-count=1', '-v', '-run', '^TestServerlessRushHour$', '-timeout', f'{args.rush_seconds + 180}s', './internal/commerce'], ROOT / 'backend', args.rush_seconds + 200)
        result['rush'] = json.loads((ROOT / '.cache/audit-rush-result.json').read_text())
finally:
    if started:
        run('stop', [BIN / 'pg_ctl.exe', '-D', RUN / 'data', '-m', 'fast', '-w', 'stop'])
    (ROOT / '.cache/audit-db-result.json').write_text(json.dumps(result, indent=2))
print(json.dumps({key: value for key, value in result.items() if key != 'sql_steps'}, indent=2))
