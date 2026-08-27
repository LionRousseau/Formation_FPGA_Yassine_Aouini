library ieee;
use ieee.std_logic_1164.all;

entity tp5_top_tb is
end entity tp5_top_tb;

architecture sim of tp5_top_tb is

  constant PERIODE_CLK : time     := 10 ns;  -- 100 MHz
  constant NB_COUPS    : positive := 4;
  constant NB_CLIGN    : positive := 10;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';
  signal fin   : boolean   := false;

  signal led0_r, led0_g, led0_b : std_logic;
  signal led1_r, led1_g, led1_b : std_logic;

  signal led0_on : std_logic;

  type couleur_t is (ETEINT, ROUGE, VERT, BLEU, INVALIDE);

  function couleur_de (r, g, b : std_logic) return couleur_t is
    variable v : std_logic_vector(2 downto 0);
  begin
    v := r & g & b;
    case v is
      when "000"  => return ETEINT;
      when "100"  => return ROUGE;
      when "010"  => return VERT;
      when "001"  => return BLEU;
      when others => return INVALIDE;
    end case;
  end function couleur_de;

  type sequence_t is array (0 to 2) of couleur_t;
  constant SEQUENCE_ATTENDUE : sequence_t := (ROUGE, BLEU, VERT);

begin

  ------------------------------------------------------------------------
  -- Horloge
  ------------------------------------------------------------------------
  clk <= not clk after PERIODE_CLK / 2 when not fin else '0';

  ------------------------------------------------------------------------
  -- Unite sous test
  ------------------------------------------------------------------------
  uut : entity work.tp5_top
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS,
      NB_CLIGNOTEMENTS => NB_CLIGN
    )
    port map (
      clk    => clk,
      reset  => reset,
      led0_r => led0_r,
      led0_g => led0_g,
      led0_b => led0_b,
      led1_r => led1_r,
      led1_g => led1_g,
      led1_b => led1_b
    );

  led0_on <= led0_r or led0_g or led0_b;

  ------------------------------------------------------------------------
  -- Verification 1 : les deux LED sont identiques en mono-horloge
  ------------------------------------------------------------------------
  p_check_identiques : process (clk)
  begin
    if rising_edge(clk) and reset = '0' then
      assert (led0_r = led1_r) and (led0_g = led1_g) and (led0_b = led1_b)
        report "Les deux LED divergent alors qu'elles partagent la meme horloge"
        severity error;
    end if;
  end process p_check_identiques;

  ------------------------------------------------------------------------
  -- Verification 2 : aucune combinaison invalide sur les sorties
  ------------------------------------------------------------------------
  p_check_valide : process (clk)
  begin
    if rising_edge(clk) and reset = '0' then
      assert couleur_de(led0_r, led0_g, led0_b) /= INVALIDE
        report "LED0 affiche plusieurs composantes simultanement"
        severity error;
    end if;
  end process p_check_valide;

  ------------------------------------------------------------------------
  -- Scenario et verification de la sequence
  ------------------------------------------------------------------------
  p_scenario : process
    variable couleur_courante : couleur_t;
    variable nb_clign         : natural;
  begin

    ----------------------------------------------------------------------
    -- Reset initial
    ----------------------------------------------------------------------
    reset <= '1';
    wait for 3 * PERIODE_CLK;
    wait until rising_edge(clk);
    reset <= '0';
    report "=== Phase 1 : deroulement nominal ===" severity note;

    wait until led0_on = '1';

    ----------------------------------------------------------------------
    -- Phase 1 : deux tours complets
    ----------------------------------------------------------------------
    for tour in 0 to 1 loop
      for indice in 0 to 2 loop

        couleur_courante := couleur_de(led0_r, led0_g, led0_b);

        assert couleur_courante = SEQUENCE_ATTENDUE(indice)
          report "Tour " & integer'image(tour) & ", position "
               & integer'image(indice) & " : couleur "
               & couleur_t'image(couleur_courante) & " au lieu de "
               & couleur_t'image(SEQUENCE_ATTENDUE(indice))
          severity error;

        nb_clign := 1;
        loop
          wait until led0_on = '0';
          wait until led0_on = '1';
          exit when couleur_de(led0_r, led0_g, led0_b) /= couleur_courante;
          nb_clign := nb_clign + 1;
        end loop;

        assert nb_clign = NB_CLIGN
          report "Couleur " & couleur_t'image(couleur_courante)
               & " : " & integer'image(nb_clign) & " clignotements au lieu de "
               & integer'image(NB_CLIGN)
          severity error;

        report "Couleur " & couleur_t'image(couleur_courante) & " : "
             & integer'image(nb_clign) & " clignotements" severity note;

      end loop;
    end loop;

    ----------------------------------------------------------------------
    -- Phase 2 : reset applique en cours de sequence
    ----------------------------------------------------------------------
    report "=== Phase 2 : reset en cours de sequence ===" severity note;

    wait until led0_on = '0';
    wait for 2 * NB_COUPS * PERIODE_CLK;

    reset <= '1';
    wait for PERIODE_CLK;

    assert led0_on = '0' and (led1_r or led1_g or led1_b) = '0'
      report "Le reset n'eteint pas immediatement les deux LED"
      severity error;

    wait for 3 * PERIODE_CLK;
    wait until rising_edge(clk);
    reset <= '0';

    ----------------------------------------------------------------------
    -- Verification du redemarrage
    ----------------------------------------------------------------------
    wait until led0_on = '1';

    couleur_courante := couleur_de(led0_r, led0_g, led0_b);
    assert couleur_courante = ROUGE
      report "Apres reset la sequence repart sur "
           & couleur_t'image(couleur_courante) & " au lieu du rouge"
      severity error;

    nb_clign := 1;
    loop
      wait until led0_on = '0';
      wait until led0_on = '1';
      exit when couleur_de(led0_r, led0_g, led0_b) /= couleur_courante;
      nb_clign := nb_clign + 1;
    end loop;

    assert nb_clign = NB_CLIGN
      report "Apres reset : " & integer'image(nb_clign)
           & " clignotements rouges au lieu de " & integer'image(NB_CLIGN)
           & ", le compteur de clignotements n'a pas ete remis a zero"
      severity error;

    assert couleur_de(led0_r, led0_g, led0_b) = BLEU
      report "Apres reset la couleur suivant le rouge n'est pas le bleu"
      severity error;

    report "SIMULATION TERMINEE : tous les scenarios sont conformes"
      severity note;

    fin <= true;
    wait;
  end process p_scenario;

end architecture sim;
