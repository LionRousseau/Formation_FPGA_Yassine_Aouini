--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : processing_chain.vhd
-- Description : Chaine de traitement complete (coeur du projet). Assemble :
--
--   source RGB --+--> luminance --> gaussien --> laplacien --> binarisation --+
--                |                                   |                        |
--                |                                   +--> suivi du maximum    |
--                |                                                            v
--                +--> ligne a retard (latence chaine, ED-02) ----> overlay --> sortie RGB
--
--   - Bifurcation (fork) de la source vers la branche de traitement et la
--     branche brute, en verrou de pas (lockstep) : les deux branches consomment
--     les memes pixels au meme instant.
--   - La ligne a retard compense EXACTEMENT la latence de la branche de
--     traitement, de sorte que le masque et le pixel brut arrivent ensemble a
--     l'overlay (ED-02, cas TC-I-03).
--   - Propagation de tuser/tlast de bout en bout (ED-03).
--
--   Latence de la branche de traitement (en transferts) :
--     luminance(1) + gaussien(IMG_W+3) + laplacien(IMG_W+3) + binarisation(1)
--     = 2*IMG_W + 8
--
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity processing_chain is
  generic (
    IMG_W : natural := C_IMG_WIDTH;
    IMG_H : natural := C_IMG_HEIGHT
  );
  port (
    clk        : in  std_logic;
    resetn     : in  std_logic;
    -- controle (banc de registres PS)
    threshold  : in  unsigned(C_RESP_W-1 downto 0);
    mode       : in  std_logic;                             -- '0'=A, '1'=B
    ovl_color  : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    -- entree source RGB (AXI4-Stream)
    s_tdata    : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    s_tvalid   : in  std_logic;
    s_tready   : out std_logic;
    s_tuser    : in  std_logic;
    s_tlast    : in  std_logic;
    -- sortie affichage RGB (AXI4-Stream)
    m_tdata    : out std_logic_vector(3*C_COMP_W-1 downto 0);
    m_tvalid   : out std_logic;
    m_tready   : in  std_logic;
    m_tuser    : out std_logic;
    m_tlast    : out std_logic;
    -- retour de donnees suivi du maximum
    max_val    : out unsigned(C_RESP_W-1 downto 0);
    max_x      : out unsigned(C_X_W-1 downto 0);
    max_y      : out unsigned(C_Y_W-1 downto 0);
    frame_tick : out std_logic;
    -- v2 : demonstration des etages (registre VIEW), defauts = v1.0
    view         : in  std_logic_vector(2 downto 0) := "000";
    gauss_bypass : in  std_logic := '0'
  );
end entity processing_chain;

architecture rtl of processing_chain is
  constant CHAIN_LAT : natural := 2*IMG_W + 8;

  -- bifurcation
  signal p_s_tvalid, p_s_tready : std_logic;   -- vers luminance
  signal r_s_tvalid, r_s_tready : std_logic;   -- vers ligne a retard

  -- luminance -> gaussien
  signal lum_tdata : std_logic_vector(C_LUMA_W-1 downto 0);
  signal lum_tvalid, lum_tready, lum_tuser, lum_tlast : std_logic;
  -- gaussien -> laplacien
  signal g_tdata : std_logic_vector(C_LUMA_W-1 downto 0);
  signal g_tvalid, g_tready, g_tuser, g_tlast : std_logic;
  -- laplacien -> binarisation (+ tap max)
  signal l_tdata : std_logic_vector(C_RESP_W-1 downto 0);
  signal l_tvalid, l_tready, l_tuser, l_tlast : std_logic;
  -- binarisation -> overlay (a)
  signal b_tdata : std_logic_vector(0 downto 0);
  -- v2 : bandes laterales alignees (sortie gaussien, reponse bornee a 255)
  signal l_center : std_logic_vector(C_LUMA_W-1 downto 0);
  signal resp8    : std_logic_vector(7 downto 0);
  signal side_in  : std_logic_vector(15 downto 0);
  signal side_out : std_logic_vector(15 downto 0);
  signal b_tvalid, b_tready, b_tuser, b_tlast : std_logic;
  -- ligne a retard -> overlay (b)
  signal r_tdata : std_logic_vector(3*C_COMP_W-1 downto 0);
  signal r_tvalid, r_tready, r_tuser, r_tlast : std_logic;
begin

  ----------------------------------------------------------------------------
  -- Bifurcation lockstep de la source.
  ----------------------------------------------------------------------------
  s_tready   <= p_s_tready and r_s_tready;
  p_s_tvalid <= s_tvalid and r_s_tready;
  r_s_tvalid <= s_tvalid and p_s_tready;

  ----------------------------------------------------------------------------
  -- Branche de traitement.
  ----------------------------------------------------------------------------
  u_luma : entity work.rgb_to_luma
    port map (
      clk => clk, resetn => resetn,
      s_tdata => s_tdata, s_tvalid => p_s_tvalid, s_tready => p_s_tready,
      s_tuser => s_tuser, s_tlast => s_tlast,
      m_tdata => lum_tdata, m_tvalid => lum_tvalid, m_tready => lum_tready,
      m_tuser => lum_tuser, m_tlast => lum_tlast);

  u_gauss : entity work.gaussian_filter
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn,
      s_tdata => lum_tdata, s_tvalid => lum_tvalid, s_tready => lum_tready,
      s_tuser => lum_tuser, s_tlast => lum_tlast,
      m_tdata => g_tdata, m_tvalid => g_tvalid, m_tready => g_tready,
      m_tuser => g_tuser, m_tlast => g_tlast,
      bypass => gauss_bypass);

  u_lapl : entity work.laplacian_filter
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn,
      s_tdata => g_tdata, s_tvalid => g_tvalid, s_tready => g_tready,
      s_tuser => g_tuser, s_tlast => g_tlast,
      m_tdata => l_tdata, m_tvalid => l_tvalid, m_tready => l_tready,
      m_tuser => l_tuser, m_tlast => l_tlast,
      m_center => l_center);

  -- reponse ramenee sur 8 bits pour l'affichage : bornee a 255 (les reponses
  -- utiles sont faibles, une division les rendrait invisibles)
  resp8   <= x"FF" when unsigned(l_tdata) > 255 else l_tdata(7 downto 0);
  side_in <= l_center & resp8;

  u_bin : entity work.binarize
    generic map (SIDE_W => 16)
    port map (
      clk => clk, resetn => resetn, thresh => threshold,
      s_tdata => l_tdata, s_tvalid => l_tvalid, s_tready => l_tready,
      s_tuser => l_tuser, s_tlast => l_tlast,
      m_tdata => b_tdata, m_tvalid => b_tvalid, m_tready => b_tready,
      m_tuser => b_tuser, m_tlast => b_tlast,
      s_side => side_in, m_side => side_out);

  ----------------------------------------------------------------------------
  -- Suivi du maximum en derivation sur le flux laplacien.
  ----------------------------------------------------------------------------
  u_max : entity work.max_tracker
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn,
      in_data => l_tdata, in_valid => l_tvalid, in_ready => l_tready,
      in_sof => l_tuser,
      max_val => max_val, max_x => max_x, max_y => max_y,
      frame_tick => frame_tick);

  ----------------------------------------------------------------------------
  -- Branche brute retardee (ED-02).
  ----------------------------------------------------------------------------
  u_delay : entity work.stream_delay
    generic map (DATA_W => 3*C_COMP_W, DEPTH => CHAIN_LAT, NPIX => IMG_W*IMG_H)
    port map (
      clk => clk, resetn => resetn,
      s_tdata => s_tdata, s_tvalid => r_s_tvalid, s_tready => r_s_tready,
      s_tuser => s_tuser, s_tlast => s_tlast,
      m_tdata => r_tdata, m_tvalid => r_tvalid, m_tready => r_tready,
      m_tuser => r_tuser, m_tlast => r_tlast);

  ----------------------------------------------------------------------------
  -- Overlay (jointure).
  ----------------------------------------------------------------------------
  u_ovl : entity work.overlay
    port map (
      clk => clk, resetn => resetn, mode => mode, ovl_color => ovl_color,
      a_tdata => b_tdata, a_tvalid => b_tvalid, a_tready => b_tready,
      a_tuser => b_tuser, a_tlast => b_tlast,
      b_tdata => r_tdata, b_tvalid => r_tvalid, b_tready => r_tready,
      b_tuser => r_tuser, b_tlast => r_tlast,
      m_tdata => m_tdata, m_tvalid => m_tvalid, m_tready => m_tready,
      m_tuser => m_tuser, m_tlast => m_tlast,
      view => view, a_side => side_out);

end architecture rtl;
