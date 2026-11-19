"""Fail before exporting secrets if this repository's artifact budget is full."""
import json
import os
import re
from urllib.request import Request, urlopen


def validate(artifacts, next_bytes):
    if not 1 <= next_bytes <= 100 * 1024 * 1024:
        raise ValueError('Invalid backup storage reserve')
    active = [item for item in artifacts if not item['expired']]
    total = sum(item['size_in_bytes'] for item in active)
    backups = sum(item['size_in_bytes'] for item in active if item['name'].startswith('tkm-private-backup-'))
    if total + next_bytes > 450 * 1024 * 1024 or backups + next_bytes > 80 * 1024 * 1024:
        raise ValueError('Artifact budget reached; move backups to dedicated storage')
    return {'active_artifact_bytes': total, 'backup_artifact_bytes': backups}


def main():
    try:
        repo = os.environ['GH_BACKUP_REPOSITORY']
        if not re.fullmatch(r'[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+', repo):
            raise ValueError('Invalid repository')
        artifacts = []
        for page in range(1, 101):
            request = Request(f'https://api.github.com/repos/{repo}/actions/artifacts?per_page=100&page={page}',
                              headers={'Authorization': 'Bearer ' + os.environ['GH_BACKUP_TOKEN'], 'Accept': 'application/vnd.github+json', 'User-Agent': 'tkm-private-backup'})
            with urlopen(request, timeout=20) as response:
                items = json.load(response)['artifacts']
            artifacts.extend(items)
            if len(items) < 100:
                break
        else:
            raise ValueError('Artifact inventory exceeded limit')
        print(json.dumps(validate(artifacts, int(os.environ['BACKUP_MAX_ARCHIVE_BYTES']))))
        return 0
    except Exception:
        print('Backup storage preflight failed. No new snapshot was exported.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
