--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : vga_stream_out.vhd
-- Description : Etage de sortie VGA (PL-DISP-002). Consomme un flux AXI4-Stream
--               RGB 24 bits en ordre raster et pilote un ecran via le Pmod VGA
--               Digilent (format 4:4:4, reseau R-2R), plus les synchros hsync et
--               vsync.
--
--               Verrouillage de trame (genlock) : le balayage VGA est cale sur
--               le premier tuser du flux amont. Cela absorbe la latence de la
--               chaine de traitement, dont le debut de trame est retarde. Une
--               fois verrouille, l'etage ne consomme un pixel que pendant la zone
--               active ; l'amont, gele hors zone active, reste en phase avec le
--               balayage. Hors zone active, la sortie est noire.
--
--               Re-verrouillage sur bascule de source (PL-IP-003) : l'entree
--               resync (impulsion emise quand le multiplexeur change reellement
--               de source) fait retomber l'etage a l'etat NON verrouille. Tant
--               qu'il n'est pas verrouille, il VIDE le flux (s_tready = '1') sans
--               rien afficher, jusqu'au prochain debut de trame (tuser) sur lequel
--               il se re-cale exactement, comme au demarrage. La bascule se
--               resorbe donc en une trame, sans decalage residuel, et sans blocage
--               (le vidage garantit qu'un nouveau debut de trame finit par arriver).
--
--               Sortie combinatoire (adaptee a un DAC R-2R analogique).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;
use work.vga_pkg.all;

entity vga_stream_out is
  port (
    clk       : in  std_logic;       -- horloge pixel 25,175 MHz
    resetn    : in  std_logic;
    -- impulsion de re-verrouillage (emise sur un changement de source)
    resync    : in  std_logic := '0';
    -- flux video AXI4-Stream (RGB 24 bits)
    s_tdata   : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    s_tvalid  : in  std_logic;
    s_tready  : out std_logic;
    s_tuser   : in  std_logic;
    s_tlast   : in  std_logic;
    -- sortie Pmod VGA
    vga_r     : out std_logic_vector(VGA_COMP_W-1 downto 0);
    vga_g     : out std_logic_vector(VGA_COMP_W-1 downto 0);
    vga_b     : out std_logic_vector(VGA_COMP_W-1 downto 0);
    vga_hsync : out std_logic;
    vga_vsync : out std_logic;
    -- suppression verticale (haute pendant le blanking vertical), pour cadencer
    -- le lancement de la lecture DMA une image a la fois (cf. video_subsystem)
    vblank_o  : out std_logic;
    -- observabilite (sondes ILA)
    locked_o  : out std_logic;
    active_o  : out std_logic;
    x_o       : out unsigned(HC_W-1 downto 0);
    y_o       : out unsigned(VC_W-1 downto 0)
  );
end entity vga_stream_out;

architecture rtl of vga_stream_out is
  signal hsync_i, vsync_i, active_i, fbeg_i, lbeg_i : std_logic;
  signal hc_i, vc_i, x_i, y_i : unsigned(HC_W-1 downto 0);
  signal sync_lock : std_logic;
  signal locked    : std_logic := '0';
begin
  ----------------------------------------------------------------------------
  -- Genlock. Tant que NON verrouille, on se cale sur le prochain debut de trame
  -- (tuser) : sync_lock remet les compteurs a (0,0) et verrouille. Un changement
  -- de source (resync) refait retomber a l'etat non verrouille, ce qui relance ce
  -- meme calage sur la trame suivante de la nouvelle source. En regime etabli,
  -- verrouille, sync_lock reste a 0 (le SOF arrive deja en (0,0)).
  ----------------------------------------------------------------------------
  sync_lock <= s_tvalid and s_tuser and (not locked);

  u_timing : entity work.vga_timing
    port map (clk => clk, resetn => resetn, sync_lock => sync_lock,
      hcount => hc_i, vcount => vc_i, x => x_i, y => y_i,
      hsync => hsync_i, vsync => vsync_i, active => active_i,
      frame_beg => fbeg_i, line_beg => lbeg_i);

  process(clk, resetn)
  begin
    if resetn = '0' then
      locked <= '0';
    elsif rising_edge(clk) then
      if resync = '1' then
        locked <= '0';           -- bascule de source : on redemande un calage
      elsif sync_lock = '1' then
        locked <= '1';           -- cale sur le debut de trame de la source active
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Consommation : verrouille, un pixel par pixel actif (l'amont reste en phase,
  -- gele hors zone active). NON verrouille, on VIDE le flux (s_tready = '1') pour
  -- atteindre a coup sur le prochain debut de trame sans se bloquer.
  ----------------------------------------------------------------------------
  -- v2 : au cycle du calage (sync_lock), on NE consomme PAS le pixel de debut
  -- de trame : il doit etre affiche en (0,0). Le vidage inconditionnel de la
  -- v1.0 l'avalait, d'ou un decalage d'un pixel vers la gauche (detecte par le
  -- banc tb_vga_display, TC-S-01).
  s_tready <= (not sync_lock) when locked = '0' else active_i;

  ----------------------------------------------------------------------------
  -- Sortie Pmod : 4 bits de poids fort par composante en zone active, noir
  -- sinon.
  ----------------------------------------------------------------------------
  vga_r <= s_tdata(3*C_COMP_W-1 downto 3*C_COMP_W-VGA_COMP_W)
             when (active_i = '1' and s_tvalid = '1' and locked = '1')
             else (others => '0');
  vga_g <= s_tdata(2*C_COMP_W-1 downto 2*C_COMP_W-VGA_COMP_W)
             when (active_i = '1' and s_tvalid = '1' and locked = '1')
             else (others => '0');
  vga_b <= s_tdata(1*C_COMP_W-1 downto 1*C_COMP_W-VGA_COMP_W)
             when (active_i = '1' and s_tvalid = '1' and locked = '1')
             else (others => '0');

  vga_hsync <= hsync_i;
  vga_vsync <= vsync_i;
  -- Suppression verticale : vrai des que la ligne courante depasse la zone
  -- visible (vc >= V_VISIBLE). Fenetre large (45 lignes) pour lancer la lecture
  -- DMA de la trame suivante avec de la marge avant le retour en zone active.
  vblank_o  <= '1' when vc_i >= to_unsigned(V_VISIBLE, vc_i'length) else '0';
  locked_o  <= locked;
  active_o  <= active_i;
  x_o       <= x_i;
  y_o       <= vc_i(VC_W-1 downto 0);
end architecture rtl;
