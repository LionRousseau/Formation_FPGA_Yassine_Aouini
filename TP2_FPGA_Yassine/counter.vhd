library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;


entity counter_unit is
    port ( 
		clk			: in std_logic; 
      -- resetn		: in std_logic; 
       --restart     : in std_logic;
        btn0        : in std_logic;
        btn1        : in std_logic;
       --end_counter			: inout std_logic
        led1_b               : out std_logic
     );
end counter_unit;

architecture behavioral of counter_unit is
	
	--Declaration des signaux internes
    constant MAX_COUNTER : positive := 200000000;  -- valeur trouvée par calcul
    --constant MAX_COUNTER : positive := 200;
	signal count      : std_logic_vector(27 downto 0);
	signal led_value        : std_logic;           -- état de la LED
	signal restart          : std_logic;      
	signal resetn           : std_logic;
	signal end_counter      : std_logic;
	
	begin
	
	restart <= btn0;               -- on associe l'evenement d'appui sur le bouton btn0 au signal restart
	resetn <= not btn1;            -- on associe l'evenement d'appui sur le bouton btn1 au signal resetn

		--Partie sequentielle
		process(clk,resetn)
		begin
			if(resetn = '0') then        -- remise à zéro du compteur
			count <= (others => '0');
			led_value <= '0';            -- reinitialisation de l'etat de la LED
			
			elsif(rising_edge(clk)) then
			     if(restart = '1') then      -- remise à zéro du compteur en cas d'activation du restart
			         count <= (others => '0');
			         led_value <= '0';       -- reinitialisation de l'etat de la LED
			         
			         
			     elsif (count = MAX_COUNTER - 1) then    -- remise à zéro du compteur lors du dépassement de la valeur seuil
			     count <= (others => '0');
			     led_value <= not led_value;             -- inversion de l'état de la LED lors de la fin de la période de 2s
			     
			     else
                count <= count + 1;                      -- incrémentation de la valeur du compteur 
                
                end if;
			
			end if;
		end process;
		
		--Partie combinatoire
		end_counter <= '1' when (count = MAX_COUNTER -1)  -- activation du flag end_counter en cas de dépassement de la valeur seuil
				else '0';
		--led <= end_counter;
		led1_b <= led_value;                              -- actualisation de la valeur de la LED
		

						

end behavioral;