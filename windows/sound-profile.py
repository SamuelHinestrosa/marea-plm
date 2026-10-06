"""Adapt the current upstream mixer to asynchronous native Windows controls."""
from pathlib import Path
import re


def replace(source, old, new):
    assert source.count(old) == 1, f'Upstream sound changed: {old[:70]}'
    return source.replace(old, new, 1)


def apply(scene, logic, root: Path):
    module = (root / 'windows/app-audio.luau').read_text(encoding='utf-8')
    logic = 'local install_app_audio = (function()\n' + module + '\nend)()\n' + logic
    logic = replace(logic, '    local shown_apps = {}', '''    local paint_sound
    local app_audio = install_app_audio(native_sys, function(message) notice(tr(message)) end,
        function() if paint_sound then paint_sound() end end)
    local shown_apps = {}''')
    logic = replace(logic, '    local function paint_sound()', '    paint_sound = function()')
    logic = replace(logic, '        audio_state = state or {}\n        paint_sound()', '''        audio_state = state or {}
        app_audio.observe(audio_state.apps)
        text.windows_mixer_status = audio_state.apps_error or ""
        paint_sound()''')
    logic = replace(logic, '            local title = a.title or ""', '''            local volume, muted = app_audio.preview(a.id, a.volume, a.muted)
            local title = a.title or ""''')
    logic = replace(logic, 'volume = math.clamp(a.volume or 0, 0, 1), muted = a.muted == true',
                    'volume = math.clamp(volume or 0, 0, 1), muted = muted == true')
    logic = replace(logic, 'if a then pcall(sys.call, "audio.app_volume", a.id, (v % 1000) / 100) end',
                    'if a then app_audio.volume(a.id, (v % 1000) / 100) end')
    logic = replace(logic, 'if a then pcall(sys.call, "audio.app_mute", a.id) end',
                    'if a then app_audio.mute(a.id) end')
    scene = replace(scene, '    text sound.more = ""', '    text sound.more = ""\n    text windows_mixer_status = ""')
    scene = replace(scene, 'model outputs max 5', 'model outputs max 32')
    scene = replace(scene, 'model mics max 4', 'model mics max 32')
    start = scene.index('    // ── sound: a mixer')
    end = scene.index('    on key Escape while page == sound', start)
    sound = scene[start:end]
    assert sound.count('n * 32 + 10') == 3
    sound = sound.replace('n * 32 + 10', 'min(n, 5) * 32 + 10')
    sound, count = re.subn(r'(?m)^(\s*)column \{\n([ \t]*)at: lx \+ 36, dy \+ 3',
        lambda m: m[1] + 'column {\n' + m[2] + 'view: 416, 160\n' + m[2] + 'at: lx + 36, dy + 3', sound)
    assert count == 2
    scene = scene[:start] + sound + scene[end:]
    scene = replace(scene, 'text "Nothing is playing right now." {', '''text windows_mixer_status { at: card.x, ay + 148; anchor: center; width: 450; lines: 2; size: 10.5; color: #ef7a66 }
        text "Nothing is playing right now." {''')
    # Sound's second pair of sliders uses the same low-latency state as the
    # control center. An absent microphone remains unavailable here as well.
    scene = replace(scene, 'let val = pick(k, vol_level, mic_level)',
                    'let val = if(pick(k, windows_level_available.1, windows_level_available.2), if(pick(k, windows_level_pending.1, windows_level_pending.2), pick(k, windows_level_target.1, windows_level_target.2), pick(k, sound.volume, sound.input)), 0)')
    for slot, event in ((0, 'set_volume'), (1, 'set_mic')):
        expr = 'clamp((pointer.x - (card.x - 168)) / 330, 0, 1)'
        for gesture in ('press', 'drag'):
            scene = replace(scene, f'on {gesture} level.{slot} {{ emit {event}({expr}) }}',
                f'on {gesture} level.{slot} {{ windows_level_drag.{slot + 1} = true; windows_level_pending.{slot + 1} = true; windows_level_target.{slot + 1}: {expr} ~16ms; emit {event}({expr}) }}')
        scene = replace(scene, f'        on drag level.{slot}',
            f'        on release level.{slot} {{ windows_level_drag.{slot + 1} = false; windows_level_pending.{slot + 1} = true; windows_level_target.{slot + 1}: {expr} ~16ms; emit {event}({expr}) }}\n        on drag level.{slot}')
    scene = replace(scene, 'zone box level.$k { from: lx + 52, py + 44; size: 346, 22; cursor: pointer; active: page == sound and paging > 0.9 and sound.choosing == 0 }',
                    'zone box level.$k { from: lx + 52, py + 44; size: 346, 22; cursor: pointer; active: page == sound and paging > 0.9 and sound.choosing == 0 and pick(k, windows_level_available.1, windows_level_available.2) }')
    return scene, logic
