--------------------------------------------------------------------------------
-- TC-U-10  Conversion luminance (ED-01)
-- Injecte des pixels RGB de reference (primaires pures, blanc, noir, teintes)
-- et verifie l'egalite bit a bit avec la procedure de reference ref_luma.
-- Verdict explicite et compte d'erreurs en fin de simulation (PV 4.2).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;
use work.ref_pkg.all;

entity tb_rgb_to_luma is
end entity;

architecture sim of tb_rgb_to_luma is
  constant N : natural := 12;
  type rgb_t is array (0 to N-1, 0 to 2) of integer;
  constant V : rgb_t := (
    (  0,  0,  0),   -- noir
    (255,255,255),   -- blanc
    (255,  0,  0),   -- rouge
    (  0,255,  0),   -- vert
    (  0,  0,255),   -- bleu
    (128,128,128),   -- gris moyen
    (255,255,  0),   -- jaune
    (  0,255,255),   -- cyan
    (255,  0,255),   -- magenta
    ( 10, 20, 30),
    (200,100, 50),
    ( 17,240,  3));

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal din    : std_logic_vector(23 downto 0) := (others => '0');
  signal dv     : std_logic := '0';
  signal dready : std_logic;
  signal yout   : std_logic_vector(7 downto 0);
  signal yv     : std_logic;
  signal errors : integer := 0;
  signal done   : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.rgb_to_luma
    port map (clk => clk, resetn => resetn,
      s_tdata => din, s_tvalid => dv, s_tready => dready,
      s_tuser => '0', s_tlast => '0',
      m_tdata => yout, m_tvalid => yv, m_tready => '1',
      m_tuser => open, m_tlast => open);

  stim : process
  begin
    resetn <= '0'; dv <= '0';
    wait for 23 ns; resetn <= '1';
    wait until rising_edge(clk);
    for i in 0 to N-1 loop
      din <= std_logic_vector(to_unsigned(V(i,0),8)) &
             std_logic_vector(to_unsigned(V(i,1),8)) &
             std_logic_vector(to_unsigned(V(i,2),8));
      dv <= '1';
      wait until rising_edge(clk);
    end loop;
    dv <= '0';
    wait for 60 ns;
    done <= true; wait;
  end process;

  -- verification en ordre : chaque sortie valide correspond au i-eme pixel.
  check : process(clk)
    variable idx : integer := 0;
    variable exp : integer;
    variable err : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and yv = '1' and idx < N then
        exp := ref_luma(V(idx,0), V(idx,1), V(idx,2));
        if to_integer(unsigned(yout)) /= exp then
          report "TC-U-10 pixel " & integer'image(idx) &
                 " got=" & integer'image(to_integer(unsigned(yout))) &
                 " exp=" & integer'image(exp) severity warning;
          err := err + 1;
        end if;
        idx := idx + 1;
        errors <= err;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-10 (luminance) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-U-10 : ECHEC" severity failure;
    report "TC-U-10 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
