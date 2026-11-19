"""Fail closed before distributing an APK. Does not sign, upload or install it."""
import argparse
import hashlib
from pathlib import Path
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('apk',type=Path)
parser.add_argument('--aapt',required=True)
parser.add_argument('--apksigner',required=True)
parser.add_argument('--certificate-sha256',required=True,help='Expected private production signing certificate digest')
args=parser.parse_args()
signer=subprocess.run([args.apksigner,'verify','--print-certs',str(args.apk)],capture_output=True,text=True)
if signer.returncode or 'Android Debug' in signer.stdout: raise SystemExit('Unsigned or debug-signed APK: distribution rejected')
expected=args.certificate_sha256.lower().replace(':','')
if len(expected)!=64 or f'certificate SHA-256 digest: {expected}' not in signer.stdout: raise SystemExit('Signing certificate does not match approved release identity')
badging=subprocess.check_output([args.aapt,'dump','badging',str(args.apk)],text=True)
if 'application-debuggable' in badging: raise SystemExit('Debuggable APK: distribution rejected')
if "name='id.alrizky.teraskayumanis.cashier'" not in badging: raise SystemExit('Unexpected application identity')
print('Release identity/signature/debug checks passed')
print('SHA256',hashlib.file_digest(args.apk.open('rb'),'sha256').hexdigest())
