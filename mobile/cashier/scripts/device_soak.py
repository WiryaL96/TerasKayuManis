"""Read device health over a shift without login, mutation, or private logs.

Use while an operator exercises the fixture/staging app. This measures native
process memory and device battery/thermal state; it does not claim Flutter FPS.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser=argparse.ArgumentParser()
parser.add_argument('--adb',default='adb')
parser.add_argument('--serial',required=True)
parser.add_argument('--hours',type=float,default=6)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
if args.output.exists() or not args.output.parent.is_dir(): parser.error('Choose a new output in an existing directory')
if not 0<args.hours<=12: parser.error('hours must be >0 and <=12')
end=time.monotonic()+args.hours*3600
with args.output.open('x',encoding='utf-8') as stream:
    while time.monotonic()<end:
        sample={'at':time.time()}
        for name,command in {
            'memory':['dumpsys','meminfo','id.alrizky.teraskayumanis.cashier'],
            'battery':['dumpsys','battery'], 'thermal':['dumpsys','thermalservice'],
        }.items():
            result=subprocess.run([args.adb,'-s',args.serial,'shell',*command],capture_output=True,text=True,timeout=20)
            sample[name]={'code':result.returncode,'data':result.stdout[:32768]}
        stream.write(json.dumps(sample)+'\n');stream.flush()
        time.sleep(min(30,max(0,end-time.monotonic())))
