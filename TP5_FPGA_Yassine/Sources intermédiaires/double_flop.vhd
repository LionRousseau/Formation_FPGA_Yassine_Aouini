library ieee;
use ieee.std_logic_1164.all;

entity double_flop is
  port (
    -- Le domaine source n'est pas utilise
    -- Le port est conserve pour que l'interface soit interchangeable avec
    -- celle de pulse_stretch et de pulse_sync.
    clk_src   : in  std_logic;
    reset_src : in  std_logic;
    pulse_in  : in  std_logic;

    clk_dst   : in  std_logic;
    reset_dst : in  std_logic;
    pulse_out : out std_logic
  );
end entity double_flop;

architecture rtl of double_flop is

  -- sync(0) : premiere bascule, celle qui peut devenir metastable
  -- sync(1) : deuxieme bascule, valeur consideree comme stabilisee
  signal sync : std_logic_vector(1 downto 0);

  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync : signal is "TRUE";

begin

  p_synchro : process (clk_dst, reset_dst)
  begin
    if reset_dst = '1' then
      sync <= (others => '0');
    elsif rising_edge(clk_dst) then
      sync <= sync(0) & pulse_in;
    end if;
  end process p_synchro;

  pulse_out <= sync(1);

end architecture rtl;
