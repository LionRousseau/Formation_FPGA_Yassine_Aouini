library ieee;
use ieee.std_logic_1164.all;

entity pulse_stretch is
  generic (
    -- Duree d'etirement, exprimee en periodes de clk_src
    NB_COUPS_ETIREMENT : positive := 16
  );
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
end entity pulse_stretch;

architecture rtl of pulse_stretch is

  -- Temps 1 : etirement dans le domaine source
  signal niveau_etire : std_logic;
  signal compteur     : natural range 0 to NB_COUPS_ETIREMENT;

  -- Temps 2 : synchronisation et detection de front dans le domaine dest.
  -- sync(0) : premiere bascule, celle qui peut devenir metastable
  -- sync(1) : deuxieme bascule, valeur consideree comme stabilisee
  -- sync(2) : retard d'un coup d'horloge pour la detection de front
  signal sync      : std_logic_vector(2 downto 0);
  signal pulse_reg : std_logic;

  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync : signal is "TRUE";

begin

  ------------------------------------------------------------------------
  -- Temps 1 : impulsion -> niveau etire, dans clk_src
  ------------------------------------------------------------------------
  p_etirement : process (clk_src, reset_src)
  begin
    if reset_src = '1' then
      niveau_etire <= '0';
      compteur     <= 0;
    elsif rising_edge(clk_src) then
      if pulse_in = '1' then
        -- Une nouvelle impulsion relance l'etirement a pleine duree
        niveau_etire <= '1';
        compteur     <= NB_COUPS_ETIREMENT;
      elsif compteur > 1 then
        compteur <= compteur - 1;
      else
        compteur     <= 0;
        niveau_etire <= '0';
      end if;
    end if;
  end process p_etirement;

  ------------------------------------------------------------------------
  -- Temps 2 : niveau etire -> impulsion propre, dans clk_dst
  ------------------------------------------------------------------------
  p_synchro : process (clk_dst, reset_dst)
  begin
    if reset_dst = '1' then
      sync      <= (others => '0');
      pulse_reg <= '0';
    elsif rising_edge(clk_dst) then
      sync <= sync(1 downto 0) & niveau_etire;
      -- Front montant detecte entre les deux bascules deja stabilisees.
      pulse_reg <= sync(1) and (not sync(2));
    end if;
  end process p_synchro;

  pulse_out <= pulse_reg;

end architecture rtl;
