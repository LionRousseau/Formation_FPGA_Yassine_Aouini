--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : tb_environnement.vhd
-- Description : Banc de test au format du formateur (harnais REF-TB) : le driver
--               AXI4-Stream lit l'image reelle en niveaux de gris
--               (sample_in_gray.txt, 640x480, format ImageJ), la chaine de
--               detection (gaussien -> laplacien -> binarisation) est intercalee,
--               et le moniteur capture la carte binaire de points d'interet.
--
--               Convention du harnais : le driver ne genere pas de tuser (SOF).
--               On le reconstruit ici par un compteur de pixels (SOF = pixel 0
--               de chaque trame) et on le propage a la chaine. Le moniteur cadre
--               sa capture sur le tuser de sortie (G_SYNC_ON_SOF).
--
--               Deux trames sont injectees : la premiere amorce les line buffers,
--               la seconde (stream_out_1.txt) est l'image de detection exploitable.
--
--               Ce banc reproduit la methode de verification du formateur
--               (Axi4s_driver -> IP etudiant -> Axi4s_monitor) appliquee a notre
--               chaine, sur l'image reelle.
-- Norme       : VHDL-2008 (driver/moniteur du formateur inclus tels quels)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tb_environnement is
  generic (
    C_IMG_WIDTH  : integer := 640;
    C_IMG_HEIGHT : integer := 480;
    C_THRESHOLD  : integer := 30;   -- seuil de binarisation (|laplacien|)
    C_NFRAMES    : integer := 1;     -- trames injectees / capturees
    C_IN_FILE    : string  := "../data/sample_in_gray.txt";
    C_OUT_BASE   : string  := "corner"
  );
end entity tb_environnement;

architecture sim of tb_environnement is
  constant NPIX : integer := C_IMG_WIDTH * C_IMG_HEIGHT;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';   -- reset actif haut (convention du harnais)
  signal resetn : std_logic;

  -- driver -> chaine
  signal drv_tvalid, drv_tlast, drv_tready : std_logic;
  signal drv_tdata : std_logic_vector(7 downto 0);
  signal drv_done  : std_logic;
  signal drv_fcnt, drv_pcnt : integer;

  -- SOF reconstruit
  signal pcnt   : integer := 0;
  signal sof    : std_logic;

  -- gaussien -> laplacien
  signal g_td : std_logic_vector(C_LUMA_W-1 downto 0);
  signal g_tv, g_tr, g_tu, g_tl : std_logic;
  -- laplacien -> binarisation
  signal l_td : std_logic_vector(C_RESP_W-1 downto 0);
  signal l_tv, l_tr, l_tu, l_tl : std_logic;
  -- binarisation -> moniteur
  signal b_td : std_logic_vector(0 downto 0);
  signal b_tv, b_tr, b_tu, b_tl : std_logic;

  signal mon_done : std_logic;
  signal mon_img, mon_line, mon_pix : integer;
begin
  clk    <= not clk after 5 ns;         -- 100 MHz (convention du harnais)
  resetn <= not rst;

  -- reset
  process
  begin
    rst <= '1';
    wait for 53 ns;
    rst <= '0';
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Driver du formateur : lit l'image reelle, la debite en AXI4-Stream 8 bits,
  -- deux passages (deux trames).
  ----------------------------------------------------------------------------
  u_drv : entity work.axi4s_driver
    generic map (
      G_FILE_PATH         => C_IN_FILE,
      G_DATA_WIDTH        => 8,
      G_INIT_DELAY        => 0,
      G_TLAST_END_OF_LINE => true,
      G_LOOP_COUNT        => 0)  -- infini : fournit les pixels de vidange
    port map (
      clk_i => clk, rst_i => rst,
      m_tvalid => drv_tvalid, m_tdata => drv_tdata, m_tlast => drv_tlast,
      m_tready => drv_tready,
      done_o => drv_done, frame_cnt_o => drv_fcnt, pixel_cnt_o => drv_pcnt);

  ----------------------------------------------------------------------------
  -- Reconstruction du SOF : pixel 0 de chaque trame.
  ----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        pcnt <= 0;
      elsif drv_tvalid = '1' and drv_tready = '1' then
        if pcnt = NPIX-1 then pcnt <= 0; else pcnt <= pcnt + 1; end if;
      end if;
    end if;
  end process;
  sof <= drv_tvalid when pcnt = 0 else '0';

  ----------------------------------------------------------------------------
  -- Chaine de detection : gaussien -> laplacien -> binarisation.
  ----------------------------------------------------------------------------
  u_g : entity work.gaussian_filter
    generic map (IMG_W => C_IMG_WIDTH, IMG_H => C_IMG_HEIGHT)
    port map (clk => clk, resetn => resetn,
      s_tdata => drv_tdata, s_tvalid => drv_tvalid, s_tready => drv_tready,
      s_tuser => sof, s_tlast => drv_tlast,
      m_tdata => g_td, m_tvalid => g_tv, m_tready => g_tr, m_tuser => g_tu, m_tlast => g_tl);

  u_l : entity work.laplacian_filter
    generic map (IMG_W => C_IMG_WIDTH, IMG_H => C_IMG_HEIGHT)
    port map (clk => clk, resetn => resetn,
      s_tdata => g_td, s_tvalid => g_tv, s_tready => g_tr, s_tuser => g_tu, s_tlast => g_tl,
      m_tdata => l_td, m_tvalid => l_tv, m_tready => l_tr, m_tuser => l_tu, m_tlast => l_tl);

  u_b : entity work.binarize
    port map (clk => clk, resetn => resetn, thresh => to_unsigned(C_THRESHOLD, C_RESP_W),
      s_tdata => l_td, s_tvalid => l_tv, s_tready => l_tr, s_tuser => l_tu, s_tlast => l_tl,
      m_tdata => b_td, m_tvalid => b_tv, m_tready => b_tr, m_tuser => b_tu, m_tlast => b_tl);

  ----------------------------------------------------------------------------
  -- Moniteur du formateur : capture deux images (carte binaire 0/1).
  ----------------------------------------------------------------------------
  u_mon : entity work.axi4s_monitor
    generic map (
      G_FILE_BASENAME => C_OUT_BASE,
      G_DATA_WIDTH    => 1,
      G_IMG_WIDTH     => C_IMG_WIDTH,
      G_IMG_HEIGHT    => C_IMG_HEIGHT,
      G_NB_IMAGES     => 1,       -- 1 trame capturee (vidangee par la suivante)
      G_TIMEOUT_CY    => 20000,
      G_SYNC_ON_SOF   => true)
    port map (
      clk_i => clk, rst_i => rst,
      s_tvalid => b_tv, s_tdata => b_td, s_tlast => b_tl, s_tuser => b_tu,
      s_tready => b_tr,
      done_o => mon_done, img_cnt_o => mon_img, line_cnt_o => mon_line, pixel_cnt_o => mon_pix);

  ----------------------------------------------------------------------------
  -- Fin de simulation quand le moniteur a capture ses deux images.
  ----------------------------------------------------------------------------
  process
  begin
    wait until mon_done = '1';
    wait for 100 ns;
    report "=== tb_environnement : capture terminee, " & integer'image(mon_pix) &
           " pixels captures (attendu " & integer'image(NPIX) & ") ===" severity note;
    assert mon_pix = NPIX
      report "tb_environnement : nombre de pixels captures inattendu" severity warning;
    report "tb_environnement : SUCCES" severity note;
    std.env.stop;
  end process;
end architecture sim;
