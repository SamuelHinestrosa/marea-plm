# Native AI agent: integration status

This work ports upstream Marea's new Pi-based chat to Windows. It is not yet
included in the installed preview.13 bundle. The full feature must not be
advertised as complete until account, positive input, UI and installer tests
below pass.

The [native host](agent-host/README.md) runs the pinned Node/SDK worker inside
an AppContainer with restricted files, processes, environment and handles.
Marea's ordinary Luau process retains the approval cards and native desktop
services. The model only proposes tool calls; it never receives a raw HWND,
Win32 handle or direct desktop access through its sandbox.

`desktop-agent.luau` implements the bridge to pleamar's `desktop.*` service.
Window/monitor queries return a catalog and cancellation epoch. Pictures are
base64 PNG data through the existing bounded pipe, avoiding extra filesystem
grants. Stop invalidates queued native actions immediately; late replies cannot
enter a cancelled/new conversation. Shared application launching now waits for
the actual native callback and reports errors instead of assuming success.

New conversations wait for the previous worker to exit before accepting a
message; text typed during shutdown stays in the input field. A failed worker's
unsent messages are discarded before another conversation starts. On Windows,
the SDK retires after 30 idle seconds when both chat and its account settings
are hidden; reopening either restores the three-minute allowance. Active turns,
approval requests and sign-in have no idle deadline. Linux keeps three minutes.
Idle retirement and model changes use the same two-second shutdown deadline. A helper that
does not exit is killed, and stale output/exit callbacks cannot affect its
replacement. These lifecycle cases are covered by the isolated chat test.

| Area | Current evidence / limitation |
| --- | --- |
| Native host + SDK startup | Real Windows isolation and signed-out startup/shutdown verified; no model conversation yet |
| Account login | Device-code path implemented and offline cancellation tested; real account validation pending |
| Window catalog and capture | Actual owned windows on DISPLAY2; resize, modal dialog and closed/reopened identities verified |
| Marea-to-native bridge | Actual Luau scene on DISPLAY2 delivered a PNG; cancellation and clean exit verified |
| Click/type/key/hotkey/scroll/drag | Native implementation exists; positive input and application acceptance tests pending |
| Foreground / independent input | Windows uses shared input. No separate compositor keyboard, pointer, glow or stop pill is claimed |
| Full Marea chat UI / performance | Complete visual flow, real conversation, memory and responsiveness measurements pending |
| Installer | Full Setup lifecycle passed in Windows CI at `57b6ef0`: Unicode install, SDK isolation/state preservation, locked-update failure, tamper rejection/repair, uninstall and optional startup. This is automated acceptance, not graphical validation |

The worker prompt and tool descriptions distinguish Windows's shared input
from Linux's compositor input. Windows may deny activation or input to protected
applications. Acceptance of an OS input request does not mean the application
completed the task; the agent must look again and verify the result.

Run portable checks from the repository root:

```powershell
Push-Location agent
npm ci --ignore-scripts --no-audit --no-fund
Pop-Location
node --test agent/state-image.test.mjs agent/auth-interaction.test.mjs agent/desktop-policy.test.mjs
python windows/test-logic.py --binary ..\pleamar\target\release\pleamar.exe --luau-runner ..\pleamar\target\release\examples\luau-test.exe
```

Six Node tests and twenty isolated Luau suites passed on 2026-10-05. These
checks do not authenticate, contact a model or automate the desktop.

The native packaging check also starts the full SDK, preserves an existing
owned state marker, keeps production and validation profile caches separate,
and removes each profile without deleting chat state. Reproduce on an **owned,
uninstalled** bundle with `windows/test-agent-package.ps1 -Package <bundle>`.
The SDK inventory contains 13,104 files including its runtimes and licenses.
An initial cold permission preparation took about 116 seconds locally; a
repeat preparation took 4.6 seconds, and signed-out readiness/shutdown completed
in 6.8 seconds. Setup prepares permissions before first use; these observations
are not a sustained memory/latency benchmark or authenticated chat test.

`python windows/measure-agent.py --package <owned-complete-bundle> --output
<new-directory> --seconds 15 --cycles 3` measures the actual signed-out SDK in
separate account state without opening a window. Three local cycles on
2026-10-05 ended at 84.7–85.3 MiB working set, 92.9–93.6 MiB private memory and
114 handles. Warm readiness took 2.3–2.4 seconds; idle CPU used about 1.0–1.2%
of one logical core over each 15-second sample. Every Node process exited with
its host and the validation profile was removed. These short observations do
not measure Marea's UI, authenticated responses or long sessions.

For the real bridge, build pleamar's release executable and lib-test executable
(`cargo test --release --locked --lib --no-run` prints its path), then pass both:

```powershell
python windows/test-desktop-runtime.py --binary <pleamar.exe> --fixture-test-binary <pleamar-lib-test.exe>
```

This test refuses to proceed without active **non-primary DISPLAY2**. It opens
only owned fixture/test windows there and sends no physical input. The returned
evidence directory includes the native scene log, facts and exit status. It
tests the actual adapter source rather than a duplicate implementation.

Linux retains upstream's compositor tools and sandbox. Windows/Ubuntu logic
and the Windows installer lifecycle passed in CI at Marea `57b6ef0` with
pleamar `cd3e4c3`. The newer idle/queue corrections pass the local isolated
suite; CI must be repeated at their new commit. Implemented with Codex.
