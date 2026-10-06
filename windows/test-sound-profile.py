"""Run the adapted upstream sound logic and verify its scene declarations."""
import argparse
from pathlib import Path
import runpy
from logic_test import runner_arguments, run_checks

parser = argparse.ArgumentParser(description=__doc__)
runner_arguments(parser)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
sources = runpy.run_path(str(root / 'windows/profile-source.py'))
scene, logic = runpy.run_path(str(root / 'windows/sound-profile.py'))['apply'](
    sources['scene_source'](root / 'marea.plm'), sources['logic_source'](root), root)
assert 'model outputs max 32' in scene and 'model mics max 32' in scene
assert scene.count('view: 416, 160') == 2
assert 'on release level.0 { windows_level_drag.1 = false;' in scene
assert 'on release level.1 { windows_level_drag.2 = false;' in scene
assert 'and pick(k, windows_level_available.1, windows_level_available.2) }' in scene
start = logic.index('    -- ── sound: where it plays')
end = logic.index('    -- ── focus', start)
module = (root / 'windows/app-audio.luau').read_text(encoding='utf-8')
checks = '''
local fact, text, model = {}, {}, {}
local hooks, apps, audio_state = { language = {} }, {}, {}
local handlers, watches, calls, notices, timers, clock, serial = {}, {}, {}, {}, {}, 0, 0
local function tr(s) return s end
local function notice(s) notices[#notices + 1] = s end
local function on(name, f) handlers[name] = f end
local function after(ms, f) serial += 1; timers[serial] = { at = clock + ms, run = f }; return serial end
local function cancel(id) timers[id] = nil end
local function advance(ms)
    local limit = clock + ms
    while true do
        local chosen, at = nil, math.huge
        for id, t in pairs(timers) do if t.at < at then chosen, at = id, t.at end end
        if not chosen or at > limit then break end
        local t = timers[chosen]; timers[chosen] = nil; clock = at; t.run()
    end
    clock = limit
end
local native_sys = { call_async = function(name, args, done) calls[#calls + 1] = { name = name, args = args, done = done } end }
local sys = {
    watch = function(name, f) watches[name] = f end,
    call = function(name, ...) native_sys.call_async(name, {...}, function() end) end,
}
local install_app_audio = (function()
__MODULE__
end)()
__SOUND__
local outputs, inputs = {}, {}
for i = 1, 16 do outputs[i] = { name = string.rep("Ñ海", 25) .. i, id = "out " .. i, default = i == 16 } end
for i = 1, 9 do inputs[i] = { name = "Micrófono " .. i, id = "in " .. i, default = i == 9 } end
local function state(apps) watches.audio({ outputs = outputs, inputs = inputs, apps = apps }) end
local a = { id = "exact-instance-A", name = "", title = "Unicode 音楽", volume = 0.3, muted = false }
local b = { id = "exact-instance-B", name = "播放器", title = "", volume = 0.7, muted = false }
state({a, b})
assert(#model.outputs == 16 and #model.mics == 9)
assert(utf8.len(text["sound.out_name"]) == 42, "shortening split a UTF-8 character")
assert(model.sound_apps[1].name == "?" and model.sound_apps[1].letter == "?")
assert(model.sound_apps[2].letter == "播")
handlers.pick_device(24)
assert(calls[1].name == "audio.default" and calls[1].args[1] == "in 9", "endpoint indexing lost an input")
for i = 1, 95 do handlers.app_volume(i) end
advance(16)
assert(#calls == 2 and calls[2].name == "audio.app_volume" and calls[2].args[1] == a.id and calls[2].args[2] == 0.95)
assert(model.sound_apps[1].volume == 0.95)
state({b, a})
calls[2].done("", 0); advance(16)
assert(model.sound_apps[1].volume == 0.7 and model.sound_apps[2].volume == 0.95, "a reordered row inherited another session's preview")
a.volume = 0.95; state({b, a})
handlers.app_mute(1); advance(16)
assert(calls[3].args[1] == a.id and calls[3].args[2] == true)
calls[3].done("", 0); a.muted = true; state({b, a}); advance(16)
assert(model.sound_apps[2].muted and not model.sound_apps[1].muted)
watches.audio({ outputs = {}, inputs = {}, apps_error = "Audio service unavailable" })
assert(#model.sound_apps == 0 and text.windows_mixer_status == "Audio service unavailable")
handlers.app_volume(10); advance(5000)
assert(#calls == 3)
log("SOUND_PROFILE_OK: current upstream page, native asynchronous mixer, device lists, Unicode and exact readback identities")
'''.replace('__MODULE__', module).replace('__SOUND__', logic[start:end])
run_checks(args, checks, 'SOUND_PROFILE_OK', 'sound profile')
