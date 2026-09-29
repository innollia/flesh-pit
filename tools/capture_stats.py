import sys, os
from PIL import Image, ImageStat
d = sys.argv[1]
for f in sorted(os.listdir(d)):
    if not f.endswith(".png"):
        continue
    im = Image.open(os.path.join(d, f)).convert("RGB")
    st = ImageStat.Stat(im)
    w, h = im.size
    sm = im.resize((64, 36))
    px = list(sm.getdata())
    white = sum(1 for r,g,b in px if r>200 and g>200 and b>200)/len(px)
    red = sum(1 for r,g,b in px if r>g*1.6 and r>50)/len(px)
    yellow = sum(1 for r,g,b in px if r>150 and g>120 and b<90)/len(px)
    skin = sum(1 for r,g,b in px if r>150 and 90<g<190 and 60<b<170 and r>g>b)/len(px)
    black = sum(1 for r,g,b in px if r+g+b<40)/len(px)
    print("%-26s %dx%d mean=(%d,%d,%d) white=%.2f red=%.2f yellow=%.2f skin=%.2f dark=%.2f" % (f, w, h, *[int(x) for x in st.mean], white, red, yellow, skin, black))
