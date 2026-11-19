import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('tkm_backup',Path(__file__).with_name('backup.py'))
backup=importlib.util.module_from_spec(spec);spec.loader.exec_module(backup)

class BackupTests(unittest.TestCase):
 def test_failure_preserves_last_success_and_restore_proof(self):
  with tempfile.TemporaryDirectory() as folder:
   path=Path(folder)/'status.json'
   backup.status(path,'Berhasil',last_success='2026-10-24T20:00:00+00:00',restore_verified_at='2026-10-24T21:00:00+00:00')
   backup.status(path,'Gagal')
   value=json.loads(path.read_text());self.assertEqual(value['result'],'Gagal');self.assertEqual(value['last_success'],'2026-10-24T20:00:00+00:00');self.assertIn('restore_verified_at',value)
 def test_manifest_checksum_detects_changed_media(self):
  with tempfile.TemporaryDirectory() as folder:
   path=Path(folder)/'media';path.write_bytes(b'photo');before=backup.digest(path);path.write_bytes(b'changed');self.assertNotEqual(before,backup.digest(path))
 def test_bucket_must_be_private_encrypted_and_retained(self):
  class S3:
   public=False;days=30
   def get_bucket_versioning(self,**kw):return {}
   def get_public_access_block(self,**kw):return {'PublicAccessBlockConfiguration':{k:not self.public for k in ('BlockPublicAcls','IgnorePublicAcls','BlockPublicPolicy','RestrictPublicBuckets')}}
   def get_bucket_encryption(self,**kw):return {'ServerSideEncryptionConfiguration':{'Rules':[{'ApplyServerSideEncryptionByDefault':{'SSEAlgorithm':'AES256'}}]}}
   def get_bucket_lifecycle_configuration(self,**kw):return {'Rules':[{'Status':'Enabled','Prefix':'backups/','Expiration':{'Days':self.days}}]}
  s3=S3();backup.validate_bucket(s3,'private','123456789012');s3.public=True
  with self.assertRaises(ValueError):backup.validate_bucket(s3,'private','123456789012')
  s3.public=False;s3.days=90
  with self.assertRaises(ValueError):backup.validate_bucket(s3,'private','123456789012')
 def test_failure_never_logs_exception_secrets(self):
  with tempfile.TemporaryDirectory() as folder,patch.dict('os.environ',{'BACKUP_STATUS_PATH':str(Path(folder)/'status.json')}),patch.object(backup,'run',side_effect=RuntimeError('SECRET_DSN')),patch('builtins.print') as output:
   self.assertEqual(backup.main(),1)
   self.assertNotIn('SECRET_DSN',str(output.call_args_list))

if __name__=='__main__':unittest.main()
