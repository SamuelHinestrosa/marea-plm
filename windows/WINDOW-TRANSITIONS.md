# Window transitions: implementation and remaining work

The requested scope is the overview **and** ordinary application opening,
minimization and restoration. The native Windows port has not completed that
scope. A passing overview test does not establish global compositor parity.

## Linux reference

`pleamar-wm/examples/session.plm` is the reference, reviewed through upstream
`1bddbd5` (0.3.4). Its overview uses the `glide = 210, 23` spring. New windows
emerge as liquid from their monitor's nearest edge. Minimization melts a window
into a droplet heading to its monitor's shore/dock; restoration reverses that
path. The current upstream destination is **not** Marea's island. The content
is scaled without asking the application to resize throughout the transition.

## Implemented foundation

The Windows overview is a native capture-based panel, not the Linux compositor.
Its 220 ms critically damped entrance expands subtly from Marea's eyes; individual
thumbnails fade in over 160 ms once a real capture arrives. It no longer moves
late-arriving images from distant desktop coordinates across the panel. Native
DWM frame geometry and per-monitor DPI remain available for accurate capture
aspect and diagnostics; applications retain their own size and position.
The view always opens on the Windows primary monitor and gathers windows from
every monitor. Minimized windows retain a selectable catalogue entry. The
32-window limit and four-card pages remain explicit limitations.

Keyboard ownership ends when closing starts. Capture resources retire after the
closing animation. Marea keeps its owned renderer warm until Marea exits;
standalone invocations retain the 60-second idle timeout. Changing the active
application or its monitor no longer recreates the renderer. The retained
renderer still occupies memory; hidden captures are released.

Marea closes its panels before opening the selector and suppresses its own
surfaces, keyboard requests and delayed panel writes until it closes. Foreground
acknowledgement uses the exact window identity before its owner and is delivered
before catalogue refresh; another monitor is not an activation error. A real
Windows foreground denial still reports an unconfirmed activation for a mouse
selection. A keyboard release dismisses the switcher regardless of native
activation success; it does not claim that the target acquired foreground.
The regular dock retains its existing monitor scope.

Win+Tab is a held-key switcher: repeated Tab presses advance the highlighted
window without toggling the view, Shift+Tab reverses, releasing the final Win
key requests activation and immediately dismisses the view, and Escape cancels.
A cold catalogue can delay the activation request without keeping or reopening
the view. A later cancellation or new view invalidates that pending request. The selected page follows the highlight.
The adapter preserves ordered steps and an early release through monitor lookup
and cold renderer startup. The menu still opens a persistent overview. These
changes require the engine's optional `Win+Release` shortcut binding.

This requires matching engine and WM builds: the engine publishes optional
`win.$i.native.{x,y,width,height}` facts, and WM accepts
`--preview-monitor all --preview-project`. Do not update only Marea's scripts
over an older installed WM executable.

## Global transitions are not enabled

Windows still composes native application windows. The current WM observes
creation and minimization using out-of-process WinEvents; these notifications
are queued asynchronously, not a transaction that suspends the application's
presentation until a replacement image is ready.

An isolated native probe on 2026-10-09 found that `DWMWA_CLOAK` succeeds for a
window owned by its caller but returns `0x80070005` for another ordinary process
under the same user. Adding `WS_EX_LAYERED`, setting alpha to zero and restoring
the original style did succeed on our own hidden cross-process Win32 fixture.
That proves one API operation, not a working animation or general compatibility.
An additional visible secondary-display probe captured the owned window before
and during zero-alpha presentation: both read-only PNG captures retained the
fixture's opaque content, and its style and foreground were restored/preserved.
This establishes a possible capture path for that window, not a continuous
GPU animation or a guarantee about other applications.
Layered windows, applications using `UpdateLayeredWindow`, protected content,
elevated applications and exclusive-fullscreen games need separate handling.

The missing implementation must retain a usable frame before presentation
changes, avoid duplicate/default transitions, and restore each window after
cancellation, renderer failure, display changes and shutdown. It also needs
bounded capture costs and native visual acceptance for actual applications.
No global transparency changes or application hooks are enabled by this change.

References: [WinEvent delivery](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook),
[DWM attributes](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute),
[layered-window restrictions](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setlayeredwindowattributes).

## Validation on 2026-10-09

- Native MSVC release build, default Luau: passed.
- WM unit tests: 59 passed, 20 explicitly ignored native scenarios, no failures.
- Generated desktop/overview/dock parsing, Luau compilation and isolated service
  logic suite: passed.
- Native overview on DISPLAY2 (1920 × 1080, scale 1.25), four owned Win32 windows:
  passed; rectangle readback matched native geometry, intermediate spring state
  observed, three warm reopenings, captures retired when hidden, minimized window
  remained selectable. No input injection or foreground change.
- Warm IPC acknowledgement measurements were approximately 203–234 ms. These
  include CLI startup/query overhead and are not end-to-end presentation latency.
- Mixed-DPI/negative-origin coordinate conversion: unit-tested. Actual windows
  on multiple differently scaled monitors, physical shortcuts, arbitrary app
  activation and global opening/minimize/restore effects were not validated by
  that local test.
- A separate native cross-monitor probe projected one owned DISPLAY2 source
  onto a closed DISPLAY1 destination. Its negative destination-relative
  coordinates matched the native catalogue; no destination input, source
  capture or foreground change occurred. This is routing/geometry evidence,
  not a visible overview on the primary monitor.

An initial native test failed because it expected `win.count` to exclude a
minimized window. That count includes it; the corrected assertion checks its
native minimized state and its continued selectable position.
The first version of the renderer-side test counter also used a property where
the scene assignment required a fact; the test fixture was corrected and a
pre-launch parse check now reports such failures directly.

Run the native test only on an explicitly selected secondary monitor locally;
keyboard/foreground tests require the disposable hosted-CI mode:

```powershell
python windows/test-logic.py --binary ..\pleamar\target\release\pleamar.exe --luau-runner ..\pleamar\target\release\examples\luau-test.exe
python windows/test-overview-native.py --binary ..\pleamar\target\release\pleamar-wm.exe --monitor '\\.\DISPLAY2' --output .tools\overview-validation --prewarm
```

Latest upstream refs were fetched for review: pleamar `548b1e6`, Marea `75a26cf`,
WM `263249e`. Fetching them is not a claim that their new changes have all been
integrated. In particular the newer engine wake/process fixes and Marea task
changes still need reconciliation with the port branch.
