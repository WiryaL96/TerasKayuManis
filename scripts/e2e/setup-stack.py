"""Provision ONLY the disposable loopback Supabase CLI stack, never a hosted DB."""
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit, quote
import os
import secrets
import psycopg
from psycopg import sql

root = Path(__file__).resolve().parents[2]
folder = root / '.cache' / 'staff-stack'
values = {}
for line in (folder / 'services.env').read_text().splitlines():
    if '=' in line:
        key, value = line.split('=', 1)
        values[key] = value.strip().strip('"').strip("'")
db_url = values['DB_URL']
api_url = values['API_URL']
if os.environ.get('TKM_E2E_ALLOW_LOCAL') != '1' or any(urlsplit(url).hostname != '127.0.0.1' for url in [db_url, api_url]):
    raise SystemExit('Explicit disposable loopback stack required')
if urlsplit(db_url).port != 54322 or urlsplit(api_url).port != 54321:
    raise SystemExit('Unexpected local Supabase ports')
password = secrets.token_urlsafe(32)
with psycopg.connect(db_url, autocommit=True) as db:
    for path in sorted((root / 'backend' / 'migrations').glob('*.sql')):
        with db.transaction():
            db.execute(path.read_text(encoding='utf-8'))
        print('Applied', path.name)
    db.execute(sql.SQL('create role tkm_e2e_runtime login inherit password {}').format(sql.Literal(password)))
    db.execute('grant tkm_runtime to tkm_e2e_runtime')
    db.execute("notify pgrst, 'reload schema'")
parsed = urlsplit(db_url)
runtime_url = urlunsplit(parsed._replace(netloc=f'tkm_e2e_runtime:{quote(password)}@127.0.0.1:54322'))
env = {
    'TKM_E2E_ALLOW_LOCAL': '1', 'DATABASE_URL': runtime_url,
    'SUPABASE_URL': api_url, 'SUPABASE_ANON_KEY': values['ANON_KEY'],
    'E2E_SERVICE_KEY': values['SERVICE_ROLE_KEY'], 'E2E_BASE_URL': 'http://127.0.0.1:3218',
    'APP_ENV': 'test', 'HOST': '127.0.0.1', 'PORT': '8081',
    'REALTIME_ORIGINS': 'http://127.0.0.1:3218',
    'NITRO_HOST': '127.0.0.1', 'NITRO_PORT': '3219',
    'NUXT_CASHIER_PIN_SECRET': secrets.token_hex(32),
    'NUXT_SITE_URL': 'http://127.0.0.1:3218', 'NUXT_GO_API_URL': 'http://127.0.0.1:8081',
    'NUXT_SUPABASE_URL': api_url, 'NUXT_SUPABASE_ANON_KEY': values['ANON_KEY'],
    'NUXT_SUPABASE_SERVICE_KEY': values['SERVICE_ROLE_KEY'],
    'NUXT_PUBLIC_SUPABASE_URL': api_url, 'NUXT_PUBLIC_SUPABASE_ANON_KEY': values['ANON_KEY'],
}
target = folder / 'app.env'
target.write_text(''.join(f'{key}={value}\n' for key, value in env.items()))
target.chmod(0o600)
print('Disposable app configuration written (credentials withheld)')
