import os, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.expanduser("~/mnt/nyc_gay_bars _xcode")
SHOTS = os.path.join(REPO, "docs/appstore/screenshots")
ICON  = os.path.join(REPO, "NYCGayBars/Assets.xcassets/AppIcon.appiconset/icon.png")
OUT   = os.path.join(REPO, "docs/marketing/instagram")
os.makedirs(OUT, exist_ok=True)

GF = "/usr/share/fonts/truetype/google-fonts/"
def f(w, s):
    return ImageFont.truetype(GF + "Poppins-" + w + ".ttf", s)

S = 1080
PINK   = (224, 33, 138)
VIOLET = (162, 59, 214)
GOLD   = (227, 179, 65)
PLUM   = (42, 16, 51)
DEEP   = (18, 15, 29)
WHITE  = (255, 255, 255)
GRAY   = (176, 168, 190)
PRIDE  = [(228,3,3),(255,140,0),(255,237,0),(0,128,38),(0,77,255),(117,7,135)]

def bg():
    top, bot = (48, 18, 58), (14, 11, 24)
    im = Image.new("RGB", (2, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / (S - 1)
        t = t ** 0.85
        d.line([(0, y), (2, y)], fill=tuple(int(top[i] + (bot[i]-top[i])*t) for i in range(3)))
    im = im.resize((S, S))
    for (cx, cy, r, col, a) in [(0.10,0.02,0.62,PINK,120),(0.98,0.30,0.55,VIOLET,95),(0.55,1.05,0.55,(90,30,160),80)]:
        im = glow(im, cx, cy, r, col, a)
    return im

def glow(im, cx, cy, r, col, a):
    n = 180
    m = Image.new("L", (n, n), 0)
    md = ImageDraw.Draw(m)
    steps = 48
    for i in range(steps, 0, -1):
        rr = n/2 * i/steps
        v = int(a * (1 - i/steps) ** 2.1)
        md.ellipse([n/2-rr, n/2-rr, n/2+rr, n/2+rr], fill=v)
    m = m.filter(ImageFilter.GaussianBlur(6)).resize((int(S*r*2), int(S*r*2)))
    layer = Image.new("RGB", im.size, col)
    full = Image.new("L", im.size, 0)
    full.paste(m, (int(S*cx - S*r), int(S*cy - S*r)))
    return Image.composite(Image.blend(im, layer, 1.0), im, full.point(lambda v: v))

def rounded(img, rad):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0]-1, img.size[1]-1], rad, fill=255)
    out = img.convert("RGBA")
    out.putalpha(m)
    return out

def phone(name, w):
    src = Image.open(os.path.join(SHOTS, name)).convert("RGB")
    h = int(src.height * w / src.width)
    src = src.resize((w, h), Image.LANCZOS)
    rad = int(w * 0.085)
    screen = rounded(src, rad)
    bez = int(w * 0.022)
    W, H = w + bez*2, h + bez*2
    body = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle([0, 0, W-1, H-1], rad + bez, fill=(10, 8, 16, 255))
    bd.rounded_rectangle([0, 0, W-1, H-1], rad + bez, outline=(255, 255, 255, 60), width=3)
    body.alpha_composite(screen, (bez, bez))
    return body

def place(canvas, obj, x, y, angle=0, shadow=True, halo=(224, 33, 138)):
    if angle:
        obj = obj.rotate(angle, resample=Image.BICUBIC, expand=True)
    if halo:
        pad = 90
        hl = Image.new("RGBA", (obj.width + pad*2, obj.height + pad*2), (0, 0, 0, 0))
        a = obj.split()[3].point(lambda v: int(v * 0.55))
        col = Image.new("RGBA", obj.size, halo + (255,)); col.putalpha(a)
        hl.alpha_composite(col, (pad, pad))
        hl = hl.filter(ImageFilter.GaussianBlur(48))
        canvas.alpha_composite(hl, (x - pad, y - pad))
    if shadow:
        sh = Image.new("RGBA", (obj.width + 160, obj.height + 160), (0, 0, 0, 0))
        a = obj.split()[3].point(lambda v: int(v * 0.62))
        blk = Image.new("RGBA", obj.size, (0, 0, 0, 255)); blk.putalpha(a)
        sh.alpha_composite(blk, (80, 80))
        sh = sh.filter(ImageFilter.GaussianBlur(34))
        canvas.alpha_composite(sh, (x - 80, y - 60))
    canvas.alpha_composite(obj, (x, y))

def track(d, xy, text, font, fill, sp=0):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill)
        x += d.textlength(ch, font=font) + sp
    return x

def wrap(d, text, font, maxw):
    out, line = [], ""
    for word in text.split():
        t = (line + " " + word).strip()
        if d.textlength(t, font=font) <= maxw or not line:
            line = t
        else:
            out.append(line); line = word
    if line: out.append(line)
    return out

def pride_bar(d, x, y, w, h, rad=None):
    seg = w / len(PRIDE)
    for i, c in enumerate(PRIDE):
        d.rectangle([x + i*seg, y, x + (i+1)*seg, y + h], fill=c)

def chrome(canvas, idx, total, footer=True):
    d = ImageDraw.Draw(canvas)
    pride_bar(d, 0, 0, S, 8)
    if footer:
        icon = rounded(Image.open(ICON).convert("RGB").resize((52, 52), Image.LANCZOS), 13)
        canvas.alpha_composite(icon, (72, S - 118))
        d.text((138, S - 112), "NYC Gay Bars", font=f("Medium", 25), fill=(214, 206, 224))
        d.text((138, S - 82), "iPhone · free on the App Store", font=f("Regular", 20), fill=(138, 130, 152))
    dx = S - 74
    for i in range(total - 1, -1, -1):
        on = (i == idx)
        r = 7 if on else 5
        d.ellipse([dx - r*2, 64 - r, dx, 64 + r], fill=PINK if on else (104, 92, 122))
        dx -= 26

def headline_block(canvas, eyebrow, lines, bullets, top=118):
    d = ImageDraw.Draw(canvas)
    y = top
    track(d, (78, y), eyebrow.upper(), f("Bold", 24), PINK, sp=3.4)
    y += 58
    hf = f("Bold", 68)
    for ln in lines:
        col = PINK if ln.startswith("*") else WHITE
        d.text((74, y), ln.lstrip("*"), font=hf, fill=col)
        y += 80
    y += 22
    bf = f("Regular", 29)
    for b in bullets:
        d.ellipse([80, y + 13, 92, y + 25], fill=VIOLET)
        for i, ln in enumerate(wrap(d, b, bf, 430)):
            d.text((114, y), ln, font=bf, fill=(206, 199, 218))
            y += 40
        y += 24
    return y

def slide_content(idx, total, eyebrow, lines, bullets, shot, cta=None):
    c = bg().convert("RGBA")
    place(c, phone(shot, 398), 618, 178, angle=-4)
    y = headline_block(c, eyebrow, lines, bullets)
    if cta:
        d = ImageDraw.Draw(c)
        pf = f("Bold", 30)
        w = int(d.textlength(cta, font=pf)) + 72
        d.rounded_rectangle([74, y + 6, 74 + w, y + 76], 35, fill=PINK)
        d.text((74 + 36, y + 24), cta, font=pf, fill=WHITE)
    chrome(c, idx, total)
    return c

def slide_cover(total):
    c = bg().convert("RGBA")
    place(c, phone("stats.png", 292), 92, 648, angle=-10)
    place(c, phone("history.png", 320), 382, 622, angle=0)
    place(c, phone("explore.png", 292), 700, 648, angle=10)
    d = ImageDraw.Draw(c)
    icon = rounded(Image.open(ICON).convert("RGB").resize((92, 92), Image.LANCZOS), 23)
    c.alpha_composite(icon, (74, 92))
    d.text((186, 100), "NYC GAY BARS", font=f("Bold", 33), fill=WHITE)
    d.text((188, 142), "Track NYC's queer nightlife", font=f("Regular", 23), fill=GRAY)
    y = 236
    for ln, col in [("EVERY GAY BAR", WHITE), ("IN NYC.", WHITE), ("IN YOUR POCKET.", PINK)]:
        d.text((72, y), ln, font=f("Bold", 82), fill=col)
        y += 94
    d.text((78, y + 10), "Map it.  Check in.  Log the night.", font=f("Medium", 31), fill=(198, 190, 212))
    chrome(c, 0, total, footer=False)
    return c

TOTAL = 5
slides = [
    ("01_cover.jpg", slide_cover(TOTAL)),
    ("02_map.jpg", slide_content(1, TOTAL, "Find your spot",
        ["80+ bars.", "*One map."],
        ["Manhattan, Brooklyn & Queens",
         "Filter by neighborhood",
         "Sort by what's closest right now"], "explore.png")),
    ("03_log.jpg", slide_content(2, TOTAL, "Remember the night",
        ["Check in.", "*Log the night."],
        ["One-tap check-ins from anywhere",
         "Log what you drank — tonight or backdated",
         "A calendar of every night out"], "history.png")),
    ("04_stats.jpg", slide_content(3, TOTAL, "Your year in bars",
        ["Your year,", "*in bars."],
        ["Favorite bar, top drink, longest streak",
         "Neighborhood progress bars",
         "30 badges to unlock"], "stats.png")),
    ("05_friends.jpg", slide_content(4, TOTAL, "Optional friends",
        ["See who's", "*out tonight."],
        ["Add friends with a code — no accounts",
         "Share a check-in with exactly who you pick",
         "Everything else stays on your phone"], "friends_1.png",
        cta="Download free on the App Store")),
]
for name, im in slides:
    im.convert("RGB").save(os.path.join(OUT, name), quality=92, subsampling=0)
    print(name, "ok")
