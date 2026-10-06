#!/usr/bin/env python3
"""
check_views.py : verification pixel par pixel des vues de demonstration v2.

1. Construit une image d'essai (Rafale sous-echantillonne) -> in_rgb.txt
2. Lance tb_views (GHDL) pour chaque configuration (vue, mode, bypass)
3. Compare la trame de sortie a un modele de reference independant, avec
   les memes arrondis que le materiel (decalages entiers, bords a zero).
4. Ecrit une image PNG par configuration (illustration pour la demo).
"""
import subprocess, sys, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work_views")
DS   = int(os.environ.get("DS", "4"))           # facteur de sous-echantillonnage
THR  = int(os.environ.get("THR", "30"))

def load_rafale():
    ch = []
    for c in "rgb":
        a = np.loadtxt(os.path.join(HERE, "data", f"sample_in_{c}.txt"), dtype=np.int64)
        ch.append(a)
    img = np.stack(ch, axis=-1)                    # 480 x 640 x 3
    return img[::DS, ::DS, :]

# ---------------- modele de reference ----------------
def luma(img):
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    y = r // 4 + r // 16 + g // 2 + g // 16 + b // 8
    return np.clip(y, 0, 255)

def conv(x, k):
    """somme(k*p) sur fenetre 3x3, bords a zero (PO-05)"""
    h, w = x.shape
    p = np.zeros((h + 2, w + 2), dtype=np.int64)
    p[1:-1, 1:-1] = x
    acc = np.zeros_like(x)
    for dy in range(3):
        for dx in range(3):
            acc += k[dy][dx] * p[dy:dy + h, dx:dx + w]
    return acc

KG = [[1, 2, 1], [2, 4, 2], [1, 2, 1]]
KL = [[0, -1, 0], [-1, 4, -1], [0, -1, 0]]

def reference(img, view, mode, bypass, thr):
    y = luma(img)
    g = y.copy() if bypass else np.clip(conv(y, KG) // 16, 0, 255)
    l = np.clip(np.abs(conv(g, KL)), 0, 2047)
    r8 = np.minimum(l, 255)
    mask = l >= thr
    gray = lambda v: np.stack([v, v, v], axis=-1)
    if view == 1:   base = gray(y)
    elif view == 2: base = gray(g)
    elif view == 3: base = gray(r8)
    elif view == 4: base = gray(np.where(mask, 255, 0))
    else:           base = img.copy()
    out = base.copy()
    if mode == 1 and view != 4:
        out[mask] = [0, 255, 0]
    return out, mask, l

# ---------------- simulation ----------------
RTL = ["pkg/video_pkg.vhd", "conv/line_buffer.vhd", "conv/window_gen.vhd",
       "conv/conv3x3.vhd", "color/rgb_to_luma.vhd", "filters/gaussian_filter.vhd",
       "filters/laplacian_filter.vhd", "threshold/binarize.vhd",
       "tracking/max_tracker.vhd", "overlay/stream_delay.vhd",
       "overlay/overlay.vhd", "top/processing_chain.vhd"]

def compile_all(rtl_dir):
    os.makedirs(WORK, exist_ok=True)
    files = [os.path.join(rtl_dir, f) for f in RTL] + [os.path.join(HERE, "tb_views.vhd")]
    subprocess.run(["ghdl", "-a", "--std=08", "-fsynopsys"] + files, cwd=WORK, check=True)
    subprocess.run(["ghdl", "-e", "--std=08", "-fsynopsys", "tb_views"], cwd=WORK, check=True)

def run(h, w, view, mode, bypass, thr, tag):
    out = os.path.join(WORK, f"out_{tag}.txt")
    cmd = ["ghdl", "-r", "--std=08", "-fsynopsys", "tb_views",
           f"-gIMG_W={w}", f"-gIMG_H={h}", f"-gVIEW={view}", f"-gMODE={mode}",
           f"-gBYPASS={bypass}", f"-gTHR={thr}", f"-gOUT_FILE={out}",
           f"-gIN_FILE={os.path.join(WORK, 'in_rgb.txt')}"]
    res = subprocess.run(cmd, cwd=WORK, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout[-2000:], res.stderr[-2000:])
        raise SystemExit(f"simulation {tag} en echec")
    vals = [int(l.strip(), 16) for l in open(out) if l.strip()]
    a = np.array(vals, dtype=np.int64).reshape(h, w)
    return np.stack([(a >> 16) & 255, (a >> 8) & 255, a & 255], axis=-1)

CONFIGS = [  # (tag, vue, mode, bypass, description)
    ("v0_B",        0, 1, 0, "overlay (v1.0)"),
    ("v0_A",        0, 0, 0, "image brute (v1.0)"),
    ("v1_luma",     1, 0, 0, "vue luminance"),
    ("v2_gauss",    2, 0, 0, "vue sortie gaussien"),
    ("v3_resp",     3, 0, 0, "vue reponse laplacien"),
    ("v4_mask",     4, 1, 0, "vue masque binaire"),
    ("v2_gauss_B",  2, 1, 0, "gaussien + overlay"),
    ("v2_byp",      2, 0, 1, "gaussien court-circuite (= luminance)"),
    ("v3_resp_byp", 3, 0, 1, "reponse laplacien SANS gaussien"),
    ("v0_B_byp",    0, 1, 1, "overlay SANS gaussien"),
]

def main():
    rtl_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "rtl")
    img = load_rafale()
    h, w, _ = img.shape
    os.makedirs(WORK, exist_ok=True)
    with open(os.path.join(WORK, "in_rgb.txt"), "w") as f:
        for p in img.reshape(-1, 3):
            f.write(f"{p[0]} {p[1]} {p[2]}\n")
    compile_all(rtl_dir)
    png_dir = os.path.join(HERE, "views_png"); os.makedirs(png_dir, exist_ok=True)
    total_err = 0
    print(f"Image d'essai {w}x{h}, seuil {THR}")
    print(f"{'config':<13}{'description':<40}{'pixels faux':>12}{'points':>9}  verdict")
    for tag, view, mode, byp, desc in CONFIGS:
        got = run(h, w, view, mode, byp, THR, tag)
        ref, mask, _ = reference(img, view, mode, byp, THR)
        bad = np.any(got != ref, axis=-1)
        nerr = int(bad.sum())
        total_err += nerr
        verdict = "SUCCES" if nerr == 0 else "ECHEC"
        print(f"{tag:<13}{desc:<40}{nerr:>12}{int(mask.sum()):>9}  {verdict}")
        if nerr:
            ys, xs = np.nonzero(bad)
            for k in range(min(5, nerr)):
                y0, x0 = ys[k], xs[k]
                print(f"    (x={x0},y={y0}) obtenu {got[y0,x0]} attendu {ref[y0,x0]}")
        Image.fromarray(got.astype(np.uint8)).save(os.path.join(png_dir, f"{tag}.png"))
    print("VERDICT GLOBAL :", "SUCCES" if total_err == 0 else f"ECHEC ({total_err} pixels faux)")
    sys.exit(0 if total_err == 0 else 1)

if __name__ == "__main__":
    main()
