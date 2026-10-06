--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : max_tracker.vhd
-- Description : Suivi de la reponse maximale du filtre laplacien sur une trame
--               (PL-IP-010). Observe (en derivation, sans back-pressure propre)
--               le flux de reponse |laplacien| et memorise la valeur maximale
--               et ses coordonnees (X,Y) dans le repere de l'image d'origine.
--
--               - Le flux etant en ordre raster et la latence de chaine etant
--                 identique pour tous les pixels, la position raster dans ce flux
--                 est directement la coordonnee source (latence compensee, TC-U-08).
--               - Regle de departage deterministe : superiorite STRICTE, donc en
--                 cas d'egalite la premiere occurrence (ordre raster) est retenue.
--               - Les registres de sortie ne sont mis a jour qu'en FIN de trame
--                 (latch de fin de trame, PO-08) : la detection de fin de trame
--                 se fait a l'arrivee du tuser de la trame suivante.
--
--               L'etage observe les transferts acceptes : en = in_valid and
--               in_ready (meme handshake que l'etage de binarisation aval), ce
--               qui garantit le synchronisme avec la chaine.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity max_tracker is
  generic (
    IMG_W : natural := C_IMG_WIDTH;
    IMG_H : natural := C_IMG_HEIGHT
  );
  port (
    clk       : in  std_logic;
    resetn    : in  std_logic;
    -- observation du flux de reponse laplacien
    in_data   : in  std_logic_vector(C_RESP_W-1 downto 0);
    in_valid  : in  std_logic;
    in_ready  : in  std_logic;                       -- ready de l'etage aval
    in_sof    : in  std_logic;                       -- tuser (debut de trame)
    -- registres de sortie (latches de fin de trame)
    max_val   : out unsigned(C_RESP_W-1 downto 0);
    max_x     : out unsigned(C_X_W-1 downto 0);
    max_y     : out unsigned(C_Y_W-1 downto 0);
    frame_tick: out std_logic                         -- impulsion : maj des latches
  );
end entity max_tracker;

architecture rtl of max_tracker is
  signal en : std_logic;

  -- coordonnee du pixel courant
  signal cx : unsigned(C_X_W-1 downto 0) := (others => '0');
  signal cy : unsigned(C_Y_W-1 downto 0) := (others => '0');

  -- max courant de la trame en cours
  signal run_val   : unsigned(C_RESP_W-1 downto 0) := (others => '0');
  signal run_x     : unsigned(C_X_W-1 downto 0) := (others => '0');
  signal run_y     : unsigned(C_Y_W-1 downto 0) := (others => '0');
  signal run_valid : std_logic := '0';   -- au moins un pixel dans la trame

  -- latches de sortie
  signal lat_val : unsigned(C_RESP_W-1 downto 0) := (others => '0');
  signal lat_x   : unsigned(C_X_W-1 downto 0) := (others => '0');
  signal lat_y   : unsigned(C_Y_W-1 downto 0) := (others => '0');
  signal tick    : std_logic := '0';
begin
  en <= in_valid and in_ready;

  process(clk, resetn)
    variable v      : unsigned(C_RESP_W-1 downto 0);
    variable px     : unsigned(C_X_W-1 downto 0);
    variable py     : unsigned(C_Y_W-1 downto 0);
  begin
    if resetn = '0' then
      cx <= (others => '0'); cy <= (others => '0');
      run_val <= (others => '0'); run_x <= (others => '0'); run_y <= (others => '0');
      run_valid <= '0';
      lat_val <= (others => '0'); lat_x <= (others => '0'); lat_y <= (others => '0');
      tick <= '0';
    elsif rising_edge(clk) then
      tick <= '0';
      if en = '1' then
        v := unsigned(in_data);

        if in_sof = '1' then
          ------------------------------------------------------------------
          -- Fin de la trame precedente : verrouillage des sorties (PO-08).
          ------------------------------------------------------------------
          if run_valid = '1' then
            lat_val <= run_val;
            lat_x   <= run_x;
            lat_y   <= run_y;
            tick    <= '1';
          end if;
          -- ce pixel est (0,0), demarrage du nouveau max
          px := (others => '0');
          py := (others => '0');
          run_val   <= v;
          run_x     <= px;
          run_y     <= py;
          run_valid <= '1';
          cx <= px;
          cy <= py;
        else
          ------------------------------------------------------------------
          -- Pixel courant : coordonnee suivante puis comparaison stricte.
          ------------------------------------------------------------------
          if cx = IMG_W-1 then
            px := (others => '0');
            if cy = IMG_H-1 then
              py := (others => '0');
            else
              py := cy + 1;
            end if;
          else
            px := cx + 1;
            py := cy;
          end if;

          if v > run_val then       -- superiorite STRICTE : 1ere occurrence
            run_val <= v;
            run_x   <= px;
            run_y   <= py;
          end if;
          cx <= px;
          cy <= py;
        end if;
      end if;
    end if;
  end process;

  max_val    <= lat_val;
  max_x      <= lat_x;
  max_y      <= lat_y;
  frame_tick <= tick;
end architecture rtl;
