#!/usr/bin/env python3
"""Build the fonts Fork's interface gets under Wine: "Inter UI" for Segoe UI, "Hack UI" for Consolas.

    ui-fonts.py <Inter.ttc> <directory with Hack-*.ttf> <out-dir>

Inter UI is Inter's text faces (not Display), renamed. Wine reports the system UI font
(SPI_GETNONCLIENTMETRICS) by the full name of the first matching face. For Inter that is
"Inter Regular", and WPF reads "<family> <style>" as a single face, so all default-styled text in Fork
rendered Regular whatever weight it asked for. Segoe UI's regular face is named just "Segoe UI"; Inter
UI's is named "Inter UI" too. The regular face stays first in the collection, so it is the face Wine
finds first.

Hack UI is Hack renamed. Wine registers the host's fonts under their own names first, and ignores a
copy in the prefix that carries the same names.

Both are drawn at SCALE of their size, by a larger unitsPerEm for the same outlines, with the vertical
metrics scaled to match so the line height stays. At the same point size Inter is about 8% larger
than Segoe UI (x-height 0.546 em against 0.500, average a-z width 0.536 em against 0.493). Hack's
TrueType hinting (ttfautohint) is dropped with its signature: changing unitsPerEm would change what the
hints were made for, and WPF's DirectWrite rendering under Wine draws outlines unhinted anyway. Inter
carries no glyph hinting.

Inter is licensed under the SIL Open Font License 1.1, which reserves no font names. Hack is licensed
under the MIT license and, for its Bitstream Vera parts, the Bitstream Vera license, which reserves the
names "Bitstream" and "Vera".
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTCollection, TTFont
from fontTools.ttLib.tables import ttProgram

SCALE = 0.95


def rename(font, old, new, postscript_new):
    """Replace the family name in the name records that carry it."""
    for rec in font["name"].names:
        if rec.nameID in (1, 3, 4, 16, 21):
            rec.string = rec.toUnicode().replace(old, new, 1)
        elif rec.nameID == 6:
            rec.string = rec.toUnicode().replace(old, postscript_new, 1)


def scale(font):
    """Draw the glyphs at SCALE of their size, keeping the line height."""
    head, hhea, os2 = font["head"], font["hhea"], font["OS/2"]
    upem = round(head.unitsPerEm / SCALE)
    grow = upem / head.unitsPerEm
    head.unitsPerEm = upem
    for table, attr in ((hhea, "ascent"), (hhea, "descent"), (hhea, "lineGap"), (os2, "sTypoAscender"),
                        (os2, "sTypoDescender"), (os2, "sTypoLineGap"), (os2, "usWinAscent"), (os2, "usWinDescent")):
        setattr(table, attr, round(getattr(table, attr) * grow))


def unhint(font):
    for tag in ("fpgm", "prep", "cvt ", "TTFA", "DSIG"):
        if tag in font:
            del font[tag]
    glyf = font["glyf"]
    for name in font.getGlyphOrder():
        glyph = glyf[name]
        if hasattr(glyph, "program"):
            glyph.program = ttProgram.Program()
            glyph.program.fromBytecode(b"")
    font["maxp"].maxSizeOfInstructions = 0


inter, hack_dir, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)

faces = []
for font in TTCollection(inter).fonts:
    name = font["name"]
    if name.getDebugName(1).startswith("Inter Display"):
        continue
    rename(font, "Inter", "Inter UI", "InterUI")
    if name.getDebugName(1) == "Inter UI" and name.getDebugName(2) == "Regular":
        for rec in name.names:
            if rec.nameID == 4:
                rec.string = "Inter UI"
    scale(font)
    faces.append(font)
collection = TTCollection()
collection.fonts = faces
collection.save(out / "InterUI.ttc")
print(f"InterUI.ttc: {len(faces)} faces")

for path in sorted(hack_dir.glob("Hack-*.ttf")):
    font = TTFont(path)
    rename(font, "Hack", "Hack UI", "HackUI")
    unhint(font)
    scale(font)
    target = out / path.name.replace("Hack-", "HackUI-")
    font.save(target)
    print(f"{target.name}: {font['name'].getDebugName(4)!r}")
