# Window transitions: implementation and remaining work

The requested scope is the overview **and** ordinary application opening,
minimization and restoration. The native Windows port has not completed that
scope. A passing overview test does not establish global compositor parity.

## Linux reference

`pleamar-wm/examples/session.plm` is the reference, reviewed through upstream
`263249e` (0.3.2). Its overview uses the `glide = 210, 23` spring. New windows
emerge as liquid from their monitor's nearest edge. Minimization melts a window
into a droplet heading to its monitor's shore/dock; restoration reverses that
path. The current upstream destination is **not** Marea's island. The content
is scaled without asking the application to resize throughout the transition.

## Implemented foundation

The Windows overview uses the same glide spring to move captured images from
their desktop rectangles into the view and back. Native rectangles are expressed
in the destination output's logical coordinates, including its origin and DPI;
source capture retains the source monitor's DPI. It does not resize applications.
The view opens on the active application's monitor and gathers windows from
every monitor. Minimized windows retain a selectable catalogue entry. The
32-window limit and four-card pages remain explicit limitations.

Keyboard ownership ends when closing starts. Capture resources retire after the
closing animation; the warm process retires after its existing idle timeout.
The regular dock retains its existing monitor scope.

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
- Warm IPC acknowledgement measurements were approximately 215–234 ms. These
  include CLI startup/query overhead and are not end-to-end presentation latency.
- Mixed-DPI/negative-origin coordinate conversion: unit-tested. Actual windows
  on multiple differently scaled monitors, physical shortcuts, arbitrary app
  activation and global opening/minimize/restore effects were not validated by
  that local test.

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
