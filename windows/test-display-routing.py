"""Route brightness and the WM overview to Marea's third native monitor."""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks

parser = argparse.ArgumentParser(description=__doc__)
runner_arguments(parser)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
adapter = (root / 'windows/desktop-adapter.luau').read_text(encoding='utf-8')
brightness = adapter[adapter.index('local function select_brightness_monitor'):adapter.index('on("windows_display_info"')]
generated = (root / 'marea-desktop.luau').read_text(encoding='utf-8')
monitor = generated.split('end)()(native_run, hooks, plugin_entries, set_menu, function()', 1)[1].split('end, notice, native_spawn)', 1)[0]
checks = r'''
local fact, text, handlers, calls = {}, {}, {}, {}
local monitors = {"DISPLAY1", "DISPLAY2", "Third display ñ 海"}
local function on(name, callback) handlers[name] = callback end
local function notice(message) error(message) end
local native_sys = {call_async = function(name, args, done)
    assert(name == "brightness.monitor")
    calls[#calls + 1] = args[1]
    done("", 0)
end}
fact["hosts.2"] = true
__BRIGHTNESS__
assert(#calls == 0, "an unnamed display sent a native brightness command")
for k = 0, 2 do
    assert(handlers["text:screen."..k..".name"] and handlers["fact:hosts."..k], "display subscriptions are missing")
    text["screen."..k..".name"] = monitors[k + 1]
    handlers["text:screen."..k..".name"]()
end
assert(#calls == 1 and calls[1] == monitors[3], "third monitor did not select its own brightness")
local function current_monitor() __MONITOR__ end
assert(current_monitor() == monitors[3], "overview was routed away from the third monitor")
text["screen.2.name"] = "Replacement monitor 海"
handlers["text:screen.2.name"]()
assert(calls[2] == "Replacement monitor 海")
fact["hosts.2"] = false; fact["hosts.0"] = true
handlers["fact:hosts.2"](); handlers["fact:hosts.0"]()
assert(#calls == 3 and calls[3] == monitors[1] and current_monitor() == monitors[1])
fact["hosts.0"] = false
assert(current_monitor() == nil)
log("PASS: all three native monitor routes, late names and changing home")
'''.replace('__BRIGHTNESS__', brightness).replace('__MONITOR__', monitor)
run_checks(args, checks, 'PASS: all three native monitor routes', 'display-routing')
