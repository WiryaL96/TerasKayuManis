"""Scheduled backup wrapper; only sanitized outcome is sent to owner dashboard."""
import os,sys,json
from pathlib import Path
from urllib.request import Request,urlopen
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from deploy.backup.backup import main
def run():
 result=main()
 try:
  request=Request(os.environ['SUPABASE_URL'].rstrip('/')+'/rest/v1/rpc/record_backup_status',data=json.dumps({'p_result':'success' if result==0 else 'failed','p_restore_verified':False}).encode(),method='POST',headers={'Content-Type':'application/json','apikey':os.environ['SUPABASE_SERVICE_ROLE_KEY'],'Authorization':'Bearer '+os.environ['SUPABASE_SERVICE_ROLE_KEY']})
  with urlopen(request,timeout=15):pass
 except Exception:
  print('Backup status could not be recorded. Inspect the scheduled workflow.');result=1
 return result
if __name__=='__main__':raise SystemExit(run())
