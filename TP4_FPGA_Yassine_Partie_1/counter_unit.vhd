library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity counter_unit is
    generic ( NOMBRE_CYCLES : positive := 200000000 );   -- nombre de coups d'horloge a compter
    port (
        clk         : in  std_logic;
        resetn      : in  std_logic;
        end_counter : out std_logic
    );
end counter_unit;

architecture behavioral of counter_unit is
    signal count : std_logic_vector(27 downto 0);   -- taille du compteur 
begin
    process(clk, resetn)
    begin
        if (resetn = '1') then -- reset actif à l'état haut pour utilisation du bouton
            count <= (others => '0');
        elsif rising_edge(clk) then
            if (count = NOMBRE_CYCLES - 1) then -- remise à zéro après avoir atteint la valeur max
                count <= (others => '0');
            else
                count <= count + 1; -- incrémentation du compteur
            end if;
        end if;
    end process;

    end_counter <= '1' when (count = NOMBRE_CYCLES - 1) else '0';
end behavioral;
