#-------------------------------------------------------------------------------
# demo_v2.tcl  -  commandes nommees pour la demonstration SoC Tracking v2.
# A charger dans la console XSCT APRES run_v2.tcl (carte programmee) :
#   source {<depot>/scripts/demo_v2.tcl}
# Puis taper : aide
#
# Toutes les commandes ecrivent/lisent le banc de registres du module video
# (base 0x43C00000). Les vues et le court-circuit du gaussien sont des
# fonctions de demonstration de la v2 (registre VIEW 0x1C, hors SRS).
#-------------------------------------------------------------------------------
set ::REG_BASE 0x43C00000


proc _adr {off} { return [format 0x%08X [expr {$::REG_BASE + $off}]] }
# lecture de n mots : mrd -value si disponible, sinon analyse du texte de mrd
proc _rdn {adr n} {
  if {![catch {set v [mrd -value $adr $n]}]} { return $v }
  set out {}
  foreach {- h} [regexp -all -inline {:\s*([0-9A-Fa-f]{8})} [mrd $adr $n]] { lappend out [expr {"0x$h"}] }
  return $out
}
proc _rd  {off} { return [expr {[lindex [_rdn [_adr $off] 1] 0]}] }
proc _wr  {off v} { mwr [_adr $off] $v }

# --- source video (PL-IP-002 / PL-IP-003) -----------------------------------
proc rafale {} { _wr 0x14 0; puts "Source : image DDR (Rafale) via DMA   \[SRC_SEL=0\]" }
proc mire   {} { _wr 0x14 1; puts "Source : mire interne (TPG)           \[SRC_SEL=1\]" }

# --- mode d'affichage (PL-DISP-003) -----------------------------------------
proc overlay {} { _wr 0x10 1; puts "Mode B : points detectes en vert      \[MODE=1\]" }
proc brut    {} { _wr 0x10 0; puts "Mode A : image naturelle              \[MODE=0\]" }

# --- seuil (PL-IP-009) --------------------------------------------------------
proc seuil {n} {
  _wr 0x0C $n
  puts "Seuil = $n (pris en compte a l'image suivante)  \[THRESHOLD\]"
}

# --- vues de demonstration (v2, registre VIEW 0x1C) ---------------------------
proc _vue {n nom} {
  set v [_rd 0x1C]
  _wr 0x1C [expr {($v & 8) | $n}]
  set g [expr {($v & 8) ? "SANS gaussien" : "avec gaussien"}]
  puts "Vue $n : $nom ($g)"
}
proc normale   {} { _vue 0 "normale (brute ou overlay selon le mode)" }
proc luminance {} { _vue 1 "luminance (niveaux de gris)" }
proc gaussien  {} { _vue 2 "sortie du filtre gaussien" }
proc reponse   {} { _vue 3 "reponse du filtre de Harris" }
proc masque    {} { _vue 4 "masque binaire apres seuil" }
proc sans_gauss {} {
  set v [_rd 0x1C]; _wr 0x1C [expr {$v | 8}]
  puts "Filtre gaussien COURT-CIRCUITE (detection sur la luminance brute)"
}
proc avec_gauss {} {
  set v [_rd 0x1C]; _wr 0x1C [expr {$v & 7}]
  puts "Filtre gaussien ACTIF"
}

# --- retour de donnees (PL-IP-010) ------------------------------------------
proc maxi {} {
  set l [_rdn [_adr 0x00] 3]
  puts [format "Maximum = %d  en  (x = %d, y = %d)" \
          [expr {[lindex $l 0]}] [expr {[lindex $l 1]}] [expr {[lindex $l 2]}]]
}

# --- etat complet -------------------------------------------------------------
proc etat {} {
  set src [_rd 0x14]; set mode [_rd 0x10]; set thr [_rd 0x0C]
  set view [_rd 0x1C]; set st [_rd 0x18]
  set noms {normale luminance gaussien reponse masque ? ? ?}
  puts "------------------------------------------------------------"
  puts [format "Source   : %s" [expr {($src & 1) ? "mire" : "Rafale (DMA)"}]]
  puts [format "Mode     : %s" [expr {($mode & 1) ? "B overlay" : "A naturel"}]]
  puts [format "Seuil    : %d" $thr]
  puts [format "Vue      : %d (%s), gaussien %s" [expr {$view & 7}] \
          [lindex $noms [expr {$view & 7}]] [expr {($view & 8) ? "court-circuite" : "actif"}]]
  puts [format "STATUS   : 0x%02X  (verrouille maintenant : %s)" $st [expr {($st & 1) ? "oui" : "NON"}]]
  maxi
  puts "------------------------------------------------------------"
}

# --- remise en configuration de depart ---------------------------------------
proc demo_reset {} {
  _wr 0x1C 0; _wr 0x0C 30; _wr 0x10 1; _wr 0x14 0
  puts "Configuration de depart : Rafale, overlay, seuil 30, vue normale, gaussien actif"
}

proc aide {} {
  puts "------------------------------------------------------------"
  puts " Source     : rafale | mire"
  puts " Mode       : overlay | brut"
  puts " Vues       : normale | luminance | gaussien | reponse | masque"
  puts " Filtre     : sans_gauss | avec_gauss"
  puts " Seuil      : seuil <n>   (ex. seuil 10, seuil 60)"
  puts " Mesure     : maxi | etat"
  puts " Reprise    : demo_reset"
  puts "------------------------------------------------------------"
}

# Connexion en dernier : les commandes ci-dessus restent definies meme si
# la connexion echoue (on peut alors la refaire a la main).
if {[catch {targets -set -filter {name =~ "*Cortex-A9*#0"}}]} {
  if {[catch {connect; targets -set -filter {name =~ "*Cortex-A9*#0"}} err]} {
    puts "ATTENTION : connexion JTAG impossible ($err). Commandes chargees quand meme."
  }
}
catch {configparams force-mem-access 1}

puts "Commandes de demonstration chargees. Taper : aide"
