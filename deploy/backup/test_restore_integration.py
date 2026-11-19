"""Optional integration: REAL pg_dump/pg_restore and checksums; fake S3 transport.
Requires a disposable localhost DB and PostgreSQL tools on PATH. Never connects
to Supabase/AWS. Run separately from the ordinary portable unit tests.
"""
import io
import importlib.util
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

folder=Path(__file__).parent
sys.path.insert(0,str(folder))
import backup
import restore_drill

@unittest.skipUnless(os.environ.get('BACKUP_TEST_DATABASE_URL'),'Disposable localhost database required')
class RestoreIntegration(unittest.TestCase):
 def test_dump_media_restore_and_corruption(self):
  import boto3
  import psycopg
  from psycopg.conninfo import conninfo_to_dict,make_conninfo
  source=os.environ['BACKUP_TEST_DATABASE_URL']
  if conninfo_to_dict(source).get('host')!='127.0.0.1' or conninfo_to_dict(source).get('dbname') not in ('tkm_operations','teraskayumanis_test','teraskayumanis_rush'):raise ValueError('Wrong fixture DB')
  target=make_conninfo(source,dbname='tkm_restore_drill')
  with psycopg.connect(source,autocommit=True) as conn:
   original_setting=conn.execute('select orders_enabled,pricing_confirmed_at from public.settings where id=1').fetchone()
   conn.execute('update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1')
   cashier=conn.execute("insert into public.profiles(id,full_name,role) values(gen_random_uuid(),'Kasir Backup Test','cashier') returning id").fetchone()[0]
   order=conn.execute("insert into public.orders(order_number,total,subtotal,reviewed_version) values(gen_random_uuid()::text,20000,20000,1) returning id").fetchone()[0]
   conn.execute("insert into public.order_items(order_id,product_name,quantity,unit_price,subtotal) values(%s,'Menu Backup Test',2,10000,20000)",(order,))
   conn.execute('select tkm.confirm_cash_verified(%s,%s,25000,1,0)',(order,cashier))
   conn.execute('create schema if not exists auth');conn.execute('create table if not exists auth.sessions(id uuid primary key,user_id uuid)')
   conn.execute('create schema if not exists storage')
   conn.execute('create table if not exists storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[])')
   conn.execute('create table if not exists storage.objects(bucket_id text,name text,updated_at timestamptz,metadata jsonb)')
   conn.execute("insert into storage.buckets values('media','media',true,null,null) on conflict do nothing")
   conn.execute("delete from storage.objects")
   conn.execute("insert into storage.objects values('media','products/photo.webp',now(),'{\"size\":5,\"mimetype\":\"image/webp\"}')")
   conn.execute('create database tkm_restore_drill')
  class S3:
   objects={}
   def get_bucket_versioning(self,**kw):return {}
   def get_public_access_block(self,**kw):return {'PublicAccessBlockConfiguration':{k:True for k in ('BlockPublicAcls','IgnorePublicAcls','BlockPublicPolicy','RestrictPublicBuckets')}}
   def get_bucket_encryption(self,**kw):return {'ServerSideEncryptionConfiguration':{'Rules':[{'ApplyServerSideEncryptionByDefault':{'SSEAlgorithm':'AES256'}}]}}
   def get_bucket_lifecycle_configuration(self,**kw):return {'Rules':[{'Status':'Enabled','Prefix':'backups/','Expiration':{'Days':30}}]}
   def put_object(self,**kw):
    value=kw['Body'];self.objects[kw['Key']]=value.read() if hasattr(value,'read') else value
   def get_object(self,**kw):return {'Body':io.BytesIO(self.objects[kw['Key']])}
  s3=S3()
  def download(base,key,bucket,name,path):Path(path).write_bytes(b'photo')
  def checked_command(args,env):
   result=subprocess.run(args,env=env,capture_output=True,text=True,timeout=60)
   if result.returncode:self.fail('Synthetic restore error: '+result.stderr)
  try:
   with tempfile.TemporaryDirectory() as local,patch.object(boto3,'client',return_value=s3),patch.object(backup,'storage_download',side_effect=download),patch.object(restore_drill,'command',side_effect=checked_command),patch.dict(os.environ,{
    'BACKUP_DATABASE_URL':source,'BACKUP_BUCKET':'synthetic-private','BACKUP_AWS_ACCOUNT':'123456789012','SUPABASE_URL':'https://synthetic.supabase.co','SUPABASE_SERVICE_ROLE_KEY':'synthetic-only','RESTORE_DATABASE_URL':target}):
    prefix=backup.run()
    self.assertTrue(prefix+'manifest.json' in s3.objects)
    restore_drill.run('synthetic-private','123456789012',prefix,'synthetic',Path(local)/'media')
    with psycopg.connect(target) as clone:
     self.assertFalse(clone.execute('select orders_enabled from public.settings').fetchone()[0])
     self.assertEqual(clone.execute('select amount_rp,received_rp,change_rp,cashier_name from public.payments where order_id=%s',(order,)).fetchone(),(20000,25000,5000,'Kasir Backup Test'))
    manifest=json.loads(s3.objects[prefix+'manifest.json']);media=[x for x in manifest['files'] if x['key'].startswith('media/')][0]
    self.assertEqual((Path(local)/'media'/media['key'].split('/')[1]).read_bytes(),b'photo')
    if os.environ.get('AGE_BINARY'):
     import artifact_backup
     identity=Path(local)/'identity.txt'
     subprocess.run([os.environ['AGE_KEYGEN_BINARY'],'-o',str(identity)],capture_output=True,check=True)
     recipient=subprocess.check_output([os.environ['AGE_KEYGEN_BINARY'],'-y',str(identity)],text=True).strip()
     with psycopg.connect(source,autocommit=True) as conn:conn.execute('create database tkm_restore_artifact')
     with patch.dict(os.environ,{'BACKUP_AGE_RECIPIENT':recipient,'RESTORE_DATABASE_URL':make_conninfo(source,dbname='tkm_restore_artifact')}):
      archive=Path(local)/'encrypted.age'
      artifact_backup.build(archive)
      artifact_backup.restore(archive,identity,'synthetic',Path(local)/'artifact-media')
     with psycopg.connect(make_conninfo(source,dbname='tkm_restore_artifact')) as clone:
      self.assertFalse(clone.execute('select orders_enabled from public.settings').fetchone()[0])
      self.assertEqual(clone.execute('select count(*) from public.payments where order_id=%s',(order,)).fetchone()[0],1)
    s3.objects[prefix+media['key']]=b'corrupted'
    # A separate empty clone is required for another restore attempt.
    with psycopg.connect(source,autocommit=True) as conn:conn.execute('create database tkm_restore_corrupt')
    with patch.dict(os.environ,{'RESTORE_DATABASE_URL':make_conninfo(source,dbname='tkm_restore_corrupt')}):
     with self.assertRaises(ValueError):restore_drill.run('synthetic-private','123456789012',prefix,'synthetic',Path(local)/'bad-media')
  finally:
   with psycopg.connect(source,autocommit=True) as conn:
    conn.execute('drop database if exists tkm_restore_drill with (force)');conn.execute('drop database if exists tkm_restore_corrupt with (force)');conn.execute('drop database if exists tkm_restore_artifact with (force)')
    conn.execute('drop schema storage cascade');conn.execute('drop schema auth cascade')
    conn.execute('delete from tkm.outbox_events where order_id=%s',(order,));conn.execute('delete from public.order_status_history where order_id=%s',(order,));conn.execute('delete from public.payments where order_id=%s',(order,));conn.execute('delete from public.orders where id=%s',(order,));conn.execute('delete from public.profiles where id=%s',(cashier,))
    conn.execute('update public.settings set orders_enabled=%s,pricing_confirmed_at=%s where id=1',original_setting)

if __name__=='__main__':unittest.main()
