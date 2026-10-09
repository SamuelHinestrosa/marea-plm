"""Held-key switching: ordered cold startup, paging, reversal and cancellation."""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks
p=argparse.ArgumentParser(description=__doc__);runner_arguments(p);args=p.parse_args()
r=Path(__file__).resolve().parents[1]
checks=r'''
local fact,text,handlers,timers,activated={overview_open=false,["win.count"]=6,["win.focus"]=0},{},{},{},{}
for i=0,5 do fact["win."..i..".open"]=true end
local sys={ask=function(_,key) return key=="MAREA_LOCALE" and "en" or key=="MAREA_OVERVIEW_WARM" and "1" or "0" end}
local function tr(s) return s end
local function on(name,fn) handlers[name]=fn end
local function after(ms,fn) timers[#timers+1]=fn end
local function run() end
local function emit(event,...)
    assert(event=="overview_accept" and not fact.overview_open)
    assert(select("#",...)==0, "Luau emit only carries the event name")
    activated[#activated+1]=fact.accepted_slot
end
__SCENE__
assert(not fact.overview_open)
for i=1,5 do
    handlers.overview_cycle_forward()
    assert(fact.overview_open and fact.keyboard_slot==i)
end
assert(fact.requested_page==1 and #activated==0)
handlers.overview_cycle_forward();assert(fact.keyboard_slot==0 and fact.requested_page==0)
handlers.overview_cycle_backward();assert(fact.keyboard_slot==5 and fact.requested_page==1)
handlers.overview_commit();assert(#activated==1 and activated[1]==5 and not fact.overview_open)
fact["win.focus"]=5;handlers["fact:win.focus"]()
assert(not fact.overview_open and fact.keyboard_slot==-1)
handlers.overview_cycle_forward();assert(fact.keyboard_slot==0)
handlers.overview_close();handlers.overview_commit();assert(#activated==1)
-- A highlighted window disappearing never focuses a now-invalid slot.
handlers.overview_cycle_backward();assert(fact.keyboard_slot==4)
fact["win.4.open"]=false;fact["win.count"]=5;handlers["fact:win.4.open"]()
assert(fact.keyboard_slot~=4)
handlers.overview_close()
-- Cold startup retains every Tab and an early Win release until the complete catalogue.
for i=0,5 do fact["win."..i..".open"]=false end
fact["win.count"]=0;fact["win.focus"]=0
handlers.overview_cycle_forward();handlers.overview_cycle_forward();handlers.overview_cycle_backward();handlers.overview_commit()
assert(#activated==1 and not fact.overview_open)
for i=0,5 do fact["win."..i..".open"]=true;handlers["fact:win."..i..".open"]() end
fact["win.count"]=6
timers[#timers]()
assert(#activated==2 and activated[2]==1)
handlers.overview_close()
for _,fn in ipairs(timers) do fn() end
assert(not fact.overview_open and #activated==2)
-- No focus acknowledgement is necessary to close, including a denied action.
handlers.overview_cycle_forward();handlers.overview_commit()
assert(not fact.overview_open and #activated==3)
-- Escape invalidates a release whose target is still waiting for its catalogue.
for i=0,5 do fact["win."..i..".open"]=false end
fact["win.count"]=0
handlers.overview_cycle_forward();handlers.overview_commit();handlers.overview_close()
for i=0,5 do fact["win."..i..".open"]=true end
fact["win.count"]=6
for _,fn in ipairs(timers) do fn() end
assert(not fact.overview_open and #activated==3)
log("PASS: held-key selection, wraparound, reverse, paging, disappearing window, early release and cancellation")
'''
run_checks(args,checks.replace('__SCENE__',(r/'tools/windows-overview.luau').read_text(encoding='utf-8')),'PASS: held-key selection','overview-cycle')
checks=r'''
local A="\\\\.\\DISPLAY1"
local fact,hooks,entries,handlers={locale="en"},{},{},{}
local children,calls,lookups,timers,notices={},{},{},{},{}
local json={decode=function() return {running=true,automatic_layouts=true,window_overview=true,monitors={{name=A,tiled=false}}} end}
local function tr(s) return s end
local function on(n,f) handlers[n]=f end
local function after(ms,f) timers[#timers+1]=f end
local function run(_,argv,done,options)
    if argv[2]=="wm" then done("status",0);return end
    calls[#calls+1]={command=argv[3],done=done}
end
local function spawn(_,argv,line,done,options)
    children[#children+1]={screen=argv[4],done=done,warm=options.env.MAREA_OVERVIEW_WARM}
end
local install=(function() __ADAPTER__ end)()
install(run,hooks,entries,function() end,function() return A end,function(s) notices[#notices+1]=s end,spawn,function(done) lookups[#lookups+1]=done end)
hooks.windows_overview_cycle(1);hooks.windows_overview_cycle(1);hooks.windows_overview_cycle(-1);hooks.windows_overview_commit()
assert(#lookups==1 and #calls==0)
lookups[1](A)
assert(#children==1 and children[1].warm=="1" and calls[1].command=="get overview_open")
-- A missing startup pipe retries only a read, never repeats a possibly executed action.
calls[1].done("not ready",1);timers[#timers]()
assert(calls[2].command=="get overview_open")
calls[2].done("false",0)
local expected={"emit overview_cycle_forward","emit overview_cycle_forward","emit overview_cycle_backward","emit overview_commit"}
for i,command in ipairs(expected) do
    assert(calls[i+2].command==command and #calls==i+2)
    calls[i+2].done("",0)
end
assert(#children==1 and #notices==0)
-- Releasing after Escape cannot resurrect or activate a cancelled session.
hooks.windows_overview_cycle(1);lookups[2](A)
hooks.windows_overview_cancel();hooks.windows_overview_commit()
assert(calls[7].command=="get overview_open");calls[7].done("false",0)
assert(calls[8].command=="emit overview_cycle_forward");calls[8].done("",0)
assert(calls[9].command=="emit overview_close");calls[9].done("",0)
assert(#calls==9 and #children==1)
log("PASS: queued Tab/Shift+Tab/release through slow lookup and cold IPC, no toggles, ordered cancellation")
'''
run_checks(args,checks.replace('__ADAPTER__',(r/'windows/window-manager.luau').read_text(encoding='utf-8')),'PASS: queued Tab','overview-cycle-routing')
