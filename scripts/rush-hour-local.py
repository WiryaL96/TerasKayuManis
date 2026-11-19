"""Create a new loopback database, run migrations, load real Go handlers, stop DB.
No source credentials or restaurant connection string are read by this script.
"""
from pathlib import Path
import argparse,json,os,re,secrets,socket,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--seconds',type=int,default=300);parser.add_argument('--verify-backup',action='store_true');args=parser.parse_args()
if not 30<=args.seconds<=1800:raise SystemExit('Duration must be 30..1800 seconds')
BIN=ROOT/'.cache/postgres-17-tools/pgsql/bin'
RUN=Path(tempfile.mkdtemp(prefix='rush-hour-',dir=ROOT/'.cache'))
pw=secrets.token_hex(24);password=RUN/'password';password.write_text(pw)
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
env=dict(os.environ,PGHOST='127.0.0.1',PGPORT=str(port),PGUSER='test_runner',PGPASSWORD=pw,PGDATABASE='teraskayumanis_rush')
env['TEST_DATABASE_URL']=f'postgresql://test_runner:{pw}@127.0.0.1:{port}/teraskayumanis_rush?sslmode=disable'
env['TKM_RUSH_SECONDS']=str(args.seconds);env['TKM_RUSH_REPORT']=str(ROOT/'.cache/rush-hour-result.json')
def run(label,cmd,cwd=ROOT,timeout=180):
 with (RUN/(label+'.log')).open('wb') as out:r=subprocess.run([str(x) for x in cmd],cwd=cwd,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
 if r.returncode:raise RuntimeError(label+' failed; diagnostics in '+RUN.name)
 print(label+': passed',flush=True)
started=False
try:
 run('init',[BIN/'initdb.exe','-D',RUN/'data','-U','test_runner','--pwfile',password,'--auth-host=scram-sha-256','--auth-local=trust']);password.unlink()
 run('start',[BIN/'pg_ctl.exe','-D',RUN/'data','-l',RUN/'postgres.log','-o',f'-h 127.0.0.1 -p {port}','-w','start']);started=True
 run('createdb',[BIN/'createdb.exe','teraskayumanis_rush'])
 workflow=(ROOT/'.github/workflows/ci.yml').read_text().split('  backend:',1)[1].split('  staff-integration:',1)[0]
 for line in workflow.splitlines():
  m=re.search(r'- run: psql .*? -f (\S+)',line)
  if not m:continue
  file=m[1]
  if file=='tests/cash_lifecycle.sql':run('enable-fixture',[BIN/'psql.exe','-v','ON_ERROR_STOP=1','-c','update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1'])
  run(Path(file).stem,[BIN/'psql.exe','-v','ON_ERROR_STOP=1',*(['-1'] if ' -1 ' in line else []),'-f',ROOT/'backend'/file],cwd=ROOT/'backend')
 if args.verify_backup:
  env['BACKUP_TEST_DATABASE_URL']=env['TEST_DATABASE_URL']
  env['PATH']=str(BIN)+os.pathsep+env['PATH']
  env['AGE_BINARY']=str(ROOT/'.cache/backup-tools/age.exe')
  env['AGE_KEYGEN_BINARY']=str(ROOT/'.cache/backup-tools/age-keygen.exe')
  env['PYTHONPATH']=str(ROOT/'.cache/operations-python')+os.pathsep+env.get('PYTHONPATH','')
  run('backup-restore',[os.sys.executable,'-m','unittest','deploy.backup.test_restore_integration','-v'])
 run('rush',['go','test','-count=1','-v','-run','^TestServerlessRushHour$','-timeout',str(args.seconds+180)+'s','./internal/commerce'],cwd=ROOT/'backend',timeout=args.seconds+200)
 print((ROOT/'.cache/rush-hour-result.json').read_text(),flush=True)
finally:
 if started:run('stop',[BIN/'pg_ctl.exe','-D',RUN/'data','-m','fast','-w','stop'])
