# Regenerates game/main/art/textures/tex_minced_meat_128.png (ending sphere).
# Raw meatball read: mottled red meat (low-freq light/dark patches, darker
# strands) + fat as a few LARGE clumped blobs, not white pepper noise.
import numpy as np
from PIL import Image
N = 128
rng = np.random.default_rng(7)
def tile_noise(cells, seed):
    r = np.random.default_rng(seed).random((cells, cells))
    x = np.arange(N) * cells / N
    i = np.floor(x).astype(int); f = x - i; f = f * f * (3 - 2 * f)
    a = r[i % cells][:, i % cells]; b = r[(i + 1) % cells][:, i % cells]
    c = r[i % cells][:, (i + 1) % cells]; d = r[(i + 1) % cells][:, (i + 1) % cells]
    fy = f[:, None]; fx = f[None, :]
    return (a * (1 - fx) + c * fx) * (1 - fy) + (b * (1 - fx) + d * fx) * fy
big = tile_noise(4, 1) * 0.6 + tile_noise(8, 2) * 0.4
mid = tile_noise(16, 3)
fine = tile_noise(32, 4)
dark = np.array([0.36, 0.06, 0.08]); red = np.array([0.66, 0.16, 0.17]); pink = np.array([0.86, 0.40, 0.40])
t = np.clip((big - 0.5) * 2.2 + (mid - 0.5) * 0.8 + (fine - 0.5) * 0.4 + 0.5, 0, 1)
col = np.where(t[..., None] < 0.5, dark + (red - dark) * (t[..., None] * 2), red + (pink - red) * ((t[..., None] - 0.5) * 2))
# minced strands: short dark worm lines
yy, xx = np.mgrid[0:N, 0:N]
for k in range(70):
    y0, x0 = rng.integers(0, N, 2); ang = rng.random() * np.pi; L = rng.integers(4, 10)
    for s in range(L):
        y = int(y0 + np.sin(ang) * s) % N; x = int(x0 + np.cos(ang) * s) % N
        col[y, x] *= 0.62
# fat: clumped blobs (clusters of 2-4 overlapping discs, radius 3-6 px)
fatmask = np.zeros((N, N))
for k in range(16):
    cy, cx = rng.integers(0, N, 2)
    for j in range(rng.integers(2, 5)):
        oy, ox = rng.normal(0, 3.0, 2); r = rng.uniform(2.5, 5.5)
        dy = (yy - cy - oy + N / 2) % N - N / 2; dx = (xx - cx - ox + N / 2) % N - N / 2
        edge = (np.sqrt(dy * dy + dx * dx) + (fine - 0.5) * 3.0) < r
        fatmask = np.maximum(fatmask, edge.astype(float))
fatcol = np.array([0.93, 0.80, 0.70]) * (0.85 + 0.2 * mid[..., None])
col = col * (1 - fatmask[..., None]) + fatcol * fatmask[..., None]
col = np.clip(col, 0, 1)
out = r"C:\Users\fixme\Desktop\flesh-pit-main\game\main\art\textures\tex_minced_meat_128.png"
Image.fromarray((col * 255).astype(np.uint8)).save(out)
print("fat%", round(fatmask.mean() * 100, 1), "lum std", round(float(col.mean(axis=2).std()), 3))