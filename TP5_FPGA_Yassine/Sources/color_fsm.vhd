library ieee;
use ieee.std_logic_1164.all;

entity color_fsm is
  port (
    clk        : in  std_logic;
    reset      : in  std_logic;                     -- actif haut, asynchrone
    ten_blinks : in  std_logic;                     -- impulsion d'un coup d'horloge
    color_code : out std_logic_vector(1 downto 0);  -- code couleur a charger
    update     : out std_logic                      -- impulsion d'un coup d'horloge
  );
end entity color_fsm;

architecture rtl of color_fsm is

  constant COULEUR_ETEINTE : std_logic_vector(1 downto 0) := "00";
  constant COULEUR_ROUGE   : std_logic_vector(1 downto 0) := "01";
  constant COULEUR_VERTE   : std_logic_vector(1 downto 0) := "10";
  constant COULEUR_BLEUE   : std_logic_vector(1 downto 0) := "11";

  type etat_t is (INIT, ROUGE, BLEU, VERT);
  signal etat : etat_t;

  signal color_reg  : std_logic_vector(1 downto 0);
  signal update_reg : std_logic;

begin

  p_fsm : process (clk, reset)
  begin
    if reset = '1' then
      etat       <= INIT;
      color_reg  <= COULEUR_ETEINTE;
      update_reg <= '0';
    elsif rising_edge(clk) then

      -- Valeur par defaut : impulsion d'un seul coup d'horloge
      update_reg <= '0';

      case etat is

        when INIT =>
          -- Chargement immediat du rouge au demarrage
          color_reg  <= COULEUR_ROUGE;
          update_reg <= '1';
          etat       <= ROUGE;

        when ROUGE =>
          if ten_blinks = '1' then
            color_reg  <= COULEUR_BLEUE;
            update_reg <= '1';
            etat       <= BLEU;
          end if;

        when BLEU =>
          if ten_blinks = '1' then
            color_reg  <= COULEUR_VERTE;
            update_reg <= '1';
            etat       <= VERT;
          end if;

        when VERT =>
          if ten_blinks = '1' then
            color_reg  <= COULEUR_ROUGE;
            update_reg <= '1';
            etat       <= ROUGE;
          end if;

      end case;

    end if;
  end process p_fsm;

  color_code <= color_reg;
  update     <= update_reg;

end architecture rtl;
