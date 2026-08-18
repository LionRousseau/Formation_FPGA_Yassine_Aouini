--   - bouton_1 = 1 a l'appui de bouton_0 -> couleur verte memorisee ;
--   - bouton_1 = 0 a l'appui de bouton_0 -> couleur bleue memorisee ;
--   - changer bouton_1 apres la memorisation ne change pas la couleur.

library ieee;
use ieee.std_logic_1164.all;

entity tb_top_led_driver is
end entity tb_top_led_driver;

architecture sim of tb_top_led_driver is

  constant C_CLK_PERIOD : time    := 8 ns;
  constant C_NB_COUPS  : natural := 4;

  signal clk      : std_logic := '0';
  signal resetn   : std_logic := '0';
  signal bouton_0 : std_logic := '0';
  signal bouton_1 : std_logic := '0';
  signal led0_r   : std_logic;
  signal led0_g   : std_logic;
  signal led0_b   : std_logic;

  signal sim_done : boolean := false;

begin

  dut : entity work.top_led_driver
    generic map (NB_COUPS_HORLOGE => C_NB_COUPS)
    port map (
      clk      => clk,
      resetn   => resetn,
      bouton_0 => bouton_0,
      bouton_1 => bouton_1,
      led0_r   => led0_r,
      led0_g   => led0_g,
      led0_b   => led0_b
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
  begin
    -- Reset
    resetn <= '1';   -- reset actif haut
    wait for 5 * C_CLK_PERIOD;
    resetn <= '0';   -- relachement du reset
    wait for 2 * C_NB_COUPS * C_CLK_PERIOD;

    -- Cas 1 : bouton_1 presse, puis appui LONG sur bouton_0
    -- -> memorisation du VERT au front de bouton_0
    report "bouton_1=1 puis appui long bouton_0 : le VERT doit clignoter.";
    bouton_1 <= '1';
    wait for 2 * C_CLK_PERIOD;
    bouton_0 <= '1';
    wait for 6 * C_NB_COUPS * C_CLK_PERIOD;   -- maintien prolonge
    assert (led0_r = '0') and (led0_b = '0')
      report "ERREUR : seul le vert devrait etre actif." severity error;

    -- Cas 2 : on relache bouton_1 PENDANT que bouton_0 reste maintenu
    -- -> update n'etant plus emis, la couleur doit RESTER verte
    report "Relachement de bouton_1, bouton_0 toujours maintenu : la couleur doit rester VERTE.";
    bouton_1 <= '0';
    wait for 4 * C_NB_COUPS * C_CLK_PERIOD;
    assert led0_b = '0'
      report "ERREUR : le bleu s'est active alors qu'aucun nouveau front n'a eu lieu (update est reste a 1 ?)."
      severity error;

    -- Cas 3 : relachement puis nouvel appui, bouton_1 = 0 -> BLEU
    report "Nouvel appui bouton_0 avec bouton_1=0 : le BLEU doit etre memorise.";
    bouton_0 <= '0';
    wait for 2 * C_NB_COUPS * C_CLK_PERIOD;
    bouton_0 <= '1';
    wait for 6 * C_NB_COUPS * C_CLK_PERIOD;
    assert (led0_r = '0') and (led0_g = '0')
      report "ERREUR : seul le bleu devrait etre actif." severity error;
    bouton_0 <= '0';

    report "Fin de simulation tb_top_led_driver.";
    sim_done <= true;
    wait;
  end process p_stim;

end architecture sim;
