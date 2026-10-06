--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : dma_mm2s_model.vhd   (MODELE DE SIMULATION, non synthetisable)
-- Description : Modele comportemental du flux de sortie de l'IP DMA MM2S fournie
--               par le formateur (DMA24bUnit_mm2s, Vitis HLS). Reproduit la
--               convention observable du port AXI4-Stream :
--                 TDATA[23:16]=R, TDATA[15:8]=G, TDATA[7:0]=B
--                 TUSER = 1 sur le premier pixel de l'image (SOF)
--                 TLAST = 1 sur le dernier pixel de chaque ligne (EOL)
--                 1 pixel par coup d'horloge, back-pressure respecte
--               et enchaine les trames en continu (equivalent autorestart).
--
--               La lecture memoire (AXI4 m_axi, format RGB888 packe, bursts,
--               FIFO) est abstraite : le modele restitue directement le pixel de
--               l'image en DDR, modelise par une fonction deterministe de (x,y).
--               Il sert a integrer et verifier la chaine en simulation ; l'IP
--               reelle du formateur est utilisee en materiel (cf DMA_INTEGRATION.md).
--
--               Generic MARK : valeur imposee a la composante R, pour distinguer
--               deux instances (utilise par le test du multiplexeur). Les
--               composantes G et B portent x et y, ce qui permet de verifier
--               l'ordre raster et l'exactitude de la relecture (TC-U-01).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity dma_mm2s_model is
  generic (
    IMG_W : natural := C_IMG_WIDTH;
    IMG_H : natural := C_IMG_HEIGHT;
    MARK  : natural := 0            -- valeur de la composante R (signature)
  );
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;
    m_tdata  : out std_logic_vector(3*C_COMP_W-1 downto 0);
    m_tvalid : out std_logic;
    m_tready : in  std_logic;
    m_tuser  : out std_logic;
    m_tlast  : out std_logic
  );
end entity dma_mm2s_model;

architecture sim of dma_mm2s_model is
  signal x : integer range 0 to IMG_W-1 := 0;
  signal y : integer range 0 to IMG_H-1 := 0;

  -- pixel de l'image en DDR (modele) : R = MARK, G = x, B = y (tronques 8 bits)
  function img_pixel(xi, yi : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(MARK mod 256, 8)) &
           std_logic_vector(to_unsigned(xi  mod 256, 8)) &
           std_logic_vector(to_unsigned(yi  mod 256, 8));
  end function;
begin
  m_tdata  <= img_pixel(x, y);
  m_tvalid <= '1';                                   -- la source a toujours un pixel
  m_tuser  <= '1' when (x = 0 and y = 0) else '0';   -- SOF
  m_tlast  <= '1' when (x = IMG_W-1) else '0';       -- EOL

  process(clk, resetn)
  begin
    if resetn = '0' then
      x <= 0; y <= 0;
    elsif rising_edge(clk) then
      if m_tready = '1' then                         -- transfert accepte
        if x = IMG_W-1 then
          x <= 0;
          if y = IMG_H-1 then
            y <= 0;                                  -- trame suivante (autorestart)
          else
            y <= y + 1;
          end if;
        else
          x <= x + 1;
        end if;
      end if;
    end if;
  end process;
end architecture sim;
