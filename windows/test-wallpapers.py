"""Exercise wallpaper confirmation and queue failures without changing the desktop."""
from pathlib import Path
import argparse

parser = argparse.ArgumentParser(description=__doc__)
from logic_test import runner_arguments, run_checks
runner_arguments(parser)
args = parser.parse_args()
module = Path(__file__).with_name('wallpapers.luau').read_text(encoding='utf-8')
checks = r'''
local fact, model, handlers, requests, events, notices = { ["tide.on"] = true }, {}, {}, {}, {}, {}
local WALLPAPER, saves, reject = "", 0, false
local function on(name, callback) handlers[name] = callback end
local function emit(name) events[#events + 1] = name end
local function notice(message) notices[#notices + 1] = message end
local function save_settings() saves += 1 end
local function queue(name, args, callback)
    if reject then error("service queue full") end
    requests[#requests + 1] = { name = name, args = args, callback = callback }
end
local native_sys = { ask_async = queue, call_async = queue }
local function complete(name, value, error)
    local request = table.remove(requests, 1)
    assert(request and request.name == name, "unexpected request: " .. name)
    request.callback(value, error)
end
__MODULE__
assert(fact["tide.on"] == false, "reload left the abandoned transition covering the desktop")
handlers.tide_done()
assert(#requests == 1, "an abandoned transition committed a wallpaper after reload")
complete("wallpaper.state", { current = "C:/original.png" })
assert(model.wallnow[1].ready and model.wallnow[1].thumb == "C:/original.png")
handlers.walls_open()
complete("wallpaper.list", { current = "C:/original.png", items = {
    { name = "Original", path = "C:/original.png" }, { name = "New", path = "C:/new.png" },
} })
handlers.wall_pick(0)
assert(#requests == 0, "selecting the current wallpaper should not change Windows")
reject = true
handlers.wall_pick(1)
assert(#notices > 0 and saves == 0, "enqueue failure was hidden")
reject = false
handlers.wall_pick(1)
complete("wallpaper.preview", nil, "invalid image")
assert(notices[#notices] == "invalid image" and saves == 0)
local function choose()
    handlers.wall_pick(1)
    complete("wallpaper.preview", "C:/preview.jpg")
    assert(events[#events] == "tide_start" and #requests == 0)
    handlers.tide_done()
end
choose()
complete("wallpaper.set", "device error", -1)
assert(events[#events] == "tide_away" and saves == 0)
choose()
complete("wallpaper.set", "", 0)
complete("wallpaper.state", { current = "C:/original.png" })
assert(saves == 0 and WALLPAPER == "C:/original.png", "unconfirmed wallpaper was persisted")
choose()
complete("wallpaper.set", "", 0)
complete("wallpaper.state", { current = "c:\\new.png" })
assert(saves == 1 and model.walls[2].current and events[#events] == "tide_away")
assert(#requests == 0)
log("PASS: wallpaper preview, queue failure, retries, native failure and confirmed persistence")
'''.replace('__MODULE__', module)
run_checks(args, checks, 'PASS: wallpaper preview', 'wallpapers')
