library ieee;
use ieee.std_logic_1164.all;

entity q1_blink_led is
  generic (
    NB_COUPS_HORLOGE : positive := 62_500_000  -- 0,5 s a 125 MHz
  );
  port (
    clk    : in  std_logic;
    resetn : in  std_logic;
    led0_r : out std_logic
  );
end entity q1_blink_led;

architecture rtl of q1_blink_led is

  type t_state is (S_OFF, S_ON);
  signal state       : t_state;
  signal end_counter : std_logic;

begin

  -- Diviseur d'horloge : impulsion end_counter toutes les NB_COUPS_HORLOGE periodes
  u_counter : entity work.counter_unit
    generic map (NOMBRE_CYCLES => NB_COUPS_HORLOGE)
    port map (
      clk         => clk,
      resetn      => resetn,
      end_counter => end_counter
    );

  -- FSM de clignotement : bascule OFF <-> ON a chaque end_counter
  p_fsm : process (clk, resetn)
  begin
    if resetn = '1' then   -- reset ACTIF HAUT
      state <= S_OFF;
    elsif rising_edge(clk) then
      if end_counter = '1' then
        case state is
          when S_OFF => state <= S_ON;
          when S_ON  => state <= S_OFF;
        end case;
      end if;
    end if;
  end process p_fsm;

  -- Sortie de Moore : ne depend que de l'etat courant
  led0_r <= '1' when state = S_ON else '0';

end architecture rtl;
