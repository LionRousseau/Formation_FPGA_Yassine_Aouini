library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity cycle_counter_unit is
    generic (
        NB_COUPS_HORLOGE : positive := 2000; -- modifier la taille du compteur de temporisation
        NB_CLIGN         : positive := 3     -- nombre de clignotements avant changement d'état
    );
    port (
        clk         : in  std_logic;
        resetn      : in  std_logic;
        restart         : in  std_logic;                     -- restart
        led_value   : out std_logic;                    -- état de la LED (allumée ou éteinte)
        count_cycle : out std_logic_vector(1 downto 0); -- 2 bits car on compte 3 clignotements
        end_cycle   : out std_logic                      -- signal de changement de couleur de la LED
    );
end cycle_counter_unit;

architecture behavioral of cycle_counter_unit is

    component counter_unit
        generic ( NOMBRE_CYCLES : positive );       -- compteur de temporisation
        port ( 
        clk : in std_logic;
        resetn : in std_logic; 
        end_counter : out std_logic );
    end component;

    signal end_counter : std_logic;
    signal led_value_s : std_logic;
    signal count_s     : std_logic_vector(1 downto 0);

begin

    counter_1 : counter_unit
        generic map ( NOMBRE_CYCLES => NB_COUPS_HORLOGE )
        port map ( clk => clk, resetn => resetn, end_counter => end_counter );

    process(clk, resetn)
    begin
        if (resetn = '1') then
            led_value_s <= '0';                 -- on éteint la LED en cas de reset
            count_s     <= (others => '0');     -- remise du compteur à zéro
        elsif rising_edge(clk) then
            if (restart = '1') then                          
                led_value_s <= '0';             -- on éteint la LED en cas de restart
                count_s     <= (others => '0'); -- remise du compteur à zéro
            elsif (end_counter = '1') then
                led_value_s <= not led_value_s; -- toggle de l'état de la LED
                if (led_value_s = '1') then
                    if (count_s = NB_CLIGN - 1) then 
                        count_s <= (others => '0');
                    else
                        count_s <= count_s + 1; -- incrémentation du compteur de clignotement
                    end if;
                end if;
            end if;
        end if;
    end process;

    led_value   <= led_value_s; 
    count_cycle <= count_s;

    -- impulsion en fin du NB_CLIGN-ieme clignotement (au moment ou le compteur reboucle)
    end_cycle <= '1' when (end_counter = '1' and led_value_s = '1' and count_s = NB_CLIGN - 1) else '0';

end behavioral;
