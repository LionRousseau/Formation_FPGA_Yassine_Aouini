#-------------------------------------------------------------------------------
# essais_v2.tcl  -  essais chiffres automatiques sur carte, SoC Tracking v2.
# Protocole d'essais PE-SOC-TRACKING rev A : TC1, TC2, TC3, TC4, TC5, TC8, TC11.
#
# A lancer dans la console XSCT APRES run_v2.tcl (carte programmee, application
# lancee, image chargee) :
#   source {<depot>/scripts/essais_v2.tcl}
#
# Chaque essai compare la valeur relue a la valeur predite par le modele de
# reference et affiche OK ou KO. Le journal est ecrit dans
#   <depot>/preuves/D_carte/journal_essais_v2_<date>_<heure>.txt
# En fin de script, la carte est remise dans l'etat de depart (Rafale,
# overlay, seuil 30, vue normale, gaussien actif). Duree : environ 1 minute.
# Le script ne fait que lire et ecrire des registres ; il ne reprogramme rien.
#-------------------------------------------------------------------------------
set V2   [file normalize [file join [file dirname [info script]] ..]]
set JDIR [file normalize [file join $V2 preuves D_carte]]
file mkdir $JDIR
set STAMP [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set ::JFILE [file join $JDIR journal_essais_v2_$STAMP.txt]
set ::JF [open $::JFILE w]
set ::NOK 0
set ::NKO 0

proc jlog {s} { puts $s; puts $::JF $s; flush $::JF }

if {[catch {targets -set -filter {name =~ "*Cortex-A9*#0"}}]} {
  connect
  targets -set -filter {name =~ "*Cortex-A9*#0"}
}
configparams force-mem-access 1

# lecture d'un mot de 32 bits (mrd -value, sinon analyse du texte de mrd)
proc rd {a} {
  if {![catch {set v [mrd -value $a]}]} {
    return [expr {[lindex $v 0] & 0xFFFFFFFF}]
  }
  set s [mrd $a]
  if {[regexp {:\s*([0-9A-Fa-f]{8})} $s -> h]} { return [expr {"0x$h" & 0xFFFFFFFF}] }
  error "lecture impossible a $a : $s"
}
proc wr {a v} { mwr $a $v }
proc attendre {ms} { after $ms }

set R_MAX 0x43C00000
set R_X   0x43C00004
set R_Y   0x43C00008
set R_THR 0x43C0000C
set R_MOD 0x43C00010
set R_SRC 0x43C00014
set R_ST  0x43C00018
set R_VW  0x43C0001C

proc maxi {} {
  return [format "%d,%d,%d" [rd $::R_MAX] [rd $::R_X] [rd $::R_Y]]
}
proc verdict {id libelle obtenu attendu} {
  if {$obtenu eq $attendu} { set r OK; incr ::NOK } else { set r KO; incr ::NKO }
  jlog [format "%-6s %-48s obtenu %-19s attendu %-19s %s" $id $libelle $obtenu $attendu $r]
  return $r
}
# temps laisse a la chaine apres un changement : 300 ms = 18 images
set PAUSE 300

jlog "=============================================================================="
jlog " SoC Tracking v2 : essais chiffres sur carte (PE-SOC-TRACKING rev A)"
jlog " Date      : [clock format [clock seconds] -format {%d/%m/%Y %H:%M:%S}]"
jlog " Bitstream : $V2/export/design_1_wrapper_v2.bit"
jlog " Journal   : $::JFILE"
jlog "=============================================================================="

# --- TC1 : image en DDR (PS-001, PL-IP-000) --------------------------------------
set m0 [format %08X [rd 0x10000000]]
set m1 [format %08X [rd 0x10000004]]
verdict TC1 "Controle memoire 0x10000000 (2 mots)" "$m0 $m1" "D6F9E3D7 E2D6F8E2"

# --- configuration de depart ---------------------------------------------------------
wr $R_VW 0; wr $R_THR 30; wr $R_MOD 1; wr $R_SRC 0
attendre $PAUSE

# --- TC5 : diagnostic (PL-DISP-002) ------------------------------------------------
verdict TC5 "STATUS (verrouillage, flux, pixels non noirs)" [format 0x%02X [rd $R_ST]] 0x3F

# --- TC2 : maximum sur le Rafale (PL-IP-010, PL-IP-000) ------------------------------
verdict TC2a "Maximum Rafale (valeur,x,y)" [maxi] "182,639,0"

# --- TC3 : maximum sur la mire, trois lectures sur 1 s (PL-IP-001, 003, 010) -------
wr $R_SRC 1; attendre $PAUSE
verdict TC3a "Maximum mire, lecture 1" [maxi] "188,0,0"
attendre 500
verdict TC3b "Maximum mire, lecture 2 (+0,5 s, carre deplace)" [maxi] "188,0,0"
attendre 500
verdict TC3c "Maximum mire, lecture 3 (+1 s)" [maxi] "188,0,0"
wr $R_SRC 0; attendre $PAUSE
verdict TC2b "Maximum Rafale apres retour de la mire" [maxi] "182,639,0"

# --- TC4 : relecture des registres de commande (PL-IP-009, 002, 003, DISP-003) -----
foreach {reg nom vals} [list $R_THR THRESHOLD {60 10 2047 30} $R_MOD MODE {0 1} \
                             $R_SRC SRC_SEL {1 0} $R_VW VIEW {3 11 0}] {
  foreach v $vals {
    wr $reg $v
    verdict TC4 "Ecriture puis relecture $nom = $v" [rd $reg] $v
  }
}
attendre $PAUSE

# --- TC4 suite : le maximum ne depend ni du seuil ni de la vue -----------------------
foreach s {10 60} {
  wr $R_THR $s; attendre $PAUSE
  verdict TC4s "Maximum Rafale avec seuil $s" [maxi] "182,639,0"
}
wr $R_THR 30
foreach v {1 2 3 4} {
  wr $R_VW $v; attendre $PAUSE
  verdict TC4v "Maximum Rafale en vue $v" [maxi] "182,639,0"
}
wr $R_VW 0; attendre $PAUSE

# --- TC8 : gaussien court-circuite (VIEW bit 3), valeurs du modele -------------------
wr $R_VW 8; attendre $PAUSE
verdict TC8a "Maximum Rafale SANS gaussien" [maxi] "484,639,0"
wr $R_SRC 1; attendre $PAUSE
verdict TC8b "Maximum mire SANS gaussien" [maxi] "502,0,0"
wr $R_SRC 0; wr $R_VW 0; attendre $PAUSE
verdict TC8c "Maximum Rafale gaussien retabli" [maxi] "182,639,0"

# --- TC11 : endurance des bascules a chaud (PL-IP-003, anomalie FA-04) -------------
# 40 bascules controlees : apres chaque bascule, le maximum doit etre celui de la
# source demandee ; puis 40 bascules rapides (20 ms) sans controle intermediaire.
set erreurs 0
set src 0
for {set i 1} {$i <= 40} {incr i} {
  set src [expr {1 - $src}]
  wr $R_SRC $src
  attendre [lindex {5 13 29 41 57} [expr {$i % 5}]]
  attendre 200
  set att [expr {$src ? "188,0,0" : "182,639,0"}]
  set got [maxi]
  if {$got ne $att} {
    incr erreurs
    jlog "       bascule $i vers [expr {$src ? {mire} : {Rafale}}] : obtenu $got, attendu $att"
  }
}
verdict TC11a "40 bascules controlees : ecarts" $erreurs 0
for {set i 1} {$i <= 40} {incr i} { wr $R_SRC [expr {$i % 2}]; attendre 20 }
wr $R_SRC 0; attendre $PAUSE
verdict TC11b "Apres 40 bascules rapides : maximum Rafale" [maxi] "182,639,0"
verdict TC11c "Apres bascules : STATUS bit 0 (verrouille)" [expr {[rd $R_ST] & 1}] 1
wr $R_SRC 1; attendre $PAUSE
verdict TC11d "Apres bascules : maximum mire" [maxi] "188,0,0"

# --- remise en etat de depart ------------------------------------------------------
wr $R_VW 0; wr $R_THR 30; wr $R_MOD 1; wr $R_SRC 0
attendre $PAUSE
verdict FIN "Etat final : maximum Rafale" [maxi] "182,639,0"

jlog "------------------------------------------------------------------------------"
jlog " Bilan : $::NOK OK, $::NKO KO"
jlog " Etat de depart retabli : Rafale, overlay, seuil 30, vue normale, gaussien actif"
jlog "=============================================================================="
close $::JF
