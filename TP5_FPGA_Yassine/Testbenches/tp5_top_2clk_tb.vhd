library ieee;
use ieee.std_logic_1164.all;

entity tp5_top_2clk_tb is
  generic (
    -- 0 = traversee directe (questions 4 a 6)
    -- 1 = synchroniseur a deux bascules seul (premiere tentative, Q8)
    -- 2 = etirement + detection de front (solution retenue, Q8)
    -- 3 = bascule d'inversion (variante discutee)
    METHODE_CDC : natural := 3
  );
end entity tp5_top_2clk_tb;

architecture sim of tp5_top_2clk_tb is

  constant PERIODE_A : time     := 4 ns;   -- 250 MHz
  constant PERIODE_B : time     := 20 ns;  --  50 MHz
  constant DEPHASAGE : time     := 3 ns;   -- desalignement volontaire
  constant NB_COUPS  : positive := 8;
  constant NB_CLIGN  : positive := 10;

  signal clkA  : std_logic := '0';
  signal clkB  : std_logic := '0';
  signal reset : std_logic := '1';
  signal fin   : boolean   := false;

  signal led0_r, led0_g, led0_b : std_logic;
  signal led1_r, led1_g, led1_b : std_logic;

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

  -- Couleur reellement chargee dans chaque driver, independamment de
  -- l'etat allume ou eteint du clignotement
  signal couleur0 : couleur_t;
  signal couleur1 : couleur_t;

  signal nb_changements0 : natural := 0;
  signal nb_changements1 : natural := 0;

begin

  ------------------------------------------------------------------------
  -- Horloges et reset
  ------------------------------------------------------------------------
  clkA <= not clkA after PERIODE_A / 2 when not fin else '0';

  p_clkB : process
  begin
    clkB <= '0';
    wait for DEPHASAGE;
    loop
      exit when fin;
      clkB <= '1';
      wait for PERIODE_B / 2;
      clkB <= '0';
      wait for PERIODE_B / 2;
    end loop;
    wait;
  end process p_clkB;

  p_reset : process
  begin
    reset <= '1';
    wait for 5 * PERIODE_B;
    wait until rising_edge(clkA);
    reset <= '0';
    wait;
  end process p_reset;

  ------------------------------------------------------------------------
  -- Unite sous test
  ------------------------------------------------------------------------
  uut : entity work.tp5_top_2clk
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS,
      NB_CLIGNOTEMENTS => NB_CLIGN,
      METHODE_CDC      => METHODE_CDC
    )
    port map (
      clkA   => clkA,
      clkB   => clkB,
      reset  => reset,
      led0_r => led0_r,
      led0_g => led0_g,
      led0_b => led0_b,
      led1_r => led1_r,
      led1_g => led1_g,
      led1_b => led1_b
    );

  ------------------------------------------------------------------------
  -- Observation des couleurs effectivement affichees
  ------------------------------------------------------------------------
  -- On memorise la derniere couleur non eteinte vue sur chaque LED, ce qui
  -- filtre les phases eteintes du clignotement.
  p_observe0 : process (led0_r, led0_g, led0_b)
    variable c : couleur_t;
  begin
    c := couleur_de(led0_r, led0_g, led0_b);
    if c /= ETEINT and c /= INVALIDE then
      couleur0 <= c;
    end if;
  end process p_observe0;

  p_observe1 : process (led1_r, led1_g, led1_b)
    variable c : couleur_t;
  begin
    c := couleur_de(led1_r, led1_g, led1_b);
    if c /= ETEINT and c /= INVALIDE then
      couleur1 <= c;
    end if;
  end process p_observe1;

  p_compte0 : process (couleur0)
  begin
    if couleur0'event then
      nb_changements0 <= nb_changements0 + 1;
    end if;
  end process p_compte0;

  p_compte1 : process (couleur1)
  begin
    if couleur1'event then
      nb_changements1 <= nb_changements1 + 1;
    end if;
  end process p_compte1;

  ------------------------------------------------------------------------
  -- Scenario et bilan
  ------------------------------------------------------------------------
  p_scenario : process
    constant NB_TOURS : positive := 3;
    -- Duree d'une couleur : NB_CLIGN clignotements de la LED0, chaque
    -- clignotement valant deux demi-periodes de NB_COUPS coups de clkA.
    constant DUREE_COULEUR : time :=
      NB_CLIGN * 2 * NB_COUPS * PERIODE_A;
  begin
    wait until reset = '0';

    case METHODE_CDC is
      when 0 =>
        report "=== Question 6 : traversee directe, sans precaution ==="
          severity note;
      when 1 =>
        report "=== Question 8, tentative 1 : synchroniseur a deux bascules seul ==="
          severity note;
      when 2 =>
        report "=== Question 8, solution retenue : etirement + detection de front ==="
          severity note;
      when others =>
        report "=== Variante : bascule d'inversion (toggle) ==="
          severity note;
    end case;

    wait for NB_TOURS * 3 * DUREE_COULEUR + DUREE_COULEUR / 2;

    report "Changements de couleur observes sur LED0 (clkA) : "
         & integer'image(nb_changements0) severity note;
    report "Changements de couleur observes sur LED1 (clkB) : "
         & integer'image(nb_changements1) severity note;

    if nb_changements1 < nb_changements0 then
      report "LED1 a rate " & integer'image(nb_changements0 - nb_changements1)
           & " changement(s) de couleur : l'impulsion update n'a pas ete "
           & "capturee de facon fiable dans le domaine clkB."
        severity warning;
    else
      report "LED1 a suivi tous les changements de couleur de LED0."
        severity note;
    end if;

    fin <= true;
    wait;
  end process p_scenario;

end architecture sim;
