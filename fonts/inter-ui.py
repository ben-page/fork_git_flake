#!/usr/bin/env python3
"""Build "Inter UI": Inter's text faces renamed so the regular face's full name is the family name.

    inter-ui.py <Inter.ttc> <out.ttc>

Wine reports the system UI font (SPI_GETNONCLIENTMETRICS) by the full name of the first matching
face. For Inter that is "Inter Regular", and WPF reads "<family> <style>" as a single face, so all
default-styled text in Fork rendered Regular whatever weight it asked for. Segoe UI's regular face is
named just "Segoe UI"; this copy does the same. The regular face stays first in the collection, so
it is the face Wine finds first. The Display faces are left out.

At the same point size Inter draws about 8% larger than Segoe UI: its x-height is 0.546 em against
0.500, its average a-z width 0.536 em against 0.493. Fork's layout is made for Segoe UI, so the
glyphs are drawn at SCALE of their size (a larger unitsPerEm for the same outlines; Inter carries no
glyph hinting), with the vertical metrics scaled to match, which keeps the line height.

Inter is licensed under the SIL Open Font License 1.1, which reserves no font names.
"""
import sys

from fontTools.ttLib import TTCollection

FAMILY, POSTSCRIPT = "Inter UI", "InterUI"
SCALE = 0.92

src, out = sys.argv[1], sys.argv[2]
faces = []
for font in TTCollection(src).fonts:
    name = font["name"]
    if name.getDebugName(1).startswith("Inter Display"):
        continue
    for rec in name.names:
        if rec.nameID in (1, 3, 4, 16, 21):
            rec.string = rec.toUnicode().replace("Inter", FAMILY, 1)
        elif rec.nameID == 6:
            rec.string = rec.toUnicode().replace("Inter", POSTSCRIPT, 1)
    if name.getDebugName(1) == FAMILY and name.getDebugName(2) == "Regular":
        for rec in name.names:
            if rec.nameID == 4:
                rec.string = FAMILY

    head, hhea, os2 = font["head"], font["hhea"], font["OS/2"]
    upem = round(head.unitsPerEm / SCALE)
    grow = upem / head.unitsPerEm
    head.unitsPerEm = upem
    for table, attr in ((hhea, "ascent"), (hhea, "descent"), (hhea, "lineGap"), (os2, "sTypoAscender"),
                        (os2, "sTypoDescender"), (os2, "sTypoLineGap"), (os2, "usWinAscent"), (os2, "usWinDescent")):
        setattr(table, attr, round(getattr(table, attr) * grow))
    faces.append(font)

collection = TTCollection()
collection.fonts = faces
collection.save(out)
for font in faces:
    name = font["name"]
    print(f"{name.getDebugName(4)!r}: family {name.getDebugName(1)!r}, style {name.getDebugName(2)!r}")
