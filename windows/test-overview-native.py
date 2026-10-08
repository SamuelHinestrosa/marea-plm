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
p.add_argument('--prewarm',action='store_true')
a=p.parse_args()
assert os.name=='nt'
if a.ci_activation:
    assert os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted'
    assert os.environ.get('MAREA_CI_OVERVIEW')=='1'
binary=a.binary.resolve(strict=True);root=Path(__file__).resolve().parents[1]
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
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
    ('WindowFromPoint',W.HWND,[W.POINT]),
    ('SetCursorPos',W.BOOL,[C.c_int,C.c_int]),
]:
    fn=getattr(u,name);fn.restype=ret;fn.argtypes=args
class CURSOR(C.Structure):
    _fields_=[('size',W.DWORD),('flags',W.DWORD),('cursor',W.HANDLE),('point',W.POINT)]
u.GetCursorInfo.argtypes=[C.POINTER(CURSOR)];u.GetCursorInfo.restype=W.BOOL
class MOUSE(C.Structure):
    _fields_=[('dx',W.LONG),('dy',W.LONG),('data',W.DWORD),('flags',W.DWORD),('time',W.DWORD),('extra',C.c_size_t)]
class INPUT(C.Structure):
    _fields_=[('type',W.DWORD),('mouse',MOUSE)]
u.SendInput.argtypes=[W.UINT,C.POINTER(INPUT),C.c_int];u.SendInput.restype=W.UINT
foreground=u.GetForegroundWindow();owned=[];process=None;cursor_adjustment=0
report=dict(passed=False,monitor=screen['name'],primary=screen['primary'],activation=a.ci_activation,physical_input=False,warm_ms=[])
env=dict(os.environ,PLEAMAR_CONFIG=str(out/'config'),PLEAMAR_SOCKET_DIR='overview-check-'+str(os.getpid()),
    PLEAMAR_DEBUG_FOCUS='1',MAREA_LOCALE='es',MAREA_OVERVIEW_WARM='1' if a.prewarm else '0',PATH=str(binary.parent)+os.pathsep+os.environ.get('PATH',''))
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
        # Hosted Windows can start in touch/pen mode (CURSOR_SUPPRESSED), which
        # is independent of ShowCursor's display count. Establish a mouse
        # baseline on our own window before simulating a game hiding it.
        assert u.SetCursorPos(bounds['x']+110,bounds['y']+110)
        event=INPUT(type=0,mouse=MOUSE(dx=1,dy=1,flags=1))
        assert u.SendInput(1,C.byref(event),C.sizeof(INPUT))==1
        for _ in range(32):
            cursor_adjustment+=1
            if u.ShowCursor(True)>=0:break
        def showing():
            info=CURSOR(size=C.sizeof(CURSOR));assert u.GetCursorInfo(C.byref(info))
            report['mouse_baseline']=dict(flags=info.flags,mouse_present=bool(u.GetSystemMetrics(19)),point=[info.point.x,info.point.y])
            return info.flags==1
        until(showing,'owned fixture mouse baseline')
        report['synthetic_mouse_setup']=True
        for _ in range(32):
            cursor_adjustment-=1
            if u.ShowCursor(False)<0:break
        info=CURSOR(size=C.sizeof(CURSOR));assert u.GetCursorInfo(C.byref(info))
        assert info.flags==0,'The fixture must hide a visible mouse cursor, not rely on touch suppression'
        report['fixture_cursor_hidden']=True
        clip=W.RECT(bounds['x']+100,bounds['y']+100,bounds['x']+120,bounds['y']+120)
        assert u.ClipCursor(C.byref(clip))
    with (out/'scene.log').open('w',encoding='utf-8') as log:
        start=time.perf_counter()
        process=subprocess.Popen([str(binary),'--scene',str(out/'windows-overview.plm'),'--screen',a.monitor,
            '--preview-monitor',a.monitor,'--preview-process',str(os.getpid()),'--window-actions','--no-hud','--stall','0'],
            env=env,stdout=log,stderr=log,creationflags=flags)
        if a.prewarm:
            until(lambda:ask('get overview_open')=='false','hidden startup')
            until(lambda:ask('get win.count')=='4','catalog startup')
            assert all(float(ask(f'get win.{i}.width'))==0 for i in range(4))
            if a.ci_activation:assert u.GetForegroundWindow()==owned[0],'Prewarming took focus'
            report['prewarmed_without_captures']=True
            start=time.perf_counter();ask('emit overview_toggle')
        until(lambda:ask('get overview_open')=='true','cold Luau readiness')
        report['cold_ready_ms']=(time.perf_counter()-start)*1000
        until(captures,'four live window pictures');capture('overview')
        report['cold_picture_ms']=(time.perf_counter()-start)*1000
        if a.ci_activation:
            until(lambda:desktop.pid(u.GetForegroundWindow())==process.pid,'overview foreground without a click')
            cursor=CURSOR(size=C.sizeof(CURSOR));assert u.GetCursorInfo(C.byref(cursor))
            report['cursor_visible']=bool(cursor.flags&1)
            report['cursor_details']=dict(flags=cursor.flags,point=[cursor.point.x,cursor.point.y],under_pid=desktop.pid(u.WindowFromPoint(cursor.point)),foreground=u.GetForegroundWindow(),overview_pid=process.pid)
            actual=W.RECT();assert u.GetClipCursor(C.byref(actual))
            report['cursor_released']=(actual.right-actual.left)>20
            assert report['cursor_visible'],'Cursor stayed hidden'
            assert report['cursor_released'],'Cursor stayed confined'
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
        for _ in range(abs(cursor_adjustment)):u.ShowCursor(cursor_adjustment<0)
    for hwnd in owned:u.DestroyWindow(hwnd)
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
