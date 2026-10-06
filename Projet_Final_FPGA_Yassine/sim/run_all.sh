#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Projet SoC Tracking : lancement de tous les testbenches unitaires et
# d'integration sous GHDL (VHDL-2008). Chaque testbench est auto-verifiant : il
# se termine par un compte d'erreurs et un message de verdict explicite (PV 4.2).
#
# Usage :   ./run_all.sh
# Sortie :  un tableau de verdicts + code de retour non nul si un test echoue.
# ------------------------------------------------------------------------------
set -u
cd "$(dirname "$0")"

STD="--std=08 -fsynopsys"
WORK="work"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

RTL_DIR=../../rtl
RTL="
  $RTL_DIR/pkg/video_pkg.vhd
  $RTL_DIR/disp/vga_pkg.vhd
  $RTL_DIR/conv/line_buffer.vhd
  $RTL_DIR/conv/window_gen.vhd
  $RTL_DIR/conv/conv3x3.vhd
  $RTL_DIR/color/rgb_to_luma.vhd
  $RTL_DIR/filters/gaussian_filter.vhd
  $RTL_DIR/filters/laplacian_filter.vhd
  $RTL_DIR/threshold/binarize.vhd
  $RTL_DIR/tracking/max_tracker.vhd
  $RTL_DIR/overlay/stream_delay.vhd
  $RTL_DIR/overlay/overlay.vhd
  $RTL_DIR/regbank/axi4lite_regs.vhd
  $RTL_DIR/source/source_mux.vhd
  $RTL_DIR/top/processing_chain.vhd
  $RTL_DIR/disp/vga_timing.vhd
  $RTL_DIR/disp/tpg.vhd
  $RTL_DIR/disp/vga_stream_out.vhd
"

TB="
  ../ref_pkg.vhd
  ../dma_mm2s_model.vhd
  ../tb_window_gen.vhd
  ../tb_rgb_to_luma.vhd
  ../tb_gaussian.vhd
  ../tb_laplacian.vhd
  ../tb_binarize.vhd
  ../tb_max_tracker.vhd
  ../tb_axis_conformance.vhd
  ../tb_chain.vhd
  ../tb_overlay.vhd
  ../tb_vga_timing.vhd
  ../tb_tpg.vhd
  ../tb_vga_display.vhd
  ../tb_dma_mm2s.vhd
  ../tb_source_mux.vhd
  ../tb_frontend.vhd
"

echo "### Analyse RTL + testbenches ###"
ghdl -a $STD $RTL $TB || { echo "ECHEC analyse"; exit 2; }

# nom d'entite testbench : cas de test associe
declare -a TESTS=(
  "tb_window_gen:TC-U-06 fenetre glissante"
  "tb_rgb_to_luma:TC-U-10 conversion luminance"
  "tb_gaussian:TC-U-04a filtre gaussien"
  "tb_laplacian:TC-U-04b filtre de Harris"
  "tb_binarize:TC-U-05 binarisation et seuil"
  "tb_max_tracker:TC-U-08 suivi du maximum"
  "tb_axis_conformance:TC-U-07 conformite AXI4-Stream"
  "tb_chain:TC-I-01 chaine complete"
  "tb_overlay:TC-I-03 alignement overlay"
  "tb_vga_timing:TC-U-09 temporisation VGA"
  "tb_tpg:TC-U-02 generateur de mire"
  "tb_vga_display:TC-S-01 (sim) mire vers VGA"
  "tb_dma_mm2s:TC-U-01 DMA lecture memoire"
  "tb_source_mux:TC-U-03 selection de source"
  "tb_frontend:Integration DMA->mux->chaine"
)

echo
echo "### Execution ###"
printf "%-22s %-34s %s\n" "TESTBENCH" "CAS DE TEST" "VERDICT"
printf "%-22s %-34s %s\n" "----------------------" "----------------------------------" "-------"

fail=0
for entry in "${TESTS[@]}"; do
  tb="${entry%%:*}"; label="${entry#*:}"
  out=$(ghdl --elab-run $STD "$tb" --stop-time=40ms 2>&1)
  if echo "$out" | grep -q "SUCCES"; then
    verdict="SUCCES"
  else
    verdict="ECHEC"; fail=1
  fi
  printf "%-22s %-34s %s\n" "$tb" "$label" "$verdict"
done

echo
if [ "$fail" -eq 0 ]; then
  echo "TOUS LES TESTS SONT PASSES."
else
  echo "AU MOINS UN TEST A ECHOUE."
fi
exit $fail
