# Fonts installed into the prefix: "Inter UI" in place of Segoe UI and "Hack UI" in place of
# Consolas, Inter and Hack renamed and sized for Wine (see fonts/ui-fonts.py).
{ runCommand, python3, inter, hack-font }:

runCommand "fork-fonts" { nativeBuildInputs = [ (python3.withPackages (p: [ p.fonttools ])) ]; } ''
  python3 ${./fonts/ui-fonts.py} ${inter}/share/fonts/truetype/Inter.ttc ${hack-font}/share/fonts/truetype $out > /dev/null
''
