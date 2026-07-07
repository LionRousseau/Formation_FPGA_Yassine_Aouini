library ieee;
use ieee.std_logic_1164.all;

entity tb_counter is
end tb_counter;

architecture behavioral of tb_counter is

	--signal resetn      : std_logic := '0';
	signal clk         : std_logic := '0';
	signal btn0         : std_logic := '0';
	signal btn1         : std_logic := '0';
	signal end_counter : std_logic;
	signal led         : std_logic;
	
	-- Les constantes suivantes permette de definir la frequence de l'horloge 
	constant hp : time := 5 ns;      --demi periode de 5ns
	constant period : time := 2*hp;  --periode de 10ns, soit une frequence de 100Hz
	
	--Declaration de l'entite a tester
	component counter_unit 
		port ( 
			clk			: in std_logic; 
			--resetn		: in std_logic; 
			btn0			: in std_logic;
			btn1			: in std_logic;
			--end_counter			: inout std_logic
			led1_b			: out std_logic
			
		 );
	end component;
	
	

	begin
	
	--Affectation des signaux du testbench avec ceux de l'entite a tester
	uut: counter_unit
        port map (
            clk => clk, 
            --resetn=>resetn, 
            btn0 => btn0,
            btn1 => btn1,
          --  end_counter => end_counter
            led1_b => led
        );
		
	--Simulation du signal d'horloge en continue
	process
    begin
		wait for hp;
		clk <= not clk;
	end process;


	process
	begin        
	 -- resetn <= '0';
	   btn1 <= '1';        -- initialisation des valeurs reset et restart
	   btn0 <= '0';
	   wait for 2*period;
	   --resetn <= '1';
	   btn1 <= '0';
	   wait;
	   -- TESTS A EFFECTUER
	   
	end process;
	
	
end behavioral;