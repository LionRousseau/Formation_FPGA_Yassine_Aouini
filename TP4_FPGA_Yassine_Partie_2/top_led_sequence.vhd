-- Objectif : saisir une sequence de couleurs a l'aide des deux boutons, la stocker
--        dans une FIFO, et la restituer sur la LED RGB a raison d'une couleur
--        par cycle complet de clignotement.

library ieee;
use ieee.std_logic_1164.all;

entity top_led_sequence is
    generic (
        NB_COUPS_HORLOGE : positive := 62_500_000
    );
    port (
        clk      : in  std_logic;
        resetn   : in  std_logic;   -- reset asynchrone
        bouton_0 : in  std_logic;
        bouton_1 : in  std_logic;
        led0_r   : out std_logic;
        led0_g   : out std_logic;
        led0_b   : out std_logic
    );
end top_led_sequence;

architecture rtl of top_led_sequence is

    signal btn_prev   : std_logic;
    signal btn_edge   : std_logic;

    signal fifo_din   : std_logic_vector(1 downto 0);
    signal fifo_dout  : std_logic_vector(1 downto 0);
    signal fifo_wr    : std_logic;
    signal fifo_rd    : std_logic;
    signal fifo_full  : std_logic;
    signal fifo_empty : std_logic;

    signal end_cycle  : std_logic;
    signal update     : std_logic;

begin

    ------------------------------------------------------------------
    -- Detecteur de front montant sur bouton_0, repris de la partie 1
    ------------------------------------------------------------------
    p_edge : process (clk, resetn)
    begin
        if (resetn = '1') then
            btn_prev <= '0';
        elsif rising_edge(clk) then
            btn_prev <= bouton_0;
        end if;
    end process p_edge;

    btn_edge <= bouton_0 and (not btn_prev);

    ------------------------------------------------------------------
    -- la couleur choisie par bouton_1 est empilee a chaque
    -- appui. L'ecriture est interdite si la file est pleine, sans quoi la
    -- donnee serait perdue.
    ------------------------------------------------------------------
    fifo_din <= "10" when bouton_1 = '1' else "11";   -- vert / bleu
    fifo_wr  <= btn_edge and (not fifo_full);

    ------------------------------------------------------------------
    -- une couleur est depilee a chaque fin de cycle complet.
    -- La lecture est interdite si la file est vide.
    ------------------------------------------------------------------
    fifo_rd <= end_cycle and (not fifo_empty);
    update  <= fifo_rd;

    u_fifo : entity work.fifo_generator_0
        port map (
            clk   => clk,
            srst  => resetn,
            din   => fifo_din,
            wr_en => fifo_wr,
            rd_en => fifo_rd,
            dout  => fifo_dout,
            full  => fifo_full,
            empty => fifo_empty
        );

    ------------------------------------------------------------------
    -- Pilotage de la LED RGB, module de la partie 1 complete par end_cycle
    ------------------------------------------------------------------
    u_driver : entity work.led_driver
        generic map (
            NB_COUPS_HORLOGE => NB_COUPS_HORLOGE
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            color_code => fifo_dout,
            update     => update,
            led_r      => led0_r,
            led_g      => led0_g,
            led_b      => led0_b,
            end_cycle  => end_cycle
        );

end rtl;
