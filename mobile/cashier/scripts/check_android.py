"""Sequential Android verification, avoiding Flutter registrant races.

No device, keystore, Supabase key, or restaurant access is needed. The release
artifact is unsigned unless android/key.properties has been privately configured.
"""
import argparse
from pathlib import Path
import os
import subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--java-home', default=os.environ.get('JAVA_HOME',''))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if not args.java_home:
        raise SystemExit('JDK17+ required. Pass --java-home or set JAVA_HOME.')
    child_env = {**os.environ, 'JAVA_HOME': args.java_home}
    def run(command, cwd=root):
        subprocess.run(command, cwd=cwd, check=True, env=child_env)
    run([args.flutter, 'build', 'apk', '--debug'])
    wrapper = root / 'android' / ('gradlew.bat' if os.name == 'nt' else 'gradlew')
    run([str(wrapper), ':app:testDebugUnitTest', ':app:assembleDebugAndroidTest', '--no-daemon'], root / 'android')
    run([args.flutter, 'build', 'apk', '--profile', '--target=lib/main_demo.dart', '--target-platform=android-arm64'])
    run([args.flutter, 'build', 'apk', '--release', '--target-platform=android-arm64'])
    run([args.flutter, 'pub', 'get', '--enforce-lockfile'],root/'perf_harness')
    run([args.flutter, 'build', 'apk', '--profile', '--target=integration_test/performance_test.dart', '--target-platform=android-arm64'],root/'perf_harness')
    print('PASS: debug app, native tests, instrumentation compilation, profile demo, unsigned release, and benchmark runner compilation', flush=True)

if __name__ == '__main__':
    main()
