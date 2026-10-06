--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : vga_pkg.vhd
-- Description : Constantes de temporisation VGA 640x480 @ 60 Hz (PL-DISP-002).
--               Standard industriel, horloge pixel 25,175 MHz.
--
--   Horizontal (en pixels)      Vertical (en lignes)
--     visible    640              visible    480
--     front porch 16              front porch 10
--     sync        96              sync         2
--     back porch  48              back porch  33
--     total      800              total      525
--
--   Polarite hsync et vsync : negative (active bas).
--   Cadence trame = 25,175e6 / (800*525) = 59,94 Hz.
--
--   Le Pmod VGA Digilent est en 4 bits par composante (reseau R-2R), soit un
--   format 4:4:4. La sortie tronque le RGB 8 bits en gardant les 4 bits de poids
--   fort de chaque composante.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package vga_pkg is
  -- horizontal
  constant H_VISIBLE : natural := 640;
  constant H_FRONT   : natural := 16;
  constant H_SYNC    : natural := 96;
  constant H_BACK    : natural := 48;
  constant H_TOTAL   : natural := H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   -- 800

  -- vertical
  constant V_VISIBLE : natural := 480;
  constant V_FRONT   : natural := 10;
  constant V_SYNC    : natural := 2;
  constant V_BACK    : natural := 33;
  constant V_TOTAL   : natural := V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   -- 525

  -- fenetres de synchro (bornes en comptes)
  constant H_SYNC_START : natural := H_VISIBLE + H_FRONT;                  -- 656
  constant H_SYNC_END   : natural := H_VISIBLE + H_FRONT + H_SYNC;         -- 752
  constant V_SYNC_START : natural := V_VISIBLE + V_FRONT;                  -- 490
  constant V_SYNC_END   : natural := V_VISIBLE + V_FRONT + V_SYNC;         -- 492

  -- largeurs de compteurs
  constant HC_W : natural := 10;   -- 0..799
  constant VC_W : natural := 10;   -- 0..524

  constant VGA_COMP_W : natural := 4;   -- bits par composante Pmod VGA
end package vga_pkg;
