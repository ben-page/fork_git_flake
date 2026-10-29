# Fork's git bridge (see git-bridge/): git.exe for the Wine prefix, and the fork-git script it runs.
{ pkgsCross, writeShellApplication }:

let
  mingw = pkgsCross.mingwW64;
in
{
  # Linked statically, so it needs nothing but kernel32 and msvcrt from Wine.
  exe = mingw.stdenv.mkDerivation {
    name = "fork-git-bridge-exe";
    src = ./git-bridge/git.c;
    dontUnpack = true;
    buildInputs = [ mingw.windows.mcfgthreads ];
    buildPhase = ''
      $CC -O2 -Wall -Werror -municode -static -o git.exe $src
    '';
    installPhase = ''
      install -D -m 644 git.exe $out/git.exe
    '';
  };

  # No runtimeInputs: git, its credential helpers, hooks and ssh see the user's PATH unchanged.
  script = writeShellApplication {
    name = "fork-git";
    text = builtins.readFile ./git-bridge/fork-git.sh;
  };
}
