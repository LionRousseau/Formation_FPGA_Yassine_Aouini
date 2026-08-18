library ieee;
use ieee.std_logic_1164.all;

entity top_led_driver is
  generic (
    NB_COUPS_HORLOGE : positive := 62_500_000
  );
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;
    bouton_0 : in  std_logic;
    bouton_1 : in  std_logic;
    led0_r   : out std_logic;
    led0_g   : out std_logic;
    led0_b   : out std_logic
  );
end entity top_led_driver;

architecture rtl of top_led_driver is

  signal btn_prev  : std_logic;
  signal update     : std_logic;
  signal color_code : std_logic_vector(1 downto 0);

begin

  -- Detecteur de front montant sur bouton_0 -> impulsion update d'un cycle
  p_edge : process (clk, resetn)
  begin
    if resetn = '1' then   -- reset ACTIF HAUT
      btn_prev <= '0';
    elsif rising_edge(clk) then
      btn_prev <= bouton_0;
    end if;
  end process p_edge;

  update <= bouton_0 and (not btn_prev);

  -- Selection de la couleur presentee au driver
  color_code <= "10" when bouton_1 = '1' else "11";  -- vert / bleu

  -- Instanciation du driver de LED RGB (Q8)
  u_led_driver : entity work.led_driver
    generic map (NB_COUPS_HORLOGE => NB_COUPS_HORLOGE)
    port map (
      clk        => clk,
      resetn     => resetn,
      color_code => color_code,
      update     => update,
      led_r      => led0_r,
      led_g      => led0_g,
      led_b      => led0_b
    );

end architecture rtl;
