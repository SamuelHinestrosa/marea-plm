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
