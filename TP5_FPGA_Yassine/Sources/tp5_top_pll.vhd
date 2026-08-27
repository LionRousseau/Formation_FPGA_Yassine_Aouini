library ieee;
use ieee.std_logic_1164.all;

entity tp5_top_pll is
  generic (
    NB_COUPS_HORLOGE : positive := 100_000_000;
    NB_CLIGNOTEMENTS : positive := 10
  );
  port (
    clk_sys  : in  std_logic;  -- horloge de la carte
    reset_bt : in  std_logic;  -- bouton poussoir, actif haut
    led0_r   : out std_logic;
    led0_g   : out std_logic;
    led0_b   : out std_logic;
    led1_r   : out std_logic;
    led1_g   : out std_logic;
    led1_b   : out std_logic
  );
end entity tp5_top_pll;

architecture rtl of tp5_top_pll is

  -- Declaration du composant genere par le Clocking Wizard.
  component clk_wiz_0 is
    port (
      clk_in1  : in  std_logic;
      reset    : in  std_logic;
      locked   : out std_logic;
      clk_out1 : out std_logic;  -- 250 MHz
      clk_out2 : out std_logic   --  50 MHz
    );
  end component clk_wiz_0;

  signal clkA   : std_logic;
  signal clkB   : std_logic;
  signal locked : std_logic;
  signal reset  : std_logic;

  -- Signaux internes remontes ici pour pouvoir les marquer en debug.
  signal color_code : std_logic_vector(1 downto 0);
  signal update     : std_logic;
  signal update1    : std_logic;
  signal end_cycle0 : std_logic;
  signal end_cycle1 : std_logic;
  signal ten_blinks : std_logic;

  attribute MARK_DEBUG : string;
  attribute MARK_DEBUG of color_code : signal is "TRUE";
  attribute MARK_DEBUG of update     : signal is "TRUE";
  attribute MARK_DEBUG of end_cycle0 : signal is "TRUE";
  attribute MARK_DEBUG of ten_blinks : signal is "TRUE";
  attribute MARK_DEBUG of update1    : signal is "TRUE";
  attribute MARK_DEBUG of end_cycle1 : signal is "TRUE";

begin

  ------------------------------------------------------------------------
  -- Generation des horloges
  ------------------------------------------------------------------------
  u_pll : clk_wiz_0
    port map (
      clk_in1  => clk_sys,
      reset    => reset_bt,
      locked   => locked,
      clk_out1 => clkA,
      clk_out2 => clkB
    );


  reset <= reset_bt or (not locked);

  ------------------------------------------------------------------------
  -- Domaine clkA
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

  u_led_driver0 : entity work.led_driver
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS_HORLOGE
    )
    port map (
      clk        => clkA,
      resetn     => reset,
      color_code => color_code,
      update     => update,
      led_r      => led0_r,
      led_g      => led0_g,
      led_b      => led0_b,
      end_cycle  => end_cycle0
    );

  ------------------------------------------------------------------------
  -- Franchissement clkA -> clkB
  ------------------------------------------------------------------------
  u_pulse_sync : entity work.pulse_sync
    port map (
      clk_src   => clkA,
      reset_src => reset,
      pulse_in  => update,
      clk_dst   => clkB,
      reset_dst => reset,
      pulse_out => update1
    );

  ------------------------------------------------------------------------
  -- Domaine clkB
  ------------------------------------------------------------------------
  u_led_driver1 : entity work.led_driver
    generic map (
      NB_COUPS_HORLOGE => NB_COUPS_HORLOGE
    )
    port map (
      clk        => clkB,
      resetn     => reset,
      color_code => color_code,
      update     => update1,
      led_r      => led1_r,
      led_g      => led1_g,
      led_b      => led1_b,
      end_cycle  => end_cycle1
    );

end architecture rtl;
