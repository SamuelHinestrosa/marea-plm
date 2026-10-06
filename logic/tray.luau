-- Marea's logic, in pieces: the system tray.
-- marea.luau loads it, and hands it what it uses of its own.
return function(shared)
    -- ── the system tray ────────────────────────────────────────────────
    --  Which icons there are is said by pleamar; here it is decided what happens
    --  when they are touched. A menu is a tree, and a submenu is ENTERED: `path` is
    --  the way down so far, and the first row goes back. That way everything fits
    --  on the same page.
    local owner = nil                 -- whose menu is being shown
    local root, path = {}, {}

    local function show_menu(list)
        local rows = #path > 0 and { { back = true, label = tr("‹  Back") } } or {}
        for _, it in ipairs(list) do rows[#rows + 1] = it end
        model.options = rows
    end

    if not sys.watch("tray", function(list) model.icons = list end) then
        log("this system has no tray")
    end

    on("systray_activate", function(i)
        local it = model.icons[i + 1]
        if it then sys.call("tray.activate", it.key) end
    end)

    on("systray_menu", function(i)
        local it = model.icons[i + 1]
        if it == nil then return end
        model.options = {}
        text["systray.title"] = it.title ~= "" and it.title or it.id
        local ok, menu = pcall(sys.ask, "tray.menu", it.key)
        if not ok or menu == nil or #menu == 0 then
            --  There is no menu to read: let it show it itself, if it knows how,
            --  and no empty page is left here acting as a waiting room.
            pcall(sys.call, "tray.context", it.key)
            fact.page = "none"
            return
        end
        owner, root, path = it, menu, {}
        show_menu(menu)
    end)

    on("systray_pick", function(i)
        local r = model.options[i + 1]
        if r == nil or owner == nil then return end
        if r.back then
            table.remove(path)
            show_menu(#path > 0 and path[#path].children or root)
        elseif r.children and #r.children > 0 then
            path[#path + 1] = r
            show_menu(r.children)
        else
            sys.call("tray.menu_click", owner.key, r.id)
            fact.page = "none"
        end
    end)
end
