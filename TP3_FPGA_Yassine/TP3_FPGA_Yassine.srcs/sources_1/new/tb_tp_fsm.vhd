--library ieee;
--use ieee.std_logic_1164.all;

--entity tb_tp_fsm is
--end tb_tp_fsm;

--architecture behavioral of tb_tp_fsm is

--    signal resetn  : std_logic := '1';  -- reset actif à l'état haut pour utilisation du bouton
--    signal clk     : std_logic := '0';
--    signal restart : std_logic := '0';
--    signal led_r   : std_logic;
--    signal led_g   : std_logic;
--    signal led_b   : std_logic;

--    -- frequence d'horloge
--    constant hp     : time := 5 ns;      -- demi periode
--    constant period : time := 2*hp;      -- periode de 10 ns (100 MHz)

--    component tp_fsm
--        generic ( NB_COUPS_HORLOGE : positive; NB_CLIGN : positive );
--        port (
--            clk     : in  std_logic;
--            resetn  : in  std_logic;
--            restart : in  std_logic;
--            led0_r   : out std_logic;
--            led0_g   : out std_logic;
--            led0_b   : out std_logic
--        );
--    end component;

--begin

--    -- NB_COUPS_HORLOGE reduit pour une simulation rapide)
--    dut : tp_fsm
--        generic map ( NB_COUPS_HORLOGE => 2000, NB_CLIGN => 3 )
--        port map (
--            clk     => clk,
--            resetn  => resetn,
--            restart => restart,
--            led0_r   => led_r,
--            led0_g   => led_g,
--            led0_b   => led_b
--        );

--    -- horloge
--    process
--    begin
--        wait for hp;
--        clk <= not clk;
--    end process;

--    -- stimuli
--    process
--    begin
--        resetn <= '1';              -- reset actif (actif haut)
--        wait for period*10;
--        resetn <= '0';              -- relache du reset

--        wait for period*40;         -- laisser defiler quelques couleurs

--        restart <= '1';             -- appui restart
--        wait for period*2;
--        restart <= '0';

--        wait for period*30;
--        wait;
--    end process;

--end behavioral;


----------------------------------------------------------------------------------
-- TP3 - Machine a etats (FSM)
-- Testbench : tb_tp_fsm
--
-- Verifie, par assertions, les comportements du systeme complet :
--   1) reset      : les LEDs sont eteintes ;
--   2) sequence   : blanc -> rouge -> bleu -> vert -> rouge, 3 clignotements par couleur
--                   (le blanc n'apparait qu'au demarrage : le cycle reboucle sur rouge) ;
--   3) restart    : ramene au blanc en cours de cycle, et le blanc reclignote 3 fois ;
--   4) reset      : teste aussi en cours de fonctionnement.
--
-- NB_COUPS_HORLOGE est reduit a 2 pour la simulation.
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity tb_tp_fsm is
end tb_tp_fsm;

architecture behavioral of tb_tp_fsm is

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '1';   -- actif haut : on demarre en reset
    signal restart : std_logic := '0';
    signal led_r   : std_logic;
    signal led_g   : std_logic;
    signal led_b   : std_logic;
    signal led_on  : std_logic;           -- '1' des qu'une composante est allumee

    constant hp     : time := 5 ns;
    constant period : time := 2*hp;

    signal fin_simu : boolean := false;

    -- codes couleur sur le bus (led_r & led_g & led_b)
    constant BLANC : std_logic_vector(2 downto 0) := "111";
    constant ROUGE : std_logic_vector(2 downto 0) := "100";
    constant BLEU  : std_logic_vector(2 downto 0) := "001";
    constant VERT  : std_logic_vector(2 downto 0) := "010";

    component tp_fsm
        generic ( NB_COUPS_HORLOGE : positive; NB_CLIGN : positive );
        port (
            clk     : in  std_logic;
            resetn   : in  std_logic;
            restart_tp : in  std_logic;
            led0_r   : out std_logic;
            led0_g   : out std_logic;
            led0_b   : out std_logic
        );
    end component;

begin

    uut : tp_fsm
        generic map ( NB_COUPS_HORLOGE => 2, NB_CLIGN => 3 )
        port map (
            clk     => clk,
            resetn   => reset,
            restart_tp => restart,
            led0_r   => led_r,
            led0_g   => led_g,
            led0_b   => led_b
        );

    led_on <= led_r or led_g or led_b;

    -- horloge
    process
    begin
        while not fin_simu loop
            clk <= '0'; wait for hp;
            clk <= '1'; wait for hp;
        end loop;
        wait;
    end process;

    -- test
    process

        -- verifie qu'une couleur clignote 3 fois de suite
        procedure verifier (couleur : std_logic_vector(2 downto 0)) is
        begin
            for i in 1 to 3 loop
                wait until led_on = '1';                       -- la LED s'allume
                assert (led_r & led_g & led_b) = couleur
                    report "ERREUR : mauvaise couleur au clignotement " & integer'image(i)
                    severity error;
                wait until led_on = '0';                       -- la LED s'eteint
            end loop;
        end procedure;

    begin
        -- 1) reset : les LEDs doivent etre eteintes
        reset <= '1';
        wait for 2*period;
        assert led_on = '0'
            report "ERREUR : une LED est allumee pendant le reset" severity error;
        report "OK : reset -> LEDs eteintes" severity note;
        reset <= '0';

        -- 2) sequence des couleurs + rebouclage
        verifier(BLANC);
        verifier(ROUGE);
        verifier(BLEU);
        verifier(VERT);
        verifier(ROUGE);        -- reboucle sur rouge, pas sur blanc
        report "OK : sequence blanc/rouge/bleu/vert/rouge correcte" severity note;

        -- 3) restart en cours de cycle : retour au blanc
        wait until led_on = '1';
        restart <= '1';
        wait for 2*period;
        restart <= '0';
        verifier(BLANC);        -- le blanc refait bien ses 3 clignotements
        report "OK : restart -> retour au blanc, 3 clignotements recomptes" severity note;

        -- 4) reset en cours de fonctionnement
        reset <= '1';
        wait for 2*period;
        assert led_on = '0'
            report "ERREUR : le reset n'eteint pas les LEDs" severity error;
        reset <= '0';
        verifier(BLANC);        -- repart du blanc
        report "OK : reset en marche -> repart du blanc" severity note;

        report "SIMULATION TERMINEE : tous les tests sont passes" severity note;
        fin_simu <= true;
        wait;
    end process;

end behavioral;
