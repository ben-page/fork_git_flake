# The `fork` command: fork.sh with Wine, its tools and the files it installs into the prefix.
{ writeShellApplication, wine, curl, python3, dotnet, winrt, fonts }:

writeShellApplication {
  name = "fork";
  runtimeInputs = [ wine curl python3 ];
  text = ''
    FORK_DOTNET=${dotnet}
    FORK_WINRT=${winrt}
    FORK_FONTS=${fonts}
  '' + builtins.readFile ./fork.sh;
}
