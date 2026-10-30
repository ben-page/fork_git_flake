# Fork on Linux

Run [Fork](https://fork.dev), the git client, on Linux. This flake runs Fork's Windows version on
Wine, together with the Wine fixes and setup it needs to work well.

Fork is commercial software, so you'll need a license from [fork.dev](https://fork.dev), the same as
on Windows or macOS. This project isn't affiliated with Fork's authors and contains no code from Fork
or Microsoft. The installer downloads Fork from Fork's own update feed and the .NET Framework and
Windows SDK files from Microsoft, and checks every download against a known hash.

## Getting started

You need [Nix](https://nixos.org/download/) with flakes turned on, on x86_64 Linux. Any distribution
works.

Install Fork, then start it:

```sh
nix run github:ben-page/fork_git_flake -- install
nix run github:ben-page/fork_git_flake
```

You can also open a repository straight away:

```sh
nix run github:ben-page/fork_git_flake -- ~/src/project
```

Once installed, Fork keeps itself up to date, just as it does on Windows. To stay on a release of
this flake, use `github:ben-page/fork_git_flake/v0.1.0`.

### The binary cache

Fork needs a patched Wine, which isn't in Nix's usual binary cache. CI builds it and uploads it to
`fork-git-flake.cachix.org`, so you don't have to compile Wine yourself. The first time you run the
flake, Nix asks whether to use that cache: answer `y` to both questions.

If Nix instead warns that it's ignoring an untrusted substituter, add these lines to
`/etc/nix/nix.conf` and restart the Nix daemon:

```
extra-substituters = https://fork-git-flake.cachix.org
extra-trusted-public-keys = fork-git-flake.cachix.org-1:eGXL0NI1ALtyerG+XH//PjtAK9zIwo38fPKCwmWkL5c=
```

Without the cache, Nix builds Wine from source on the first run, which takes a while.

## Commands

With `nix run`, put these after `--`, as above. If you install the flake with
`nix profile install github:ben-page/fork_git_flake`, the command is just `fork`.

| Command | What it does |
|---------|--------------|
| `fork [repository...]` | Start Fork, opening any repositories you name |
| `fork install` | Set up the Wine prefix and install .NET Framework 4.8, the fonts and Fork |
| `fork exec <command...>` | Run a command inside the prefix, such as `regedit`, `winecfg` or `cmd` |
| `fork kill` | Stop everything running in the prefix |

Everything lives in `~/.local/share/fork-wine`. To uninstall, delete that folder.

## Settings

These are environment variables; none of them are required.

| Variable | Default | What it does |
|----------|---------|--------------|
| `FORK_HOME` | `~/.local/share/fork-wine` | Where everything lives. The Wine prefix is in `prefix/` inside it |
| `FORK_DPI` | your desktop's scale | Wine's DPI. By default it's 96 × the scale of KDE's primary display or sway's focused display on Wayland, and `Xft.dpi` on X11 |
| `FORK_WAYLAND` | `1` | Use Wine's Wayland driver in a Wayland session. Set it to `0` to use X11 (Xwayland) instead |
| `FORK_GIT` | | Set it to `bundled` to use the Git for Windows that comes with Fork instead of your own git. Not recommended (see [Git](#git)) |
| `FORK_GIT_TRACE` | | A file to log every git command Fork runs |
| `WINEDEBUG` | `-all` | Wine's debug logging |

## Git

Fork runs its git commands with your own git: the `git` on your `PATH`, or nixpkgs' git if you don't
have one. Your `~/.gitconfig`, credential helpers, SSH keys and agent, and hooks all work the way
they do on the command line, and there's nothing to set up inside Fork. If git needs a password that
nothing else provides, Fork asks for it in its usual prompt.

This is what `git-bridge/` does. Inside Wine, Fork runs a small `git.exe` that converts the Windows
paths in each command to Linux paths and hands the command to your git. For the few git commands
that print absolute paths, it converts those back to Windows paths so Fork understands them.

Fork's bundled Git for Windows doesn't work well here. Wine has no execute bits, so it shows every
executable file as modified, and its `core.autocrlf=true` setting rewrites line endings.

## Known problems

* Fork's window is drawn in software rather than on the GPU (see below). That's fine for a git
  client.
* Resizing a large window lags behind the pointer: Fork takes up to about half a second to redraw
  at each new size.

## What this fixes

Fork doesn't run on stock Wine. Each problem below was tracked down in Wine's and .NET's logs and
fixed in its own commit.

* **Fork crashes at start-up.** Fork's theme code listens for Windows color changes. To do that,
  .NET Framework calls a WinRT function, `RoGetParameterizedTypeInstanceIID`, that Wine only stubs
  out, so Fork exits with `E_NOTIMPL`. `patches/wine/` implements it, with conformance tests.
* **.NET Framework 4.8 won't install.** winetricks' `dotnet48` fails in its .NET 4.0 step with MSI
  error 1603. Instead, the 4.8 installer runs directly, and the launcher adds the `mscoree.dll`
  loader from the 4.0 package and the registry keys it reads (`dotnet.nix`).
* **Fork can't load Windows' type information.** Wine generates WinRT metadata (`.winmd` files) for
  only a few types, under names .NET rejects. The launcher moves Wine's files aside and installs the
  Windows SDK's metadata where Wine looks for it (`winrt.nix`). It also installs
  `System.Runtime.WindowsRuntime`, which the .NET 4.8 installer leaves out on Windows 7, from the
  Windows 10 package inside the same installer.
* **The window is blurry on HiDPI displays.** Wine's DPI is set from your desktop's scale every
  time Fork starts.
* **On Wayland, the window stops updating after the first frame.** Wine's Wayland driver keeps
  showing a Direct3D surface's first frame, so WPF's hardware rendering is turned off.
* **The pointer gets stuck after you drag the window.** When the window asks the compositor to move
  or resize it, the compositor keeps the mouse button's release, so Fork thought the button was
  still held: it showed a "no" sign and ignored drags until the next click. `patches/wine/` sends
  Fork the release.
* **The window is hard to resize.** Fork draws its own frame, so you could only grab its edge a few
  pixels inside the window. `patches/wine/` adds an invisible border just outside the window's
  edges, like other windows have, where you can grab it.
* **The fonts are wrong.** Windows' Segoe UI and Consolas aren't there, so text fell back to Tahoma,
  and bold and semibold text came out regular. Fork now gets Inter in place of Segoe UI and Hack in
  place of Consolas, drawn at 92% of their size to come closer to the Windows fonts, and Segoe UI
  becomes the system UI font, as on Windows (`fonts/ui-fonts.py`). The fonts are renamed "Inter UI"
  and "Hack UI" for Wine. Wine reports the system font by its full name, "Inter Regular", which WPF
  reads as a single regular face. And Wine ignores a font in the prefix that shares its name with
  one installed on your system.
* **Some menu text is black.** In Fork's dark menus, submenu headers had black text because WPF had
  fallen back to its old Classic theme. The .NET 4.8 installer skips WPF's Aero2 theme on Windows
  7, and Wine names its Aero color scheme `Blue` where Windows says `NormalColor`, which WPF builds
  the theme's name from. The launcher installs Aero2, and `patches/wine/` renames the color scheme.
* **Git for Windows misreads Linux checkouts.** Fork's git commands run on your Linux git instead
  (see [Git](#git)).

## License

MIT, see `LICENSE`. The Wine patches in `patches/wine/` are licensed under the GNU LGPL 2.1 or later,
like Wine itself.
