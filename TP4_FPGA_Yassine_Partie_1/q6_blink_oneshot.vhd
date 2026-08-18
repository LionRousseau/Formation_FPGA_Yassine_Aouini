library ieee;
use ieee.std_logic_1164.all;

entity q6_blink_oneshot is
    generic (
        NB_COUPS_HORLOGE : positive := 62_500_000
    );
    port (
        clk      : in  std_logic;
        resetn   : in  std_logic;   -- reset asynchrone ACTIF HAUT
        bouton_0 : in  std_logic;
        led0_r   : out std_logic;
        led0_g   : out std_logic
    );
end q6_blink_oneshot;

architecture rtl of q6_blink_oneshot is

    signal end_counter : std_logic;
    signal led_value   : std_logic;   -- cadence : '1' = phase allumee
    signal btn_prev    : std_logic;   -- valeur de bouton_0 au coup d'horloge precedent
    signal btn_edge    : std_logic;   -- impulsion d'un cycle sur front montant
    signal vert_actif  : std_logic;   -- autorisation du clignotement vert en cours

begin

    u_counter : entity work.counter_unit
        generic map (
            NOMBRE_CYCLES => NB_COUPS_HORLOGE
        )
        port map (
            clk         => clk,
            resetn      => resetn,
            end_counter => end_counter
        );

    p_blink : process (clk, resetn)
    begin
        if (resetn = '1') then
            led_value <= '0';
        elsif rising_edge(clk) then
            if (end_counter = '1') then
                led_value <= not led_value;
            end if;
        end if;
    end process p_blink;

    p_edge : process (clk, resetn)
    begin
        if (resetn = '1') then
            btn_prev <= '0';
        elsif rising_edge(clk) then
            btn_prev <= bouton_0;
        end if;
    end process p_edge;

    btn_edge <= bouton_0 and (not btn_prev);

    p_vert : process (clk, resetn)
    begin
        if (resetn = '1') then
            vert_actif <= '0';
        elsif rising_edge(clk) then
            if (btn_edge = '1') then
                vert_actif <= '1';
            elsif (end_counter = '1' and led_value = '1') then
                vert_actif <= '0';
            end if;
        end if;
    end process p_vert;

    led0_g <= led_value and vert_actif;
    led0_r <= led_value and (not vert_actif);

end rtl;
