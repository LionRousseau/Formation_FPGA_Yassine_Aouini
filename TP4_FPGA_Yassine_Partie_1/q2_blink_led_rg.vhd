library ieee;
use ieee.std_logic_1164.all;

entity q2_blink_led_rg is
  generic (
    NB_COUPS_HORLOGE : positive := 62_500_000
  );
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;
    bouton_0 : in  std_logic;
    led0_r   : out std_logic;
    led0_g   : out std_logic
  );
end entity q2_blink_led_rg;

architecture rtl of q2_blink_led_rg is

  type t_state is (S_OFF, S_ON);
  signal state       : t_state;
  signal end_counter : std_logic;
  signal led_value   : std_logic;  -- onde de clignotement commune

begin

  u_counter : entity work.counter_unit
    generic map (NOMBRE_CYCLES => NB_COUPS_HORLOGE)
    port map (
      clk         => clk,
      resetn      => resetn,
      end_counter => end_counter
    );

  p_fsm : process (clk, resetn)
  begin
    if resetn = '1' then   -- reset ACTIF HAUT (convention du counter_unit du TP2)
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

  led_value <= '1' when state = S_ON else '0';

  -- Aiguillage combinatoire selon bouton_0
  led0_r <= led_value and (not bouton_0);
  led0_g <= led_value and bouton_0;

end architecture rtl;
