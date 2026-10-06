-- Marea's logic, in pieces: the photograph, the recording.
-- marea.luau loads it, and hands it what it uses of its own.
return function(shared)
    local home_dir = shared.home_dir
    -- ── the photograph ─────────────────────────────────────────────────
    --  The whole design rests on a decision that comes from Marea: you do not
    --  frame the live desktop, you frame a FROZEN one. She leaves the frame, a
    --  photo of everything is taken, and that photo is what gets cropped. That way
    --  a menu that closes on the first click, a video that keeps playing or a
    --  notice that arrives mid-selection cannot spoil anything: what comes out was
    --  already done.
    --
    --  The scene says `gone` when she is no longer there; here the screen is
    --  frozen, she is told `frozen` so that she comes back —turned into a camera—,
    --  the crop is worked out according to what was asked for, and `shoot` is the
    --  shutter's click.
    --  Who says how the desktop is —the monitors, which one has the focus, where
    --  the active window is—: Hyprland when she lives on it; else pleamar-wm's own
    --  session, which says it in the same words (`pleamar-wm hyprctl …`).
    local on_hyprland = (sys.ask("env", "HYPRLAND_INSTANCE_SIGNATURE") or "") ~= ""
    local function hyprctl(what, done)
        if on_hyprland then
            run("hyprctl", { what }, done)
        else
            run("pleamar-wm", { "hyprctl", what }, done)
        end
    end

    --  In the pictures folder the session names —`~/Pictures` in English,
    --  `~/Imágenes` in Spanish—, as the videos do.
    local PHOTOS = home_dir .. "/Imágenes/Marea"
    local FRAME = (sys.ask("env", "XDG_RUNTIME_DIR") or "/tmp") .. "/marea-plm-frame.png"
    run("xdg-user-dir", { "PICTURES" }, function(d)
        if d and d ~= "" then PHOTOS = d .. "/Marea" end
        run("mkdir", { "-p", PHOTOS })
    end)

    --  The monitors: where the plane starts —`grim` photographs it whole and its
    --  corner is the one of the monitor furthest up and to the left— and which one
    --  has the focus.
    local function parse_monitors(txt)
        local minx, miny, focused = 0, 0, nil
        for block in (txt .. "\n\n"):gmatch("(Monitor .-)\n\n") do
            local w, h, x, y = block:match("(%d+)x(%d+)@[%d%.]+ at (%-?%d+)x(%-?%d+)")
            if w then
                x, y = tonumber(x), tonumber(y)
                minx, miny = math.min(minx, x), math.min(miny, y)
                if block:find("focused: yes") then focused = { x = x, y = y, w = tonumber(w), h = tonumber(h) } end
            end
        end
        return minx, miny, focused
    end

    local function save(x, y, w, h)
        if w == nil or w < 2 or h < 2 then emit("shot_cancelled"); return end
        local dest = PHOTOS .. "/marea-" .. os.date("%Y%m%d-%H%M%S") .. ".png"
        run("magick", { FRAME, "-crop", string.format("%dx%d+%d+%d", w, h, x, y), "+repage", dest }, function(_, code)
            if code ~= 0 then log("photo · could not be cropped"); emit("shot_cancelled"); return end
            emit("shoot")
            --  To the clipboard too. `wl-copy` stays in the background serving what
            --  was copied, so there is no waiting for what it writes.
            run("wl-copy", { "--type", "image/png" }, nil, { stdin = dest, output = false })
            log("photo ·", dest)
        end)
    end

    on("gone", function()
        if fact.purpose ~= "shot" then return end
        local scope = fact.scope
        --  A breather so the compositor can take away whatever was closing.
        after(140, function()
            --  The active window is asked BEFORE freezing: it is the one that was there.
            hyprctl("activewindow", function(window)
                hyprctl("monitors", function(mons)
                    local minx, miny, focused = parse_monitors(mons or "")
                    run("grim", { FRAME }, function(_, code)
                        if code ~= 0 then log("photo · grim could not freeze the screen"); emit("shot_cancelled"); return end
                        emit("frozen")
                        if scope == "display" and focused then
                            save(focused.x - minx, focused.y - miny, focused.w, focused.h)
                        elseif scope == "active_window" then
                            local ax, ay = (window or ""):match("at: (%-?%d+),(%-?%d+)")
                            local aw, ah = (window or ""):match("size: (%d+),(%d+)")
                            if ax then save(tonumber(ax) - minx, tonumber(ay) - miny, tonumber(aw), tonumber(ah))
                            else emit("shot_cancelled") end
                        else
                            --  `slurp` gives «X,Y WxH» on the whole plane; Esc leaves with nothing.
                            run("slurp", {}, function(sel, c2)
                                local x, y, w, h = (sel or ""):match("(%-?%d+),(%-?%d+) (%d+)x(%d+)")
                                if c2 ~= 0 or x == nil then emit("shot_cancelled"); return end
                                save(tonumber(x) - minx, tonumber(y) - miny, tonumber(w), tonumber(h))
                            end)
                        end
                    end)
                end)
            end)
        end)
    end)

    -- ── the recording ──────────────────────────────────────────────────
    --  Marea already learned the hard part, and here it is copied as it is:
    --  · The countdown happens BEFORE starting the recorder: three seconds to move
    --    the mouse out of the way, and none of them in the video because there is
    --    no video yet.
    --  · Constant frame rate (`-r 60 -D`). Without it `wf-recorder` only emits a
    --    frame when something changes and the video's clock stops being the real one.
    --  · Stopping is SIGINT and never killing: an MP4 writes its index at the end,
    --    and without an index nobody can open it. That is why the recording is not
    --    considered finished when «Stop» is pressed, but when the recorder HAS EXITED.
    local VIDEOS = home_dir .. "/Vídeos/Marea"
    run("xdg-user-dir", { "VIDEOS" }, function(d)
        if d and d ~= "" then VIDEOS = d .. "/Marea" end
        run("mkdir", { "-p", VIDEOS })
    end)
    local nvenc = false
    run("test", { "-e", "/proc/driver/nvidia/version" }, function(_, code) nvenc = code == 0 end)
    --  With the system's sound —what is playing, not the microphone, which is not
    --  opened—, which is how Marea recorded. It is asked when going to record,
    --  because the current output may have changed since it started.

    local recorder, video = nil, nil
    --  The last one saved, for the card's buttons.
    local last_video = nil
    on("reel_watch", function() if last_video then run("xdg-open", { last_video }, function() end) end end)
    on("reel_folder", function() run("xdg-open", { VIDEOS }, function() end) end)
    on("reel_copy", function() if last_video then run("wl-copy", { last_video }, function() end) end end)

    on("fact:face", function(face)
        if face ~= "rec" or recorder ~= nil then return end
        run("pactl", { "get-default-sink" }, function(sound_sink, sink_code)
        if sink_code ~= 0 or sound_sink == "" then sound_sink = nil end
        hyprctl("monitors", function(mons)
            if fact.face ~= "rec" then return end          -- she changed her mind during the countdown
            local monitor = nil
            for block in ((mons or "") .. "\n\n"):gmatch("(Monitor .-)\n\n") do
                if block:find("focused: yes") then monitor = block:match("Monitor (%S+)") end
            end
            video = VIDEOS .. "/marea-" .. os.date("%Y%m%d-%H%M%S") .. ".mp4"
            local args = { "-f", video }
            local codec = nvenc and { "-c", "h264_nvenc", "-p", "preset=p5", "-p", "rc=vbr", "-p", "cq=23" }
                                or { "-c", "libx264", "-p", "preset=veryfast", "-p", "crf=23" }
            for _, a in ipairs(codec) do args[#args + 1] = a end
            for _, a in ipairs({ "-r", "60", "-D" }) do args[#args + 1] = a end
            if monitor then args[#args + 1] = "-o"; args[#args + 1] = monitor end
            --  `--audio=DEVICE` with the value attached: that is how `wf-recorder`
            --  documents it, and separated it silently takes it as «the default
            --  device», which is the microphone.
            if sound_sink then args[#args + 1] = "--audio=" .. sound_sink .. ".monitor" end
            local this_one
            --  Whether it got to record: kept here, not read from `taping`, which the
            --  scene switches off the moment «stop» is pressed —long before the
            --  recorder has finished—, so a finished recording never had its party.
            local reached = false
            local this_video = video
            this_one = spawn("wf-recorder", args, function() end, function(_, code)
                --  Now it really has finished, with its index written.
                if recorder == this_one then recorder = nil end
                local recorded = reached
                fact.taping = false
                log("recording · saved", video, "· exit", code)
                --  If it left on its own —it could not start—, let her not stay in
                --  the corner recording nothing.
                if fact.face == "rec" then emit("stop") end
                --  A video really made —it was recording, and the recorder closed it
                --  cleanly— deserves a party. Once she is back from her corner: she
                --  comes down 300 ms after `stop`, and the fireworks are hers.
                --  And the card that comes out of her: watch it, its folder, or its path.
                if recorded and (code == nil or code == 0) then
                    last_video = this_video
                    text["reel.name"] = this_video:match("[^/]+$") or this_video
                    after(700, function()
                        emit("celebrate")
                        emit("recorded")
                    end)
                end
            end)
            recorder = this_one
            --  «Really running»: if it is still alive after 400 ms, the red is its own.
            after(400, function()
                if recorder == this_one then
                    fact.taping = true
                    reached = true
                end
            end)
        end)
        end)
    end)

    on("stop", function()
        if recorder ~= nil then kill(recorder, "int") end
    end)
    return { hyprctl = hyprctl }
end
