# Fonts installed into the prefix: "Inter UI" (Inter renamed for Wine, see fonts/inter-ui.py) in
# place of Segoe UI, and Hack in place of Consolas.
{ runCommand, python3, inter, hack-font }:

runCommand "fork-fonts" { nativeBuildInputs = [ (python3.withPackages (p: [ p.fonttools ])) ]; } ''
  mkdir -p $out
  python3 ${./fonts/inter-ui.py} ${inter}/share/fonts/truetype/Inter.ttc $out/InterUI.ttc > /dev/null
  install -m 644 ${hack-font}/share/fonts/truetype/Hack-*.ttf $out/
''
