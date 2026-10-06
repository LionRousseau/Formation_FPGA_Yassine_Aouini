--------------------------------------------------------------------------------
-- tb_response.vhd  (banc d'analyse, harnais REF-TB du formateur)
-- Identique a tb_environnement mais capture la REPONSE |laplacien| (11 bits) au
-- lieu de la carte binaire. Sert a regler le seuil hors-ligne (histogramme de la
-- reponse reelle) et a produire l'image de reponse. La binarisation RTL applique
-- ensuite exactement la comparaison v >= seuil (verifiee par TC-U-05).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tb_response is
  generic (
    C_IMG_WIDTH  : integer := 640;
    C_IMG_HEIGHT : integer := 480;
    C_IN_FILE    : string  := "../data/sample_in_gray.txt";
    C_OUT_BASE   : string  := "response"
  );
end entity tb_response;

architecture sim of tb_response is
  constant NPIX : integer := C_IMG_WIDTH * C_IMG_HEIGHT;
  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal resetn : std_logic;
  signal drv_tvalid, drv_tlast, drv_tready : std_logic;
  signal drv_tdata : std_logic_vector(7 downto 0);
  signal drv_done  : std_logic;
  signal drv_fcnt, drv_pcnt : integer;
  signal pcnt   : integer := 0;
  signal sof    : std_logic;
  signal g_td : std_logic_vector(C_LUMA_W-1 downto 0);
  signal g_tv, g_tr, g_tu, g_tl : std_logic;
  signal l_td : std_logic_vector(C_RESP_W-1 downto 0);
  signal l_tv, l_tr, l_tu, l_tl : std_logic;
  signal mon_done : std_logic;
  signal mon_img, mon_line, mon_pix : integer;
begin
  clk    <= not clk after 5 ns;
  resetn <= not rst;
  process begin rst <= '1'; wait for 53 ns; rst <= '0'; wait; end process;

  u_drv : entity work.axi4s_driver
    generic map (G_FILE_PATH => C_IN_FILE, G_DATA_WIDTH => 8, G_INIT_DELAY => 0,
      G_TLAST_END_OF_LINE => true, G_LOOP_COUNT => 0)
    port map (clk_i => clk, rst_i => rst,
      m_tvalid => drv_tvalid, m_tdata => drv_tdata, m_tlast => drv_tlast, m_tready => drv_tready,
      done_o => drv_done, frame_cnt_o => drv_fcnt, pixel_cnt_o => drv_pcnt);

  process(clk) begin
    if rising_edge(clk) then
      if rst = '1' then pcnt <= 0;
      elsif drv_tvalid = '1' and drv_tready = '1' then
        if pcnt = NPIX-1 then pcnt <= 0; else pcnt <= pcnt + 1; end if;
      end if;
    end if;
  end process;
  sof <= drv_tvalid when pcnt = 0 else '0';

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

  u_mon : entity work.axi4s_monitor
    generic map (G_FILE_BASENAME => C_OUT_BASE, G_DATA_WIDTH => C_RESP_W,
      G_IMG_WIDTH => C_IMG_WIDTH, G_IMG_HEIGHT => C_IMG_HEIGHT, G_NB_IMAGES => 1,
      G_TIMEOUT_CY => 20000, G_SYNC_ON_SOF => true)
    port map (clk_i => clk, rst_i => rst,
      s_tvalid => l_tv, s_tdata => l_td, s_tlast => l_tl, s_tuser => l_tu, s_tready => l_tr,
      done_o => mon_done, img_cnt_o => mon_img, line_cnt_o => mon_line, pixel_cnt_o => mon_pix);

  process begin
    wait until mon_done = '1'; wait for 100 ns;
    report "=== tb_response : " & integer'image(mon_pix) & " pixels captures ===" severity note;
    std.env.stop;
  end process;
end architecture sim;
