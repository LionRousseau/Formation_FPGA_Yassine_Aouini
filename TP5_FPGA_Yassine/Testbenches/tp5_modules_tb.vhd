library ieee;
use ieee.std_logic_1164.all;

entity tp5_modules_tb is
end entity tp5_modules_tb;

architecture sim of tp5_modules_tb is

  constant PERIODE_CLK  : time     := 10 ns;
  constant NB_CLIGN     : positive := 10;
  -- Nombre de coups d'horloge entre deux impulsions end_cycle. Emule la
  -- demi-periode de clignotement du led_driver.
  constant ESPACEMENT   : positive := 6;
  constant NB_TOURS     : positive := 4;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';
  signal fin   : boolean   := false;

  signal end_cycle  : std_logic;
  signal ten_blinks : std_logic;
  signal color_code : std_logic_vector(1 downto 0);
  signal update     : std_logic;

  signal nb_update : natural := 0;

  constant COULEUR_ROUGE : std_logic_vector(1 downto 0) := "01";
  constant COULEUR_VERTE : std_logic_vector(1 downto 0) := "10";
  constant COULEUR_BLEUE : std_logic_vector(1 downto 0) := "11";

  type sequence_t is array (0 to 2) of std_logic_vector(1 downto 0);
  constant SEQUENCE_ATTENDUE : sequence_t :=
    (COULEUR_ROUGE, COULEUR_BLEUE, COULEUR_VERTE);

begin

  clk <= not clk after PERIODE_CLK / 2 when not fin else '0';

  ------------------------------------------------------------------------
  -- Generateur d'impulsions end_cycle, a la place du led_driver
  ------------------------------------------------------------------------
  p_gen_end_cycle : process (clk, reset)
    variable div : natural range 0 to ESPACEMENT - 1;
  begin
    if reset = '1' then
      div       := 0;
      end_cycle <= '0';
    elsif rising_edge(clk) then
      end_cycle <= '0';
      if div = ESPACEMENT - 1 then
        div       := 0;
        end_cycle <= '1';
      else
        div := div + 1;
      end if;
    end if;
  end process p_gen_end_cycle;

  ------------------------------------------------------------------------
  -- Unites sous test
  ------------------------------------------------------------------------
  u_blink_counter : entity work.blink_counter
    generic map (NB_CLIGNOTEMENTS => NB_CLIGN)
    port map (
      clk        => clk,
      reset      => reset,
      end_cycle  => end_cycle,
      ten_blinks => ten_blinks
    );

  u_color_fsm : entity work.color_fsm
    port map (
      clk        => clk,
      reset      => reset,
      ten_blinks => ten_blinks,
      color_code => color_code,
      update     => update
    );

  ------------------------------------------------------------------------
  -- Verifications
  ------------------------------------------------------------------------
  p_check : process (clk)
    variable tb_prev  : std_logic := '0';
    variable up_prev  : std_logic := '0';
    variable cc_prev  : std_logic_vector(1 downto 0) := "00";
    variable nb_ec    : natural := 0;
    variable idx      : natural := 0;
    variable premiere : boolean := true;
  begin
    if rising_edge(clk) and reset = '0' then

      -- 1 et 2 : largeur des impulsions
      assert not (ten_blinks = '1' and tb_prev = '1')
        report "ten_blinks reste a 1 plus d'un coup d'horloge"
        severity error;

      assert not (update = '1' and up_prev = '1')
        report "update reste a 1 plus d'un coup d'horloge : la contrainte "
             & "de l'enonce est violee"
        severity error;

      -- 4 : color_code ne bouge qu'accompagne de update
      assert (color_code = cc_prev) or (update = '1')
        report "color_code a change sans impulsion update : le led_driver "
             & "peut capturer une valeur transitoire"
        severity error;

      -- 3 : espacement des impulsions ten_blinks
      if end_cycle = '1' then
        nb_ec := nb_ec + 1;
      end if;

      if ten_blinks = '1' then
        assert nb_ec = NB_CLIGN
          report "ten_blinks apres " & integer'image(nb_ec)
               & " impulsions end_cycle au lieu de " & integer'image(NB_CLIGN)
          severity error;
        nb_ec := 0;
      end if;

      -- 5 et 6 : sequence des couleurs, dont le chargement initial
      if update = '1' then
        assert color_code = SEQUENCE_ATTENDUE(idx)
          report "Impulsion update numero " & integer'image(nb_update + 1)
               & " : code couleur inattendu"
          severity error;

        if premiere then
          assert color_code = COULEUR_ROUGE
            report "L'etat INIT ne charge pas le rouge au demarrage"
            severity error;
          premiere := false;
          report "Etat INIT : rouge charge des la sortie de reset"
            severity note;
        end if;

        idx       := (idx + 1) mod 3;
        nb_update <= nb_update + 1;
      end if;

      tb_prev := ten_blinks;
      up_prev := update;
      cc_prev := color_code;

    end if;
  end process p_check;

  ------------------------------------------------------------------------
  -- Scenario
  ------------------------------------------------------------------------
  p_scenario : process
  begin
    reset <= '1';
    wait for 3 * PERIODE_CLK;
    wait until rising_edge(clk);
    reset <= '0';

    -- Duree : NB_TOURS x 3 couleurs x NB_CLIGN clignotements x ESPACEMENT
    wait for NB_TOURS * 3 * NB_CLIGN * ESPACEMENT * PERIODE_CLK
           + 20 * PERIODE_CLK;

    report "Impulsions update observees : " & integer'image(nb_update)
      severity note;

    assert nb_update >= NB_TOURS * 3
      report "Trop peu d'impulsions update : le sequencement est bloque"
      severity error;

    report "TESTBENCH UNITAIRE TERMINE : impulsions et sequence conformes"
      severity note;

    fin <= true;
    wait;
  end process p_scenario;

end architecture sim;
