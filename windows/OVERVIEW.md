# Native window overview

The Windows view uses Marea's charcoal panel, mint accents, rounded cards and
companion silhouette. It requests keyboard focus while open; Escape and the
close button hide it, and another overview shortcut toggles the same view.
Window selection still waits for native foreground acknowledgement before
closing. A refused activation keeps the view open with an error.

One hidden view is prepared three seconds after Marea initialization, if the
native manager is available. Hidden views have no keyboard request or active
hit regions. Native window captures and full-size swapchains are retired when
closed. The process remains warm for up to a minute, then exits. Opening after
that idle timeout still requires renderer startup. Each owner has a separate
command namespace and its child ends with Marea.

The view currently shows four windows per page on Marea's selected monitor.
It is not an in-preview application input surface or a virtual desktop manager.
An application using exclusive fullscreen, foreground locking or elevated
input may still prevent activation; we do not bypass Windows' restrictions.

`windows/test-overview-native.py` measures cold readiness and warm command
round trips, checks four native captures, retirement while hidden and reuse.
Those timings include command-client startup and are not compositor FPS.
Local mode requires an explicit secondary monitor and disables activation.
The installer CI separately exercises keyboard focus and a confined/hidden
cursor with owned Win32 windows. That fixture is not acceptance against a real
game or its anti-cheat software.

Validation on 2026-10-09: the native Windows workflow run
[37851177356](https://github.com/SamuelHinestrosa/marea-plm/actions/runs/37851177356)
passed cold and prewarmed activation, cursor visibility and confinement release,
Escape without a click, three reopenings in the same process and capture
retirement while hidden. The fixture first establishes a visible mouse on its
own window, then hides and confines it. Earlier runs could not establish that
baseline because the hosted desktop reported `CURSOR_SUPPRESSED`; moving the
synthetic mouse by one pixel during CI setup resolved that fixture limitation.
No synthetic mouse input is used by Marea or by local nonactivating tests.

On the local secondary display, three warm command round trips measured
244–281 ms. The shared CI host measured 1.11–1.30 s. These include process startup
for the command clients and polling, so they do not establish input-to-frame
latency or animation smoothness. Real-game acceptance remains pending. A view
on Marea's monitor does not move the pointer there from another monitor.
