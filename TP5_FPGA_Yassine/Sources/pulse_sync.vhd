library ieee;
use ieee.std_logic_1164.all;

entity pulse_sync is
  port (
    -- Domaine source
    clk_src   : in  std_logic;
    reset_src : in  std_logic;  -- actif haut, asynchrone
    pulse_in  : in  std_logic;  -- impulsion d'un coup d'horloge de clk_src

    -- Domaine destination
    clk_dst   : in  std_logic;
    reset_dst : in  std_logic;  -- actif haut, asynchrone
    pulse_out : out std_logic   -- impulsion d'un coup d'horloge de clk_dst
  );
end entity pulse_sync;

architecture rtl of pulse_sync is

  signal toggle : std_logic;

  -- sync(0) : premiere bascule, celle qui peut devenir metastable
  -- sync(1) : deuxieme bascule, valeur consideree comme stabilisee
  -- sync(2) : retard d'un coup d'horloge pour la detection de front
  signal sync : std_logic_vector(2 downto 0);

  signal pulse_reg : std_logic;


  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync : signal is "TRUE";

  attribute MARK_DEBUG : string;
  attribute MARK_DEBUG of toggle    : signal is "TRUE";
  attribute MARK_DEBUG of sync      : signal is "TRUE";
  attribute MARK_DEBUG of pulse_reg : signal is "TRUE";

begin

  ------------------------------------------------------------------------
  -- Domaine source : conversion impulsion -> niveau
  ------------------------------------------------------------------------
  p_src : process (clk_src, reset_src)
  begin
    if reset_src = '1' then
      toggle <= '0';
    elsif rising_edge(clk_src) then
      if pulse_in = '1' then
        toggle <= not toggle;
      end if;
    end if;
  end process p_src;

  ------------------------------------------------------------------------
  -- Domaine destination : synchronisation puis detection de front
  ------------------------------------------------------------------------
  p_dst : process (clk_dst, reset_dst)
  begin
    if reset_dst = '1' then
      sync      <= (others => '0');
      pulse_reg <= '0';
    elsif rising_edge(clk_dst) then
      sync      <= sync(1 downto 0) & toggle;
      -- Front detecte entre les deux bascules deja stabilisees
      pulse_reg <= sync(1) xor sync(2);
    end if;
  end process p_dst;

  pulse_out <= pulse_reg;

end architecture rtl;
