# Marea on Windows

Start with the [Windows desktop guide](DESKTOP.md) for requirements, native
pleamar builds, installation, updates, controls and the capability matrix.
The port is under development; the guide distinguishes implemented features
from limited integrations and hardware checks that remain unverified.

The new upstream chat is being integrated separately; see its
[Windows agent status and validation](AGENT.md). Packaging now includes its
native host and locked SDK; full account and desktop interaction validation
remains pending.

The upstream chat/memory changes through `90e4f4b` are integrated: reading-paced
answers, the corrected input position, and Settings > What she remembers.
Memory uses the native files service under `%APPDATA%/pleamar/marea-desktop`.
The Windows settings grid now scrolls so the ninth tile (startup) remains
reachable. Shared memory logic and a real isolated storage roundtrip passed;
the Spanish memory/settings/chat layouts were captured from owned D3D12 windows
on DISPLAY2. These checks use fixture data and do not establish signed-in model
or physical mouse/keyboard acceptance. Storage-error handling and larger memory
libraries still need review before claiming full memory-feature acceptance.

From the repository root, after preparing the native x64/MSVC pleamar build
with default Luau and its app-local runtime files:

```powershell
cargo build --release --locked --manifest-path deriva/Cargo.toml
# Prepare the native AI host, Node and SDK as shown in windows/DESKTOP.md.
.\install-windows.ps1 -PleamarBinary ..\pleamar\target\release\pleamar.exe
```

`install-windows.ps1` delegates to `install-desktop.ps1`; both install the same
desktop profile and preserve existing destinations. Use `update-desktop.ps1`
to update an existing desktop installation with a backup. The previous limited
window preview is no longer a source installation option. Existing preview
installations and their separate settings are not removed or migrated.

`build-desktop.py` generates `marea-desktop.plm` and `marea-desktop.luau` from the
upstream scenes and the adapters here. Those generated files are not tracked;
the installer and logic checks regenerate them. Linux uses the original files.

An experimental native `pleamar-wm` session can now supply automatic per-monitor
layouts. When its Windows executable is available beside pleamar and its
session is running, Marea's context menu and finder expose the supported
layout/restore actions. Capability detection never enables Linux-only rain,
snow, ride or agent-seat actions. The adapter has passed isolated logic tests
and a real Luau/IPC test arranging owned windows on DISPLAY2. The package now bundles the CLI and a small background host, with recovery
tied to the exact Marea process. Full Marea UI acceptance and compositor-effect
parity remain pending. Updating these sources does not update an existing
installed preview.

AI assistance: the Windows port and its validation tools were developed with
Codex. This branch is not an upstream Marea Windows release.
