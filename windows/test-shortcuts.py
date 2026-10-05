"""Optional Windows-key ownership, native readback, persistence and action routing."""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks

parser = argparse.ArgumentParser(description=__doc__)
runner_arguments(parser)
args = parser.parse_args()
module = Path(__file__).with_name('shortcuts.luau').read_text(encoding='utf-8')
checks = r'''
local fact, text, handlers, requests, timers, notices, events = {}, {}, {}, {}, {}, {}, {}
local watcher
local function tr(s) return s end
local function on(n,f) handlers[n]=f end
local function after(_,f) timers[#timers+1]=f end
local function emit(n) events[#events+1]=n end
local native={ask=function(n,k) assert(n=="env" and k=="MAREA_SEARCH_HOTKEY");return nil end,
    watch=function(n,f) assert(n=="hotkeys");watcher=f;f({sequence=0,event=""}) end,
    call_async=function(n,a,f) requests[#requests+1]={name=n,args=a,done=f} end,
    ask_async=function(n,a,f) requests[#requests+1]={name=n,args=a,done=f} end}
local install=(function() __MODULE__ end)()
local overview=0
install(native,function(message) notices[#notices+1]=message end,{windows_overview=function() overview+=1 end})
assert(requests[1].name=="hotkeys.bind" and requests[1].args[2]=="Ctrl+Alt+Space")
requests[1].done("",0)
assert(requests[2].name=="files.read");requests[2].done(nil,"not found")
assert(requests[3].name=="hotkeys.windows" and requests[3].args[1]==false)
requests[3].done("",0);requests[4].done({available=true,windows_key=false},nil)
assert(not fact.windows_key_enabled and not fact.windows_key_busy and fact.windows_key_available)
assert(#notices==0 and text.windows_search_hint:find("Ctrl+Alt+Space",1,true))
handlers.windows_toggle_key();handlers.windows_toggle_key()
assert(#requests==5 and requests[5].args[1]["Win"]=="search" and requests[5].args[1]["Win+Shift+A"]=="chat")
requests[5].done("",0);requests[6].done({available=true,windows_key=true},nil)
assert(requests[7].name=="files.write" and requests[7].args[1]=="shortcuts.json" and requests[7].args[2].windows_key)
requests[7].done("",0)
assert(fact.windows_key_enabled and not fact.windows_key_busy)
for i,name in ipairs({"search","chat","controls","settings","notifications","windows"}) do watcher({sequence=i,event=name}) end
assert(table.concat(events,",")=="search,chat,windows_controls,settings,open_tray" and overview==1)
watcher({sequence=6,event="windows"});watcher({sequence=7,event="unrelated"})
assert(overview==1 and #events==5)
handlers.windows_toggle_key();assert(requests[8].args[1]==false)
requests[8].done("",0);requests[9].done({available=true,windows_key=false},nil)
requests[10].done("disk full",1)
assert(not fact.windows_key_enabled and not fact.windows_key_busy and #notices==1)
assert(text.windows_key_status:find("saving failed",1,true))
handlers.windows_toggle_key();requests[11].done("already owned",1)
requests[12].done({available=true,windows_key=false},nil)
assert(not fact.windows_key_enabled and #notices==2 and #requests==12)
handlers.windows_toggle_key();requests[13].done("",0)
requests[14].done({available=true,windows_key=true},nil)
timers[#timers]()
assert(not fact.windows_key_available and not fact.windows_key_busy)
requests[15].done("",0) -- A late file reply cannot overwrite timeout state.
assert(not fact.windows_key_available)
handlers["fact:section"]("windows_shortcuts")
requests[16].done({available=true,windows_key=true},nil)
assert(fact.windows_key_available and fact.windows_key_enabled)
-- Restore only a recognized saved opt-in; preserve custom and disabled fallback shortcuts.
for _,case in ipairs({{version=1,windows_key=true}, {version=2,windows_key=true}, {version=1,windows_key=false}}) do
    fact, text, handlers, requests, timers, notices, events = {}, {}, {}, {}, {}, {}, {}
    native.ask=function() return case.version==2 and "" or "Ctrl+Shift+K" end
    install(native,function(message) notices[#notices+1]=message end,{})
    assert(requests[1].name==(case.version==2 and "hotkeys.unbind" or "hotkeys.bind"))
    if case.version==1 then assert(requests[1].args[2]=="Ctrl+Shift+K") end
    requests[1].done("",0);requests[2].done(case,nil)
    local wanted=case.version==1 and case.windows_key
    assert((type(requests[3].args[1])=="table")==wanted)
    requests[3].done("",0);requests[4].done({available=true,windows_key=wanted},nil)
    assert(fact.windows_key_enabled==wanted and not fact.windows_key_busy and #requests==4)
end
log("PASS: optional Windows-key layer, native confirmation, persistence failure, duplicate/stale callbacks and action routing")
'''
run_checks(args, checks.replace('__MODULE__', module), 'PASS: optional Windows-key', 'shortcuts')
