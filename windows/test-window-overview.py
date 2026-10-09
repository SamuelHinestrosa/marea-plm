"""Window selection closes the overview only after native focus acknowledgement."""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks

parser = argparse.ArgumentParser(description=__doc__)
runner_arguments(parser)
args = parser.parse_args()
module = (Path(__file__).resolve().parents[1] / 'tools/windows-overview.luau').read_text(encoding='utf-8')
checks = r'''
local handlers, timers, requests = {}, {}, {}
local fact, text = {overview_open=true,["win.0.open"]=true,["win.1.open"]=true,["win.focus"]=-1}, {}
local warm, keep_warm = false, false
local sys = {ask=function(service,key) assert(service=="env");if key=="MAREA_OVERVIEW_KEEP_WARM" then return keep_warm and "1" or "0" end;return key=="MAREA_LOCALE" and "es" or key=="MAREA_OVERVIEW_WARM" and warm and "1" or "0" end}
local function tr(s) return s end
local function on(name,callback) handlers[name]=callback end
local function after(ms,callback) timers[#timers+1]={ms=ms,fire=callback} end
local function run(command,args,callback)
    assert(command=="pleamar-wm" and args[1]=="--say" and args[2]=="windows-overview" and args[3]=="quit")
    requests[#requests+1]=callback
end
local function install() __MODULE__ end
install()
assert(fact.locale=="es")
assert(fact.overview_count==2 and fact["overview_place.0"]==0 and fact["overview_place.1"]==1)
-- Minimized windows remain selectable, including windows on later pages.
fact["win.9.open"]=true;fact["win.9.minimized"]=true
handlers["fact:win.9.open"](true)
assert(fact.overview_count==3 and fact["overview_place.9"]==2)
fact["win.0.open"]=false;handlers["fact:win.0.open"](false)
assert(fact.overview_count==2 and fact["overview_place.0"]==-1 and fact["overview_place.1"]==0 and fact["overview_place.9"]==1)
fact["win.9.open"]=false;handlers["fact:win.9.open"](false)
fact["win.0.open"]=true;handlers["fact:win.0.open"](true)
assert(fact.overview_count==2 and fact["overview_place.9"]==-1)
for _,slot in ipairs({-1,32,0.5,"0",2}) do handlers.overview_select(slot) end
assert(#timers==0 and #requests==0)
handlers.overview_select(0);handlers.overview_select(0)
timers[1].fire();assert(text.overview_status=="" and fact.overview_open)
timers[2].fire();assert(text.overview_status:find("has not been confirmed",1,true) and fact.overview_open)
fact["win.focus"]=0;handlers["fact:win.focus"](0)
assert(fact.overview_open) -- Expired selection cannot dismiss a later view.
handlers.overview_select(1)
fact["win.focus"]=1;handlers["fact:win.focus"](1)
assert(not fact.overview_open and #requests==0 and timers[4].ms==60000)
handlers.overview_close();assert(#timers==4)
handlers.overview_toggle();assert(fact.overview_open and text.overview_status=="")
timers[3].fire();timers[4].fire();assert(fact.overview_open and #requests==0)
handlers.overview_toggle();assert(not fact.overview_open)
handlers.overview_select(0);assert(#timers==5)
timers[5].fire();assert(#requests==1)
warm = true;timers={};requests={};handlers={}
install()
assert(not fact.overview_open and #timers==1 and timers[1].ms==60000)
handlers.overview_toggle();assert(fact.overview_open)
timers[1].fire();assert(#requests==0)
handlers.overview_close();assert(not fact.overview_open and #timers==2)
timers[2].fire();assert(#requests==1)
keep_warm = true; timers={};requests={};handlers={}
install();assert(not fact.overview_open and #timers==0)
handlers.overview_toggle();handlers.overview_close()
assert(not fact.overview_open and #timers==0 and #requests==0)
log("PASS: overview selection acknowledgement, reuse, closed input and stale idle timers")

'''
run_checks(args, checks.replace('__MODULE__', module), 'PASS: overview selection', 'window-overview')
