export function desktopPolicy(platform = process.platform) {
    return platform === "win32"
        ? "Windows desktop tools use the user's shared keyboard and pointer, not a separate input seat. Never promise background input or that the user can keep typing or gaming while you act. List windows and use their opaque catalog ids (not OS process ids). Request desktop_focus before input if the target is not foreground; Windows may deny focus or input to protected/elevated windows. Capture is of one window, not the whole screen. A new dialog may require listing again. After every input, look again; stale images, resized windows and covered points are rejected. The action result confirms input acceptance, not completion of the application's task: verify the result. Do not claim a separate cursor, monitor glow or stop pill exists on Windows."
        : "You have a pointer and keyboard of your own, apart from the user's; they see your mint cursor and the glow on the monitor you work on. The compositor supplies window identities, dialog routing and the stop control.";
}

export function describeDesktopTool(tool, platform = process.platform) {
    if (platform !== "win32") return tool.description;
    const descriptions = {
        desktop_windows: "Lists native windows and monitors. The pid field takes the opaque catalog id shown in this list, not an OS process id. Reports physical boxes, monitor names, foreground focus, minimized state and dialog ownership.",
        desktop_look: "Captures one native window in physical pixels. Its picture is the coordinate system for input. Capture a fresh picture after every action. A modal dialog routes only when it is present in the current window catalog; list again if a new dialog appears.",
        desktop_click: "Clicks using the user's shared pointer. Requires this window in the foreground and a fresh picture; covered or out-of-bounds points are rejected.",
        desktop_type: "Types Unicode text using the user's shared foreground keyboard. Click the field, then look again before typing. Do not act while the user is typing or gaming.",
        desktop_focus: "Restores and requests foreground focus for a window. This changes the user's active application. Windows may refuse focus; a failure is not success.",
    };
    return descriptions[tool.name] ?? tool.description;
}
