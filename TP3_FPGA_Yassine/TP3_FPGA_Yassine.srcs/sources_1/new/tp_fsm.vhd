library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity tp_fsm is
    generic (
        NB_COUPS_HORLOGE : positive := 200000000;   -- valeur max du compteur de temporisation
        NB_CLIGN         : positive := 3       -- nombre de clignotements par etat
    );
    port (
        clk     : in  std_logic;
        resetn  : in  std_logic;               -- reset actif à l'état haut pour utilisation du bouton
        restart_tp : in  std_logic;               -- bouton : retour a l'etat initial (blanc)
        led0_r   : out std_logic;
        led0_g   : out std_logic;
        led0_b   : out std_logic
    );
end tp_fsm;

architecture behavioral of tp_fsm is

    -- etats de la machine (un nom par couleur)
    type state is (blanc, rouge, bleu, vert);
    signal current_state : state;   -- etat actuel
    signal next_state    : state;   -- etat au prochain coup d'horloge

    -- compteur de cycles
    component cycle_counter_unit
        generic ( 
        NB_COUPS_HORLOGE : positive;
        NB_CLIGN : positive );
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            restart         : in  std_logic;
            led_value   : out std_logic;
            count_cycle : out std_logic_vector(1 downto 0);
            end_cycle   : out std_logic
        );
    end component;

    signal led_value : std_logic;   -- etat clignotement (venant du compteur)
    signal end_cycle : std_logic;   -- impulsion : 3 clignotements termines
    signal couleur_r : std_logic;   -- couleur de l'etat (avant clignotement)
    signal couleur_g : std_logic;
    signal couleur_b : std_logic;

begin

    -- instanciation du compteur de cycles ; restart le remet a zero
    compteur_cycles : cycle_counter_unit
        generic map ( NB_COUPS_HORLOGE => NB_COUPS_HORLOGE, NB_CLIGN => NB_CLIGN )
        port map (
            clk         => clk,
            resetn      => resetn,
            restart         => restart_tp,
            led_value   => led_value,
            count_cycle => open,
            end_cycle   => end_cycle
        );

    -- process sequentiel : memorisation de l'etat
    process(clk, resetn)
    begin
        if (resetn = '1') then
            current_state <= blanc;             -- etat initial
        elsif (rising_edge(clk)) then
            current_state <= next_state;
        end if;
    end process;

    -- process combinatoire : etat suivant + couleur de l'etat courant
    process(current_state, restart_tp, end_cycle)
    begin
        -- couleur associee a l'etat courant
        case current_state is
            when blanc => couleur_r <= '1'; couleur_g <= '1'; couleur_b <= '1';
            when rouge => couleur_r <= '1'; couleur_g <= '0'; couleur_b <= '0';
            when bleu  => couleur_r <= '0'; couleur_g <= '0'; couleur_b <= '1';
            when vert  => couleur_r <= '0'; couleur_g <= '1'; couleur_b <= '0';
        end case;

        -- calcul de l'etat suivant
        if (restart_tp = '1') then
            next_state <= blanc;                -- restart prioritaire
        elsif (end_cycle = '1') then            -- 3 clignotements : couleur suivante
            case current_state is
                when blanc => next_state <= rouge;
                when rouge => next_state <= bleu;
                when bleu  => next_state <= vert;
                when vert  => next_state <= rouge;
            end case;
        else
            next_state <= current_state;        -- sinon on reste
        end if;
    end process;

    -- clignotement : la couleur n'est visible que lorsque led_value = 1
    led0_r <= couleur_r and led_value;
    led0_g <= couleur_g and led_value;
    led0_b <= couleur_b and led_value;

end behavioral;
