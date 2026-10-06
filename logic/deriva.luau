-- ── Deriva: what is dropped on her, kept, and found again ──────────
--  Her library is `deriva-worker`, the same one the Quickshell Marea used: a
--  local SQLite with the files kept by their hash, which saves, searches and
--  gives back. It answers a line of JSON. What is let go on her goes in —the
--  inbox, or «Read later» / «Inspiration» if it was let go on their drops—, and
--  the page shows it again: her folders as chips, six cards, and on each card
--  its star, its folder and the trash.
--  marea.luau loads it, and hands it what it uses of its own.
return function(shared)
    local hooks, home_dir, day_label = shared.hooks, shared.home_dir, shared.day_label
    local DRIFT = "deriva-worker"
    local items, offset = {}, 0
    --  What is being looked at: all · today · fav · trash · a folder's id.
    local view = "all"
    local folders, counts, chip_keys = {}, { today = 0, fav = 0 }, {}

    local function drift_run(args, done)
        run(DRIFT, args, function(out, code)
            local ok, v = pcall(json.decode, tostring(out or ""))
            if code ~= 0 or not ok or type(v) ~= "table" then
                log("deriva ·", args[1], args[2] or "", "did not answer", code)
                if done then done(nil) end
                return
            end
            --  Its answers come wrapped (`{ ok, result }`); `where` does not.
            if v.ok == false then
                log("deriva ·", args[1], args[2] or "", "said no:", v.error and v.error.message or "?")
                if done then done(nil) end
                return
            end
            if done then done(v.result or v) end
        end)
    end
    --  Any of its methods, with its params (`call`).
    local function call(method, params, done)
        drift_run({ "call", method, "--params", json.encode(params) }, done)
    end
    --  Searching by meaning loads a model of half a gigabyte, three seconds
    --  each time from the command line: while you search, one worker stays
    --  alive (`stdio`) with it loaded —the first search waits for it, the
    --  next ones take milliseconds— and two minutes after the last search it
    --  is let go, and the memory with it.
    local searcher, asked, answers, idle = nil, 0, {}, nil
    local function search_call(params, done)
        if searcher == nil then
            searcher = spawn(DRIFT, { "stdio" }, function(line)
                local ok, v = pcall(json.decode, tostring(line or ""))
                if not ok or type(v) ~= "table" or answers[v.id] == nil then return end
                local answer = answers[v.id]
                answers[v.id] = nil
                answer(v.ok and v.result or nil)
            end, function()
                searcher = nil
                for id, answer in pairs(answers) do answers[id] = nil; answer(nil) end
            end, { stdin = "open" })
        end
        asked = asked + 1
        local id = "s" .. asked
        answers[id] = done
        if searcher == nil or not write(searcher, json.encode({ v = 1, id = id, method = "search", params = params }) .. "\n") then
            answers[id] = nil
            return call("search", params, done)
        end
        if idle then cancel(idle) end
        idle = after(120000, function()
            idle = nil
            if searcher then write(searcher) end
        end)
    end
    --  No answer at all: the library is not there, or not yet (her launcher
    --  builds it the first time, in the background).
    local function drift_where(done)
        drift_run({ "where" }, function(r)
            fact["drift.missing"] = r == nil
            if done then done() end
        end)
    end
    drift_where()

    local function toast(words)
        fact["drift.result"] = 1
        text["drift.toast"] = words
        emit("say_toast")
    end
    local function host_of(u) return ((tostring(u or ""):match("^%a+://([^/]+)") or ""):gsub("^www%.", "")) end
    local function url_of(it)
        local u = it.canonical_url or it.source_url
        return type(u) == "string" and u:match("^https?://") and u or nil
    end
    local function link_of(it)
        if type(it.source_url) == "string" and it.source_url ~= "" then return it.source_url end
        return it.blob_path or ""
    end
    local function rgb_of(hex)
        local r, g, b = tostring(hex or ""):match("^#(%x%x)(%x%x)(%x%x)")
        if not r then return 0.62, 0.84, 0.74 end
        return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
    end
    --  The three that come with her have Spanish ids and names: said in the
    --  language she speaks. Yours keep the name you gave them.
    local OWN_FOLDERS = { inspiracion = "Inspiration", ["leer-luego"] = "Read later", proyectos = "Projects" }
    local function folder_name(f) return OWN_FOLDERS[f.id] and tr(OWN_FOLDERS[f.id]) or f.name end

    --  A cover drawn when there is no picture: its site's colour and a sign.
    local LOOKS = {
        github = { 0.17, 0.19, 0.23, "</>" }, x = { 0.15, 0.17, 0.21, "X" }, reddit = { 0.62, 0.24, 0.10, "r/" },
        youtube = { 0.62, 0.13, 0.12, "▶" }, image = { 0.17, 0.22, 0.33, "IMG" }, video = { 0.25, 0.17, 0.32, "▶" },
        audio = { 0.15, 0.24, 0.32, "♪" }, document = { 0.27, 0.25, 0.17, "DOC" }, code = { 0.12, 0.24, 0.30, "</>" },
        file = { 0.20, 0.21, 0.22, "FILE" }, text = { 0.24, 0.19, 0.12, "" },
    }
    local KIND_NAMES = { image = "Image", video = "Video", audio = "Audio", document = "Document", code = "Code", file = "File", text = "Note" }
    local function look_of(it)
        local l = LOOKS[it.source] or LOOKS[it.type]
        if l then return l[1], l[2], l[3], l[4] end
        local host = host_of(url_of(it))
        return 0.12, 0.29, 0.25, string.upper(host:sub(1, 1))
    end
    local function source_of(it)
        if it.source ~= nil and it.source ~= "" and it.source ~= "web" then return it.source end
        local host = host_of(url_of(it))
        if host ~= "" then return host end
        return tr(KIND_NAMES[it.type] or "File")
    end

    -- ── the covers ──────────────────────────────────────────────────
    --  pleamar fits a picture without cutting it, and a page's picture is
    --  rarely the card's shape: each one is cut to it once, with `magick`,
    --  into the cache, named after what it was cut from.
    local THUMBS = home_dir .. "/.cache/marea/deriva"
    run("mkdir", { "-p", THUMBS }, function() end)
    local thumbs, making = {}, {}
    local function cover_of(it)
        if type(it.preview_path) == "string" and it.preview_path ~= "" then return it.preview_path end
        if it.type == "image" and type(it.blob_path) == "string" then return it.blob_path end
        return nil
    end

    local function paint_cards()
        local cards = {}
        for k = offset * 3 + 1, math.min(offset * 3 + 6, #items) do
            local it = items[k]
            local title = (it.title ~= nil and it.title ~= "") and it.title or it.blob_name or it.excerpt or "…"
            local r, g, b, glyph = look_of(it)
            local sr, sg, sb, in_space = 0, 0, 0, false
            for _, f in ipairs(folders) do
                if it.spaces and it.spaces[1] == f.id then sr, sg, sb = rgb_of(f.color); in_space = true end
            end
            local thumb = thumbs[it.id]
            cards[#cards + 1] = {
                title = tostring(title):gsub("%s+", " "), source = source_of(it),
                date = day_label(math.floor((it.captured_at or 0) / 1000)),
                thumb = thumb or "", has_thumb = type(thumb) == "string", link = link_of(it),
                fav = it.favorite == true, glyph = glyph, note = it.type == "text",
                excerpt = ("\n" .. tostring(it.excerpt or "")):gsub("\n%s*#+%s*", "\n"):gsub("\n+", "\n"):sub(2, 221),
                cr = r, cg = g, cb = b, in_space = in_space, sr = sr, sg = sg, sb = sb,
            }
        end
        model.drift = cards
        fact["drift.offset"] = offset
    end
    table.insert(hooks.language, paint_cards)

    local function make_thumbs()
        for k = offset * 3 + 1, math.min(offset * 3 + 6, #items) do
            local it = items[k]
            local src = cover_of(it)
            if src and thumbs[it.id] == nil and not making[it.id] then
                local id = it.id
                local out = THUMBS .. "/" .. tostring(src):match("([^/]+)$") .. ".jpg"
                making[id] = true
                run("test", { "-s", out }, function(_, exists)
                    local function done(ok)
                        making[id] = nil
                        thumbs[id] = ok and out or false
                        paint_cards()
                    end
                    if exists == 0 then return done(true) end
                    run("magick", { src .. "[0]", "-thumbnail", "288x168^", "-gravity", "center", "-extent", "288x168", "-quality", "85", out },
                        function(_, code)
                            if code ~= 0 then log("deriva · no cover for", id) end
                            done(code == 0)
                        end)
                end)
            end
        end
    end

    -- ── fetching what a link lacks ──────────────────────────────────
    --  What was kept without its picture —saved with no network, or before
    --  anyone looked— gets it here: the page's own (`og:image`), or for a
    --  post on X the picture fxtwitter gives (X shows nothing without
    --  JavaScript). Its title and its words too, if it had none. The worker
    --  never goes to the network; this does, one link at a time, each one
    --  once per session, the ones on screen first, and hands it what it found
    --  through `enrich`, which never treads on what is yours.
    local UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
    local tried, fetching = {}, false
    local show
    local function unescape(s)
        s = s:gsub("&#x(%x+);", function(h) return utf8.char(tonumber(h, 16)) end)
        s = s:gsub("&#(%d+);", function(d) return utf8.char(tonumber(d)) end)
        return (s:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
    end
    local function meta(html, key)
        for tag in html:gmatch("<meta%s[^>]+>") do
            local k = tag:match('property%s*=%s*"([^"]+)"') or tag:match('name%s*=%s*"([^"]+)"')
                or tag:match("property%s*=%s*'([^']+)'") or tag:match("name%s*=%s*'([^']+)'")
            if k == key then
                local v = tag:match('content%s*=%s*"([^"]*)"') or tag:match("content%s*=%s*'([^']*)'")
                if v and v ~= "" then return unescape(v) end
            end
        end
        return nil
    end
    local function url_encode(v)
        return (tostring(v):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
    end
    local function curl(args, done)
        local all = { "-sL", "--proto", "=http,https", "--max-time", "10", "-A", UA }
        for _, a in ipairs(args) do all[#all + 1] = a end
        run("curl", all, function(out, code) done(code == 0 and tostring(out or "") or nil) end)
    end
    local fetch_next
    local function hand_over(it, found)
        local params = { id = it.id }
        if found.title and found.title ~= "" then params.title = found.title end
        if found.excerpt and found.excerpt ~= "" then params.excerpt = found.excerpt end
        local function send(picture)
            if picture == nil and params.title == nil and params.excerpt == nil then
                fetching = false
                return fetch_next()
            end
            local args = { "call", "enrich", "--params", json.encode(params) }
            if picture then args[#args + 1] = "--preview-file"; args[#args + 1] = picture end
            drift_run(args, function(r)
                fetching = false
                if r and type(r.item) == "table" then
                    for k, other in ipairs(items) do
                        if other.id == it.id then items[k] = r.item end
                    end
                    thumbs[it.id] = nil
                    show()
                end
                fetch_next()
            end)
        end
        if found.image == nil then return send(nil) end
        local raw, picture = THUMBS .. "/fetched", THUMBS .. "/fetched.jpg"
        curl({ "--max-filesize", "8000000", "-o", raw, found.image }, function(ok)
            if ok == nil then return send(nil) end
            run("magick", { raw .. "[0]", "-resize", "800x800>", "-quality", "82", picture }, function(_, code)
                send(code == 0 and picture or nil)
            end)
        end)
    end
    local function fetch_one(it, url)
        local post = (host_of(url) == "x.com" or host_of(url) == "twitter.com") and url:match("/status/(%d+)")
        if post then
            return curl({ "https://api.fxtwitter.com/status/" .. post }, function(body)
                local ok, v = pcall(json.decode, body or "")
                local t = ok and type(v) == "table" and v.tweet
                if type(t) ~= "table" then return hand_over(it, {}) end
                local m, a = t.media or {}, t.author or {}
                local picture = (m.photos and m.photos[1] and m.photos[1].url)
                    or (m.videos and m.videos[1] and m.videos[1].thumbnail_url) or a.avatar_url
                hand_over(it, { image = picture, excerpt = t.text,
                                title = a.name and string.format("%s (@%s)", a.name, tostring(a.screen_name)) or nil })
            end)
        end
        --  Reddit answers a page that is only «Reddit» without JavaScript:
        --  its oEmbed has the post's title, and no picture.
        if host_of(url):match("reddit%.com$") then
            return curl({ "https://www.reddit.com/oembed?url=" .. url_encode(url) }, function(body)
                local ok, v = pcall(json.decode, body or "")
                hand_over(it, { title = ok and type(v) == "table" and v.title or nil })
            end)
        end
        curl({ "--max-filesize", "3000000", url }, function(html)
            html = html or ""
            local picture = meta(html, "og:image") or meta(html, "twitter:image")
            --  X's own «there is nothing here without JavaScript».
            if picture and picture:find("abs.twimg.com/rweb/ssr/default", 1, true) then picture = nil end
            if picture and picture:sub(1, 2) == "//" then picture = "https:" .. picture
            elseif picture and picture:sub(1, 1) == "/" then picture = url:match("^(https?://[^/]+)") .. picture end
            --  Only the page's own title: a `<title>` is often the site's
            --  name on a page that would not show itself.
            hand_over(it, { image = picture, title = meta(html, "og:title"),
                            excerpt = meta(html, "og:description") or meta(html, "description") })
        end)
    end
    fetch_next = function()
        if fetching or fact.page ~= "drift" or view == "trash" then return end
        for k = offset * 3 + 1, math.min(offset * 3 + 6, #items) do
            local it = items[k]
            local url = url_of(it)
            if url and cover_of(it) == nil and not tried[it.id] then
                tried[it.id] = true
                fetching = true
                return fetch_one(it, url)
            end
        end
    end

    show = function()
        paint_cards()
        make_thumbs()
        fetch_next()
    end

    -- ── what is looked at ───────────────────────────────────────────
    local function paint_chips()
        local chips, keys = {}, {}
        local function chip(key, label, n, color)
            if #chips >= 8 then return end
            local r, g, b = rgb_of(color)
            chips[#chips + 1] = { label = n and string.format("%s  %d", label, n) or label, chosen = view == key,
                                  dot = color ~= nil, cr = r, cg = g, cb = b }
            keys[#keys + 1] = key
        end
        --  All of them is counted in the header; an empty folder has no chip
        --  (it is still offered when moving a card).
        chip("all", tr("All"))
        if counts.today > 0 or view == "today" then chip("today", tr("Today"), counts.today) end
        if counts.fav > 0 or view == "fav" then chip("fav", "★", counts.fav) end
        for _, f in ipairs(folders) do
            if f.count > 0 or view == f.id then chip(f.id, folder_name(f), f.count, f.color or "#9ed6bd") end
        end
        model.drift_chips = chips
        chip_keys = keys
    end
    table.insert(hooks.language, paint_chips)

    local EMPTY = {
        all = "Carry anything over her: a link, a file, an image.",
        today = "Nothing kept today",
        fav = "No favourites yet: the star on a card",
        trash = "The trash is empty",
    }
    local loading = 0
    local function load(keep_place)
        loading = loading + 1
        local mine = loading
        local q = text.drift_q or ""
        fact["drift.searching"] = q ~= ""
        local function got(list, empty)
            if mine ~= loading then return end
            items = list or {}
            if not keep_place then offset = 0 end
            offset = math.max(0, math.min(offset, math.ceil(#items / 3) - 2))
            fact["drift.found"] = #items
            text["drift.empty"] = empty
            show()
        end
        if q ~= "" then
            local tag = q:match("^#(%S+)$")
            if tag then
                return call("list", { limit = 200, tag = tag:lower() }, function(r)
                    got(r and r.items, string.format(tr("Nothing tagged #%s"), tag))
                end)
            end
            return search_call({ query = q, limit = 60 }, function(r)
                got(r and r.items, string.format(tr("Nothing matches «%s»"), q))
            end)
        end
        local params = { limit = 200 }
        if view == "today" then params.today = true
        elseif view == "trash" then params.trashed = true
        elseif view ~= "all" and view ~= "fav" then params.space = view end
        call("home", params, function(r)
            if r == nil then return got({}, "") end
            local stats = r.stats or {}
            folders = {}
            for _, s in ipairs(r.sections or {}) do
                if s.kind == "space" then folders[#folders + 1] = { id = s.id, name = s.name, color = s.color, count = s.count or 0 }
                elseif s.kind == "today" then counts.today = s.count or 0 end
            end
            fact["drift.kept"] = stats.captures or 0
            fact["drift.trashed"] = stats.trashed or 0
            local list = r.items or {}
            if view == "all" or view == "fav" then
                local favs = {}
                for _, it in ipairs(list) do if it.favorite then favs[#favs + 1] = it end end
                counts.fav = #favs
                if view == "fav" then list = favs end
            end
            --  A folder that is gone (deleted elsewhere) is not looked at.
            local known = view == "all" or view == "today" or view == "fav" or view == "trash"
            for _, f in ipairs(folders) do if f.id == view then known = true end end
            if not known then view = "all"; return load() end
            paint_chips()
            got(list, tr(EMPTY[view] or "Nothing in this folder yet"))
        end)
    end
    hooks.drift_load = load

    on("drift_open", function()
        fact["drift.moving"] = -1
        if fact["drift.missing"] then drift_where(load) else load() end
    end)
    --  Typing searches, a moment after the last key.
    local typed = 0
    on("text:drift_q", function()
        typed = typed + 1
        local mine = typed
        after(260, function() if mine == typed then load() end end)
    end)
    on("drift_scroll", function(w)
        local before = offset
        offset = offset + ((w or 0) > 0 and -1 or 1)
        offset = math.max(0, math.min(offset, math.ceil(#items / 3) - 2))
        if offset ~= before then show() end
    end)
    on("drift_chip", function(i)
        local key = chip_keys[(i or 0) + 1]
        if key == nil then return end
        view = key
        fact["drift.trash"] = false
        if (text.drift_q or "") ~= "" then text.drift_q = "" end
        load()
    end)
    on("drift_bin_view", function()
        view = view == "trash" and "all" or "trash"
        fact["drift.trash"] = view == "trash"
        if (text.drift_q or "") ~= "" then text.drift_q = "" end
        paint_chips()
        load()
    end)

    local function card(i) return items[offset * 3 + (i or 0) + 1] end
    on("drift_pick", function(i)
        local it = card(i)
        if it == nil then return end
        call("annotate", { id = it.id, opened = true })
        --  A note has nowhere to open: it is copied, whole.
        if it.type == "text" then
            return call("get", { id = it.id }, function(r)
                local words = r and r.text ~= "" and r.text or it.excerpt or ""
                --  wl-copy stays behind serving it: nothing to wait for.
                run("wl-copy", {}, nil, { input = words, output = false })
                toast(tr("Copied"))
            end)
        end
        local link = link_of(it)
        if link ~= "" then run("xdg-open", { link }, function() end) end
    end)
    on("drift_fav", function(i)
        local it = card(i)
        if it == nil then return end
        local now = not it.favorite
        it.favorite = now
        counts.fav = math.max(0, counts.fav + (now and 1 or -1))
        paint_cards()
        paint_chips()
        call("annotate", { id = it.id, favorite = now }, function(r)
            if r == nil then it.favorite = not now; paint_cards() end
            if view == "fav" then load(true) end
        end)
    end)
    on("drift_bin", function(i)
        local it = card(i)
        if it == nil then return end
        local back = view == "trash"
        call(back and "untrash" or "trash", { id = it.id }, function(r)
            if r == nil then return end
            toast(back and tr("Back from the trash") or tr("In the trash"))
            load(true)
        end)
    end)
    --  Its folders: the card turns into the list of them, with «none» last.
    local moving = nil
    on("drift_move", function(i)
        local it = card(i)
        if it == nil then return end
        moving = it
        local here = it.spaces and it.spaces[1] or ""
        local list = {}
        for k = 1, math.min(#folders, 5) do
            local f = folders[k]
            local r, g, b = rgb_of(f.color or "#9ed6bd")
            list[k] = { name = folder_name(f), here = f.id == here, dot = true, cr = r, cg = g, cb = b }
        end
        list[#list + 1] = { name = tr("No folder"), here = here == "", dot = false, cr = 0, cg = 0, cb = 0 }
        model.drift_spaces = list
        fact["drift.moving"] = i
    end)
    on("drift_to", function(k)
        local it = moving
        fact["drift.moving"] = -1
        moving = nil
        if it == nil then return end
        local f = folders[(k or 0) + 1]
        if (k or 0) + 1 > math.min(#folders, 5) then f = nil end
        call("annotate", { id = it.id, space = f and f.id or "" }, function(r)
            if r == nil then return end
            toast(f and string.format(tr("Moved to %s"), folder_name(f)) or tr("Out of its folder"))
            load(true)
        end)
    end)

    --  What a file is, by its extension: it decides its icon and its filters.
    local KINDS = {
        image = { "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "avif", "heic" },
        video = { "mp4", "mkv", "webm", "mov", "avi" },
        audio = { "mp3", "ogg", "flac", "wav", "m4a", "opus" },
        document = { "pdf", "odt", "doc", "docx", "txt", "md", "epub", "rtf", "ods", "xlsx", "odp", "pptx" },
        code = { "rs", "py", "js", "ts", "lua", "luau", "c", "h", "cpp", "go", "java", "sh", "json", "toml", "yaml", "yml", "plm", "qml", "html", "css" },
    }
    local function kind_of(path)
        local ext = tostring(path):match("%.([%w]+)$")
        ext = ext and ext:lower() or ""
        for kind, list in pairs(KINDS) do
            for _, e in ipairs(list) do if e == ext then return kind end end
        end
        return "file"
    end
    local function url_decode(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

    local SPACES = { drift_drop = nil, drift_later = "leer-luego", drift_insp = "inspiracion" }
    local PLACES = { drift_drop = "Deriva", drift_later = "Read later", drift_insp = "Inspiration" }

    local function keep(data, mime, zone)
        local urls, groups, words = {}, {}, {}
        for line in tostring(data or ""):gmatch("[^\r\n]+") do
            local l = line:match("^%s*(.-)%s*$")
            if l:match("^file://") then
                local p = url_decode(l:gsub("^file://[^/]*", ""))
                local k = kind_of(p)
                groups[k] = groups[k] or {}
                table.insert(groups[k], p)
            elseif l:match("^https?://%S+$") then
                urls[#urls + 1] = l
            elseif l ~= "" and not l:match("^#") then
                words[#words + 1] = l
            end
        end
        local requests = {}
        for _, u in ipairs(urls) do requests[#requests + 1] = { type = "url", source_url = u } end
        for k, paths in pairs(groups) do requests[#requests + 1] = { type = k, paths = paths } end
        if #words > 0 and mime ~= "text/uri-list" then requests[#requests + 1] = { type = "text", text = table.concat(words, "\n") } end
        if #requests == 0 then return end
        local space = SPACES[zone]
        local saved, duplicates, failed, left = 0, 0, 0, #requests
        local function finished()
            if saved > 0 then
                fact["drift.result"] = 1
                text["drift.toast"] = string.format(tr("Kept in %s"), tr(PLACES[zone] or "Deriva"))
            elseif duplicates > 0 then
                fact["drift.result"] = 2
                text["drift.toast"] = tr("It was already there")
            else
                fact["drift.result"] = 3
                text["drift.toast"] = tr("Could not keep it")
            end
            emit("drift_saved")
            if fact.page == "drift" then load() end
        end
        for _, req in ipairs(requests) do
            if space then req.space = space end
            drift_run({ "ingest", "--request", json.encode(req) }, function(r)
                if r then
                    saved = saved + (r.saved or 0)
                    duplicates = duplicates + (r.duplicates or 0)
                else
                    failed = failed + 1
                end
                left = left - 1
                if left == 0 then finished() end
            end)
        end
    end
    for zone in pairs(PLACES) do
        on("drop:" .. zone, function(data, mime) keep(data, mime, zone) end)
    end
    --  And what is copied, from her menu or the finder: kept without carrying it.
    hooks.keep_copied = function()
        local ok, copied = pcall(sys.ask, "clipboard")
        if ok and type(copied) == "string" and copied ~= "" then keep(copied, "text/plain", "drift_drop") end
    end
end
