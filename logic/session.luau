-- Marea's logic, in pieces: the session, the lock.
-- marea.luau loads it, and hands it what it uses of its own.
return function(shared)
    -- ── the session ────────────────────────────────────────────────────
    --  The only thing in the whole scene that cannot be undone, so it wears two
    --  belts. The first one is the sheet's and lives in the scene: logging out,
    --  rebooting and powering off open a separate question, and the answer needs
    --  a new press. The second one is from here: with `MAREA_TESTING` set, what
    --  would be done is noted down and not done, which is what lets you rehearse
    --  the whole gesture without being left without a machine halfway through the
    --  test.
    -- ── the lock ──────────────────────────────────────────────────────
    --  Marea locks the door herself —the scene, with `kind: lock`—; here it is
    --  only asked whether the password is the right one. Who gets in is decided by
    --  PAM, and it takes its time on purpose when it is not: meanwhile, the scene
    --  stays alive and says it is checking.
    --  The emergency exit is its own thing, not the testing mode's: `MAREA_TESTING`
    --  makes powering off and rebooting only be noted down, and that has no reason
    --  to go together with the lock opening with Esc. The first real locks carry
    --  the exit; when the variable is removed, it stops being there.
    fact.with_exit = (sys.ask("env", "MAREA_LOCK_WITH_EXIT") or "") ~= "" or (sys.ask("env", "MAREA_TESTING") or "") ~= ""
    --  A rule cannot touch a text, so emptying the box is this side's business:
    --  when the lock goes on and when it comes off, let nothing be left written.
    on("fact:locked", function() text.password = "" end)
    on("submit:password", function(value)
        if fact.locked ~= true or fact.checking == true then return end
        if value == nil or value == "" then return end
        fact.checking = true
        --  Whatever happens with the check, «checking» does not stay on: with it
        --  on you cannot try again, and a lock screen that does not let you try
        --  again is a broken lock screen.
        after(8000, function() fact.checking = false end)
        local ok, valid = pcall(sys.ask, "auth.check", value)
        text.password = ""
        fact.checking = false
        if ok and valid == true then
            fact.locked = false
        else
            if not ok then log("lock · the password could not be checked:", valid) end
            emit("wrong_password")
        end
    end)

    local commands = { "session.lock", "session.suspend", "session.logout", "session.reboot", "session.poweroff" }
    local testing = sys.ask("env", "MAREA_TESTING")

    on("session", function(k)
        local command = commands[k]
        if command == nil then
            log("session: there is no action number", k)
            return
        end
        if testing ~= nil and testing ~= "" then
            log("session · testing: it would call", command)
            return
        end
        --  Once and only once: «after confirming, send the request a single time».
        log("session ·", command)
        sys.call(command)
    end)
end
