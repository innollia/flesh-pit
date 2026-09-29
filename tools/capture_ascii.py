import sys
from PIL import Image
# Prints a coarse character map of an image: hue class + brightness.
# W white/very light, w light gray, . dark, R red, r dark red, Y yellow, S skin, G green, B blue-ish, ' ' black
im = Image.open(sys.argv[1]).convert("RGB")
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 96
rows = int(cols * im.size[1] / im.size[0] / 2)
sm = im.resize((cols, rows), Image.BOX)
out = []
for y in range(rows):
    line = ""
    for x in range(cols):
        r, g, b = sm.getpixel((x, y))
        s = r + g + b
        if s < 45: ch = " "
        elif r > 205 and g > 205 and b > 205: ch = "W"
        elif abs(r - g) < 20 and abs(g - b) < 20: ch = "w" if s > 360 else ("-" if s > 180 else ".")
        elif r > 150 and g > 120 and b < 100 and g > r * 0.65: ch = "Y"
        elif r > 160 and 95 < g < 200 and b > 60 and r > g > b and g > r * 0.55: ch = "S"
        elif g > r and g > b: ch = "G"
        elif b > r and b >= g: ch = "B"
        elif r > g * 1.5: ch = "R" if r > 140 else "r"
        else: ch = "o"
        line += ch
    out.append(line)
print("\n".join(out))
