-- Hidden native surfaces sleep their scene rules. Reject delayed Luau writes
-- before they reach the renderer, and clear queued panels before releasing it.
return function(native)
    local panels={open=true,menu_open=true,searching=true,chatting=true,tray_open=true,reel_open=true,note=true}
    return setmetatable({}, {
        __index=function(_,key) return native[key] end,
        __newindex=function(_,key,value)
            if key == "windows_overview_active" then
                for panel in pairs(panels) do native[panel]=false end
            elseif panels[key] and value and native.windows_overview_active then
                value=false
            end
            native[key]=value
        end,
    })
end
