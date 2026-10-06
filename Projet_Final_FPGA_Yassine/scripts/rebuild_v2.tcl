#-------------------------------------------------------------------------------
# rebuild_v2.tcl  -  synthese + implementation + bitstream de la v2, puis
# export dans export/ : bitstream, XSA (avec bitstream) et ps7_init.tcl.
# Reinitialise TOUS les runs de synthese hors-contexte (dont le module video)
# pour relire le RTL modifie.
#
# UTILISATION (console Tcl de Vivado) :
#   source {<depot>/scripts/rebuild_v2.tcl}
#-------------------------------------------------------------------------------
set V2   [file normalize [file join [file dirname [info script]] ..]]
set PROJ $V2/vivado/soc_tracking_v2.xpr
set EXP  $V2/export

if {[current_project -quiet] eq ""} { open_project $PROJ }
if {![string match -nocase "*/vivado*" [get_property DIRECTORY [current_project]]]} {
  error "Le projet ouvert n'est pas la v2 ([get_property DIRECTORY [current_project]]) : fermer le projet et relancer."
}

foreach r [get_runs] {
  if {[get_property IS_SYNTHESIS $r] && $r ne "synth_1"} { catch { reset_run $r } }
}
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  error "impl_1 ne s'est pas terminee correctement, voir les journaux."
}

file mkdir $EXP
set rdir [get_property DIRECTORY [get_runs impl_1]]
file copy -force $rdir/design_1_wrapper.bit $EXP/design_1_wrapper_v2.bit
write_hw_platform -fixed -include_bit -force $EXP/design_1_wrapper_v2.xsa
set ps7 [lindex [glob -nocomplain [get_property DIRECTORY [current_project]]/*.gen/sources_1/bd/design_1/ip/*processing_system7*/ps7_init.tcl] 0]
file copy -force $ps7 $EXP/ps7_init.tcl

# Resume timing pour le dossier de validation
open_run impl_1
report_timing_summary -file $EXP/timing_summary_v2.rpt
report_utilization    -file $EXP/utilization_v2.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "======================================================================"
puts " OK  v2 construite. Exports dans $EXP"
puts "     WNS = $wns ns   WHS = $whs ns   (doivent etre >= 0)"
puts " Etape suivante (XSCT, apres SRST) : source {$V2/scripts/run_v2.tcl}"
puts "======================================================================"
