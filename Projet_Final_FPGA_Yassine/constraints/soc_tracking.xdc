## =============================================================================
## SoC Tracking - contraintes carte Cora Z7-10 (xc7z010clg400-1)
## Broches issues du fichier maitre Digilent (Cora-Z7-10-Master.xdc, fourni par
## le formateur). Ce fichier n'active que ce dont le projet a besoin.
##
## NOTE : l'horloge pixel 25 MHz est derivee de l'oscillateur 125 MHz de la
## carte (broche H16, port sysclk) via la Clocking Wizard du block design.
## Le domaine AXI (PS, interconnexion, GPIO) reste cadence par FCLK_CLK0.
## =============================================================================

## --- Oscillateur systeme 125 MHz (broche H16), entree de la Clocking Wizard --
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { sysclk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sysclk }];

## --- Sortie Pmod VGA (Digilent Pmod VGA, format 4:4:4) ----------------------
## Broches Cora : ja[0..3]=Y18,Y19,Y16,Y17 ; ja[4..7]=U18,U19,W18,W19
##                jb[0..3]=W14,Y14,T11,T10 ; jb[4..5]=V16,W16

## Rouge (Pmod JA, broches 1..4)
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }];
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }];
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }];
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }];
## Bleu (Pmod JA, broches 7..10)
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }];
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }];
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }];
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }];
## Vert (Pmod JB, broches 1..4)
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }];
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }];
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }];
## Synchros (Pmod JB, broches 7..8)
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { vga_hsync }];
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports { vga_vsync }];

## --- LED RGB de la carte (pilotees par les deux AXI GPIO du block design) ----
## Necessaires pour que le bitstream se genere (ports sinon non contraints).
## LED0 : led_tri_o[0]=bleu, [1]=vert, [2]=rouge
set_property -dict { PACKAGE_PIN L15 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[0] }];
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[1] }];
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[2] }];
## LED1 : led2_tri_o[0]=bleu, [1]=vert, [2]=rouge
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { led2_tri_o[0] }];
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports { led2_tri_o[1] }];
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { led2_tri_o[2] }];

## Les sorties VGA sont a 25 MHz (horloge pixel), largement relachees vis-a-vis
## des IO ; aucune contrainte de timing d'IO specifique n'est requise ici.
