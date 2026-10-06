--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : gaussian_filter.vhd
-- Description : Filtre gaussien 3x3 (PL-IP-006). Instancie le moteur generique
--               conv3x3 avec le noyau [1 2 1;2 4 2;1 2 1] et division par 16.
--               Entree/sortie luminance 8 bits, flux AXI4-Stream.
--               v2 : entree bypass ('1' = etage court-circuite, sortie = pixel
--               d'entree, meme latence) pour montrer l'effet du lissage.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.video_pkg.all;

entity gaussian_filter is
  generic (
    IMG_W : natural := C_IMG_WIDTH;
    IMG_H : natural := C_IMG_HEIGHT
  );
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;
    s_tdata  : in  std_logic_vector(C_LUMA_W-1 downto 0);
    s_tvalid : in  std_logic;
    s_tready : out std_logic;
    s_tuser  : in  std_logic;
    s_tlast  : in  std_logic;
    m_tdata  : out std_logic_vector(C_LUMA_W-1 downto 0);
    m_tvalid : out std_logic;
    m_tready : in  std_logic;
    m_tuser  : out std_logic;
    m_tlast  : out std_logic;
    bypass   : in  std_logic := '0'
  );
end entity gaussian_filter;

architecture rtl of gaussian_filter is
begin
  u_conv : entity work.conv3x3
    generic map (
      IN_W   => C_LUMA_W,
      OUT_W  => C_LUMA_W,
      KERNEL => C_KERNEL_GAUSS,
      DIV_SH => C_GAUSS_DIV_SH,       -- division par 16
      DO_ABS => false,
      IMG_W  => IMG_W,
      IMG_H  => IMG_H
    )
    port map (
      clk => clk, resetn => resetn,
      s_tdata => s_tdata, s_tvalid => s_tvalid, s_tready => s_tready,
      s_tuser => s_tuser, s_tlast => s_tlast,
      m_tdata => m_tdata, m_tvalid => m_tvalid, m_tready => m_tready,
      m_tuser => m_tuser, m_tlast => m_tlast,
      bypass => bypass, m_center => open);
end architecture rtl;
