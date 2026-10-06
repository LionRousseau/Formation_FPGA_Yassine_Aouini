--------------------------------------------------------------------------------
-- vga_pkg_mid : format VGA reduit (32x16 visibles) pour les simulations
-- systeme rapides (tb_switch_sys). Memes noms de constantes que vga_pkg ;
-- a compiler A LA PLACE de rtl/disp/vga_pkg.vhd, uniquement en simulation.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
package vga_pkg is
  constant H_VISIBLE : natural := 32;
  constant H_FRONT   : natural := 2;
  constant H_SYNC    : natural := 4;
  constant H_BACK    : natural := 2;
  constant H_TOTAL   : natural := H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   -- 40
  constant V_VISIBLE : natural := 16;
  constant V_FRONT   : natural := 1;
  constant V_SYNC    : natural := 1;
  constant V_BACK    : natural := 2;
  constant V_TOTAL   : natural := V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   -- 20
  constant H_SYNC_START : natural := H_VISIBLE + H_FRONT;
  constant H_SYNC_END   : natural := H_VISIBLE + H_FRONT + H_SYNC;
  constant V_SYNC_START : natural := V_VISIBLE + V_FRONT;
  constant V_SYNC_END   : natural := V_VISIBLE + V_FRONT + V_SYNC;
  constant HC_W : natural := 6;
  constant VC_W : natural := 6;
  constant VGA_COMP_W : natural := 4;
end package vga_pkg;
