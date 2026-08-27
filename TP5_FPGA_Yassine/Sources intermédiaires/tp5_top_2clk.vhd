library ieee;
use ieee.std_logic_1164.all;

entity tp5_top_2clk is
  generic (
    NB_COUPS_HORLOGE   : positive := 100_000_000;
    NB_CLIGNOTEMENTS   : positive := 10;
    -- Methode de franchissement du domaine clkA vers clkB :
    --   0 = aucune, traversee directe        
    --   1 = synchroniseur a deux bascules    
    --   2 = etirement + detection de front   
    --   3 = bascule d'inversion (toggle)     
    METHODE_CDC        : natural  := 3;
    -- Duree d'etirement en periodes de clkA, utilisee si METHODE_CDC = 1.
    -- Doit valoir au moins 2 x T_clkB / T_clkA, soit 10 pour 250 et 50 MHz.
    NB_COUPS_ETIREMENT : positive := 16
  );
  port (
    clkA   : in  std_logic;  -- domaine rapide (250 MHz)
    clkB   : in  std_logic;  -- domaine lent (50 MHz)
    reset  : in  std_logic;  -- actif haut, asynchrone
    led0_r : out std_logic;
    led0_g : out std_logic;
    led0_b : out std_logic;
    led1_r : out std_logic;
    led1_g : out std_logic;
    led1_b : out std_logic
  );
end entity tp5_top_2clk;

architecture rtl of tp5_top_2clk is

  signal color_code : std_logic_vector(1 downto 0);  -- domaine clkA
  signal update     : std_logic;                     -- domaine clkA
  signal update0    : std_logic;                     -- domaine clkA
  signal update1    : std_logic;                     -- domaine clkB si resynchro
  signal end_cycle0 : std_logic;                     -- domaine clkA
  signal end_cycle1 : std_logic;                     -- domaine clkB, sonde ILA
  signal ten_blinks : std_logic;                     -- domaine clkA

begin

  ------------------------------------------------------------------------
  -- Domaine clkA : comptage des clignotements et sequencement
  ------------------------------------------------------------------------
  u_blink_counter : entity work.blink_counter
    generic map (
      NB_CLIGNOTEMENTS => NB_CLIGNOTEMENTS
    )
    port map (
      clk        => clkA,
      reset      => reset,
      end_cycle  => end_cycle0,
      ten_blinks => ten_blinks
    );

  u_color_fsm : entity work.color_fsm
    port map (
      clk        => clkA,
      reset      => reset,
      ten_blinks => ten_blinks,
      color_code => color_code,
      update     => update
    );

  update0 <= update;

  ------------------------------------------------------------------------
  -- Franchissement de domaine clkA -> clkB
  ------------------------------------------------------------------------

  -- METHODE_CDC = 0, question 4 : traversee directe. L'impulsion dure une
  -- periode de clkA, soit 4 ns a 250 MHz, alors que la periode de clkB vaut
  -- 20 ns. Elle tombe donc entre deux fronts de clkB et disparait.
  gen_direct : if METHODE_CDC = 0 generate
    update1 <= update;
  end generate gen_direct;

  -- METHODE_CDC = 1, premiere tentative : synchroniseur a deux bascules
  -- seul. Il traite la metastabilite mais pas la perte d'evenement, et le
  -- resultat de simulation reste identique a celui de la question 6.
  gen_double_flop : if METHODE_CDC = 1 generate
    u_double_flop : entity work.double_flop
      port map (
        clk_src   => clkA,
        reset_src => reset,
        pulse_in  => update,
        clk_dst   => clkB,
        reset_dst => reset,
        pulse_out => update1
      );
  end generate gen_double_flop;

  -- METHODE_CDC = 2, etirement de l'impulsion cote clkA,
  -- puis double bascule et detection de front cote clkB.
  gen_etirement : if METHODE_CDC = 2 generate
    u_pulse_stretch : entity work.pulse_stretch
      generic map (
        NB_COUPS_ETIREMENT => NB_COUPS_ETIREMENT
      )
      port map (
        clk_src   => clkA,
        reset_src => reset,
        pulse_in  => update,
        clk_dst   => clkB,
        reset_dst => reset,
        pulse_out => update1
      );
  end generate gen_etirement;

  -- METHODE_CDC = 3 : variante par bascule d'inversion.
  gen_toggle : if METHODE_CDC = 3 generate
    u_pulse_sync : entity work.pulse_sync
      port map (
        clk_src   => clkA,
        reset_src => reset,
        pulse_in  => update,
        clk_dst   => clkB,
        reset_dst => reset,
        pulse_out => update1
      );
  end generate gen_toggle;

  ------------------------------------------------------------------------
  -- Domaine clkA : LED0
  ------------------------------------------------------------------------
  u_led_driver0 : entity work.led_driver
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS_HORLOGE
    )
    port map (
      clk        => clkA,
      resetn     => reset,      --actif haut
      color_code => color_code,
      update     => update0,
      led_r      => led0_r,
      led_g      => led0_g,
      led_b      => led0_b,
      end_cycle  => end_cycle0
    );

  ------------------------------------------------------------------------
  -- Domaine clkB : LED1
  ------------------------------------------------------------------------
  --
  u_led_driver1 : entity work.led_driver
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS_HORLOGE
    )
    port map (
      clk        => clkB,
      resetn     => reset,      -- actif haut
      color_code => color_code,
      update     => update1,
      led_r      => led1_r,
      led_g      => led1_g,
      led_b      => led1_b,
      end_cycle  => end_cycle1
    );

end architecture rtl;
