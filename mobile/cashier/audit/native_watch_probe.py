"""Run native JVM regression tests. Keystore tests require an Android device.

Replaces the historical audit extractor after the service implementation changed.
Run from mobile/cashier with the pinned SDK prepared and JAVA_HOME configured.
"""
import os
from pathlib import Path
import subprocess

if __name__ == '__main__':
    android = Path(__file__).resolve().parents[1] / 'android'
    wrapper = android / ('gradlew.bat' if os.name == 'nt' else 'gradlew')
    raise SystemExit(subprocess.call([str(wrapper), ':app:testDebugUnitTest', '--no-daemon'], cwd=android))
