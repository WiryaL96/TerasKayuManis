import contextlib,io,json,unittest
from unittest.mock import patch
from deploy.backup import cloud_runner

class CloudStatusTests(unittest.TestCase):
 def test_backup_outcome_is_recorded_without_claiming_restore(self):
  for outcome in (0,1):
   with self.subTest(outcome=outcome),patch.dict('os.environ',{'SUPABASE_URL':'https://fixture.supabase.co','SUPABASE_SERVICE_ROLE_KEY':'synthetic-server-key'}),patch.object(cloud_runner,'main',return_value=outcome),patch.object(cloud_runner,'urlopen',return_value=contextlib.nullcontext()) as send:
    self.assertEqual(cloud_runner.run(),outcome)
    body=json.loads(send.call_args.args[0].data)
    self.assertEqual(body,{'p_result':'success' if outcome==0 else 'failed','p_restore_verified':False})
 def test_status_failure_is_reported_without_raw_provider_error(self):
  output=io.StringIO()
  with patch.dict('os.environ',{'SUPABASE_URL':'https://fixture.supabase.co','SUPABASE_SERVICE_ROLE_KEY':'synthetic-server-key'}),patch.object(cloud_runner,'main',return_value=0),patch.object(cloud_runner,'urlopen',side_effect=RuntimeError('synthetic-sensitive-provider-error')),contextlib.redirect_stdout(output):
   self.assertEqual(cloud_runner.run(),1)
  self.assertNotIn('synthetic-sensitive',output.getvalue())
