--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : laplacian_filter.vhd
-- Description : Second etage de filtre 3x3 (PL-IP-007). D'apres PO-01 le noyau
--               retenu est un laplacien [0 -1 0;-1 4 -1;0 -1 0] (et non le
--               critere de Harris det(M)-k*tr(M)^2). Pas de division. La valeur
--               absolue est prise avant seuillage (PO-06). Sortie |reponse| sur
--               C_RESP_W bits (0..1020, borne PO-02).
--
--               Entree : luminance filtree 8 bits. Sortie : reponse AXI4-Stream.
--               v2 : m_center = entree de l'etage (sortie du gaussien) au meme
--               pixel, alignee sur la reponse (visualisation de l'etage gaussien).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.video_pkg.all;

entity laplacian_filter is
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
    m_tdata  : out std_logic_vector(C_RESP_W-1 downto 0);  -- |laplacien|
    m_tvalid : out std_logic;
    m_tready : in  std_logic;
    m_tuser  : out std_logic;
    m_tlast  : out std_logic;
    m_center : out std_logic_vector(C_LUMA_W-1 downto 0)
  );
end entity laplacian_filter;

architecture rtl of laplacian_filter is
begin
  u_conv : entity work.conv3x3
    generic map (
      IN_W   => C_LUMA_W,
      OUT_W  => C_RESP_W,
      KERNEL => C_KERNEL_LAPL,
      DIV_SH => C_LAPL_DIV_SH,        -- pas de division
      DO_ABS => true,                 -- valeur absolue (PO-06)
      IMG_W  => IMG_W,
      IMG_H  => IMG_H
    )
    port map (
      clk => clk, resetn => resetn,
      s_tdata => s_tdata, s_tvalid => s_tvalid, s_tready => s_tready,
      s_tuser => s_tuser, s_tlast => s_tlast,
      m_tdata => m_tdata, m_tvalid => m_tvalid, m_tready => m_tready,
      m_tuser => m_tuser, m_tlast => m_tlast,
      bypass => '0', m_center => m_center);
end architecture rtl;
