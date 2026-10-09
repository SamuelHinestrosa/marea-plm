"""Native overview reuse and capture lifetime; activation is CI-only.

Local runs use only owned windows on an explicit secondary display and disable
the scene's keyboard request. That mode does not claim foreground acceptance.
"""
from pathlib import Path
import argparse, ctypes as C, importlib.util, json, os, shutil, subprocess, time, sys, msvcrt
from ctypes import wintypes as W

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True)
p.add_argument('--monitor',required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--ci-activation',action='store_true')
p.add_argument('--prewarm',action='store_true')
p.add_argument('--keep-warm',action='store_true')
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
dwm=C.WinDLL('dwmapi')
dwm.DwmGetWindowAttribute.argtypes=[W.HWND,W.DWORD,W.LPVOID,W.DWORD]
dwm.DwmGetWindowAttribute.restype=C.c_long
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
    PLEAMAR_DEBUG_FOCUS='1',MAREA_LOCALE='es',MAREA_OVERVIEW_KEEP_WARM='1' if a.keep_warm else '0',MAREA_OVERVIEW_WARM='1' if a.prewarm else '0',PATH=str(binary.parent)+os.pathsep+os.environ.get('PATH',''))
source=(root/'tools/windows-overview.plm').read_text(encoding='utf-8')
if not a.ci_activation:source=source.replace('keyboard: exclusive while overview_open or overview_committing','keyboard: none')
# Observe inside the renderer: launching an IPC client can outlast a short
# animation on a loaded CI machine and miss every intermediate sample.
source=source.replace('fact overview_open = false', '''fact overview_open = false
    fact observed_transition = 0
    fact observed_preview = 0
    fact observed_accept = -1
    on overview_accept { observed_accept = accepted_slot }
    on change preview.0 while preview.0 > 0.01 and preview.0 < 0.99 { observed_preview = preview.0 }
    on change reveal while reveal > 0.05 and reveal < 0.95 { observed_transition = reveal }''')
(out/'windows-overview.plm').write_text(source,encoding='utf-8')
shutil.copyfile(root/'tools/windows-overview.luau',out/'windows-overview.luau')
subprocess.run([str(binary),'--check',str(out/'windows-overview.plm')],check=True,creationflags=flags)

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

def release_without_foreground_grant():
    # The real Marea sender is in the background. Do not let a foreground test
    # launcher grant the selector extra activation rights through --say.
    kernel=C.WinDLL('kernel32')
    kernel.GetNamedPipeServerProcessId.argtypes=[W.HANDLE,C.POINTER(W.DWORD)]
    for name in os.listdir('\\\\.\\pipe\\'):
        if not (name.startswith('pleamar-') and name.endswith('-windows-overview')):continue
        with open('\\\\.\\pipe\\'+name,'r+b',buffering=0) as pipe:
            pid=W.DWORD()
            assert kernel.GetNamedPipeServerProcessId(msvcrt.get_osfhandle(pipe.fileno()),C.byref(pid))
            if pid.value!=process.pid:continue
            pipe.write(b'emit overview_commit\n')
            assert not pipe.readline().startswith(b'?'),'Commit was rejected'
            report['release_ipc_grants_foreground']=False
            return
    raise AssertionError('Owned overview command pipe missing')

class BackgroundChild:
    def __init__(self,argv,log):
        pidfile=out/'background-child.pid'
        code='import subprocess,sys; from pathlib import Path; p=subprocess.Popen(sys.argv[2:],creationflags=subprocess.CREATE_NO_WINDOW); Path(sys.argv[1]).write_text(str(p.pid)); sys.exit(p.wait())'
        self.parent=subprocess.Popen([sys.executable,'-c',code,str(pidfile),*argv],env=env,stdout=log,stderr=log,creationflags=flags)
        end=time.monotonic()+10
        while not pidfile.exists():
            assert self.parent.poll() is None and time.monotonic()<end,'Background launcher failed'
            pump();time.sleep(.02)
        self.pid=int(pidfile.read_text())
    def poll(self):return self.parent.poll()
    def wait(self,timeout):return self.parent.wait(timeout=timeout)
    def kill(self):
        kernel=C.WinDLL('kernel32')
        kernel.OpenProcess.argtypes=[W.DWORD,W.BOOL,W.DWORD];kernel.OpenProcess.restype=W.HANDLE
        kernel.TerminateProcess.argtypes=[W.HANDLE,W.UINT];kernel.CloseHandle.argtypes=[W.HANDLE]
        handle=kernel.OpenProcess(1,False,self.pid)
        if handle:
            try:kernel.TerminateProcess(handle,1)
            finally:kernel.CloseHandle(handle)
def until(fn,label,timeout=35):
    end=time.monotonic()+timeout;last=None
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
        until(lambda:u.GetForegroundWindow()==owned[0], 'owned fixture foreground')
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
        def hidden():
            info=CURSOR(size=C.sizeof(CURSOR));assert u.GetCursorInfo(C.byref(info))
            report['hidden_mouse_baseline']=dict(flags=info.flags,foreground=u.GetForegroundWindow(),expected_foreground=owned[0])
            return info.flags==0
        until(hidden,'fixture hides a visible mouse cursor without touch suppression')
        report['fixture_cursor_hidden']=True
        clip=W.RECT(bounds['x']+100,bounds['y']+100,bounds['x']+120,bounds['y']+120)
        assert u.ClipCursor(C.byref(clip))
    with (out/'scene.log').open('w',encoding='utf-8') as log:
        start=time.perf_counter()
        argv=[str(binary),'--scene',str(out/'windows-overview.plm'),'--screen',a.monitor,
            '--preview-monitor','all','--preview-project','--preview-process',str(os.getpid()),*(['--window-actions'] if a.ci_activation else []),'--no-hud','--stall','0']
        if a.ci_activation and a.prewarm:
            process=BackgroundChild(argv,log)
            report['background_launcher']=True
        else:process=subprocess.Popen(argv,env=env,stdout=log,stderr=log,creationflags=flags)
        if a.prewarm:
            until(lambda:ask('get overview_open')=='false','hidden startup')
            until(lambda:ask('get win.count')=='4','catalog startup')
            assert all(float(ask(f'get win.{i}.width'))==0 for i in range(4))
            if a.ci_activation:assert u.GetForegroundWindow()==owned[0],'Prewarming took focus'
            report['prewarmed_without_captures']=True
            start=time.perf_counter();ask('emit overview_toggle')
        until(lambda:ask('get overview_open')=='true','cold Luau readiness')
        report['cold_ready_ms']=(time.perf_counter()-start)*1000
        until(captures,'four live window pictures')
        until(lambda:all(float(ask(f'get preview.{i}'))>.99 for i in range(4)),'thumbnail fade completed')
        report['thumbnail_fade_sample']=float(ask('get observed_preview'))
        report['thumbnail_fade_observed']=0.01<report['thumbnail_fade_sample']<0.99
        if not report['thumbnail_fade_observed']:
            # WARP can take longer than the entire 160 ms fade per frame.
            # Settled pictures and activation remain mandatory, but that host
            # cannot establish intermediate motion. Hardware runs must do so.
            assert a.ci_activation and 'Microsoft Basic Render Driver' in (out/'scene.log').read_text(encoding='utf-8')
            report['motion_validation_limit']='Software-rendered frames skipped the thumbnail fade; hardware acceptance required.'
        capture('overview')
        report['cold_picture_ms']=(time.perf_counter()-start)*1000
        until(lambda:float(ask('get overview_count'))==4,'complete overview catalogue')
        report['native_rectangles']=[[float(ask(f'get win.{i}.native.{key}')) for key in ['x','y','width','height']] for i in range(4)]
        assert all(rect[2]>0 and rect[3]>0 for rect in report['native_rectangles'])
        expected=[]
        for hwnd in owned:
            rect=W.RECT();assert dwm.DwmGetWindowAttribute(hwnd,9,C.byref(rect),C.sizeof(rect))==0
            expected.append([round((rect.left-screen['bounds']['x'])/screen['scale'],2),
                             round((rect.top-screen['bounds']['y'])/screen['scale'],2),
                             round((rect.right-rect.left)/screen['scale'],2),round((rect.bottom-rect.top)/screen['scale'],2)])
        expected.sort()
        assert sorted([[round(v,2) for v in rect] for rect in report['native_rectangles']])==expected
        for i,rect in enumerate(report['native_rectangles']):
            for at,key in [(2,'width'),(3,'height')]:
                assert abs(rect[at]-float(ask(f'get win.{i}.{key}')))<=1,'Captured image and native frame differ'
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
            if i==0:
                until(lambda:.05<float(ask('get observed_transition'))<.95,'renderer observed an intermediate animation state')
                until(lambda:float(ask('get reveal'))>.99,'settled transition')
                report['animation_sample']=float(ask('get observed_transition'))
            if a.ci_activation:
                until(lambda:desktop.pid(u.GetForegroundWindow())==process.pid,'warm foreground without a click')
            until(captures,'fresh captures after reopening')
        capture('overview-reopened')
        u.ShowWindow(owned[1],7)
        until(lambda:any(ask(f'get win.{j}.minimized')=='true' for j in range(4)),'native minimization')
        assert float(ask('get overview_count'))==4,'Minimization removed a selectable window'
        assert sorted(float(ask(f'get overview_place.{j}')) for j in range(4))==[0,1,2,3]
        report['minimized_remains_selectable']=True
        ask('emit overview_close');until(lambda:ask('get overview_open')=='false','close before cycling')
        ask('emit overview_cycle_forward')
        until(lambda:int(float(ask('get keyboard_slot')))>=0,'first keyboard preselection')
        first=int(float(ask('get keyboard_slot')))
        before_cycle_focus=u.GetForegroundWindow()
        for step in range(1,5):
            ask('key Tab' if a.ci_activation else 'emit overview_cycle_forward')
            until(lambda:int(float(ask('get keyboard_slot')))==(first+step)%4,'successive Tab preselection')
            assert ask('get overview_open')=='true','Tab toggled the overview closed'
            assert u.GetForegroundWindow()==before_cycle_focus,'Preselection activated a window early'
        ask('key Shift+Tab' if a.ci_activation else 'emit overview_cycle_backward')
        until(lambda:int(float(ask('get keyboard_slot')))==(first-1)%4,'reverse preselection')
        capture('overview-keyboard-selection')
        report['keyboard_cycle_without_closing']=True
        report['keyboard_reverse']=True
        chosen=int(float(ask('get keyboard_slot')))
        expected_title=ask(f'get win.{chosen}.title')
        report['expected_commit']=dict(slot=chosen,title=expected_title)
        if a.ci_activation:
            if a.prewarm:
                u.AllowSetForegroundWindow.argtypes=[W.DWORD];u.AllowSetForegroundWindow.restype=W.BOOL
                assert u.AllowSetForegroundWindow(os.getpid()),'Could not revoke the opening grant'
                report['opening_foreground_grant_revoked']=True
            release_without_foreground_grant()
            until(lambda:ask('get overview_open')=='false','release activates the preselected window')
            until(lambda:int(float(ask('get observed_accept')))==chosen,'selected target dispatched after release')
            # Closing can transiently restore the previous foreground while
            # an asynchronously requested minimized target is being restored.
            # Require the exact target, not merely any owned foreground window.
            report['focus_after_release']=[]
            def chosen_foreground():
                hwnd=u.GetForegroundWindow()
                title=C.create_unicode_buffer(1024);u.GetWindowTextW(hwnd,title,len(title))
                observed=title.value if hwnd in owned else "outside fixture"
                if not report['focus_after_release'] or report['focus_after_release'][-1]!=observed:
                    report['focus_after_release'].append(observed)
                return hwnd in owned and title.value==expected_title
            until(chosen_foreground,'release transfers foreground to the exact selected window',timeout=5)
            assert desktop.pid(u.GetForegroundWindow())==os.getpid()
            report['keyboard_commit_native_focus']=True
            report['keyboard_committed_title']=expected_title
            until(lambda:ask('get overview_committing')=='false','foreground handoff releases keyboard ownership')
        else:
            # A view-only native backend rejects activation. Releasing Win must
            # still dismiss its UI; do not activate anything on the user's desktop.
            ask('emit overview_commit')
            until(lambda:ask('get overview_open')=='false','release closes despite native action refusal')
            until(lambda:int(float(ask('get observed_accept')))==chosen,'selected target survives payloadless Luau event')
            until(lambda:'window actions require --window-actions' in (out/'scene.log').read_text(encoding='utf-8'),'native action refused')
            assert u.GetForegroundWindow()==foreground
            until(lambda:ask('get overview_committing')=='false','denied activation releases keyboard ownership within its deadline')
            report['release_closes_on_activation_denial']=True
        ask('emit overview_close');until(lambda:ask('get overview_open')=='false','final close')
        ask('emit overview_commit')
        assert ask('get overview_open')=='false','Release after cancellation reopened the overview'
        report['keyboard_cancel_ignores_release']=True
        lifecycle=(out/'scene.log').read_text(encoding='utf-8')
        assert 'luau   · marea-overview-state:open' in lifecycle
        assert 'luau   · marea-overview-state:closed' in lifecycle
        report['native_lifecycle_markers']=True
        report['keep_warm']=a.keep_warm
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
