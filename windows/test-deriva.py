"""Exercise Deriva's Windows adapter and generated logic with a mocked worker.

This is protocol/interaction coverage. test-deriva-native.py tests the real store.
"""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks

parser = argparse.ArgumentParser(description=__doc__)
runner_arguments(parser)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
module = (root / 'windows/deriva-worker.luau').read_text(encoding='utf-8')
generated = (root / 'marea-desktop.luau').read_text(encoding='utf-8')
scene = (root / 'marea-desktop.plm').read_text(encoding='utf-8')
assert 'She builds it herself when she starts, if Rust (cargo) is installed.' not in scene
presentation = generated.split('-- ── Deriva:', 1)[1].split('\nlocal seen = {}', 1)[0]
presentation = presentation[presentation.index('local drift_run'):]
checks = r'''
-- The isolated runner has no service/JSON globals. Mock the serialization
-- boundary as well as the process; the native rehearsal covers launch failure.
local encoded, serial = {}, 0
local json = {
    encode=function(value) serial += 1; local key = tostring(serial); encoded[key] = value; return key end,
    decode=function(value) assert(encoded[value], "invalid JSON fixture"); return encoded[value] end,
}
local install_deriva_worker = (function()
__MODULE__
end)()
local pending, reject = {}, false
local function native_run(command, args, done, options)
    if reject then error("missing worker") end
    assert(command == "deriva-worker" and options.cwd == ".")
    pending[#pending + 1] = {args=args, done=done}
end
local invoke, path = install_deriva_worker(native_run)
assert(path("file:///C:/Fotos%20%C3%B1/%E6%B5%B7%20%F0%9F%9A%80.png") == "C:/Fotos ñ/海 🚀.png")
assert(path("FILE://localhost/D:/a%231%25%2B.txt") == "D:/a#1%+.txt")
assert(path("file://server/share/a%20b.txt") == "//server/share/a b.txt")
for _, value in ipairs({"file:///tmp/file.txt", "file:///C:/a%GG", "file:///C:/a%", "file:///C:/a%00.txt",
    "file:///C:/a%0A.txt", "file:///C:/a%FF.txt", "file://server/", "file://user@server/share/a", "file:///C:/a?x"}) do
    assert(path(value) == nil, value)
end
local function response(args, data, code)
    local answer, message
    invoke(args, function(r, err) answer, message = r, err end)
    pending[#pending].done(type(data) == "string" and data or json.encode(data), code or 0)
    return answer, message
end
assert(response({"where"}, {blobs="C:/Store ñ/blobs"}).blobs == "C:/Store ñ/blobs")
assert(response({"where"}, {blobs="//server/share/blobs"}))
assert(not response({"where"}, {blobs="/home/test/blobs"}))
assert(not response({"list"}, "not JSON"))
assert(not response({"list"}, {ok=false, error={message="locked"}}))
local _, failure = response({"list"}, {ok=false, error={message="locked"}}, 1)
assert(failure:find("locked") and not failure:find("PATH"))
_, failure = response({"list"}, "stderr only", 2)
assert(failure:find("código 2") and not failure:find("PATH"))
assert(not response({"list"}, {result={items={"invalid"}}}))
assert(not response({"list"}, {result={items={a={title="wrong keys"}}}}))
assert(not response({"list"}, {result={items={{source={}}}}}))
assert(not response({"list"}, {result={items={{captured_at=1e100}}}}))
assert(not response({"list"}, {}))
assert(not response({"ingest"}, {result={saved="1"}}))
assert(not response({"ingest"}, {result={saved=-1}}))
assert(not response({"ingest"}, {result={saved=0}}))
assert(response({"ingest"}, {result={saved=1, duplicates=0}}).saved == 1)
assert(response({"ingest"}, {result={failed=1}}).failed == 1)
reject = true
local delivered = false
invoke({"where"}, function(r, err) assert(not r and err:find("PATH")); delivered = true end)
assert(delivered)
reject = false
local count = 0
invoke({"where"}, function() count += 1 end)
pending[#pending].done(json.encode({blobs="C:/store"}), 0)
pending[#pending].done('bad', 1)
assert(count == 1)

pending = {}
local fact, text, model, hooks, handlers, timers, emitted = {page="other"}, {}, {}, {}, {}, {}, {}
local function on(name, callback) handlers[name] = callback end
local function after(_, callback) timers[#timers + 1] = callback end
local function emit(name) emitted[#emitted + 1] = name end
local function tr(s) return s end
local function day_label(_) return "Today" end
local opened
local function run(cmd, args) assert(cmd == "xdg-open"); opened = args[1] end
local copied = "# Clipboard ñ\n\n  indented 海\nhttps://example.com/quoted\n"
local sys = {ask=function() return copied end}
__PRESENTATION__
assert(#pending == 0, "startup must not spawn a worker for an unopened page")
local function reply(index, value, code)
    pending[index].done(json.encode(value), code or 0)
end
handlers.drift_open()
assert(pending[1].args[1] == "where" and fact.windows_deriva_busy)
reply(1, {}, -1)
assert(not fact.windows_deriva_busy and not fact.windows_deriva_loaded and text.windows_deriva_status:find("PATH"))
handlers.drift_open()
reply(2, {blobs="C:/Library ñ/blobs"})
assert(pending[3].args[1] == "list")
reply(3, {ok=true,result={items={{title="original",blob_hash="abcdef", captured_at=0}}}})
assert(model.drift[1].title == "original" and fact["drift.kept"] == 1 and fact.windows_deriva_loaded)
assert(model.drift[1].link == "C:/Library ñ/blobs/ab/cd/abcdef")
handlers.drift_pick(0); assert(opened == model.drift[1].link)
text.drift_q = "old"; handlers["text:drift_q"](); timers[#timers]()
local old = #pending
text.drift_q = "new"; handlers["text:drift_q"]()
reply(old, {result={items={{title="stale"}}}})
assert(model.drift[1].title == "original", "new typing invalidates replies during debounce")
timers[#timers]()
local fresh = #pending
reply(fresh, {result={items={{title="latest"}}}})
assert(model.drift[1].title == "latest" and not fact.windows_deriva_busy)
reply(old, {}, 1)
assert(text.windows_deriva_status == "", "late errors cannot replace current state")
handlers.drift_open(); reply(#pending, {ok=false,error={message="database locked"}})
assert(model.drift[1].title == "latest" and fact["drift.kept"] == 1 and text.windows_deriva_status:find("locked"))
assert(not fact["drift.missing"], "a temporary query failure hid the previously loaded cards")
text.drift_q = "none"; handlers["text:drift_q"](); timers[#timers]()
reply(#pending, {result={items={}}})
assert(#model.drift == 0 and fact["drift.kept"] == 1 and text.windows_deriva_status:find("Sin resultados"))

fact.page = "other" -- Keep ingestion replies independent of automatic page refresh.
handlers["drop:drift_later"]("file:///C:/Files%20%C3%B1/a.txt\r\nfile://server/share/b.txt", "text/uri-list")
local request = json.decode(pending[#pending].args[3])
assert(request.type == "document" and request.space == "leer-luego")
assert(request.paths[1] == "C:/Files ñ/a.txt" and request.paths[2] == "//server/share/b.txt")
reply(#pending, {result={saved=1,failed=1}})
assert(fact["drift.result"] == 3 and text["drift.toast"]:find("Guardados: 1") and text["drift.toast"]:find("Fallidos: 1"))
handlers["drop:drift_insp"]("file:///C:/a%GG.txt\nhttps://example.com/real", "text/uri-list")
request = json.decode(pending[#pending].args[3])
assert(request.space == "inspiracion" and request.type == "url")
reply(#pending, {result={duplicates=1}})
assert(fact["drift.result"] == 3 and text["drift.toast"]:find("Fallidos: 1"))
local before = #pending
handlers["drop:drift_drop"]("file:///C:/bad%00.txt", "text/uri-list")
assert(#pending == before and fact["drift.result"] == 3 and emitted[#emitted] == "drift_saved")
handlers["drop:drift_drop"]("# URI comment\r\ninvalid://entry", "text/uri-list")
assert(#pending == before and fact["drift.result"] == 3 and text["drift.toast"]:find("Fallidos: 1"))
hooks.keep_copied()
request = json.decode(pending[#pending].args[3])
assert(request.type == "text" and request.text == copied)
reply(#pending, {result={saved=1}})
assert(fact["drift.result"] == 1)
handlers["drop:drift_drop"]("file:///C:/a.txt\nfile:///C:/b.txt", "text/uri-list")
reply(#pending, {}, 1)
assert(text["drift.toast"]:find("Fallidos: 2"))
fact.page = "drift"
do
__PRESENTATION__
end
assert(not fact.windows_deriva_loaded and fact.windows_deriva_busy and #model.drift == 0)
assert(pending[#pending].args[1] == "where", "reload of an open library must recheck its location")
reply(#pending, {}, -1)
assert(not fact.windows_deriva_busy and text.windows_deriva_status:find("PATH"))
log("PASS: Deriva Windows URIs, mocked transport, stale queries, failure preservation, partial ingestion and retry")
'''.replace('__MODULE__', module).replace('__PRESENTATION__', presentation)
run_checks(args, checks, 'PASS: Deriva Windows URIs', 'deriva')
