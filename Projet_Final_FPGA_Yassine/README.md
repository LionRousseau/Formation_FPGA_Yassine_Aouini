# SoC Tracking

Projet FPGA de détection et de suivi de points d'intérêt sur un flux vidéo, réalisé sur carte Digilent Cora Z7-10 (Zynq-7000).

Yassine Aouini, septembre 2026.

## Présentation

Une image 640 x 480 RGB (avion Rafale) est chargée en DDR à l'adresse 0x10000000 par XSCT. Le DMA (IP HLS DMA24bUnit_mm2s) la relit en continu et la transmet en AXI4-Stream à la partie PL. Une mire interne (TPG) peut remplacer l'image à chaud, la bascule se faisant à la frontière d'image.

La chaîne de traitement est la suivante :

```
source (DMA ou mire) -> luminance -> filtre gaussien 3x3 -> filtre de Harris 3x3 (|reponse|)
                     -> seuil -> overlay (points detectes en vert) -> VGA 640 x 480 @ 60 Hz
```

Le maximum de la réponse et ses coordonnées sont relus par le PS dans les registres AXI4-Lite et affichés sur le terminal série (UART, 115200 bauds).

## Arborescence

| Dossier | Contenu |
|---|---|
| `rtl/` | Sources VHDL-2008 de la partie PL (chaîne de traitement, affichage VGA, registres, sélection de source) |
| `bd/` | Block design Vivado exporté (`write_bd_tcl`) : PS7, DMA, interconnexions AXI, horloge pixel |
| `constraints/` | Contraintes XDC (broches Pmod VGA, horloges) |
| `scripts/` | Scripts Vivado (création, construction), XSCT (programmation, démonstration, essais) et comptage du masque |
| `sw/` | Application PS (`main_step3.c`), script d'édition de liens et exécutable `.elf` |
| `data/` | Image Rafale au format mémoire du DMA (`rafale_640x480_rgb.bin`, 921 600 octets) |
| `ip/` | IP HLS DMA24bUnit_mm2s (fournie par le formateur), utilisée par le block design |
| `export/` | Bitstream, plateforme matérielle `.xsa`, `ps7_init.tcl`, rapports de timing et d'utilisation |
| `sim/` | Bancs de test auto-vérifiants, modèles de référence, scripts de régression GHDL |
| `tools/` | Script Python de génération des images de la démonstration en simulation |
| `livrables/` | Plan de validation, rapport de validation, dossier de preuves IADT, schéma d'architecture, vidéo de bascule de source à chaud |
| `preuves/` | Preuves brutes : journaux de simulation (`T_simulation`), analyses (`A_analyse`), captures sur carte (`D_carte`) |

## Outils

Vivado et Vitis 2020.2, GHDL 4.x (VHDL-2008) pour la simulation, Python 3 avec numpy et pillow pour les modèles de référence et les figures.

## Lancer la démonstration sur carte (sans reconstruire)

Matériel : Cora Z7-10 en mode JTAG (cavalier JP2), Pmod VGA sur les connecteurs JA et JB, écran VGA, câble USB.

1. Alimenter la carte, fermer le Hardware Manager de Vivado, appuyer sur SRST.
2. Ouvrir un terminal série sur le port COM de la Cora (115200 bauds, 8N1).
3. Dans la console XSCT :

```tcl
source {<chemin>/Projet_Final_FPGA_Yassine/scripts/run_v2.tcl}
```

Le script programme le FPGA, initialise le PS, charge l'application, puis charge l'image en DDR avec la commande du SRS (`mwr -bin -file`). Le contrôle mémoire qui suit doit afficher `D6F9E3D7 E2D6F8E2`.

4. Pour les commandes de démonstration :

```tcl
source {<chemin>/Projet_Final_FPGA_Yassine/scripts/demo_v2.tcl}
aide
```

| Commande | Effet |
|---|---|
| `rafale` / `mire` | Source vidéo : image DDR ou mire interne |
| `overlay` / `brut` | Mode B (points détectés en vert) ou mode A (image naturelle) |
| `seuil <n>` | Seuil de binarisation |
| `normale`, `luminance`, `gaussien`, `reponse`, `masque` | Vue affichée (étage de la chaîne) |
| `sans_gauss` / `avec_gauss` | Court-circuit du filtre gaussien |
| `maxi`, `etat` | Lecture du maximum et de l'état des registres |
| `demo_reset` | Retour à la configuration de départ |

`scripts/essais_v2.tcl` enchaîne les essais chiffrés automatiques et écrit un journal dans `preuves/D_carte/`.

## Reconstruire le matériel

Dans la console Tcl de Vivado 2020.2 :

```tcl
source {<chemin>/Projet_Final_FPGA_Yassine/scripts/create_project_v2.tcl}
source {<chemin>/Projet_Final_FPGA_Yassine/scripts/rebuild_v2.tcl}
```

Le premier script crée le projet dans `vivado/` (non versionné), ajoute les sources, recrée le block design et règle l'horloge pixel. Le second lance la synthèse, l'implémentation et la génération du bitstream, puis exporte les fichiers dans `export/`.

L'IP HLS `DMA24bUnit_mm2s` fournie par le formateur est dans `ip/`. Le script la cherche dans cet ordre : variable d'environnement `DMA_IP_REPO`, dossier `ip/`, puis son emplacement d'origine sur le poste de développement.

L'application PS se reconstruit dans Vitis 2020.2 à partir de `export/design_1_wrapper_v2.xsa`, avec `sw/main_step3.c` et `sw/lscript.ld`.

## Simulation

Depuis `sim/`, avec GHDL dans le PATH :

```sh
./run_all.sh       # 15 bancs unitaires et d'integration, tableau de verdicts
./run_preuves.sh   # tous les bancs + contre-epreuves, journaux dans preuves/T_simulation
./run_demo.sh      # demonstration sur l'image reelle avec le harnais du formateur (sim/reftb)
```

Chaque banc est auto-vérifiant : il compare la sortie du RTL à un modèle de référence (`ref_pkg.vhd`), compte les erreurs et se termine par une assertion `errors = 0` et un verdict SUCCES ou ECHEC. Les contre-épreuves vérifient que les bancs détectent bien les défauts connus : `tb_vga_display` sur les fichiers VGA de la version précédente (`sim/contre_epreuves/v1.0_vga`) et `tb_switch_sys` sur un mutant du sélecteur de source (`sim/mutants`). Les deux doivent échouer.

`check_views.py` est le modèle numpy de la chaîne complète utilisé pour les valeurs attendues sur carte (maximum, nombre de points détectés).

## Carte des registres (base 0x43C00000)

| Offset | Nom | Accès | Contenu |
|---|---|---|---|
| 0x00 | MAX_VAL | RO | Réponse maximale de la dernière image |
| 0x04 | MAX_X | RO | Colonne du maximum |
| 0x08 | MAX_Y | RO | Ligne du maximum |
| 0x0C | THRESHOLD | RW | Seuil de binarisation (30 au démarrage) |
| 0x10 | MODE | RW | bit 0 : mode d'affichage A (0) ou B (1) |
| 0x14 | SRC_SEL | RW | bit 0 : source mémoire (0) ou mire (1) |
| 0x18 | STATUS | RO | Diagnostic (verrouillage horloge, activité du flux) |
| 0x1C | VIEW | RW | bits 2:0 : vue affichée, bit 3 : gaussien court-circuité |

Les registres MAX_* sont échantillonnés en fin d'image, ce qui garantit un triplet cohérent.

## Plan mémoire

| Zone | Adresses | Taille |
|---|---|---|
| Application PS (code et données) | 0x00100000 à 0x0010D82F | 54 Ko |
| Image Rafale lue par le DMA | 0x10000000 à 0x100E0FFF | 921 600 octets |
| DDR de la Cora Z7-10 | 0x00000000 à 0x1FFFFFFF | 512 Mo |
| Registres du module vidéo (AXI4-Lite, M_AXI_GP0) | 0x43C00000 à 0x43C0001F | 32 octets |

L'application est placée par `sw/lscript.ld` au début de la DDR ; l'image se trouve 255 Mo plus loin, sans recouvrement.

## Résultats principaux

| Mesure | Valeur |
|---|---|
| Bancs de test | 19 bancs auto-vérifiants en succès, 2 contre-épreuves en échec attendu |
| Fermeture de timing | WNS = +3,802 ns, aucun chemin en échec |
| Ressources | 10 229 LUT (58 %), 13 255 registres (38 %), 6 BRAM (10 %), 2 DSP (2,5 %) |
| Horloge pixel | 25,174 MHz (écart de 41 ppm, tolérance VESA 0,5 %), 59,94 images/s |
| Maximum sur carte, image Rafale | 182 en (639, 0) |
| Maximum sur carte, mire | 188 en (0, 0) |
| Points détectés sur carte (seuils 10 / 30 / 60) | 16 754 / 7 878 / 2 887, pour 16 939 / 7 982 / 2 923 attendus (écart inférieur à 1,5 %) |

Le détail de la méthode (inspection, analyse, démonstration, test) et l'ensemble des résultats sont dans `livrables/Rapport_Validation_SoC_Tracking.pdf` et `livrables/Dossier_Preuves_IADT_SoC_Tracking.pdf`.

## Limites connues

Les pixels du pourtour de l'image sont mis à zéro dans les filtres ; le maximum peut donc se trouver sur le bord de l'image (cas de l'image Rafale). Lors d'une bascule de source, l'écran peut rester noir quelques instants, le temps que le moniteur se resynchronise.
