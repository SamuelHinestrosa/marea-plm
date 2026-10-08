"""Native overview reuse and capture lifetime; activation is CI-only.

Local runs use only owned windows on an explicit secondary display and disable
the scene's keyboard request. That mode does not claim foreground acceptance.
"""
from pathlib import Path
import argparse, ctypes as C, importlib.util, json, os, shutil, subprocess, time
from ctypes import wintypes as W

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True)
p.add_argument('--monitor',required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--ci-activation',action='store_true')
a=p.parse_args()
assert os.name=='nt'
if a.ci_activation:
    assert os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted'
    assert os.environ.get('MAREA_CI_OVERVIEW')=='1'
binary=a.binary.resolve(strict=True);root=Path(__file__).resolve().parents[1]
out=a.output.resolve();out.mkdir(exist_ok=False)
flags=subprocess.CREATE_NO_WINDOW|subprocess.BELOW_NORMAL_PRIORITY_CLASS
screens=json.loads(subprocess.check_output([str(binary),'monitors'],creationflags=flags,encoding='utf-8'))
screen=next(s for s in screens if s['name']==a.monitor and (a.ci_activation or not s['primary']))
spec=importlib.util.spec_from_file_location('profile_ui',root/'windows/test-profile-ui-ci.py')
ui=importlib.util.module_from_spec(spec);spec.loader.exec_module(ui)
desktop=ui.Desktop();u=desktop.user
for name,ret,args in [
    ('CreateWindowExW',W.HWND,[W.DWORD,W.LPCWSTR,W.LPCWSTR,W.DWORD,C.c_int,C.c_int,C.c_int,C.c_int,W.HWND,W.HMENU,W.HINSTANCE,W.LPVOID]),
    ('ShowWindow',W.BOOL,[W.HWND,C.c_int]),('DestroyWindow',W.BOOL,[W.HWND]),
    ('GetForegroundWindow',W.HWND,[]),('SetForegroundWindow',W.BOOL,[W.HWND]),
    ('PeekMessageW',W.BOOL,[C.POINTER(W.MSG),W.HWND,W.UINT,W.UINT,W.UINT]),
    ('TranslateMessage',W.BOOL,[C.POINTER(W.MSG)]),('DispatchMessageW',C.c_ssize_t,[C.POINTER(W.MSG)]),
    ('ShowCursor',C.c_int,[W.BOOL]),('ClipCursor',W.BOOL,[C.POINTER(W.RECT)]),
    ('GetClipCursor',W.BOOL,[C.POINTER(W.RECT)]),
]:
    fn=getattr(u,name);fn.restype=ret;fn.argtypes=args
class CURSOR(C.Structure):
    _fields_=[('size',W.DWORD),('flags',W.DWORD),('cursor',W.HANDLE),('point',W.POINT)]
u.GetCursorInfo.argtypes=[C.POINTER(CURSOR)];u.GetCursorInfo.restype=W.BOOL
foreground=u.GetForegroundWindow();owned=[];process=None;cursor_hidden=False
report=dict(passed=False,monitor=screen['name'],primary=screen['primary'],activation=a.ci_activation,physical_input=False,warm_ms=[])
env=dict(os.environ,PLEAMAR_CONFIG=str(out/'config'),PLEAMAR_SOCKET_DIR='overview-check-'+str(os.getpid()),
    MAREA_LOCALE='es',PATH=str(binary.parent)+os.pathsep+os.environ.get('PATH',''))
source=(root/'tools/windows-overview.plm').read_text(encoding='utf-8')
if not a.ci_activation:source=source.replace('keyboard: exclusive while overview_open','keyboard: none')
(out/'windows-overview.plm').write_text(source,encoding='utf-8')
shutil.copyfile(root/'tools/windows-overview.luau',out/'windows-overview.luau')

def pump():
    msg=W.MSG()
    while u.PeekMessageW(C.byref(msg),None,0,0,1):u.TranslateMessage(C.byref(msg));u.DispatchMessageW(C.byref(msg))
    if not a.ci_activation:assert u.GetForegroundWindow()==foreground,'The test changed foreground'

def command(*args):
    pump()
    r=subprocess.run([str(binary),*args],env=env,capture_output=True,encoding='utf-8',errors='replace',creationflags=flags,timeout=8)
    pump()
    if r.returncode or r.stdout.startswith('?'):raise RuntimeError(r.stdout+r.stderr)
    return r.stdout.strip()
def ask(line):return command('--say','windows-overview',line)
def until(fn,label):
    end=time.monotonic()+35;last=None
    while time.monotonic()<end:
        pump()
        if process and process.poll() is not None:raise RuntimeError('Overview exited: '+(out/'scene.log').read_text())
        try:
            last=fn()
            if last:return last
        except (RuntimeError,ValueError) as e:last=str(e)
        time.sleep(.02)
    raise TimeoutError(f'{label}: {last}')
def captures():return all(float(ask(f'get win.{i}.width'))>1 for i in range(4))
def capture(name):
    found=[]
    @desktop.callback
    def visit(hwnd,_):
        if desktop.pid(hwnd)==process.pid and u.IsWindowVisible(hwnd):found.append(hwnd)
        return True
    assert u.EnumWindows(visit,0) and found
    # The renderer and input proxy overlap exactly; sample their owned screen
    # rectangle, never a primary output in local mode.
    picture=desktop.pixels(found[0])
    ui.png(out/(name+'.png'),picture)

try:
    bounds=screen['work'] if 'work' in screen else screen['bounds']
    # STATIC is a stock Win32 class, not an external application.
    for i,title in enumerate(['Notas · España','Música · Marea','Proyecto · 海','Vídeo · Ventana de prueba']):
        hwnd=u.CreateWindowExW(0,'STATIC',title,0x00CF0000,bounds['x']+60+i*35,bounds['y']+70+i*25,360,240,None,None,None,None)
        assert hwnd;owned.append(hwnd);u.ShowWindow(hwnd,4)
    pump()
    if a.ci_activation:
        assert u.SetForegroundWindow(owned[0])
        cursor_hidden=u.ShowCursor(False)<0
        clip=W.RECT(bounds['x']+100,bounds['y']+100,bounds['x']+120,bounds['y']+120)
        assert u.ClipCursor(C.byref(clip))
    with (out/'scene.log').open('w',encoding='utf-8') as log:
        start=time.perf_counter()
        process=subprocess.Popen([str(binary),'--scene',str(out/'windows-overview.plm'),'--screen',a.monitor,
            '--preview-monitor',a.monitor,'--preview-process',str(os.getpid()),'--window-actions','--no-hud','--stall','0'],
            env=env,stdout=log,stderr=log,creationflags=flags)
        until(lambda:ask('get overview_open')=='true','cold Luau readiness')
        report['cold_ready_ms']=(time.perf_counter()-start)*1000
        until(captures,'four live window pictures');capture('overview')
        report['cold_picture_ms']=(time.perf_counter()-start)*1000
        if a.ci_activation:
            until(lambda:desktop.pid(u.GetForegroundWindow())==process.pid,'overview foreground without a click')
            cursor=CURSOR(size=C.sizeof(CURSOR));assert u.GetCursorInfo(C.byref(cursor))
            report['cursor_visible']=bool(cursor.flags&1);assert report['cursor_visible'],'Cursor stayed hidden'
            actual=W.RECT();assert u.GetClipCursor(C.byref(actual))
            report['cursor_released']=(actual.right-actual.left)>20;assert report['cursor_released'],'Cursor stayed confined'
            assert u.PostMessageW(u.GetForegroundWindow(),0x100,0x1B,1)
            until(lambda:ask('get overview_open')=='false','Escape delivered to the activated overview')
            report['escape_without_click']=True
        for i in range(3):
            ask('emit overview_close');until(lambda:ask('get overview_open')=='false','closed state')
            until(lambda:all(float(ask(f'get win.{j}.width'))==0 for j in range(4)),'hidden capture retirement')
            start=time.perf_counter();ask('emit overview_toggle')
            until(lambda:ask('get overview_open')=='true','warm opening')
            report['warm_ms'].append((time.perf_counter()-start)*1000)
            if a.ci_activation:
                until(lambda:desktop.pid(u.GetForegroundWindow())==process.pid,'warm foreground without a click')
            until(captures,'fresh captures after reopening')
        capture('overview-reopened')
        ask('emit overview_close');until(lambda:ask('get overview_open')=='false','final close')
        report.update(passed=True,same_process=True,hidden_captures_retired=True,foreground_unchanged=not a.ci_activation)
finally:
    if process and process.poll() is None:
        try:ask('quit');process.wait(timeout=10)
        except Exception:process.kill();process.wait(timeout=10)
    if a.ci_activation:
        u.ClipCursor(None)
        if cursor_hidden:u.ShowCursor(True)
    for hwnd in owned:u.DestroyWindow(hwnd)
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
