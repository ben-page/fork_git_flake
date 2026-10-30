# Wine patches

Patches applied on top of nixpkgs' Wine (`wineWow64Packages.unstable`). They are generated with
`git format-patch` from a Wine tree.

Like Wine itself, these patches are licensed under the GNU Lesser General Public License, version 2.1
or later. The rest of this repository is MIT-licensed (see `LICENSE`).

| Patch | What it fixes |
|-------|---------------|
| `0001-combase-tests-Add-tests-for-RoGetParameterizedTypeIn.patch` | Conformance tests for `RoGetParameterizedTypeInstanceIID` (marked `todo_wine`) |
| `0002-combase-Implement-RoGetParameterizedTypeInstanceIID.patch` | Implements `RoGetParameterizedTypeInstanceIID`, a stub in Wine. .NET Framework calls it to marshal generic WinRT types; without it Fork dies at start-up with `E_NOTIMPL` when it subscribes to `UISettings.ColorValuesChanged` |
| `0003-uxtheme-tests-Check-the-color-and-size-names-GetCurr.patch` | Conformance test: with Aero, `GetCurrentThemeName()` reports the color scheme `NormalColor` (marked `todo_wine`) |
| `0004-aero.msstyles-Name-the-color-scheme-NormalColor-like.patch` | Names Wine's Aero color scheme `NormalColor`, as Windows does, instead of `Blue`. WPF builds its theme dictionary's name from it (`themes/aero2.normalcolor`) and otherwise falls back to its Classic theme |
| `0005-winewayland-Release-the-mouse-button-after-starting-.patch` | Sends a window the mouse button release once the compositor has taken over a move or resize, since the compositor keeps the real one. Without it, Fork showed the no-drop cursor after a title-bar drag and ignored drags until the next click |
| `0006-winewayland-Let-resizable-windows-be-resized-from-ju.patch` | Gives resizable windows an invisible border 8 units wide just outside their edges, where the pointer shows resize cursors and a press starts a compositor resize, as with other Wayland windows. Fork draws its own frame, so before this it could only be resized from a few pixels inside its edge. Whether the pointer is on the border is decided from its position, because KWin keeps reporting the pointer on whichever surface it was on after a move or resize |
