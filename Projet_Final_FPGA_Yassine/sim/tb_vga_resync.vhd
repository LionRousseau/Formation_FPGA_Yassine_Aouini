--------------------------------------------------------------------------------
-- tb_vga_resync : verifie le re-verrouillage de vga_stream_out sur bascule.
-- Le flux source encode l'INDICE du pixel dans s_tdata (0..W*H-1), tuser sur 0.
-- On capture, a chaque trame, l'indice affiche a l'origine (x=0,y=0,actif) :
--   * apres verrouillage il doit valoir K = 0 (pixel 0 a l'origine, v2) ;
--   * un SAUT DE PHASE sans resync doit le decaler (image decalee, persistante) ;
--   * une impulsion resync doit le ramener a K (image realignee).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.video_pkg.all;
use work.vga_pkg.all;

entity tb_vga_resync is end entity;

architecture sim of tb_vga_resync is
  constant W : integer := C_IMG_WIDTH;
  constant H : integer := C_IMG_HEIGHT;
  constant N : integer := W*H;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal resync : std_logic := '0';
  signal s_tdata : std_logic_vector(3*C_COMP_W-1 downto 0) := (others=>'0');
  signal s_tvalid : std_logic := '1';
  signal s_tready : std_logic;
  signal s_tuser  : std_logic := '0';
  signal s_tlast  : std_logic := '0';
  signal vga_r,vga_g,vga_b : std_logic_vector(VGA_COMP_W-1 downto 0);
  signal hs,vs : std_logic;
  signal locked_o, active_o : std_logic;
  signal x_o : unsigned(HC_W-1 downto 0);
  signal y_o : unsigned(VC_W-1 downto 0);

  signal ptr  : integer := 0;      -- indice du pixel presente
  signal jump : std_logic := '0';  -- injecte un saut de phase (1 coup)
  signal done : boolean := false;
  signal origin_idx : integer := -1;   -- indice affiche a l'origine (derniere trame)
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.vga_stream_out
    port map (clk=>clk, resetn=>resetn, resync=>resync,
      s_tdata=>s_tdata, s_tvalid=>s_tvalid, s_tready=>s_tready,
      s_tuser=>s_tuser, s_tlast=>s_tlast,
      vga_r=>vga_r, vga_g=>vga_g, vga_b=>vga_b, vga_hsync=>hs, vga_vsync=>vs,
      locked_o=>locked_o, active_o=>active_o, x_o=>x_o, y_o=>y_o);

  -- source : presente le pixel d'indice ptr, avance quand accepte
  s_tdata <= std_logic_vector(to_unsigned(ptr,3*C_COMP_W));
  s_tuser <= '1' when ptr=0 else '0';
  s_tvalid <= '1';

  process(clk)
  begin
    if rising_edge(clk) then
      if resetn='0' then
        ptr <= 0;
      elsif s_tready='1' then
        if jump='1' then
          ptr <= (ptr + 100000) mod N;   -- saut de phase (bascule simulee)
        elsif ptr = N-1 then
          ptr <= 0;
        else
          ptr <= ptr + 1;
        end if;
      end if;
    end if;
  end process;

  -- moniteur : capture l'indice affiche a l'origine (x=0,y=0) une fois verrouille
  process(clk)
  begin
    if rising_edge(clk) then
      if locked_o='1' and active_o='1' and x_o=0 and y_o=0 then
        origin_idx <= to_integer(unsigned(s_tdata));
        report "origin_idx = " & integer'image(to_integer(unsigned(s_tdata)));
      end if;
    end if;
  end process;

  stim : process
    variable K : integer;
  begin
    resetn <= '0'; wait for 100 ns; resetn <= '1';

    -- ~3 trames pour verrouiller et stabiliser
    wait for 3 ms;
    K := origin_idx;
    report "K (aligne) = " & integer'image(K);
    -- v2 : exigence stricte, le pixel 0 de la trame doit etre affiche en (0,0)
    -- (la v1.0 donnait K = 1 : image decalee d'un pixel vers la gauche)
    assert K = 0
      report "ECHEC: premier pixel non affiche a l'origine (K /= 0)" severity error;

    -- SAUT DE PHASE sans resync : doit decaler durablement
    wait until rising_edge(clk); jump <= '1';
    wait until rising_edge(clk); jump <= '0';
    wait for 6 ms;   -- ~1.5 trame apres le saut
    assert origin_idx /= K
      report "ATTENDU: sans resync, image decalee (origin_idx != K)" severity error;
    report "sans resync, origin_idx = " & integer'image(origin_idx) & " (decale, OK)";

    -- IMPULSION RESYNC : doit realigner sur K
    wait until rising_edge(clk); resync <= '1';
    wait until rising_edge(clk); resync <= '0';
    wait for 9 ms;   -- laisser 2 trames pour drainer + re-verrouiller
    report "apres resync, origin_idx = " & integer'image(origin_idx);
    assert origin_idx = K
      report "ECHEC: apres resync, image non realignee" severity error;
    report "SUCCES: resync realigne l'image (origin_idx = K = " & integer'image(K) & ")";

    done <= true; wait;
  end process;
end architecture sim;
