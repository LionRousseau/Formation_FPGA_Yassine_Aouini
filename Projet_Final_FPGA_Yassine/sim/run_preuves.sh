#!/usr/bin/env bash
# Relance de TOUS les bancs de la v2 avec journaux complets (preuves de test).
# Usage (depuis <depot>/sim, GHDL 4.x dans le PATH) : ./run_preuves.sh
# Sorties : <depot>/preuves/T_simulation (T_*.log, C_*.log, 00_contexte.txt, 99_synthese.txt)
set -u
cd "$(dirname "$0")"
SIM=$(pwd); R=$(cd ../rtl && pwd)
OUT=${1:-$(cd .. && pwd)/preuves/T_simulation}; mkdir -p "$OUT"   # <depot>/preuves/T_simulation
STD="--std=08 -fsynopsys"
{
  echo "Date      : $(date '+%d/%m/%Y %H:%M:%S %Z')"
  echo "Simulateur: $(ghdl --version | head -1)"
  echo "RTL teste : v2 (empreintes MD5 ci-dessous, identiques a <depot>/rtl)"
  (cd "$R" && find . -name '*.vhd' | sort | xargs md5sum)
} > "$OUT/00_contexte.txt"

# 1) 15 bancs historiques (run_all.sh), journal complet par banc
W=$SIM/w_p1; rm -rf $W; mkdir $W; cd $W
RTLF="$R/pkg/video_pkg.vhd $R/disp/vga_pkg.vhd $R/conv/line_buffer.vhd $R/conv/window_gen.vhd $R/conv/conv3x3.vhd $R/color/rgb_to_luma.vhd $R/filters/gaussian_filter.vhd $R/filters/laplacian_filter.vhd $R/threshold/binarize.vhd $R/tracking/max_tracker.vhd $R/overlay/stream_delay.vhd $R/overlay/overlay.vhd $R/regbank/axi4lite_regs.vhd $R/source/source_mux.vhd $R/top/processing_chain.vhd $R/disp/vga_timing.vhd $R/disp/tpg.vhd $R/disp/vga_stream_out.vhd"
TBS="tb_window_gen tb_rgb_to_luma tb_gaussian tb_laplacian tb_binarize tb_max_tracker tb_axis_conformance tb_chain tb_overlay tb_vga_timing tb_tpg tb_vga_display tb_dma_mm2s tb_source_mux tb_frontend"
TBF="$SIM/ref_pkg.vhd $SIM/dma_mm2s_model.vhd"; for t in $TBS; do TBF="$TBF $SIM/$t.vhd"; done
ghdl -a $STD $RTLF $TBF > "$OUT/01_analyse.txt" 2>&1
for t in $TBS; do
  ghdl --elab-run $STD $t --stop-time=40ms > "$OUT/T_$t.log" 2>&1
done
# 2) tb_regs_view (registres, RTL reel)
ghdl -a $STD $SIM/tb_regs_view.vhd && ghdl --elab-run $STD tb_regs_view > "$OUT/T_tb_regs_view.log" 2>&1
# 3) tb_seq_cmp (modeles de sequenceur)
ghdl -a $STD $SIM/tb_seq_cmp.vhd && ghdl --elab-run $STD tb_seq_cmp > "$OUT/T_tb_seq_cmp.log" 2>&1
# 4) bancs au format VGA reduit : tb_vga_resync, tb_switch_sys
W2=$SIM/w_p2; rm -rf $W2; mkdir $W2; cd $W2
ghdl -a $STD $R/pkg/video_pkg.vhd $SIM/vga_pkg_mid.vhd $R/conv/line_buffer.vhd $R/conv/window_gen.vhd $R/conv/conv3x3.vhd \
  $R/color/rgb_to_luma.vhd $R/filters/gaussian_filter.vhd $R/filters/laplacian_filter.vhd $R/threshold/binarize.vhd \
  $R/tracking/max_tracker.vhd $R/overlay/stream_delay.vhd $R/overlay/overlay.vhd $R/top/processing_chain.vhd \
  $R/disp/tpg.vhd $R/source/source_mux.vhd $R/disp/vga_timing.vhd $R/disp/vga_stream_out.vhd $R/regbank/axi4lite_regs.vhd \
  $R/top/video_subsystem_step2.vhd $SIM/tb_switch_sys.vhd > "$OUT/02_analyse_reduit.txt" 2>&1
ghdl --elab-run $STD tb_switch_sys > "$OUT/T_tb_switch_sys.log" 2>&1
# 5) tb_vga_resync : format VGA reel 640x480
W3=$SIM/w_p3; rm -rf $W3; mkdir $W3; cd $W3
ghdl -a $STD $R/pkg/video_pkg.vhd $R/disp/vga_pkg.vhd $R/disp/vga_timing.vhd $R/disp/vga_stream_out.vhd $SIM/tb_vga_resync.vhd
ghdl --elab-run $STD tb_vga_resync > "$OUT/T_tb_vga_resync.log" 2>&1
# 6) CONTRE-EPREUVES : les bancs doivent ECHOUER sur les defauts connus
# Fichiers VGA de la version precedente (defaut FA-05), copies dans contre_epreuves/v1.0_vga
V1=$SIM/contre_epreuves/v1.0_vga; MUT=$SIM/mutants
W4=$SIM/w_p4; rm -rf $W4; mkdir $W4; cd $W4
ghdl -a $STD $V1/pkg/video_pkg.vhd $V1/disp/vga_pkg.vhd $V1/disp/vga_timing.vhd $V1/disp/tpg.vhd $V1/disp/vga_stream_out.vhd $SIM/tb_vga_display.vhd
ghdl --elab-run $STD tb_vga_display --stop-time=40ms > "$OUT/C_tb_vga_display_sur_v1.0.log" 2>&1
W5=$SIM/w_p5; rm -rf $W5; mkdir $W5; cd $W5
ghdl -a $STD $R/pkg/video_pkg.vhd $SIM/vga_pkg_mid.vhd $R/conv/line_buffer.vhd $R/conv/window_gen.vhd $R/conv/conv3x3.vhd \
  $R/color/rgb_to_luma.vhd $R/filters/gaussian_filter.vhd $R/filters/laplacian_filter.vhd $R/threshold/binarize.vhd \
  $R/tracking/max_tracker.vhd $R/overlay/stream_delay.vhd $R/overlay/overlay.vhd $R/top/processing_chain.vhd \
  $R/disp/tpg.vhd $R/source/source_mux.vhd $R/disp/vga_timing.vhd $R/disp/vga_stream_out.vhd $R/regbank/axi4lite_regs.vhd \
  $MUT/video_subsystem_srcsel.vhd $SIM/tb_switch_sys.vhd
ghdl --elab-run $STD tb_switch_sys > "$OUT/C_tb_switch_sys_sur_mutant_FA04.log" 2>&1
# Synthese
cd "$OUT"
{
  echo "BANC                  VERDICT"
  for f in T_*.log; do
    b=${f#T_}; b=${b%.log}
    if grep -q "SUCCES" $f && ! grep -qi "ECHEC\|failure" $f; then v=SUCCES; else v=ECHEC; fi
    printf "%-22s %s\n" "$b" "$v"
  done
  echo
  echo "CONTRE-EPREUVE (echec attendu)          RESULTAT"
  for f in C_*.log; do
    b=${f#C_}; b=${b%.log}
    if grep -qi "ECHEC\|failure" $f; then v="ECHEC (defaut detecte)"; else v="PASSE (banc trop faible)"; fi
    printf "%-38s %s\n" "$b" "$v"
  done
} > 99_synthese.txt
cat 99_synthese.txt
