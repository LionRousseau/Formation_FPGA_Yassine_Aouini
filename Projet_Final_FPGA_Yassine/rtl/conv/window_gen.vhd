--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : window_gen.vhd
-- Description : Generateur de fenetre glissante 3x3 sur un flux raster
--               (PL-IP-004, architecture sliding window). Reconstitue le
--               voisinage 3x3 de chaque pixel a partir de deux lignes a retard
--               (line_buffer) et de registres a decalage horizontaux.
--
--               - Bords de l'image forces a zero (hypothese PO-05).
--               - Suivi de la coordonnee du pixel central (col, row) exprimee
--                 dans le repere de l'image.
--               - Regeneration des marqueurs AXI4-Stream sof (tuser, premier
--                 pixel de trame) et eol (tlast, dernier pixel de ligne) alignes
--                 sur la fenetre (ED-03).
--
--               La fenetre est exposee sur le port win_o (9 pixels) : c'est le
--               point d'observation du cas de test TC-U-06.
--
--               Ordre des 9 elements de la fenetre (lecture ligne par ligne) :
--                 0 1 2   ->  (col-1,row-1) (col,row-1) (col+1,row-1)
--                 3 4 5   ->  (col-1,row  ) (col,row  ) (col+1,row  )
--                 6 7 8   ->  (col-1,row+1) (col,row+1) (col+1,row+1)
--               L'element 4 est le pixel central.
--
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity window_gen is
  generic (
    DATA_W : natural := 8;
    IMG_W  : natural := C_IMG_WIDTH;
    IMG_H  : natural := C_IMG_HEIGHT
  );
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;                       -- reset asynchrone actif bas
    en       : in  std_logic;                       -- avance le pipeline (1 pixel)
    -- entree flux
    din      : in  unsigned(DATA_W-1 downto 0);
    din_sof  : in  std_logic;                        -- premier pixel de trame
    din_valid: in  std_logic;                        -- pixel valide presente
    -- sortie fenetre alignee
    win_o    : out window3x3_t;                      -- 9 pixels (DATA_W = 8)
    col_o    : out unsigned(C_X_W-1 downto 0);       -- coordonnee X du centre
    row_o    : out unsigned(C_Y_W-1 downto 0);       -- coordonnee Y du centre
    valid_o  : out std_logic;                        -- fenetre valide
    sof_o    : out std_logic;                        -- centre = (0,0)
    eol_o    : out std_logic                         -- centre en fin de ligne
  );
end entity window_gen;

architecture rtl of window_gen is

  -- Flux des trois lignes : courante, N-1 (via 1 line buffer), N-2 (via 2).
  signal row_mid  : unsigned(DATA_W-1 downto 0);   -- din retarde de IMG_W
  signal row_top  : unsigned(DATA_W-1 downto 0);   -- din retarde de 2*IMG_W

  -- Registres a decalage horizontaux (3 colonnes par ligne).
  -- index 0 = colonne la plus recente (col+1), 1 = col, 2 = col-1.
  type tap3_t is array (0 to 2) of unsigned(DATA_W-1 downto 0);
  signal b_sr, m_sr, t_sr : tap3_t := (others => (others => '0'));

  -- Chaine de retard des marqueurs pour aligner la coordonnee du centre.
  -- Reglee par simulation : le centre est le pixel entre COORD_DELAY avances
  -- plus tot (formation de la fenetre : 2 line buffers + registres de taps).
  constant COORD_DELAY : natural := IMG_W + 1;
  signal sof_dl   : std_logic_vector(COORD_DELAY-1 downto 0) := (others => '0');
  signal val_dl   : std_logic_vector(COORD_DELAY-1 downto 0) := (others => '0');

  signal sof_c    : std_logic;   -- sof retarde (pilote le compteur)
  signal val_c    : std_logic;   -- valid retarde (pilote le compteur)

  -- Coordonnee du pixel central (registree) et sa validite alignee.
  signal col_r : unsigned(C_X_W-1 downto 0) := (others => '0');
  signal row_r : unsigned(C_Y_W-1 downto 0) := (others => '0');
  signal val_q : std_logic := '0';   -- validite alignee sur col_r/row_r et win

  -- Drapeaux de bord (combinatoires a partir de col_r/row_r).
  signal edge_l, edge_r, edge_t, edge_b : std_logic;

begin

  ----------------------------------------------------------------------------
  -- Deux lignes a retard : row_mid = ligne N-1, row_top = ligne N-2.
  ----------------------------------------------------------------------------
  lb1 : entity work.line_buffer
    generic map (DATA_W => DATA_W, DEPTH => IMG_W)
    port map (clk => clk, en => en, din => din, dout => row_mid);

  lb2 : entity work.line_buffer
    generic map (DATA_W => DATA_W, DEPTH => IMG_W)
    port map (clk => clk, en => en, din => row_mid, dout => row_top);

  ----------------------------------------------------------------------------
  -- Registres a decalage horizontaux et chaine de retard des marqueurs.
  ----------------------------------------------------------------------------
  process(clk, resetn)
  begin
    if resetn = '0' then
      b_sr   <= (others => (others => '0'));
      m_sr   <= (others => (others => '0'));
      t_sr   <= (others => (others => '0'));
      sof_dl <= (others => '0');
      val_dl <= (others => '0');
    elsif rising_edge(clk) then
      if en = '1' then
        -- decalage horizontal : entree en position 0, propagation vers 2
        b_sr(0) <= din;      b_sr(1) <= b_sr(0);  b_sr(2) <= b_sr(1);
        m_sr(0) <= row_mid;  m_sr(1) <= m_sr(0);  m_sr(2) <= m_sr(1);
        t_sr(0) <= row_top;  t_sr(1) <= t_sr(0);  t_sr(2) <= t_sr(1);
        -- retard des marqueurs
        sof_dl <= sof_dl(COORD_DELAY-2 downto 0) & din_sof;
        val_dl <= val_dl(COORD_DELAY-2 downto 0) & din_valid;
      end if;
    end if;
  end process;

  sof_c <= sof_dl(COORD_DELAY-1);
  val_c <= val_dl(COORD_DELAY-1);

  ----------------------------------------------------------------------------
  -- Compteur de coordonnee du centre, resynchronise a chaque trame par sof_c.
  ----------------------------------------------------------------------------
  process(clk, resetn)
  begin
    if resetn = '0' then
      col_r <= (others => '0');
      row_r <= (others => '0');
    elsif rising_edge(clk) then
      if en = '1' then
        -- validite alignee sur la coordonnee registree (et donc sur win)
        val_q <= val_c;
        if val_c = '1' then
          if sof_c = '1' then
            col_r <= (others => '0');
            row_r <= (others => '0');
          elsif col_r = IMG_W-1 then
            col_r <= (others => '0');
            if row_r = IMG_H-1 then
              row_r <= (others => '0');
            else
              row_r <= row_r + 1;
            end if;
          else
            col_r <= col_r + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Drapeaux de bord et construction de la fenetre avec forcage a zero (PO-05).
  ----------------------------------------------------------------------------
  edge_l <= '1' when col_r = 0        else '0';
  edge_r <= '1' when col_r = IMG_W-1  else '0';
  edge_t <= '1' when row_r = 0        else '0';
  edge_b <= '1' when row_r = IMG_H-1  else '0';

  -- Mapping taps -> fenetre :
  --   colonne col-1 = index 2, col = index 1, col+1 = index 0
  --   ligne  row-1 = t_sr (N-2 flux = ligne au dessus du centre)
  --   ligne  row   = m_sr
  --   ligne  row+1 = b_sr
  win_o(0) <= (others => '0') when (edge_l or edge_t) = '1' else t_sr(2); -- (c-1,r-1)
  win_o(1) <= (others => '0') when (edge_t) = '1'            else t_sr(1); -- (c  ,r-1)
  win_o(2) <= (others => '0') when (edge_r or edge_t) = '1' else t_sr(0); -- (c+1,r-1)
  win_o(3) <= (others => '0') when (edge_l) = '1'            else m_sr(2); -- (c-1,r  )
  win_o(4) <=                                                     m_sr(1); -- (c  ,r  ) centre
  win_o(5) <= (others => '0') when (edge_r) = '1'            else m_sr(0); -- (c+1,r  )
  win_o(6) <= (others => '0') when (edge_l or edge_b) = '1' else b_sr(2); -- (c-1,r+1)
  win_o(7) <= (others => '0') when (edge_b) = '1'            else b_sr(1); -- (c  ,r+1)
  win_o(8) <= (others => '0') when (edge_r or edge_b) = '1' else b_sr(0); -- (c+1,r+1)

  -- Sorties alignees sur la coordonnee registree (col_r/row_r) et sur win.
  col_o   <= col_r;
  row_o   <= row_r;
  valid_o <= val_q;
  sof_o   <= val_q when (col_r = 0 and row_r = 0) else '0';
  eol_o   <= val_q when (col_r = IMG_W-1)        else '0';

end architecture rtl;
