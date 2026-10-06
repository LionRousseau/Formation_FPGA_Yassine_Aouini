#-------------------------------------------------------------------------------
# create_project_v2.tcl  -  cree le projet Vivado PROPRE de la v2, a partir de
# zero, dans vivado/ (a la racine du depot). N'utilise QUE le contenu du depot (la v1 n'est
# jamais lue ni modifiee) :
#   - rtl/**              sources VHDL de la v2
#   - constraints/        contraintes
#   - bd/design_1_bd.tcl     block design (export write_bd_tcl de la v1)
# Point 4 : horloge pixel reglee a 25,175 MHz (VESA 640x480 @ 59,94 Hz).
#
# UTILISATION (console Tcl de Vivado, AUCUN projet ouvert) :
#   source {<depot>/scripts/create_project_v2.tcl}
#-------------------------------------------------------------------------------
set V2        [file normalize [file join [file dirname [info script]] ..]]
set PROJ_DIR  $V2/vivado
set PROJ_NAME soc_tracking_v2
set PART      xc7z010clg400-1
# IP HLS DMA24bUnit_mm2s (fournie par le formateur), copiee dans ip/.
# Ordre de recherche : variable d'environnement DMA_IP_REPO, puis dossier ip/ du depot,
# puis l'emplacement d'origine sur le poste de developpement.
if {[info exists ::env(DMA_IP_REPO)]} {
  set IP_REPO $::env(DMA_IP_REPO)
} elseif {[file isdirectory $V2/ip]} {
  set IP_REPO $V2/ip
} else {
  set IP_REPO C:/Users/yassi/Downloads/DMA_RGB24b/hls/DMA24b_mm2s_prj/solution1/impl/ip
}
set BD_TCL    $V2/bd/design_1_bd.tcl
set PIX_MHZ   25.175

if {![file exists $BD_TCL]} {
  error "Block design introuvable : $BD_TCL (faire d'abord l'export write_bd_tcl depuis la v1)"
}
if {[file exists $PROJ_DIR/$PROJ_NAME.xpr]} {
  error "Le projet existe deja : $PROJ_DIR/$PROJ_NAME.xpr (l'ouvrir, ou renommer vivado/ pour repartir de zero)"
}
if {[current_project -quiet] ne ""} { close_project }

# 1) Projet
create_project $PROJ_NAME $PROJ_DIR -part $PART
set_property target_language VHDL [current_project]
set_property ip_repo_paths $IP_REPO [current_project]
update_ip_catalog

# 2) Sources RTL et contraintes (rtl/ et constraints/ du depot)
add_files -norecurse [glob $V2/rtl/*/*.vhd]
add_files -fileset constrs_1 -norecurse [glob $V2/constraints/*.xdc]
update_compile_order -fileset sources_1

# 3) Block design (recree a l'identique de la v1)
source $BD_TCL
set bd_file [get_files design_1.bd]
open_bd_design $bd_file

# 4) Point 4 : horloge pixel a 25,175 MHz
set clk [get_bd_cells -quiet clk_pix]
if {$clk eq ""} { set clk [get_bd_cells -hierarchical -filter {VLNV =~ "xilinx.com:ip:clk_wiz:*"}] }
puts "Horloge pixel : cellule $clk, avant = [get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $clk] MHz"
set_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $PIX_MHZ $clk
validate_bd_design
set fin  [get_property CONFIG.PRIM_IN_FREQ $clk]
set mult [get_property CONFIG.MMCM_CLKFBOUT_MULT_F $clk]
set dvc  [get_property CONFIG.MMCM_DIVCLK_DIVIDE $clk]
set dv0  [get_property CONFIG.MMCM_CLKOUT0_DIVIDE_F $clk]
set fpix [expr {$fin * $mult / ($dvc * $dv0)}]
puts [format "Horloge pixel obtenue : %.4f MHz  (%s x %s / (%s x %s))  -> trame %.3f Hz" \
        $fpix $fin $mult $dvc $dv0 [expr {$fpix * 1e6 / (800.0 * 525.0)}]]
save_bd_design

# 5) Wrapper HDL et top
make_wrapper -files $bd_file -top
set wr [glob -nocomplain $PROJ_DIR/$PROJ_NAME.gen/sources_1/bd/design_1/hdl/design_1_wrapper.vhd \
                         $PROJ_DIR/$PROJ_NAME.srcs/sources_1/bd/design_1/hdl/design_1_wrapper.vhd]
add_files -norecurse [lindex $wr 0]
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "======================================================================"
puts " Projet v2 cree : $PROJ_DIR/$PROJ_NAME.xpr"
puts " Etape suivante : source {$V2/scripts/rebuild_v2.tcl}"
puts "======================================================================"
