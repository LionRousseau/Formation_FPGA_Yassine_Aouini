library ieee;
use ieee.std_logic_1164.all;


entity full_adder is

	Port ( 
		--Exemple d'entrees
		--input 	: in std_logic;
		A 		: in std_logic;
		B 		: in std_logic;
		Cin 		: in std_logic;
		
		--Exemple de sorties
		--output 	: out std_logic;
		S		: out std_logic;
		Cout    : out std_logic
	);

end full_adder;

 

architecture behavior of full_adder is
 
begin
	S    <= A xor B xor Cin;
	Cout <= (A and B) or (Cin and (A xor B));
   -- output <= XX;  --Affectation d'une sortie

end behavior;

