library ieee;
use ieee.std_logic_1164.all;

entity tp5_top is
  generic (
    NB_COUPS_HORLOGE : positive := 100_000_000;  -- demi-periode de clignotement
    NB_CLIGNOTEMENTS : positive := 10            -- clignotements par couleur
  );
  port (
    clk    : in  std_logic;
    reset  : in  std_logic;  -- actif haut, asynchrone
    led0_r : out std_logic;
    led0_g : out std_logic;
    led0_b : out std_logic;
    led1_r : out std_logic;
    led1_g : out std_logic;
    led1_b : out std_logic
  );
end entity tp5_top;

architecture rtl of tp5_top is

  signal color_code : std_logic_vector(1 downto 0);
  signal update     : std_logic;

  signal update0 : std_logic;
  signal update1 : std_logic;

  signal end_cycle0 : std_logic;  -- pilote le comptage des clignotements
  signal end_cycle1 : std_logic;  -- inutilise ici, pour sonde ILA
  signal ten_blinks : std_logic;

begin

  ------------------------------------------------------------------------
  -- Comptage des clignotements de la LED0
  ------------------------------------------------------------------------
  u_blink_counter : entity work.blink_counter
    generic map (
      NB_CLIGNOTEMENTS => NB_CLIGNOTEMENTS
    )
    port map (
      clk        => clk,
      reset      => reset,
      end_cycle  => end_cycle0,
      ten_blinks => ten_blinks
    );

  ------------------------------------------------------------------------
  -- Sequencement des couleurs
  ------------------------------------------------------------------------
  u_color_fsm : entity work.color_fsm
    port map (
      clk        => clk,
      reset      => reset,
      ten_blinks => ten_blinks,
      color_code => color_code,
      update     => update
    );

  -- Distribution de l'impulsion update vers les deux drivers
  update0 <= update;
  update1 <= update;

  ------------------------------------------------------------------------
  -- Pilotage des deux LED RGB
  ------------------------------------------------------------------------
  u_led_driver0 : entity work.led_driver
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS_HORLOGE
    )
    port map (
      clk        => clk,
      resetn     => reset,      -- port nomme resetn mais actif haut
      color_code => color_code,
      update     => update0,
      led_r      => led0_r,
      led_g      => led0_g,
      led_b      => led0_b,
      end_cycle  => end_cycle0
    );

  u_led_driver1 : entity work.led_driver
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS_HORLOGE
    )
    port map (
      clk        => clk,
      resetn     => reset,      -- port nomme resetn mais actif haut
      color_code => color_code,
      update     => update1,
      led_r      => led1_r,
      led_g      => led1_g,
      led_b      => led1_b,
      end_cycle  => end_cycle1
    );

end architecture rtl;
