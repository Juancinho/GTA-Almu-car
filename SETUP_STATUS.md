# Setup status — 2026-09-29

Environment inspected on Windows 11 Professional (build 26200), PowerShell 7.6.6. This is a detection snapshot, not a claim that the game builds. The repository was empty before M0 setup.

| Dependency | Required | Detected | Status | Action |
|------------|----------|----------|--------|--------|
| OS | Windows PC | Windows 11 Pro x64 | DONE | None. |
| Git | Git | 2.45.2, `C:\Program Files\Git\cmd\git.exe` | DONE | Local repository initialized. |
| Git LFS | Git LFS | 3.5.1 | DONE | Local hooks initialized; patterns in `.gitattributes`. |
| Codex | Available for tooling | CLI 0.155.1; desktop 26.924.2738.0 | DONE | `codex doctor` ran. Its terminal/MCP warnings do not block game development. |
| Blender | 5.2 LTS x64 | 5.2.2 LTS at `.tools\blender\blender.exe` | DONE | Project-local executable verified. |
| Godot | 4.7.x stable, standard x64 | 4.7.2 stable at `.tools\godot\godot.exe` | DONE | Project-local executable verified. |
| Python | Python 3.11+ | `python` 3.11.9 at `C:\msys64\mingw64\bin\python.exe`; `py` 3.13.7 | DONE | Prefer `py -3.13` for Windows scripts. |
| uv | Available | 0.10.9 | DONE | None. |
| GPU | Vulkan capable GPU preferred | NVIDIA GeForce GTX 1650 and AMD Radeon Graphics | DETECTED | Renderer/performance still need in-engine validation. |
| Disk | Space for tools/assets | D: 140.3 GiB free | DONE | None. |

## Exact installation steps

The project-local portable installations are now present. To recreate them on another machine, no administrator rights, global PATH edit, or system configuration change is required. Download only from the official sources:

1. Download [Godot 4.7.2 stable, standard Windows x86_64](https://godotengine.org/download/windows/). Choose **Godot Engine 4.7.2**, not the .NET edition or a 4.8 preview. Extract the ZIP to `D:\Proyectos\GTA Almuñecar\.tools\godot\`. Rename its main executable to `godot.exe` in that directory. Confirm `D:\Proyectos\GTA Almuñecar\.tools\godot\godot.exe --version` prints `4.7.2.stable`.
2. Download [Blender 5.2.2 LTS Windows x64 portable ZIP](https://download.blender.org/release/Blender5.2/blender-5.2.2-windows-x64.zip). Extract it to `D:\Proyectos\GTA Almuñecar\.tools\blender\` so that `D:\Proyectos\GTA Almuñecar\.tools\blender\blender.exe` exists. If the archive creates an extra `blender-5.2.2-windows-x64` directory, move its contents into `.tools\blender\`. Confirm `D:\Proyectos\GTA Almuñecar\.tools\blender\blender.exe --background --version` begins with `Blender 5.2.2`.
3. From this repository run `pwsh -File .\tools\bootstrap.ps1`. It accepts project-local executables and can also find compatible executables on PATH. All required rows should report `OK`.

The project ignores `.tools/`, so the binaries stay local and are not committed. The Godot standard build is correct because this project uses GDScript. Blender 5.2.2 is a 5.2 LTS patch release, and Godot 4.7.2 is a 4.7 stable patch release. [Godot Windows downloads](https://godotengine.org/download/windows/) and [Blender 5.2 release files](https://download.blender.org/release/Blender5.2/) were checked on 2026-09-29.

## Diagnostics and gate

`codex doctor` reported healthy core runtime, auth, disk and networking. It flagged `TERM=dumb`, an optional missing MCP environment variable and unverified Defender exclusions. These are not blockers for this repository. `pwsh -File .\tools\bootstrap.ps1` and `pwsh -File .\tools\validate.ps1` now pass. Interactive handling and 1080p/60 FPS remain unverified.
