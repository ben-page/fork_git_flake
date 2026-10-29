# fork: run Fork, the git client, from its Windows build on Wine.
# fork.nix puts Wine and the other tools on PATH and prepends FORK_* variables holding the store
# paths of the files this script installs into the prefix.

: "${FORK_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/fork-wine}"
FORK_PREFIX="$FORK_HOME/prefix"
FORK_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/fork-wine"
FORK_FEED="https://fork.dev/update/win"
WIN_DIR="$FORK_PREFIX/drive_c/windows"
FORK_DIR="$FORK_PREFIX/drive_c/users/${USER:-$(id -un)}/AppData/Local/Fork"

export WINEPREFIX="$FORK_PREFIX"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"  # no .desktop files for Wine's tools

log() { printf '\033[1;34m[fork]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[fork]\033[0m %s\n' "$*" >&2; exit 1; }

# Import registry entries read from stdin, in .reg syntax without the header.
import_reg() {
  local file="$WIN_DIR/../fork-import.reg"
  { printf 'Windows Registry Editor Version 5.00\r\n\r\n'; sed 's/$/\r/'; } > "$file"
  wine regedit /S 'C:\fork-import.reg'
  rm -f "$file"
}

create_prefix() {
  [ -f "$FORK_PREFIX/system.reg" ] && return 0
  log "Creating the Wine prefix in $FORK_PREFIX"
  mkdir -p "$FORK_HOME"
  # Without mscoree and mshtml Wine doesn't offer to download Wine Mono and Gecko. Fork runs on
  # Microsoft's .NET Framework and needs neither.
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES;mscoree=;mshtml=" wineboot -i
  wineserver -w
}

is_wine_builtin() {
  [ "$(dd if="$1" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ]
}

# winetricks' dotnet48 first installs .NET 4.0 on Windows XP, and that MSI fails under current Wine
# (error 1603). Only two things are needed from it: the mscoree.dll shim (later .NET installers
# expect Windows to provide it) and the registry keys the shim reads to find the runtime.
install_dotnet() {
  if [ -f "$WIN_DIR/Microsoft.NET/Framework64/v4.0.30319/clr.dll" ] && ! is_wine_builtin "$WIN_DIR/system32/mscoree.dll"; then
    return 0
  fi
  log "Installing .NET Framework 4.8 (this takes a few minutes)"
  wine winecfg -v win7
  local rc=0
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES;fusion=b" wine "$FORK_DOTNET/ndp48-x86-x64-allos-enu.exe" /q /norestart || rc=$?
  wineserver -w
  case "$rc" in 0|3010) ;; *) die ".NET Framework 4.8 setup failed with exit code $rc" ;; esac
  [ -f "$WIN_DIR/Microsoft.NET/Framework64/v4.0.30319/clr.dll" ] || die ".NET Framework 4.8 setup did not install the runtime"

  install -m 644 "$FORK_DOTNET/x86_64/mscoree.dll" "$FORK_DOTNET/x86_64/mscorees.dll" "$WIN_DIR/system32/"
  install -m 644 "$FORK_DOTNET/i386/mscoree.dll" "$FORK_DOTNET/i386/mscorees.dll" "$WIN_DIR/syswow64/"
  import_reg <<'EOF'
[HKEY_LOCAL_MACHINE\Software\Microsoft\.NETFramework]
"InstallRoot"="C:\\windows\\Microsoft.NET\\Framework64\\"
"OnlyUseLatestCLR"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Microsoft\.NETFramework\Policy\v4.0]
"30319"="30319-30319"

[HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\.NETFramework]
"InstallRoot"="C:\\windows\\Microsoft.NET\\Framework\\"
"OnlyUseLatestCLR"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\.NETFramework\Policy\v4.0]
"30319"="30319-30319"

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
"mscoree"="native"
EOF
  wine winecfg -v win10
  wineserver -w
}

# Install the newest full package from Fork's Velopack update feed, laid out as its installer would.
# Fork updates itself from there on.
install_fork() {
  [ -f "$FORK_DIR/current/Fork.exe" ] && return 0
  local feed file sha
  feed="$(curl -fsSL "$FORK_FEED/releases.win.json?arch=x64&os=win&rid=win-x64")" || die "Cannot read Fork's release feed"
  read -r file sha < <(python3 -I -c '
import json, sys
assets = [a for a in json.load(sys.stdin)["Assets"] if a.get("Type") == "Full"]
newest = max(assets, key=lambda a: tuple(int(p) for p in a["Version"].split(".")))
print(newest["FileName"], newest["SHA256"].lower())' <<<"$feed")
  mkdir -p "$FORK_CACHE"
  if [ "$(sha256sum "$FORK_CACHE/$file" 2>/dev/null | cut -d' ' -f1)" != "$sha" ]; then
    log "Downloading $file"
    curl -fL --progress-bar -o "$FORK_CACHE/$file.part" "$FORK_FEED/$file" || die "Download failed: $FORK_FEED/$file"
    [ "$(sha256sum "$FORK_CACHE/$file.part" | cut -d' ' -f1)" = "$sha" ] || die "Checksum mismatch for $file"
    mv "$FORK_CACHE/$file.part" "$FORK_CACHE/$file"
  fi
  log "Installing $file"
  mkdir -p "$FORK_DIR/packages"
  python3 -I - "$FORK_CACHE/$file" "$FORK_DIR" <<'EOF'
import os, shutil, sys, zipfile
package, root = sys.argv[1:]
current = os.path.join(root, "current")
with zipfile.ZipFile(package) as nupkg:
    for entry in nupkg.infolist():
        if entry.is_dir() or not entry.filename.startswith("lib/app/"):
            continue
        target = os.path.join(current, *entry.filename[len("lib/app/"):].split("/"))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with nupkg.open(entry) as src, open(target, "wb") as dst:
            shutil.copyfileobj(src, dst)
shutil.copy(os.path.join(current, "Squirrel.exe"), os.path.join(root, "Update.exe"))
shutil.copy(os.path.join(current, "Fork_ExecutionStub.exe"), os.path.join(root, "Fork.exe"))
EOF
}

# Settings that follow the desktop, checked on every start: in a Wayland session, Wine's Wayland
# driver (FORK_WAYLAND=0 for X11/Xwayland).
apply_settings() {
  local driver=x11 wanted
  if [ "${FORK_WAYLAND:-1}" = 1 ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then driver="wayland,x11"; fi
  wanted="driver=$driver"
  [ "$(cat "$FORK_HOME/.settings" 2>/dev/null)" = "$wanted" ] && return 0
  log "Setting graphics driver $driver"
  import_reg <<EOF
[HKEY_CURRENT_USER\Software\Wine\Drivers]
"Graphics"="$driver"
EOF
  printf '%s' "$wanted" > "$FORK_HOME/.settings"
}

cmd_install() {
  create_prefix
  install_dotnet
  install_fork
  wineserver -w
  log "Done. Start Fork with: fork [repository...]"
}

cmd_run() {
  [ -f "$FORK_DIR/current/Fork.exe" ] || die "Fork is not installed; run: fork install"
  apply_settings
  local args=() arg
  for arg in "$@"; do
    if [ -e "$arg" ]; then args+=("$(winepath -w "$(realpath "$arg")")"); else args+=("$arg"); fi
  done
  exec wine "$FORK_DIR/current/Fork.exe" "${args[@]}"
}

usage() {
  cat <<EOF
Usage: fork [repository...]   start Fork, opening the given repositories
       fork install           create the Wine prefix and install .NET, fonts and Fork
       fork exec <cmd...>     run a command in the prefix (regedit, winecfg, cmd, ...)
       fork kill              stop everything running in the prefix

Environment: FORK_HOME (default ~/.local/share/fork-wine), FORK_WAYLAND=0, WINEDEBUG
EOF
}

case "${1:-}" in
  install) cmd_install ;;
  exec) shift; [ $# -gt 0 ] || die "Usage: fork exec <cmd...>"; exec wine "$@" ;;
  kill) wineserver -k ;;
  -h|--help|help) usage ;;
  *) cmd_run "$@" ;;
esac
