"""Synthetic archives and mocked services: never contacts production."""
import hashlib
import io
import os
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from deploy import deploy_release as installer

SHA = 'a' * 40

def archive_bytes(extra=None, revision=SHA):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as archive:
        entries = [('server', b'synthetic executable'), ('web/server/index.mjs', b'export {}'), ('REVISION', revision.encode())]
        if extra:
            entries.append(extra)
        for name, content in entries:
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return data.getvalue()

class ArchiveTests(unittest.TestCase):
    def validate(self, contents):
        with tarfile.open(fileobj=io.BytesIO(contents), mode='r:gz') as archive:
            installer.validate_archive(archive, SHA)

    def test_accepts_matching_release(self):
        self.validate(archive_bytes())

    def test_rejects_wrong_revision(self):
        with self.assertRaisesRegex(ValueError, 'revision mismatch'):
            self.validate(archive_bytes(revision='b' * 40))

    def test_rejects_unexpected_traversal_and_duplicate_files(self):
        for name in ['web/../../etc/passwd', '/web/absolute', 'backend.env', 'REVISION']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.validate(archive_bytes((name, b'bad')))

    def test_rejects_oversized_unpacked_release(self):
        with patch.object(installer, 'MAX_EXTRACTED_BYTES', 1), self.assertRaisesRegex(ValueError, 'extraction limit'):
            self.validate(archive_bytes())

class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.releases = self.root / 'releases'
        self.releases.mkdir()
        self.previous = self.releases / 'manual-release'
        self.previous.mkdir()
        self.upload = self.root / 'release.tar.gz'
        self.upload.write_bytes(archive_bytes())
        self.digest = hashlib.sha256(self.upload.read_bytes()).hexdigest()
        for name, value in [('ROOT', self.root), ('RELEASES', self.releases), ('INCOMING', self.upload)]:
            patcher = patch.object(installer, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.current = patch.object(installer, 'current_release', return_value=self.previous)
        self.current.start()
        self.addCleanup(self.current.stop)

    def snapshot(self, destination, checksum):
        if hashlib.sha256(self.upload.read_bytes()).hexdigest() != checksum:
            raise ValueError('Release checksum mismatch')
        shutil.copyfile(self.upload, destination)

    def test_failed_health_restores_previous_release(self):
        with patch.object(installer, 'snapshot_upload', self.snapshot), patch.object(installer, 'activate') as activate, patch.object(installer, 'restart') as restart, patch.object(installer, 'healthy', side_effect=[False, True]):
            with self.assertRaisesRegex(RuntimeError, 'previous release restored'):
                installer.deploy(SHA, self.digest)
            self.assertEqual([call.args[0] for call in activate.call_args_list], [self.releases / ('ci-' + SHA + '-' + self.digest[:12]), self.previous])
            self.assertEqual(restart.call_count, 2)

    def test_bad_checksum_does_not_activate_or_restart(self):
        with patch.object(installer, 'snapshot_upload', self.snapshot), patch.object(installer, 'activate') as activate, patch.object(installer, 'restart') as restart:
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                installer.deploy(SHA, '0' * 64)
            activate.assert_not_called()
            restart.assert_not_called()

    @unittest.skipUnless(hasattr(os, 'O_NOFOLLOW'), 'Linux upload protection')
    def test_real_snapshot_checks_checksum(self):
        installer.snapshot_upload(self.root / 'snapshot', self.digest)
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            installer.snapshot_upload(self.root / 'snapshot', '0' * 64)

    @unittest.skipUnless(hasattr(os, 'O_NOFOLLOW'), 'Linux symlink protection')
    def test_upload_symlink_is_rejected(self):
        self.upload.unlink()
        target = self.root / 'other-file'
        target.write_bytes(b'private')
        self.upload.symlink_to(target)
        with self.assertRaises(OSError):
            installer.snapshot_upload(self.root / 'snapshot', self.digest)

if __name__ == '__main__':
    unittest.main()
