#!/usr/bin/env bash
# Lance tb_switch_sys (format reduit) sur le RTL donne en argument (defaut ../rtl)
set -e
cd "$(dirname "$0")"
R=${1:-$(cd ../rtl && pwd)}
rm -rf work_switch && mkdir work_switch && cd work_switch
ghdl -a --std=08 -fsynopsys $R/pkg/video_pkg.vhd ../vga_pkg_mid.vhd \
  $R/conv/line_buffer.vhd $R/conv/window_gen.vhd $R/conv/conv3x3.vhd \
  $R/color/rgb_to_luma.vhd $R/filters/gaussian_filter.vhd $R/filters/laplacian_filter.vhd \
  $R/threshold/binarize.vhd $R/tracking/max_tracker.vhd $R/overlay/stream_delay.vhd \
  $R/overlay/overlay.vhd $R/top/processing_chain.vhd $R/disp/tpg.vhd $R/source/source_mux.vhd \
  $R/disp/vga_timing.vhd $R/disp/vga_stream_out.vhd $R/regbank/axi4lite_regs.vhd \
  ${TOP:-$R/top/video_subsystem_step2.vhd} ../tb_switch_sys.vhd
ghdl -e --std=08 -fsynopsys tb_switch_sys
ghdl -r --std=08 -fsynopsys tb_switch_sys ${GEN:-} 2>&1 | grep -E "image|OK|ECHEC|SUCCES|erreur|dbg" | sed 's/.*(report [a-z]*): //'
