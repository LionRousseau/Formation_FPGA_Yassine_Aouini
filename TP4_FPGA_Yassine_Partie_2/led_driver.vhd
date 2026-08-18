-- Module de pilotage d'une LED RGB.
-- Fait clignoter la LED RGB avec la couleur definie par color_code.
-- La couleur n'est prise en compte QUE lorsque update = '1' :
-- color_code est memorise dans un registre 2 bits avec enable (la
-- "memoire" du TP). Tant qu'aucun update n'arrive, la LED garde sa
-- couleur courante.
--
-- Table de codes (enonce) :
--   "01" -> rouge, "10" -> verte, "11" -> bleue, "00" -> eteinte

library ieee;
use ieee.std_logic_1164.all;

entity led_driver is
  generic (
    NB_COUPS_HORLOGE : positive := 62_500_000
  );
  port (
    clk        : in  std_logic;
    resetn     : in  std_logic;
    color_code : in  std_logic_vector(1 downto 0);
    update     : in  std_logic;
    led_r      : out std_logic;
    led_g      : out std_logic;
    led_b      : out std_logic;
    end_cycle  : out std_logic   -- impulsion d'un cycle a la fin d'une phase allumee
  );
end entity led_driver;

architecture rtl of led_driver is

  signal end_counter : std_logic;
  signal led_value : std_logic;                     -- cadence : '1' = phase allumee
  signal color_reg   : std_logic_vector(1 downto 0);  -- couleur memorisee

begin

  -- Moteur de clignotement (counter_unit du TP2 + toggle)
  u_counter : entity work.counter_unit
    generic map (NOMBRE_CYCLES => NB_COUPS_HORLOGE)
    port map (
      clk         => clk,
      resetn      => resetn,
      end_counter => end_counter
    );

  p_blink : process (clk, resetn)
  begin
    if resetn = '1' then   -- reset ACTIF HAUT
      led_value <= '0';
    elsif rising_edge(clk) then
      if end_counter = '1' then
        led_value <= not led_value;
      end if;
    end if;
  end process p_blink;

  -- Registre de couleur : charge color_code uniquement si update = '1'
  -- (registre avec enable = la memoire du design)
  p_color : process (clk, resetn)
  begin
    if resetn = '1' then   -- reset ACTIF HAUT
      color_reg <= "00";                -- LED eteinte apres reset
    elsif rising_edge(clk) then
      if update = '1' then
        color_reg <= color_code;
      end if;
    end if;
  end process p_color;

  -- Decodeur couleur : applique l'onde de clignotement a la LED
  -- correspondant au code memorise
  led_r <= led_value when color_reg = "01" else '0';
  led_g <= led_value when color_reg = "10" else '0';
  led_b <= led_value when color_reg = "11" else '0';
  end_cycle <= end_counter and led_value;

end architecture rtl;
