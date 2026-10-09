"""Active-window routing and cached renderer retirement, without desktop input."""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks

p = argparse.ArgumentParser(description=__doc__)
runner_arguments(p)
args = p.parse_args()
module = Path(__file__).with_name('window-manager.luau').read_text(encoding='utf-8')
checks = r'''
local A, B = "\\\\.\\DISPLAY1", "\\\\.\\DISPLAY2"
local fact, hooks, entries, handlers = {locale="es"}, {}, {}, {}
local children, calls, lookups, timers, notices = {}, {}, {}, {}, {}
local json = {decode=function() return {running=true,automatic_layouts=true,window_overview=true,
    monitors={{name=A,tiled=false},{name=B,tiled=false}}} end}
local function tr(s) return s end
local function on(name, fn) handlers[name]=fn end
local function after(ms, fn) timers[#timers+1]=fn end
local function run(command, argv, done, options)
    assert(command=="pleamar-wm")
    if argv[2]=="wm" then assert(argv[3]=="status");done("status",0);return end
    assert(argv[2]=="windows-overview")
    calls[#calls+1]={command=argv[3],done=done,endpoint=options.env.PLEAMAR_SOCKET_DIR}
end
local function spawn(command, argv, line, done, options)
    assert(command=="pleamar-wm" and argv[2]=="tools/windows-overview.plm")
    assert(argv[3]=="--screen" and argv[5]=="--preview-monitor" and argv[6]=="all" and argv[7]=="--preview-project")
    children[#children+1]={screen=argv[4],done=done,warm=options.env.MAREA_OVERVIEW_WARM,
        endpoint=options.env.PLEAMAR_SOCKET_DIR}
end
local install=(function() __MODULE__ end)()
install(run,hooks,entries,function() end,function() return B end,
    function(message) notices[#notices+1]=message end,spawn,
    function(done) lookups[#lookups+1]=done end)
-- A real request arriving during preparation must promote the pending lookup.
hooks.windows_overview(true);hooks.windows_overview()
assert(#lookups==1 and #children==0)
lookups[1](A)
assert(#children==1 and children[1].screen==A and children[1].warm=="0", "used Marea's home instead of the active program")
hooks.windows_overview();lookups[2](A)
assert(#children==1 and calls[1].command=="emit overview_toggle")
calls[1].done("",0)
-- A monitor change retires the old child before launching another renderer.
hooks.windows_overview();lookups[3](B)
assert(#children==1 and calls[2].command=="quit" and calls[2].endpoint==children[1].endpoint)
calls[2].done("",0);assert(#children==1,"quit acknowledgement is not process exit")
children[1].done("",0)
assert(#children==2 and children[2].screen==B and children[2].warm=="0")
children[1].done("",0);lookups[3](A)
assert(#children==2,"stale callbacks reopened the wrong monitor")
for _,fire in ipairs(timers) do fire() end
assert(#notices==0)
-- Failed retirement stays owned, then a subsequent request can retry it.
hooks.windows_overview();lookups[4](A)
calls[3].done("pipe busy",1);timers[#timers]()
assert(#children==2 and #notices==1 and notices[1]:find("could not close",1,true))
hooks.windows_overview();lookups[5](A)
assert(calls[4].command=="quit")
children[2].done("",0)
assert(#children==3 and children[3].screen==A)
-- Missing, invalid and late monitor results never fall back to Marea's home.
hooks.windows_overview();lookups[6]("\\\\.\\DISPLAY99")
hooks.windows_overview();lookups[7](nil,"native lookup failed")
assert(#children==3 and #calls==4 and #notices==3)
hooks.windows_overview();timers[#timers]()
lookups[8](B)
assert(#children==3 and #calls==4 and #notices==4)
-- A hidden prewarmed view also follows a later change of active monitor.
children[3].done("",0)
hooks.windows_overview(true);lookups[9](B)
assert(children[4].screen==B and children[4].warm=="1")
hooks.windows_overview();lookups[10](A)
assert(#children==4 and calls[5].command=="quit")
children[4].done("",0)
assert(#children==5 and children[5].screen==A and children[5].warm=="0")
log("PASS: active-program monitor, warm reuse, cross-monitor retirement, failures and stale callbacks")
'''
run_checks(args, checks.replace('__MODULE__', module), 'PASS: active-program monitor', 'overview-routing')
