"""Native WM menus reflect real capabilities and acknowledgements."""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks

parser = argparse.ArgumentParser(description=__doc__)
runner_arguments(parser)
args = parser.parse_args()
module = Path(__file__).with_name('window-manager.luau').read_text(encoding='utf-8')
checks = r'''
local handlers, requests, notices, entries, hooks = {}, {}, {}, {{id="desktop"}}, {in_wm=false}
local replies = {}
local json = {decode=function(key) assert(replies[key]); return replies[key] end}
local function tr(s) return s end
local function on(name, callback) handlers[name]=callback end
local changed = 0
local screen = "\\\\.\\DISPLAY2"
local function run(name, args, callback)
    assert(name=="pleamar-wm" and args[1]=="--say" and args[2]=="wm")
    requests[#requests+1]={command=args[3],done=callback}
end
local install=(function() __MODULE__ end)()
install(run,hooks,entries,function() changed+=1 end,function() return screen end,function(message) notices[#notices+1]=message end)
assert(#requests==1 and requests[1].command=="status")
requests[1].done("not installed",1)
assert(#entries==1 and #notices==0 and not hooks.windows_wm_allowed("Tiled or free windows"))
handlers["fact:menu_open"](true)
handlers["fact:menu_open"](true)
assert(#requests==2)
replies.good={running=true,automatic_layouts=true,monitors={{name=screen,tiled=false}}}
requests[2].done("good",0)
assert(#entries==3 and hooks.windows_wm_allowed("Tiled or free windows") and hooks.in_wm==false)
for _,title in ipairs({"Rain on the windows","Rain intensity","Snow on the windows","Ride a window"}) do
    assert(not hooks.windows_wm_allowed(title))
end
hooks.wm_free();hooks.wm_free()
assert(#requests==3 and requests[3].command=="toggle "..screen)
requests[3].done("good",0)
assert(#entries==3 and #notices==0)
screen="\\\\.\\DISPLAY1"
hooks.wm_free(); assert(#requests==3 and #notices==1)
screen="\\\\.\\DISPLAY2"
hooks.wm_free(); requests[4].done("native window refused resizing",1)
assert(#entries==1 and #notices==2 and not hooks.windows_wm_allowed("Tiled or free windows"))
requests[4].done("good",0) -- duplicate/stale completion cannot revive the session
assert(#entries==1)
handlers["fact:searching"](true)
requests[5].done("good",0)
assert(#entries==3 and hooks.windows_wm_allowed("Bring back every window"))
log("PASS: native WM capability menus, serialization, monitor scope and failed actions")
'''
run_checks(args, checks.replace('__MODULE__', module), 'PASS: native WM capability', 'window-manager')
