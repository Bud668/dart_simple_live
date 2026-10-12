#!/usr/bin/env python3
import os,subprocess,sys
def windows_path(path): return 'Z:' + path.replace('/', '\\')
args=[]
for arg in sys.argv[1:]:
 key,sep,value=arg.partition('=')
 if sep and value.startswith('/'): arg=key+'='+windows_path(value)
 elif arg.startswith('/'): arg=windows_path(arg)
 args.append(arg)
os.environ['WINEDEBUG']='-all'
sys.exit(subprocess.run(['/usr/lib/wine/wine64','/workspace/windows-compiler/gen_snapshot.exe',*args]).returncode)
