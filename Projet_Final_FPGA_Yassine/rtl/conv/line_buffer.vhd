--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : line_buffer.vhd
-- Description : Ligne a retard de profondeur DEPTH echantillons, avec validation
--               d'horloge (clock-enable). La sortie dout est l'entree din
--               retardee d'exactement DEPTH avances (en = '1').
--
--               Utilisee par window_gen pour reconstituer les lignes N-1 et N-2
--               de l'image (DEPTH = largeur d'image). Lecture combinatoire en
--               queue de registre a decalage : Vivado infere une chaine SRL
--               (SRLC32E) economique, ou un bloc BRAM selon les options de
--               synthese. C'est l'element << line buffer >> de la planche SCH-03.
--
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity line_buffer is
  generic (
    DATA_W : natural := 8;
    DEPTH  : natural := 640            -- retard en nombre d'echantillons
  );
  port (
    clk  : in  std_logic;
    en   : in  std_logic;              -- avance le registre a decalage
    din  : in  unsigned(DATA_W-1 downto 0);
    dout : out unsigned(DATA_W-1 downto 0)   -- din retarde de DEPTH avances
  );
end entity line_buffer;

architecture rtl of line_buffer is
  type sr_t is array (0 to DEPTH-1) of unsigned(DATA_W-1 downto 0);
  signal sr : sr_t := (others => (others => '0'));
begin
  -- sr(0) = din retarde de 1 avance, ... sr(DEPTH-1) = din retarde de DEPTH.
  process(clk)
  begin
    if rising_edge(clk) then
      if en = '1' then
        sr(0) <= din;
        for i in 1 to DEPTH-1 loop
          sr(i) <= sr(i-1);
        end loop;
      end if;
    end if;
  end process;

  dout <= sr(DEPTH-1);
end architecture rtl;
