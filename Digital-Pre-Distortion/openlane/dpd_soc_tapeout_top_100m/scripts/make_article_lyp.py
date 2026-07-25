#!/usr/bin/env python3
import re
import sys
import xml.etree.ElementTree as ET

src, dst = sys.argv[1], sys.argv[2]
tree = ET.parse(src)
root = tree.getroot()

styles = {
    "prBoundary.boundary": ("#f6f6f6", "#080b10", "I0", True, True),
    "diff.drawing": ("#2cff6f", "#2cff6f", "C21", True, True),
    "tap.drawing": ("#28b463", "#28b463", "C21", True, True),
    "poly.drawing": ("#ff3333", "#ff3333", "C4", True, True),
    "licon1.drawing": ("#ffffff", "#ffffff", "C1", True, False),
    "li1.drawing": ("#f7d84a", "#f7d84a", "C7", True, True),
    "mcon.drawing": ("#ffffff", "#ffffff", "C1", True, False),
    "via.drawing": ("#ffffff", "#ffffff", "C1", True, False),
    "via2.drawing": ("#ffffff", "#ffffff", "C1", True, False),
    "via3.drawing": ("#ffffff", "#ffffff", "C1", True, False),
    "via4.drawing": ("#ffffff", "#ffffff", "C1", True, False),
    "met1.drawing": ("#3478ff", "#3478ff", "C7", True, True),
    "met2.drawing": ("#b45cff", "#b45cff", "C7", True, True),
    "met3.drawing": ("#19d4ff", "#19d4ff", "C7", True, True),
    "met4.drawing": ("#ff9d26", "#ff9d26", "I3", True, True),
    "met5.drawing": ("#ffe45c", "#ffe45c", "I5", True, True),
}

hide_patterns = [
    r"\.fill\b",
    r"\.label\b",
    r"\.pin\b",
    r"\.net\b",
    r"\.blockage\b",
    r"\.res\b",
    r"\.cut\b",
    r"\.short\b",
    r"\.probe\b",
    r"\.option",
    r"\.psa",
    r"well",
    r"implant",
    r"npc",
    r"areaid",
]

def set_text(prop, tag, text):
    elem = prop.find(tag)
    if elem is not None:
        elem.text = text

for prop in root.findall("properties"):
    name_elem = prop.find("name")
    name = name_elem.text if name_elem is not None and name_elem.text else ""
    base = name.split(" - ", 1)[0]

    visible = False
    style = None
    if base in styles:
        style = styles[base]
        visible = style[3]
    elif re.match(r"^met[1-5]\.drawing$", base):
        style = styles[base]
        visible = True
    elif re.match(r"^via[234]?\.drawing$|^mcon\.drawing$|^licon1\.drawing$", base):
        style = ("#ffffff", "#ffffff", "C1", True, False)
        visible = True
    elif base == "prBoundary.boundary":
        style = styles[base]
        visible = True
    elif any(re.search(p, base) for p in hide_patterns):
        visible = False

    set_text(prop, "visible", "true" if visible else "false")
    set_text(prop, "valid", "true")

    if style is not None:
        frame, fill, pattern, _, transparent = style
        set_text(prop, "frame-color", frame)
        set_text(prop, "fill-color", fill)
        set_text(prop, "dither-pattern", pattern)
        set_text(prop, "transparent", "true" if transparent else "false")
        set_text(prop, "width", "2" if base == "prBoundary.boundary" else "1")

tree.write(dst, encoding="utf-8", xml_declaration=True)
