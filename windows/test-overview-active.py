"""Check the real native primary-monitor service through Marea's adapter.

The owner surface stays closed and child spawning is recorded rather than
performed. This checks native data and routing, not multi-monitor rendering.
"""
from pathlib import Path
import argparse, ctypes as C, json, os, subprocess, time
from ctypes import wintypes as W

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True)
p.add_argument('--wm',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[1]
binary=a.binary.resolve(strict=True);out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
flags=subprocess.CREATE_NO_WINDOW|subprocess.BELOW_NORMAL_PRIORITY_CLASS
screens=json.loads(subprocess.check_output([str(a.wm.resolve(strict=True)),'monitors'],creationflags=flags,encoding='utf-8'))
u=C.WinDLL('user32');u.GetForegroundWindow.restype=W.HWND
foreground=u.GetForegroundWindow()  # Primary routing also works with no foreground window.
primary=next(s["name"] for s in screens if s["primary"])
home=next((s['name'] for s in screens if s['name']!=primary),'\\\\.\\DISPLAY999')
host=next((s['name'] for s in screens if not s['primary']),primary)
module=(root/'windows/window-manager.luau').read_text(encoding='utf-8')
generated=(root/'marea-desktop.luau').read_text(encoding='utf-8')
provider=generated.split('end, notice, native_spawn, function(done)\n',1)[1].split('\nend)\nend\ninstall_shortcuts',1)[0]
status=json.dumps(dict(running=True,automatic_layouts=True,window_overview=True,monitors=screens))
logic='''local native_sys = sys
local hooks, entries = {}, {}
local function run(command, args, done)
    assert(command == "pleamar-wm" and args[2] == "wm" and args[3] == "status")
    done([==[__STATUS__]==], 0)
end
local function spawn(command, args, line, done, options)
    text.selected = args[4]
    text.preview = args[6]
end
local function primary_monitor(done) __PROVIDER__ end
local install = (function() __MODULE__ end)()
install(run, hooks, entries, function() end, function() return [==[__HOME__]==] end,
    function(message) text.problem = message end, spawn, primary_monitor)
on("invoke", function() hooks.windows_overview() end)
'''.replace('__STATUS__',status).replace('__PROVIDER__',provider).replace('__MODULE__',module).replace('__HOME__',home)
scene=out/'active-monitor.plm'
scene.write_text('''scene Probe {
surface { size: 2, 2; open: false; keyboard: none; reserve: 0 }
permissions { services: "window.*" }
fact windows_overview_active = false
fact open = false
fact menu_open = false
fact searching = false
fact chatting = false
fact tray_open = false
fact reel_open = false
fact note = false
fact windows_wm_available = false
fact windows_wm_busy = false
fact windows_wm_layout = -1
text selected = ""
text preview = ""
text problem = ""
event invoke ->
}''',encoding='utf-8')
scene.with_suffix('.luau').write_text(logic,encoding='utf-8')
env=dict(os.environ,PLEAMAR_CONFIG=str(out/'config'),PLEAMAR_SOCKET_DIR='active-monitor-'+str(os.getpid()))
def ask(line):
    r=subprocess.run([str(binary),'--say','active-monitor',line],env=env,capture_output=True,encoding='utf-8',creationflags=flags,timeout=4)
    return r.stdout.strip().strip('"') if r.returncode==0 else None
def wait(fn):
    end=time.monotonic()+20
    while time.monotonic()<end:
        assert u.GetForegroundWindow()==foreground,'Foreground changed during the measurement; retry with a stable active program'
        result=fn()
        if result:return result
        time.sleep(.03)
    raise TimeoutError((ask('get problem'), (out/'scene.log').read_text(encoding='utf-8')))
report=dict(passed=False,primary_monitor=primary,marea_home=home,host_monitor=host,physical_input=False,child_windows_spawned=False)
with (out/'scene.log').open('w',encoding='utf-8') as log:
    process=subprocess.Popen([str(binary),'--scene',str(scene),'--screen',host,'--seconds','40','--stall','0','--no-hud'],env=env,creationflags=flags,stdout=log,stderr=log)
    try:
        wait(lambda:ask('get windows_wm_available')=='true')
        ask('emit invoke')
        selected=wait(lambda:ask('get selected'))
        assert selected==primary and selected!=home,(selected,primary,home,ask('get problem'))
        assert ask('get preview')=='all'
        report.update(passed=True,selected_monitor=selected,foreground_unchanged=True)
    finally:
        report['problem']=ask('get problem')
        try:ask('quit');process.wait(timeout=5)
        except Exception:process.kill();process.wait(timeout=5)
        (out/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
