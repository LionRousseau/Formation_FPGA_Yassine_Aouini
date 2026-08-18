-- Testbench du module led_driver seul (Q8).
-- Verifie que :
--   - apres reset, la LED est eteinte (color_reg = "00") ;
--   - color_code n'est pas pris en compte sans update ;
--   - sur une impulsion update, la couleur est memorisee et la LED
--     correspondante clignote ;
--   - un changement de color_code sans update ne change rien.

library ieee;
use ieee.std_logic_1164.all;

entity tb_led_driver is
end entity tb_led_driver;

architecture sim of tb_led_driver is

  constant C_CLK_PERIOD : time    := 8 ns;
  constant C_NB_COUPS  : natural := 4;

  signal clk        : std_logic := '0';
  signal resetn     : std_logic := '0';
  signal color_code : std_logic_vector(1 downto 0) := "00";
  signal update     : std_logic := '0';
  signal led_r      : std_logic;
  signal led_g      : std_logic;
  signal led_b      : std_logic;

  signal sim_done : boolean := false;

begin

  dut : entity work.led_driver
    generic map (NB_COUPS_HORLOGE => C_NB_COUPS)
    port map (
      clk        => clk,
      resetn     => resetn,
      color_code => color_code,
      update     => update,
      led_r      => led_r,
      led_g      => led_g,
      led_b      => led_b
    );

  p_clk : process
  begin
    while not sim_done loop
      clk <= '0'; wait for C_CLK_PERIOD / 2;
      clk <= '1'; wait for C_CLK_PERIOD / 2;
    end loop;
    wait;
  end process p_clk;

  p_stim : process
    -- Genere une impulsion update d'exactement un cycle
    procedure pulse_update is
    begin
      wait until rising_edge(clk);
      update <= '1';
      wait until rising_edge(clk);
      update <= '0';
    end procedure;
  begin
    -- Phase 0 : reset -> LED eteinte
    resetn <= '1';   -- reset actif haut
    wait for 5 * C_CLK_PERIOD;
    resetn <= '0';   -- relachement du reset
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert (led_r = '0') and (led_g = '0') and (led_b = '0')
      report "ERREUR : LED non eteinte apres reset (code 00 attendu)." severity error;

    -- Phase 1 : color_code = rouge SANS update -> rien ne change
    report "color_code=01 (rouge) presente SANS update : la LED doit rester eteinte.";
    color_code <= "01";
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert (led_r = '0') and (led_g = '0') and (led_b = '0')
      report "ERREUR : la couleur a change sans update." severity error;

    -- Phase 2 : impulsion update -> le rouge clignote
    report "Impulsion update : le ROUGE doit maintenant clignoter.";
    pulse_update;
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert (led_g = '0') and (led_b = '0')
      report "ERREUR : seule la LED rouge devrait etre active." severity error;

    -- Phase 3 : color_code = bleu SANS update -> le rouge continue
    report "color_code=11 (bleu) SANS update : le rouge doit continuer a clignoter.";
    color_code <= "11";
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert (led_g = '0') and (led_b = '0')
      report "ERREUR : la LED bleue s'est activee sans update." severity error;

    -- Phase 4 : update -> passage au bleu
    report "Impulsion update : passage au BLEU.";
    pulse_update;
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert (led_r = '0') and (led_g = '0')
      report "ERREUR : seule la LED bleue devrait etre active." severity error;

    report "Fin de simulation tb_led_driver.";
    sim_done <= true;
    wait;
  end process p_stim;

end architecture sim;
