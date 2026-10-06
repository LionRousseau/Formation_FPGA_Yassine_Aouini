--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : rgb_to_luma.vhd
-- Description : Etage de conversion RGB 8:8:8 -> luminance 8 bits (ED-01, PO-04),
--               place en amont du filtre gaussien.
--
--               tdata d'entree (24 bits) : R = bits 23..16, G = 15..8, B = 7..0.
--               BT.601 approximee par decalages (aucun multiplieur) :
--                 Y = (R>>2)+(R>>4) + (G>>1)+(G>>4) + (B>>3)
--                 poids dyadiques 5/16, 9/16, 2/16 (somme = 1)
--               Sortie bornee a [0,255].
--
--               Etage pipeline a une avance de latence, handshake AXI4-Stream a
--               gel global (lossless). tuser/tlast propages (ED-03).
--
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity rgb_to_luma is
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;
    s_tdata  : in  std_logic_vector(3*C_COMP_W-1 downto 0);   -- 24 bits RGB
    s_tvalid : in  std_logic;
    s_tready : out std_logic;
    s_tuser  : in  std_logic;
    s_tlast  : in  std_logic;
    m_tdata  : out std_logic_vector(C_LUMA_W-1 downto 0);     -- 8 bits luminance
    m_tvalid : out std_logic;
    m_tready : in  std_logic;
    m_tuser  : out std_logic;
    m_tlast  : out std_logic
  );
end entity rgb_to_luma;

architecture rtl of rgb_to_luma is
  signal en      : std_logic;
  signal ready_i : std_logic;
  signal val_r   : std_logic := '0';
  signal sof_r   : std_logic := '0';
  signal eol_r   : std_logic := '0';
  signal y_r     : unsigned(C_LUMA_W-1 downto 0) := (others => '0');
begin
  ready_i  <= m_tready or (not val_r);
  s_tready <= ready_i;
  en       <= s_tvalid and ready_i;

  process(clk, resetn)
    variable r, g, b, y : integer;
  begin
    if resetn = '0' then
      y_r <= (others => '0'); val_r <= '0'; sof_r <= '0'; eol_r <= '0';
    elsif rising_edge(clk) then
      if en = '1' then
        r := to_integer(unsigned(s_tdata(3*C_COMP_W-1 downto 2*C_COMP_W)));
        g := to_integer(unsigned(s_tdata(2*C_COMP_W-1 downto   C_COMP_W)));
        b := to_integer(unsigned(s_tdata(  C_COMP_W-1 downto          0)));
        y := (r/4) + (r/16) + (g/2) + (g/16) + (b/8);
        y := clamp_u(y, C_LUMA_W);
        y_r   <= to_unsigned(y, C_LUMA_W);
        val_r <= s_tvalid;
        sof_r <= s_tuser;
        eol_r <= s_tlast;
      elsif m_tready = '1' then
        val_r <= '0';                  -- drain apres consommation (TC-U-07)
      end if;
    end if;
  end process;

  m_tdata  <= std_logic_vector(y_r);
  m_tvalid <= val_r;
  m_tuser  <= sof_r;
  m_tlast  <= eol_r;
end architecture rtl;
