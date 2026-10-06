#-------------------------------------------------------------------------------
# run_v2.tcl  -  programme la carte avec la v2 et lance la demonstration.
# Fichiers pris uniquement dans le depot (export/, sw/, data/).
# Point 3 : l'image est chargee avec la commande du SRS (PS-001) :
#   mwr -bin -file image.bin <adresse> <nombre de mots>
#
# AVANT : carte alimentee, JP2 sur JTAG, Pmod VGA sur JA/JB, Hardware Manager
#         de Vivado ferme, appui sur SRST.
# UTILISATION (console XSCT) :
#   source {<depot>/scripts/run_v2.tcl}
#-------------------------------------------------------------------------------
set V2  [file normalize [file join [file dirname [info script]] ..]]
set BIT $V2/export/design_1_wrapper_v2.bit
set PS7 $V2/export/ps7_init.tcl
set ELF $V2/sw/soc_tracking_app_step3.elf
set IMG $V2/data/rafale_640x480_rgb.bin
set IMG_ADDR 0x10000000
set IMG_WORDS [expr {[file size $IMG] / 4}]     ;# 921600 octets = 230400 mots

foreach f [list $BIT $PS7 $ELF $IMG] {
  if {![file exists $f]} { error "Fichier manquant : $f" }
}

connect
configparams force-mem-access 1
fpga -file $BIT
targets -set -filter {name =~ "*Cortex-A9*#0"}
stop
source $PS7
ps7_init
ps7_post_config
dow $ELF

# Point 3 : commande du SRS (au lieu de dow -data)
mwr -bin -file $IMG $IMG_ADDR $IMG_WORDS
puts "controle memoire, doit afficher D6F9E3D7 puis E2D6F8E2 (octets D7 E3 F9 D6 E2 F8 D6 E2 du fichier) :"
mrd $IMG_ADDR 2

con
puts "======================================================================"
puts " v2 lancee : Rafale + overlay vert au VGA."
puts " Source       : mwr 0x43C00014 1 (mire) / 0 (Rafale)"
puts " Vues (0x1C)  : 0 normale  1 luminance  2 gaussien  3 reponse  4 masque"
puts "                +8 = gaussien court-circuite (ex. mwr 0x43C0001C 8)"
puts " Overlay      : mwr 0x43C00010 1 (points verts) / 0 (sans)"
puts " Seuil        : mwr 0x43C0000C 30   Maximum : mrd 0x43C00000 3"
puts "======================================================================"
