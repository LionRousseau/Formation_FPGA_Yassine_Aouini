#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Demonstration sur image reelle, via le harnais du formateur (REF-TB).
#   axi4s_driver (lit sample_in_gray.txt) -> gaussien -> laplacien -> binarisation
#   -> axi4s_monitor (ecrit corner_0.txt)
# Produit aussi la reponse |laplacien| (tb_response -> response_0.txt).
# Ensuite tools/overlay_corners.py fabrique les images de docs/results/.
#
# Usage : ./run_demo.sh
# Necessite GHDL. La simulation d'une trame 640x480 prend ~1 a 2 min (GHDL mcode).
# ------------------------------------------------------------------------------
set -u
cd "$(dirname "$0")"
STD="--std=08 -fsynopsys"
rm -rf work && mkdir -p work && cd work

RTL="../../rtl/pkg/video_pkg.vhd ../../rtl/conv/line_buffer.vhd ../../rtl/conv/window_gen.vhd
     ../../rtl/conv/conv3x3.vhd ../../rtl/filters/gaussian_filter.vhd
     ../../rtl/filters/laplacian_filter.vhd ../../rtl/threshold/binarize.vhd"
REFTB="../reftb/Axi4s_driver.vhd ../reftb/Axi4s_monitor.vhd"

echo "### Analyse ###"
ghdl -a $STD $RTL $REFTB ../tb_response.vhd ../tb_environnement.vhd || exit 2

echo "### Reponse |laplacien| (tb_response) ###"
ghdl -e $STD tb_response && ghdl -r $STD tb_response 2>&1 | grep -Ei "captures|desalign"

echo "### Carte binaire de detection (tb_environnement, seuil 30) ###"
ghdl -e $STD tb_environnement && ghdl -r $STD tb_environnement 2>&1 | grep -Ei "SUCCES|captures"

echo "### Images (docs/results/) ###"
if command -v python3 >/dev/null && python3 -c "import numpy,PIL" 2>/dev/null; then
  python3 ../../tools/overlay_corners.py --resp response_0.txt --corners corner_0.txt
else
  echo "python3 + numpy + pillow requis pour generer les images ; corner_0.txt et response_0.txt sont produits."
fi
