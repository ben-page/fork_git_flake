# Fork on Linux

A Nix flake that runs [Fork](https://fork.dev), the git client, on Linux: Fork's Windows build on
Wine, with the Wine fixes and prefix setup it needs.

This repository contains no code from Fork or Microsoft. `fork install` downloads Fork from its
official update feed and the .NET Framework and Windows SDK files from Microsoft, and checks each
download's hash. Fork is commercial software; buy a license from [fork.dev](https://fork.dev) as you
would on Windows or macOS. This project is not affiliated with Fork's authors.

## Usage

```sh
nix run github:ben-page/fork_git_flake -- install          # create the Wine prefix, install .NET, fonts and Fork
nix run github:ben-page/fork_git_flake                     # start Fork
nix run github:ben-page/fork_git_flake -- ~/src/project    # start Fork with a repository open
```

The first run builds Wine from source with the patches in `patches/wine/`, which takes a while.
After installing, Fork updates itself as it does on Windows.

| Command | |
|---------|---|
| `fork [repository...]` | start Fork, opening the given repositories |
| `fork install` | create the prefix and install .NET Framework 4.8, fonts and Fork |
| `fork exec <cmd...>` | run a command in the prefix (`regedit`, `winecfg`, `cmd`, ...) |
| `fork kill` | stop everything running in the prefix |

| Variable | Default | |
|----------|---------|---|
| `FORK_HOME` | `~/.local/share/fork-wine` | the Wine prefix lives in `prefix/` |
| `FORK_DPI` | from the desktop | Wine's dpi. Unset: 96 × the scale of KDE's primary output or sway's focused output on Wayland, `Xft.dpi` on X11 |
| `FORK_WAYLAND` | `1` | Wine's Wayland driver in a Wayland session; `0` for X11/Xwayland |
| `WINEDEBUG` | `-all` | Wine debug channels |

## Known problems

* **Use Fork on test repositories only for now.** Fork drives the Git for Windows it bundles, which
  misreads repositories on Linux: Wine has no execute bits, so executable files show as modified
  (mode 100755 to 100644), and its `core.autocrlf=true` rewrites line endings on checkout. Handing
  Fork's git commands to Linux git is the next piece of work.
* WPF renders in software (see below); fine for a git client.
* Not tested yet: fetch and push with credentials, interactive rebase, license activation,
  notifications, multiple monitors.

## What the launcher fixes

Each fix was found by reading Wine's and .NET's logs and is a separate commit.

| Problem | Fix |
|---------|-----|
| Fork exits at start with `E_NOTIMPL` while subscribing to `UISettings.ColorValuesChanged` | Wine's `combase` stubbed `RoGetParameterizedTypeInstanceIID`, which .NET Framework calls for every generic WinRT type. `patches/wine/` implements it, with conformance tests |
| winetricks' `dotnet48` fails: its .NET 4.0 step dies with MSI error 1603 | Run the 4.8 offline installer directly, then install the `mscoree.dll` shim from the 4.0 package and the registry keys it reads (`dotnet.nix`) |
| `TypeLoadException` in Fork's theme code: no WinRT metadata | Wine generates `.winmd` files for a few types only, under assembly names .NET rejects. Move them aside and install the Windows SDK's API contract metadata where Wine's `RoResolveNamespace` looks (`winrt.nix`) |
| `FileNotFoundException`: `System.Runtime.WindowsRuntime` | The .NET 4.8 installer leaves it out on Windows 7. Install it from the Windows 10 package inside the same installer |
| Blurry, scaled-up window on HiDPI outputs | Set Wine's dpi from the desktop's scale on every start |
| On Wayland the window stops updating after the first frame | Wine's Wayland driver keeps showing a Direct3D surface's first frame. Turn off WPF's hardware rendering |
| Segoe UI and Consolas missing; text falls back to Tahoma, bold and semibold render regular | Map Segoe UI to "Inter UI" and Consolas to Hack, and make Segoe UI the system UI font as on Windows. "Inter UI" is Inter with its regular face renamed: Wine reports the system font by its full name, "Inter Regular", which WPF reads as a single face (`fonts/inter-ui.py`) |

## License

MIT, see `LICENSE`. The Wine patches in `patches/wine/` are licensed under the GNU LGPL 2.1 or later,
like Wine.
