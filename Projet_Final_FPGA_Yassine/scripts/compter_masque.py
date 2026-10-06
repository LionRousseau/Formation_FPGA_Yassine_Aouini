#!/usr/bin/env python3
"""
compter_masque.py : compte les points detectes sur une capture d'ecran de la
vue "masque" (VIEW = 4) de SoC Tracking v2.

Principe : a tout seuil, les 2 236 pixels du pourtour de l'image sont detectes
(bords mis a zero dans les filtres) ; ils forment un cadre blanc qui delimite
exactement l'image 640 x 480 dans la capture, quels que soient le format et
les bandes noires de la carte d'acquisition. On recadre sur ce cadre, on
ramene a 640 x 480 par moyenne de surface, puis on compte les pixels blancs.

Usage : python compter_masque.py capture.png [capture2.png ...]
Attendu (modele de reference, image Rafale, gaussien actif) :
  seuil 10 : 16 939   seuil 30 : 7 982   seuil 60 : 2 923
Critere : ecart inferieur a 10 % et ordre seuil 10 > seuil 30 > seuil 60.
"""
import sys
import numpy as np
from PIL import Image

ATTENDU = {10: 16939, 30: 7982, 60: 2923}

def compter(chemin):
    g = np.asarray(Image.open(chemin).convert("L"), dtype=np.float64)
    blanc = g >= 128
    lignes = np.where(blanc.mean(axis=1) > 0.5)[0]     # lignes du cadre (haut, bas)
    cols = np.where(blanc.mean(axis=0) > 0.5)[0]       # colonnes du cadre (gauche, droite)
    if len(lignes) < 2 or len(cols) < 2:
        raise SystemExit(f"{chemin} : cadre blanc introuvable (vue masque affichee ?)")
    y0, y1, x0, x1 = lignes[0], lignes[-1], cols[0], cols[-1]
    zone = Image.fromarray(g[y0:y1 + 1, x0:x1 + 1].astype(np.uint8))
    zone = np.asarray(zone.resize((640, 480), Image.BOX), dtype=np.float64)
    n = int((zone >= 128).sum())
    return n, (x0, y0, x1 - x0 + 1, y1 - y0 + 1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    for f in sys.argv[1:]:
        n, (x, y, w, h) = compter(f)
        print(f"{f} : {n} pixels detectes (image trouvee en x={x}, y={y}, {w} x {h})")
    print("Attendu : " + "   ".join(f"seuil {s} : {v}" for s, v in ATTENDU.items()))
