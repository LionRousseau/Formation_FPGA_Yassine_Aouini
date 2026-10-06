#!/usr/bin/env python3
"""
overlay_corners.py -- fabrique les images de la demonstration sur image reelle.

Entrees :
  - response_0.txt : reponse |laplacien| capturee par tb_response (640x480, decimal)
  - corner_0.txt   : carte binaire capturee par tb_environnement (0/1)
  - les plans couleur sample_in_{r,g,b}.txt (image Rafale) et sample_in_gray.txt

Sorties dans docs/results/ :
  01_rafale_gray.png     image d'entree (niveaux de gris)
  02_rafale_response.png reponse |laplacien| normalisee
  03_rafale_corners.png  carte binaire des points detectes
  04_rafale_overlay.png  image couleur + points detectes en vert (overlay mode B)

La binarisation appliquee ici (reponse >= seuil) est identique a celle du module
RTL binarize (verifie bit a bit : corner_0.txt == (response_0 >= seuil)).
"""
import argparse, os, sys
import numpy as np
try:
    from PIL import Image
except ImportError:
    sys.exit("Installer pillow : pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--resp", default="response_0.txt")
    ap.add_argument("--corners", default="corner_0.txt")
    ap.add_argument("--threshold", type=int, default=30)
    ap.add_argument("--planes-dir", default=os.path.join(ROOT, "sim", "data"),
                    help="repertoire des plans sample_in_{r,g,b}.txt et sample_in_gray.txt")
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "results"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    resp = np.loadtxt(args.resp, dtype=int)
    h, w = resp.shape

    def plane(name):
        p = os.path.join(args.planes_dir, name)
        return np.loadtxt(p, dtype=np.uint8) if os.path.exists(p) else None

    gray = plane("sample_in_gray.txt")
    R, G, B = plane("sample_in_r.txt"), plane("sample_in_g.txt"), plane("sample_in_b.txt")

    # carte binaire : de preference la sortie RTL, sinon seuillage de la reponse
    if os.path.exists(args.corners):
        mask = np.loadtxt(args.corners, dtype=int).astype(bool)
    else:
        mask = resp >= args.threshold
    # suppression du cadre (artefact de bord zero-pad, PO-05)
    mask[:2, :] = False; mask[-2:, :] = False; mask[:, :2] = False; mask[:, -2:] = False

    if gray is not None:
        Image.fromarray(gray, "L").save(os.path.join(args.out, "01_rafale_gray.png"))
    rn = (255.0 * np.clip(resp, 0, 120) / 120).astype(np.uint8)
    Image.fromarray(rn, "L").save(os.path.join(args.out, "02_rafale_response.png"))
    Image.fromarray((mask * 255).astype(np.uint8), "L").save(
        os.path.join(args.out, "03_rafale_corners.png"))

    # dilatation 1 px pour la visibilite de l'overlay
    m = mask.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            m |= np.roll(np.roll(mask, dy, 0), dx, 1)
    if R is not None and G is not None and B is not None:
        rgb = np.dstack([R, G, B]).copy()
        rgb[m] = [0, 255, 0]
        Image.fromarray(rgb, "RGB").save(os.path.join(args.out, "04_rafale_overlay.png"))

    print("points detectes : %d (%.2f%%), seuil %d" %
          (int(mask.sum()), 100.0 * mask.sum() / mask.size, args.threshold))
    print("images ecrites dans %s" % args.out)


if __name__ == "__main__":
    main()
