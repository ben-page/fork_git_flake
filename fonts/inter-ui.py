#!/usr/bin/env python3
"""Build "Inter UI": Inter's text faces renamed so the regular face's full name is the family name.

    inter-ui.py <Inter.ttc> <out.ttc>

Wine reports the system UI font (SPI_GETNONCLIENTMETRICS) by the full name of the first matching
face. For Inter that is "Inter Regular", and WPF reads "<family> <style>" as a single face, so all
default-styled text in Fork rendered Regular whatever weight it asked for. Segoe UI's regular face is
named just "Segoe UI"; this copy does the same. The regular face stays first in the collection, so
it is the face Wine finds first. The Display faces are left out.

Inter is licensed under the SIL Open Font License 1.1, which reserves no font names.
"""
import sys

from fontTools.ttLib import TTCollection

FAMILY, POSTSCRIPT = "Inter UI", "InterUI"

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
    faces.append(font)

collection = TTCollection()
collection.fonts = faces
collection.save(out)
for font in faces:
    name = font["name"]
    print(f"{name.getDebugName(4)!r}: family {name.getDebugName(1)!r}, style {name.getDebugName(2)!r}")
