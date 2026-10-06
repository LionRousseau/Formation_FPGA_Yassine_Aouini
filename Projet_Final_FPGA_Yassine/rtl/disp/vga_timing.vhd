--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : vga_timing.vhd
-- Description : Generateur de temporisation VGA 640x480 @ 60 Hz (PL-DISP-002).
--               Compteurs pixel/ligne libres, signaux de synchronisation hsync
--               et vsync (actifs bas), zone active, coordonnees (x,y) et
--               impulsions de debut de ligne / trame.
--
--               Entree sync_lock : lorsqu'elle est active, les compteurs sont
--               ramenes a (0,0). Elle permet de verrouiller le balayage sur le
--               debut de trame d'un flux video amont (genlock), afin d'absorber
--               la latence de la chaine de traitement. Laisser a '0' pour un
--               balayage libre (mire directe).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vga_pkg.all;

entity vga_timing is
  port (
    clk       : in  std_logic;       -- horloge pixel 25,175 MHz
    resetn    : in  std_logic;
    sync_lock : in  std_logic;       -- genlock : remet les compteurs a (0,0)
    hcount    : out unsigned(HC_W-1 downto 0);
    vcount    : out unsigned(VC_W-1 downto 0);
    x         : out unsigned(HC_W-1 downto 0);   -- coordonnee active (=hcount)
    y         : out unsigned(VC_W-1 downto 0);   -- coordonnee active (=vcount)
    hsync     : out std_logic;       -- actif bas
    vsync     : out std_logic;       -- actif bas
    active    : out std_logic;       -- zone video active
    frame_beg : out std_logic;       -- impulsion : (hcount=0, vcount=0)
    line_beg  : out std_logic        -- impulsion : hcount=0
  );
end entity vga_timing;

architecture rtl of vga_timing is
  signal hc : unsigned(HC_W-1 downto 0) := (others => '0');
  signal vc : unsigned(VC_W-1 downto 0) := (others => '0');
begin
  process(clk, resetn)
  begin
    if resetn = '0' then
      hc <= (others => '0');
      vc <= (others => '0');
    elsif rising_edge(clk) then
      if sync_lock = '1' then
        hc <= (others => '0');
        vc <= (others => '0');
      elsif hc = H_TOTAL-1 then
        hc <= (others => '0');
        if vc = V_TOTAL-1 then
          vc <= (others => '0');
        else
          vc <= vc + 1;
        end if;
      else
        hc <= hc + 1;
      end if;
    end if;
  end process;

  hcount <= hc;
  vcount <= vc;
  x      <= hc;
  y      <= vc;

  hsync  <= '0' when (hc >= H_SYNC_START and hc < H_SYNC_END) else '1';
  vsync  <= '0' when (vc >= V_SYNC_START and vc < V_SYNC_END) else '1';
  active <= '1' when (hc < H_VISIBLE and vc < V_VISIBLE) else '0';

  frame_beg <= '1' when (hc = 0 and vc = 0) else '0';
  line_beg  <= '1' when (hc = 0) else '0';
end architecture rtl;
