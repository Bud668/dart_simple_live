"""Debug only an isolated validation process; native crashes fail the run.

The debugger consumes unhandled exceptions before Windows displays a modal error.
This does not fix or ignore the exception: its code/address and a failed result
are persisted alongside the real process exit code. User processes are untouched.
"""
import ctypes as C
from ctypes import wintypes as W
import datetime as dt
import json
import pathlib
import subprocess
import sys
import time

class ExceptionRecord(C.Structure):
    _fields_ = [('code', W.DWORD), ('flags', W.DWORD), ('record', C.c_void_p),
                ('address', C.c_void_p), ('count', W.DWORD), ('info', C.c_size_t * 15)]
class ExceptionInfo(C.Structure):
    _fields_ = [('record', ExceptionRecord), ('firstChance', W.DWORD)]
class CreateProcessInfo(C.Structure):
    _fields_ = [('file', W.HANDLE), ('process', W.HANDLE), ('thread', W.HANDLE),
                ('base', C.c_void_p), ('offset', W.DWORD), ('size', W.DWORD),
                ('tls', C.c_void_p), ('start', C.c_void_p), ('name', C.c_void_p), ('unicode', W.WORD)]
class LoadDllInfo(C.Structure):
    _fields_ = [('file', W.HANDLE), ('base', C.c_void_p), ('offset', W.DWORD),
                ('size', W.DWORD), ('name', C.c_void_p), ('unicode', W.WORD)]
class CreateThreadInfo(C.Structure):
    _fields_ = [('thread', W.HANDLE), ('tls', C.c_void_p), ('start', C.c_void_p)]
class DebugUnion(C.Union):
    _fields_ = [('exception', ExceptionInfo), ('created', CreateProcessInfo),
                ('dll', LoadDllInfo), ('thread', CreateThreadInfo), ('exitCode', W.DWORD),
                ('raw', C.c_byte * 160)]
class DebugEvent(C.Structure):
    _fields_ = [('code', W.DWORD), ('pid', W.DWORD), ('tid', W.DWORD), ('data', DebugUnion)]

kernel = C.WinDLL('kernel32', use_last_error=True)
kernel.WaitForDebugEvent.argtypes = [C.POINTER(DebugEvent), W.DWORD]
kernel.WaitForDebugEvent.restype = W.BOOL
kernel.ContinueDebugEvent.argtypes = [W.DWORD, W.DWORD, W.DWORD]
kernel.ContinueDebugEvent.restype = W.BOOL
kernel.CloseHandle.argtypes = [W.HANDLE]
kernel.TerminateProcess.argtypes = [W.HANDLE, W.UINT]
kernel.GetFinalPathNameByHandleW.argtypes = [W.HANDLE, W.LPWSTR, W.DWORD, W.DWORD]
kernel.GetFinalPathNameByHandleW.restype = W.DWORD

exe = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
if not exe.is_file():
    raise SystemExit('The isolated validation executable does not exist')

def module_name(handle):
    if not handle: return None
    b = C.create_unicode_buffer(32768)
    if kernel.GetFinalPathNameByHandleW(handle, b, len(b), 0):
        return pathlib.PureWindowsPath(b.value).name
    return None

started = dt.datetime.now().astimezone().isoformat()
errors = []
modules = []
exit_code = None
timed_out = False
with (out/'stdout.txt').open('wb') as stdout, (out/'stderr.txt').open('wb') as stderr:
    process = subprocess.Popen([str(exe), str(out/'report.json'), *sys.argv[3:]],
                               cwd=exe.parent, stdout=stdout, stderr=stderr,
                               creationflags=0x2 | 0x08000000)
    print(json.dumps({'pid': process.pid, 'started': started}), flush=True)
    deadline = time.monotonic()+480
    while True:
        event = DebugEvent()
        got_event = kernel.WaitForDebugEvent(C.byref(event), 500)
        if not got_event:
            err = C.get_last_error()
            if err != 121:
                errors.append({'debuggerError':err})
                kernel.TerminateProcess(int(process._handle), 1)
                break
            if time.monotonic()>deadline:
                timed_out=True
                kernel.TerminateProcess(int(process._handle), 1)
            continue
        status=0x00010002
        if event.code==1:
            info=event.data.exception
            if info.record.code not in (0x80000003, 0x80000004):
                status=0x80010001
                if not info.firstChance:
                    address=info.record.address or 0
                    preceding=[m for m in modules if m['base']<=address]
                    nearest=max(preceding,key=lambda m:m['base']) if preceding else None
                    errors.append({'exception':f'0x{info.record.code:08x}',
                        'address':hex(address), 'thread':event.tid,
                        'nearestModule':nearest['name'] if nearest else None,
                        'moduleOffset':hex(address-nearest['base']) if nearest else None})
                    kernel.TerminateProcess(int(process._handle), info.record.code)
        elif event.code==3:
            info=event.data.created
            modules.append({'base':info.base or 0,'name':module_name(info.file)})
            for h in (info.file, info.thread, info.process):
                if h and int(h) != int(process._handle): kernel.CloseHandle(h)
        elif event.code==2:
            if event.data.thread.thread: kernel.CloseHandle(event.data.thread.thread)
        elif event.code==6:
            info=event.data.dll
            modules.append({'base':info.base or 0,'name':module_name(info.file)})
            if info.file: kernel.CloseHandle(info.file)
        elif event.code==5:
            exit_code=int(event.data.exitCode)
        if not kernel.ContinueDebugEvent(event.pid,event.tid,status):
            errors.append({'continueError':C.get_last_error()})
        if event.code==5: break
    process.wait(timeout=10)

functional=None
if (out/'report.json').exists():
    functional=json.loads((out/'report.json').read_text(encoding='utf-8'))
result={'started':started,'finished':dt.datetime.now().astimezone().isoformat(),
        'pid':process.pid,'exitCode':exit_code,'exitCodeHex':hex(exit_code) if exit_code is not None else None,
        'nativeExceptions':errors,'timedOut':timed_out,'functionalPassed':bool(functional and functional.get('passed')),
        'passed':exit_code==0 and not errors and not timed_out and bool(functional and functional.get('passed')),
        'scope':'Isolated instrumented app under a native debugger; unhandled exceptions fail rather than open a modal dialog.'}
(out/'native-exit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False),flush=True)
sys.exit(0 if result['passed'] else 1)
