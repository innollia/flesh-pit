import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
for name, box in [("top", (0.3, 0.1, 0.7, 0.4)), ("mid", (0.3, 0.4, 0.7, 0.6)), ("left", (0.02, 0.35, 0.3, 0.8)), ("right", (0.7, 0.35, 0.98, 0.8)), ("bottom", (0.2, 0.75, 0.8, 1.0))]:
    c = im.crop((int(box[0]*w), int(box[1]*h), int(box[2]*w), int(box[3]*h))).resize((1, 1), Image.BOX).getpixel((0, 0))
    print(name, c)
