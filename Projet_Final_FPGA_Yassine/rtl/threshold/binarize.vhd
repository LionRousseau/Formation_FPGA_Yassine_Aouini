--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : binarize.vhd
-- Description : Etage de binarisation par seuillage (PL-IP-008 / PL-IP-009).
--               La sortie vaut 1 lorsque la reponse d'entree est superieure ou
--               egale au seuil, 0 sinon (PL-IP-008 : 0 sous le seuil, 1 au seuil
--               et au-dessus).
--
--               Le seuil (thresh) est parametrable a chaud par le PS via le banc
--               de registres. Pour eviter toute image corrompue, la valeur vive
--               est verrouillee en debut de trame (sur tuser) : un changement de
--               seuil est donc pris en compte a la trame suivante (TC-U-05).
--
--               Etage pipeline a une avance de latence, handshake AXI4-Stream a
--               gel global.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity binarize is
  generic (
    SIDE_W : natural := 1             -- v2 : largeur de la bande laterale
  );
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;
    thresh   : in  unsigned(C_RESP_W-1 downto 0);         -- seuil vif (du PS)
    s_tdata  : in  std_logic_vector(C_RESP_W-1 downto 0); -- |laplacien|
    s_tvalid : in  std_logic;
    s_tready : out std_logic;
    s_tuser  : in  std_logic;
    s_tlast  : in  std_logic;
    m_tdata  : out std_logic_vector(0 downto 0);          -- masque binaire
    m_tvalid : out std_logic;
    m_tready : in  std_logic;
    m_tuser  : out std_logic;
    m_tlast  : out std_logic;
    -- v2 : bande laterale transportee en phase avec le masque (vues de
    -- l'overlay). Valeur par defaut : inutilisee.
    s_side   : in  std_logic_vector(SIDE_W-1 downto 0) := (others => '0');
    m_side   : out std_logic_vector(SIDE_W-1 downto 0)
  );
end entity binarize;

architecture rtl of binarize is
  signal en        : std_logic;
  signal ready_i   : std_logic;
  signal val_r     : std_logic := '0';
  signal sof_r     : std_logic := '0';
  signal eol_r     : std_logic := '0';
  signal bit_r     : std_logic := '0';
  signal side_r    : std_logic_vector(SIDE_W-1 downto 0) := (others => '0');
  signal thr_latch : unsigned(C_RESP_W-1 downto 0) := (others => '0');
begin
  ready_i  <= m_tready or (not val_r);
  s_tready <= ready_i;
  en       <= s_tvalid and ready_i;

  process(clk, resetn)
    variable v : unsigned(C_RESP_W-1 downto 0);
  begin
    if resetn = '0' then
      val_r <= '0'; sof_r <= '0'; eol_r <= '0'; bit_r <= '0';
      side_r <= (others => '0');
      thr_latch <= (others => '0');
    elsif rising_edge(clk) then
      if en = '1' then
        -- verrouillage du seuil en debut de trame
        if s_tuser = '1' then
          thr_latch <= thresh;
          v := thresh;
        else
          v := thr_latch;
        end if;
        if unsigned(s_tdata) >= v then
          bit_r <= '1';
        else
          bit_r <= '0';
        end if;
        val_r <= s_tvalid;
        side_r <= s_side;
        sof_r <= s_tuser;
        eol_r <= s_tlast;
      elsif m_tready = '1' then
        val_r <= '0';                  -- drain apres consommation (TC-U-07)
      end if;
    end if;
  end process;

  m_tdata(0) <= bit_r;
  m_tvalid   <= val_r;
  m_tuser    <= sof_r;
  m_tlast    <= eol_r;
  m_side     <= side_r;
end architecture rtl;
