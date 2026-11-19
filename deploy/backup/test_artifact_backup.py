import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
import artifact_backup
import artifact_budget


class ArchiveSafetyTests(unittest.TestCase):
    def test_traversal_symlinks_and_duplicate_members_are_rejected(self):
        for kind in ('traversal', 'symlink', 'duplicate'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / 'test.tar'
                with tarfile.open(archive, 'w') as tar:
                    item = tarfile.TarInfo('../outside' if kind == 'traversal' else 'manifest.json')
                    if kind == 'symlink':
                        item.type = tarfile.SYMTYPE
                        item.linkname = '/etc/passwd'
                        tar.addfile(item)
                    else:
                        item.size = 2
                        tar.addfile(item, io.BytesIO(b'{}'))
                        if kind == 'duplicate':
                            tar.addfile(item, io.BytesIO(b'{}'))
                with self.assertRaises(ValueError):
                    artifact_backup.extract(archive, Path(directory) / 'restored')
                self.assertFalse((Path(directory).parent / 'outside').exists())

    def test_storage_budget_preserves_unrelated_artifacts_and_counts_only_active_bytes(self):
        artifacts = [{'name': 'ci-build', 'expired': False, 'size_in_bytes': 400 * 1024 * 1024},
                     {'name': 'old-build', 'expired': True, 'size_in_bytes': 999 * 1024 * 1024}]
        self.assertEqual(artifact_budget.validate(artifacts, 2 * 1024 * 1024)['active_artifact_bytes'], 400 * 1024 * 1024)
        artifacts.append({'name': 'tkm-private-backup-1', 'expired': False, 'size_in_bytes': 80 * 1024 * 1024})
        with self.assertRaises(ValueError):
            artifact_budget.validate(artifacts, 1)

    def test_sensitive_exceptions_are_never_logged(self):
        with patch('sys.argv', ['artifact_backup.py', 'build', '--output', 'test.age']), patch.object(artifact_backup, 'build', side_effect=RuntimeError('PRIVATE_PASSWORD')), patch('builtins.print') as out:
            self.assertEqual(artifact_backup.main(), 1)
            self.assertNotIn('PRIVATE_PASSWORD', str(out.call_args_list))

    def test_backup_recipient_cannot_be_a_private_identity(self):
        with patch.dict(os.environ, {'BACKUP_AGE_RECIPIENT': 'AGE-SECRET-KEY-PRIVATE'}):
            with self.assertRaises(ValueError):
                artifact_backup.build('ignored.age')

    def test_transient_backup_errors_retry_with_backoff_without_logging_provider_secrets(self):
        with patch('sys.argv', ['artifact_backup.py', 'build', '--output', 'test.age']), patch.object(artifact_backup, 'build', side_effect=[ConnectionError('PRIVATE_CONNECTION'), {'encrypted_bytes': 1}]) as build, patch.object(artifact_backup.time, 'sleep') as sleep, patch('builtins.print') as out:
            self.assertEqual(artifact_backup.main(), 0)
            self.assertEqual(build.call_count, 2)
            sleep.assert_called_once_with(5)
            self.assertNotIn('PRIVATE_CONNECTION', str(out.call_args_list))


@unittest.skipUnless(shutil.which(os.environ.get('AGE_BINARY', 'age')), 'Install age for the real encryption round trip')
class EncryptionTests(unittest.TestCase):
    def test_encryption_roundtrip_tampering_wrong_key_and_size_limit(self):
        age = os.environ.get('AGE_BINARY', 'age')
        keygen = os.environ.get('AGE_KEYGEN_BINARY', str(Path(age).with_name('age-keygen.exe' if os.name == 'nt' else 'age-keygen')))
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            identity = directory / 'identity.txt'
            subprocess.run([keygen, '-o', str(identity)], check=True, capture_output=True)
            recipient = subprocess.check_output([keygen, '-y', str(identity)], text=True).strip()
            def fixture(folder):
                folder = Path(folder)
                (folder / 'database.dump').write_bytes(b'synthetic private database')
                value = {'files': [{'key': 'database.dump'}]}
                (folder / 'manifest.json').write_text(json.dumps(value), encoding='utf-8')
                return value
            with patch.dict(os.environ, {'BACKUP_AGE_RECIPIENT': recipient}), patch.object(artifact_backup, 'export_snapshot', side_effect=fixture):
                encrypted = directory / 'backup.age'
                result = artifact_backup.build(encrypted)
                self.assertNotIn(b'synthetic private database', encrypted.read_bytes())
                decrypted = directory / 'decrypted.tar'
                artifact_backup.checked([age, '-d', '-i', str(identity), '-o', str(decrypted), str(encrypted)])
                artifact_backup.extract(decrypted, directory / 'restored')
                self.assertEqual((directory / 'restored/database.dump').read_bytes(), b'synthetic private database')
                other = directory / 'wrong-key.txt'
                subprocess.run([keygen, '-o', str(other)], check=True, capture_output=True)
                with self.assertRaises(subprocess.CalledProcessError):
                    artifact_backup.checked([age, '-d', '-i', str(other), '-o', str(directory / 'wrong.tar'), str(encrypted)])
                broken = bytearray(encrypted.read_bytes())
                broken[-1] ^= 1
                damaged = directory / 'damaged.age'
                damaged.write_bytes(broken)
                with self.assertRaises(subprocess.CalledProcessError):
                    artifact_backup.checked([age, '-d', '-i', str(identity), '-o', str(directory / 'damaged.tar'), str(damaged)])
                self.assertGreater(result['encrypted_bytes'], 0)
                with patch.dict(os.environ, {'BACKUP_MAX_ARCHIVE_BYTES': '1024'}):
                    with self.assertRaises(ValueError):
                        artifact_backup.build(directory / 'oversize.age')
                    self.assertFalse((directory / 'oversize.age').exists())


if __name__ == '__main__':
    unittest.main()
