library ieee;
use ieee.std_logic_1164.all;

entity blink_counter is
  generic (
    NB_CLIGNOTEMENTS : positive := 10
  );
  port (
    clk        : in  std_logic;
    reset      : in  std_logic;  -- actif haut, asynchrone
    end_cycle  : in  std_logic;  -- impulsion d'un coup d'horloge (LED0)
    ten_blinks : out std_logic   -- impulsion d'un coup d'horloge
  );
end entity blink_counter;

architecture rtl of blink_counter is

  signal compteur  : natural range 0 to NB_CLIGNOTEMENTS - 1;
  signal impulsion : std_logic;

begin

  p_compte : process (clk, reset)
  begin
    if reset = '1' then
      compteur  <= 0;
      impulsion <= '0';
    elsif rising_edge(clk) then

      -- Valeur par defaut de la sortie : garantit l'impulsion d'un seul
      -- coup d'horloge.
      impulsion <= '0';

      if end_cycle = '1' then
        if compteur = NB_CLIGNOTEMENTS - 1 then
          compteur  <= 0;
          impulsion <= '1';
        else
          compteur <= compteur + 1;
        end if;
      end if;

    end if;
  end process p_compte;

  ten_blinks <= impulsion;

end architecture rtl;
