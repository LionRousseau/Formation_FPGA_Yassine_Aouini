--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : tpg.vhd
-- Description : Generateur de mire (Test Pattern Generator, PL-IP-001). Source
--               AXI4-Stream RGB 640x480, en ordre raster, avec :
--                 - huit barres de couleur verticales (element statique) ;
--                 - un carre mobile dont la position horizontale progresse a
--                   chaque trame (element dynamique, exige par PL-IP-001).
--
--               Convention video : m_tuser marque le premier pixel de trame,
--               m_tlast le dernier pixel de chaque ligne. La source est toujours
--               valide (m_tvalid = '1') et respecte le back-pressure (m_tready).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tpg is
  generic (
    IMG_W : natural := C_IMG_WIDTH;
    IMG_H : natural := C_IMG_HEIGHT
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
end entity tpg;

architecture rtl of tpg is
  constant BOX_W : integer := 40;
  constant BOX_H : integer := 40;
  constant BOX_Y : integer := 220;              -- position verticale fixe
  constant BOX_STEP : integer := 4;             -- deplacement par trame

  signal x     : unsigned(C_X_W-1 downto 0) := (others => '0');
  signal y     : unsigned(C_Y_W-1 downto 0) := (others => '0');
  signal box_x : unsigned(C_X_W-1 downto 0) := (others => '0');
  signal en    : std_logic;

  -- couleur des barres verticales en fonction de la colonne
  function bar_color(xi : integer; w : integer) return std_logic_vector is
    variable idx : integer;
  begin
    idx := (xi * 8) / w;                        -- 0..7
    case idx is
      when 0 => return x"FFFFFF";               -- blanc
      when 1 => return x"FFFF00";               -- jaune
      when 2 => return x"00FFFF";               -- cyan
      when 3 => return x"00FF00";               -- vert
      when 4 => return x"FF00FF";               -- magenta
      when 5 => return x"FF0000";               -- rouge
      when 6 => return x"0000FF";               -- bleu
      when others => return x"000000";          -- noir
    end case;
  end function;

  signal pix : std_logic_vector(3*C_COMP_W-1 downto 0);
begin
  en <= m_tready;                                -- source toujours valide

  -- pixel courant (combinatoire)
  process(x, y, box_x)
    variable xi, yi, bx : integer;
  begin
    xi := to_integer(x); yi := to_integer(y); bx := to_integer(box_x);
    if xi >= bx and xi < bx + BOX_W and yi >= BOX_Y and yi < BOX_Y + BOX_H then
      pix <= x"FF8000";                          -- carre mobile (orange)
    else
      pix <= bar_color(xi, IMG_W);
    end if;
  end process;

  -- balayage raster + deplacement du carre a chaque trame
  process(clk, resetn)
  begin
    if resetn = '0' then
      x <= (others => '0'); y <= (others => '0'); box_x <= (others => '0');
    elsif rising_edge(clk) then
      if en = '1' then
        if x = IMG_W-1 then
          x <= (others => '0');
          if y = IMG_H-1 then
            y <= (others => '0');
            -- fin de trame : deplacement du carre
            if to_integer(box_x) >= IMG_W - BOX_W - BOX_STEP then
              box_x <= (others => '0');
            else
              box_x <= box_x + BOX_STEP;
            end if;
          else
            y <= y + 1;
          end if;
        else
          x <= x + 1;
        end if;
      end if;
    end if;
  end process;

  m_tdata  <= pix;
  m_tvalid <= '1';
  m_tuser  <= '1' when (x = 0 and y = 0) else '0';
  m_tlast  <= '1' when (x = IMG_W-1) else '0';
end architecture rtl;
