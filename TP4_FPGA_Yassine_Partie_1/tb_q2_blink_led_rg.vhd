-- Scenario :
--   1) reset, bouton relache -> la LED ROUGE clignote, la verte reste a 0
--   2) appui LONG sur bouton_0 (plusieurs periodes de clignotement)
--   3) relachement -> retour au clignotement rouge.

library ieee;
use ieee.std_logic_1164.all;

entity tb_q2_blink_led_rg is
end entity tb_q2_blink_led_rg;

architecture sim of tb_q2_blink_led_rg is

  constant C_CLK_PERIOD : time    := 8 ns;  -- 125 MHz
  constant C_NB_COUPS  : natural := 4;     -- valeur reduite pour la simu

  signal clk      : std_logic := '0';
  signal resetn   : std_logic := '0';
  signal bouton_0 : std_logic := '0';
  signal led0_r   : std_logic;
  signal led0_g   : std_logic;

  signal sim_done : boolean := false;

begin

  dut : entity work.q2_blink_led_rg
    generic map (NB_COUPS_HORLOGE => C_NB_COUPS)
    port map (
      clk      => clk,
      resetn   => resetn,
      bouton_0 => bouton_0,
      led0_r   => led0_r,
      led0_g   => led0_g
    );

  p_clk : process
  begin
    while not sim_done loop
      clk <= '0'; wait for C_CLK_PERIOD / 2;
      clk <= '1'; wait for C_CLK_PERIOD / 2;
    end loop;
    wait;
  end process p_clk;

  -- Stimuli
  p_stim : process
  begin
    -- Phase 0 : reset
    resetn   <= '1';   -- reset actif haut
    bouton_0 <= '0';
    wait for 5 * C_CLK_PERIOD;
    resetn <= '0';   -- relachement du reset
    report "Reset relache : la LED rouge doit clignoter.";

    -- Phase 1 : bouton relache pendant 4 periodes de clignotement
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert led0_g = '0'
      report "ERREUR : led0_g devrait rester a 0 sans appui." severity error;

    -- Phase 2 : APPUI LONG (bouton maintenu plusieurs periodes)
    report "Appui LONG sur bouton_0 : la LED verte clignote tant que le bouton est maintenu.";
    bouton_0 <= '1';
    wait for 6 * C_NB_COUPS * C_CLK_PERIOD;
    assert led0_r = '0'
      report "ERREUR : led0_r devrait etre forcee a 0 pendant l'appui." severity error;

    -- Phase 3 : relachement
    report "Relachement : retour au clignotement rouge.";
    bouton_0 <= '0';
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert led0_g = '0'
      report "ERREUR : led0_g devrait revenir a 0 apres relachement." severity error;

    report "Fin de simulation tb_q2_blink_led_rg.";
    sim_done <= true;
    wait;
  end process p_stim;

end architecture sim;
