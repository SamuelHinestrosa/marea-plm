# Windows preview installer

`Marea-VERSION-windows-x64-setup.exe` is an offline, per-user package. It
contains pleamar with default Luau, the real Deriva worker, Node.js for the
Agents page, app-local Microsoft C++ runtime DLLs and the DXC shader compiler.
End users do not need Rust, Python, a separate Node installation or the source
repository. Windows 10 build 17763 or newer, an x64 CPU and a DX12 driver are
required; Windows N requires the Media Feature Pack.

Run the setup, choose the directory and install. The default destination is
`%LOCALAPPDATA%\Programs\Marea`. Launch **Marea Windows → Marea** from Start.
Launching after installation is optional and unchecked. There is no automatic
startup or change to global PATH or execution policy. The bundled PowerShell
launch uses a process-scoped policy; organization-enforced restrictions still
apply. This preview is unsigned: there is no publisher signing certificate.
The adjacent SHA-256 file detects download changes; it is not a signature.

Run a newer setup to update the same installation. It verifies all payload
hashes, executes Luau without a display, checks the generated scene, and runs
the real worker before replacing files. It closes only Marea processes from
that installation; a locked file prevents the update. Unrelated folders and
older source-script installations are not overwritten or migrated. Close the
older Marea before starting this one; only one desktop instance can run.

Uninstall from Windows Installed apps or Start. Packaged files and shortcuts
are removed. Deriva in `%LOCALAPPDATA%\proyecto-marea\deriva`, pleamar settings,
screenshots and user-created files/logs are preserved. Setup never recursively
deletes the installation directory. No private libraries, preferences, access
tokens or test data are included in the distribution.

## Rebuild

Use the repository's native default-Luau release build and Deriva release build.
Prepare app-local DXC with pleamar's `scripts/prepare-windows-runtime.ps1`.
Run `windows/prepare-installer-tools.ps1` to obtain checksum-pinned official
Inno Setup 6.7.3 and Node.js 22.23.3 in `.tools/installer-tools`.
The C++ DLLs must come from the installed Visual Studio 2022 redistributable
directory, subject to its license and Distributable Code list.

```powershell
.\windows\prepare-installer-tools.ps1
python windows/build-installer.py --pleamar-binary ../pleamar/target/release/pleamar.exe --worker deriva/target/release/deriva-worker.exe --node-directory .tools/installer-tools/node-v22.23.3-win-x64 --crt-directory "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT" --iscc .tools/installer-tools/inno-6.7.3/ISCC.exe --version 0.2.8-preview.1 --engine-source ENGINE_COMMIT --output dist/windows
python windows/test-installer.py --setup dist/windows/Marea-0.2.8-preview.1-windows-x64-setup.exe --payload dist/windows/payload --output .tools/installer-smoke
```

The smoke test uses a fresh Unicode directory and its own Start-menu group,
installs silently, verifies the actual native package, updates, rejects a
locked file, uninstalls and checks data preservation. It does not launch Marea
or validate the wizard visually. A clean Windows VM without development tools,
interactive wizard/accessibility and current desktop/performance checks remain
required before declaring a production release. See the packaged `README.md`
(`windows/DESKTOP.md` in the source repository) for functional
and hardware limitations. Developed with Codex.
