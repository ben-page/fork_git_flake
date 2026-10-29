# The `fork` command: fork.sh with Wine, its tools and the files it installs into the prefix.
{ lib, writeShellApplication, wine, curl, python3, git, dotnet, winrt, fonts, gitBridge }:

writeShellApplication {
  name = "fork";
  runtimeInputs = [ wine curl python3 ];
  text = ''
    FORK_DOTNET=${dotnet}
    FORK_WINRT=${winrt}
    FORK_FONTS=${fonts}
    FORK_GIT_EXE=${gitBridge.exe}
    FORK_GIT_SCRIPT=${lib.getExe gitBridge.script}
    FORK_NIX_GIT=${lib.getExe git}
  '' + builtins.readFile ./fork.sh;
}
