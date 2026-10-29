# The `fork` command: fork.sh with Wine, its tools and the files it installs into the prefix.
{ writeShellApplication, wine, curl, python3 }:

writeShellApplication {
  name = "fork";
  runtimeInputs = [ wine curl python3 ];
  text = builtins.readFile ./fork.sh;
}
