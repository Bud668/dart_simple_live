"""Run an isolated probe without debugger timing interference.

SEM_NOGPFAULTERRORBOX is inherited only by this child. It prevents a crash
dialog; nonzero native exit codes remain failures and are reported as such.
"""
from pathlib import Path
import ctypes, datetime as dt, json, subprocess, sys

exe=Path(sys.argv[1]).resolve()
out=Path(sys.argv[2]).resolve()
out.mkdir(parents=True,exist_ok=True)
kernel=ctypes.WinDLL('kernel32',use_last_error=True)
kernel.SetErrorMode(0x0001|0x0002)
started=dt.datetime.now().astimezone().isoformat()
timed_out=False
with (out/'stdout.txt').open('wb') as stdout, (out/'stderr.txt').open('wb') as stderr:
    process=subprocess.Popen([str(exe),str(out/'report.json'),*sys.argv[3:]],cwd=exe.parent,
        stdout=stdout,stderr=stderr,creationflags=0x08000000)
    print(json.dumps({'pid':process.pid,'started':started,'debugger':False}),flush=True)
    try:
        code=process.wait(timeout=480)
    except subprocess.TimeoutExpired:
        timed_out=True
        process.kill()
        code=process.wait(timeout=15)
functional=json.loads((out/'report.json').read_text(encoding='utf-8')) if (out/'report.json').exists() else {}
result={'started':started,'finished':dt.datetime.now().astimezone().isoformat(),
    'pid':process.pid,'exitCode':code,'exitCodeHex':hex(code & 0xffffffff),
    'nativeExceptions':([] if code==0 else [{'exitCode':hex(code & 0xffffffff)}]),
    'timedOut':timed_out,'functionalPassed':functional.get('passed',False),
    'passed':code==0 and not timed_out and functional.get('passed',False),
    'scope':'Isolated instrumented app without debugger; process-local inherited error mode suppresses Windows crash dialogs but preserves actual failure exit code.'}
(out/'native-exit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False),flush=True)
sys.exit(0 if result['passed'] else 1)
