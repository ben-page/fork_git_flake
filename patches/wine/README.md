# Wine patches

Patches applied on top of nixpkgs' Wine (`wineWow64Packages.unstable`). They are generated with
`git format-patch` from a Wine tree and written so they can go upstream unchanged.

Like Wine itself, these patches are licensed under the GNU Lesser General Public License, version 2.1
or later. The rest of this repository is MIT-licensed (see `LICENSE`).

| Patch | What it fixes |
|-------|---------------|
| `0001-combase-tests-Add-tests-for-RoGetParameterizedTypeIn.patch` | Conformance tests for `RoGetParameterizedTypeInstanceIID` (marked `todo_wine`) |
| `0002-combase-Implement-RoGetParameterizedTypeInstanceIID.patch` | Implements `RoGetParameterizedTypeInstanceIID`, a stub in Wine. .NET Framework calls it to marshal generic WinRT types; without it Fork dies at start-up with `E_NOTIMPL` when it subscribes to `UISettings.ColorValuesChanged` |
| `0003-uxtheme-tests-Check-the-color-and-size-names-GetCurr.patch` | Conformance test: with Aero, `GetCurrentThemeName()` reports the color scheme `NormalColor` (marked `todo_wine`) |
| `0004-aero.msstyles-Name-the-color-scheme-NormalColor-like.patch` | Names Wine's Aero color scheme `NormalColor`, as Windows does, instead of `Blue`. WPF builds its theme dictionary's name from it (`themes/aero2.normalcolor`) and otherwise falls back to its Classic theme |
