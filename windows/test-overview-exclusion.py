"""Exercise generated panel exclusion in the native renderer without input or focus."""
from pathlib import Path
import argparse, ctypes, json, os, re, subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True)
p.add_argument('--monitor',required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[1]
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
binary=a.binary.resolve(strict=True)
u=ctypes.WinDLL('user32');u.GetForegroundWindow.restype=ctypes.c_void_p
foreground=u.GetForegroundWindow()
scene=(root/'marea-desktop.plm').read_text(encoding='utf-8')
assert scene.count('and not windows_overview_active') >= 5
for folder in ['common','lang','shaders','assets','wardrobe']:
    scene=scene.replace('"'+folder+'/', '"'+(root/folder).as_posix()+'/')
# Keep the fixture inert while unlocked. Run the real fact adapter below.
scene=re.sub(r'(?m)^(        open: )(.+)$',r'\1false',scene)
scene=re.sub(r'(?m)^(        keyboard: )(.+)$',r'\1none',scene)
path=out/'overview-exclusion.plm';path.write_text(scene,encoding='utf-8')
logic="""
local panels={"open","menu_open","searching","chatting","tray_open","reel_open","note"}
local function closed()
    for _,key in ipairs(panels) do assert(not fact[key], key .. " escaped overview exclusion") end
end
-- Existing panels close when the overview acquires ownership.
after(5000,function() fact.open=true; fact.chatting=true; fact.windows_overview_active=true end)
after(5600,function()
    closed()
    -- All possible delayed service writes are rejected by the scene guards.
    for _,key in ipairs(panels) do fact[key]=true end
end)
after(6200,function() closed(); fact.windows_overview_active=false end)
after(6800,function()
    closed(); fact.open=true
end)
after(7400,function()
    assert(fact.open,"ordinary panel opening did not recover")
    fact.open=false
    log("PASS: native overview exclusion, delayed service writes and unlock")
end)
"""
logic="local fact = (function()\n"+(root/'windows/overview-exclusion.luau').read_text(encoding='utf-8')+"\nend)()(fact)\n"+logic
path.with_suffix('.luau').write_text(logic,encoding='utf-8')
env=dict(os.environ,PLEAMAR_CONFIG=str(out/'config'),PLEAMAR_SOCKET_DIR='exclusive-'+str(os.getpid()))
result=subprocess.run([str(binary),'--scene',str(path),'--screen',a.monitor,'--seconds','9','--stall','0','--no-hud'],env=env,cwd=root,capture_output=True,encoding='utf-8',timeout=40,creationflags=subprocess.CREATE_NO_WINDOW|subprocess.BELOW_NORMAL_PRIORITY_CLASS)
output=result.stdout+result.stderr;(out/'scene.log').write_text(output,encoding='utf-8')
assert result.returncode==0 and 'PASS: native overview exclusion' in output and 'runtime error' not in output,output[-6000:]
assert foreground==u.GetForegroundWindow(),'Foreground changed during the fixture'
report=dict(passed=True,monitor=a.monitor,physical_input=False,foreground_unchanged=True,native_fact_adapter=True,visible_surfaces=False)
(out/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
