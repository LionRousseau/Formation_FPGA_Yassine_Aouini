-- Scenarios :
--   1 - apres reset, file vide : la LED reste eteinte
--   2 - une couleur ecrite : elle apparait au cycle suivant
--   3 - trois couleurs ecrites d'affilee : elles sont restituees dans l'ordre,
--       une par cycle complet. C'est le test central de la partie 2.
--   4 - file videe : la derniere couleur est conservee
--   5 - bouton_0 maintenu : une seule ecriture, donc un seul changement
--   6 - exclusivite permanente des trois sorties
--   7 - cadence de clignotement invariante
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity tb_top_led_sequence is
end tb_top_led_sequence;

architecture bench of tb_top_led_sequence is

    constant C_CLK_PERIOD : time     := 8 ns;
    constant C_NB_COUPS   : positive := 8;
    constant C_PHASE      : time     := C_NB_COUPS * C_CLK_PERIOD;   -- 64 ns
    constant C_PERIODE    : time     := 2 * C_PHASE;                 -- 128 ns

    signal clk      : std_logic := '0';
    signal resetn   : std_logic := '0';
    signal bouton_0 : std_logic := '0';
    signal bouton_1 : std_logic := '0';
    signal led0_r   : std_logic;
    signal led0_g   : std_logic;
    signal led0_b   : std_logic;

    signal led_union : std_logic;
    signal u_prev    : std_logic := '0';
    signal nb_cycles : natural   := 0;
    signal check_on  : boolean   := false;
    signal arme      : boolean   := false;   -- la 1ere transition apres activation n'est pas mesurable
    signal sim_done  : boolean   := false;

begin

    uut : entity work.top_led_sequence
        generic map (NB_COUPS_HORLOGE => C_NB_COUPS)
        port map (
            clk => clk, resetn => resetn,
            bouton_0 => bouton_0, bouton_1 => bouton_1,
            led0_r => led0_r, led0_g => led0_g, led0_b => led0_b
        );

    led_union <= led0_r or led0_g or led0_b;

    p_clk : process
    begin
        while not sim_done loop
            clk <= '0'; wait for C_CLK_PERIOD / 2;
            clk <= '1'; wait for C_CLK_PERIOD / 2;
        end loop;
        wait;
    end process p_clk;

    ------------------------------------------------------------------
    -- 6) Exclusivite : au plus une couleur allumee a la fois
    ------------------------------------------------------------------
    p_exclusivite : process (clk)
        variable n : natural;
    begin
        if rising_edge(clk) then
            n := 0;
            if led0_r = '1' then n := n + 1; end if;
            if led0_g = '1' then n := n + 1; end if;
            if led0_b = '1' then n := n + 1; end if;
            assert n <= 1
                report "ERREUR : plusieurs couleurs allumees simultanement"
                severity error;
        end if;
    end process p_exclusivite;

    ------------------------------------------------------------------
    -- 7) Cadence : les phases doivent toutes durer C_NB_COUPS cycles.
    --    N'est verifiee que lorsque la LED est effectivement pilotee.
    ------------------------------------------------------------------
    p_cadence : process (clk)
    begin
        if rising_edge(clk) then
            if (led_union /= u_prev) then
                -- la phase qui precede l'activation du moniteur a commence avant
                -- que la LED ne soit pilotee : elle n'est pas comparable.
                if check_on and arme then
                    assert nb_cycles = C_NB_COUPS
                        report "CADENCE PERTURBEE : phase de " & integer'image(nb_cycles)
                             & " cycles au lieu de " & integer'image(C_NB_COUPS)
                        severity error;
                end if;
                if check_on then
                    arme <= true;
                end if;
                nb_cycles <= 1;
            else
                nb_cycles <= nb_cycles + 1;
            end if;
            u_prev <= led_union;
        end if;
    end process p_cadence;

    ------------------------------------------------------------------
    -- Stimuli
    ------------------------------------------------------------------
    p_stim : process

        -- Ecriture d'une couleur : bouton_1 positionne, puis appui sur bouton_0.
        procedure ecrire(vert : in boolean; nb_cycles_appui : in natural) is
        begin
            if vert then
                bouton_1 <= '1';
            else
                bouton_1 <= '0';
            end if;
            wait until rising_edge(clk);
            wait for 3 ns;
            bouton_0 <= '1';
            for i in 1 to nb_cycles_appui loop
                wait until rising_edge(clk);
            end loop;
            wait for 3 ns;
            bouton_0 <= '0';
        end procedure ecrire;

        -- Attend le debut de la prochaine phase allumee et verifie la couleur.
        procedure verifier(r, g, b : in std_logic; msg : in string) is
        begin
            wait until led_union = '1';
            wait for C_CLK_PERIOD;
            assert (led0_r = r and led0_g = g and led0_b = b)
                report msg severity error;
        end procedure verifier;

    begin
        resetn <= '1';
        wait for 4 * C_CLK_PERIOD;
        resetn <= '0';

        ----------------------------------------------------------------
        -- Scenario 1 : file vide, la LED doit rester eteinte
        ----------------------------------------------------------------
        report "Scenario 1 : file vide";
        for i in 1 to 3 loop
            wait for C_PERIODE;
            assert led_union = '0'
                report "Scenario 1 : la LED s'allume alors que la file est vide"
                severity error;
        end loop;

        ----------------------------------------------------------------
        -- Scenario 2 : une seule couleur ecrite
        ----------------------------------------------------------------
        report "Scenario 2 : ecriture d'une couleur verte";
        ecrire(true, 2);
        verifier('0', '1', '0', "Scenario 2 : la couleur affichee n'est pas verte");
        -- la LED clignote desormais : la cadence peut etre surveillee. L'activer
        -- plus tot ferait mesurer la longue phase eteinte initiale comme une phase.
        check_on <= true;

        ----------------------------------------------------------------
        -- Scenario 3 : sequence de trois couleurs, ordre a respecter
        ----------------------------------------------------------------
        report "Scenario 3 : sequence bleu, vert, bleu";
        ecrire(false, 2);   -- bleu
        wait for 3 * C_CLK_PERIOD;
        ecrire(true,  2);   -- vert
        wait for 3 * C_CLK_PERIOD;
        ecrire(false, 2);   -- bleu
        verifier('0', '0', '1', "Scenario 3 : la 1ere couleur de la sequence n'est pas bleue");
        verifier('0', '1', '0', "Scenario 3 : la 2eme couleur de la sequence n'est pas verte");
        verifier('0', '0', '1', "Scenario 3 : la 3eme couleur de la sequence n'est pas bleue");

        ----------------------------------------------------------------
        -- Scenario 4 : file videe, la derniere couleur est conservee
        ----------------------------------------------------------------
        report "Scenario 4 : file videe";
        verifier('0', '0', '1', "Scenario 4 : la derniere couleur n'est pas conservee");
        verifier('0', '0', '1', "Scenario 4 : la derniere couleur n'est pas conservee");

        ----------------------------------------------------------------
        -- Scenario 5 : bouton_0 maintenu, une seule ecriture attendue
        ----------------------------------------------------------------
        report "Scenario 5 : bouton_0 maintenu longtemps";
        ecrire(true, 5 * 2 * C_NB_COUPS);
        verifier('0', '1', '0', "Scenario 5 : la couleur verte n'a pas ete ecrite");
        verifier('0', '1', '0', "Scenario 5 : le maintien a provoque plus d'une ecriture");
        verifier('0', '1', '0', "Scenario 5 : le maintien a provoque plus d'une ecriture");

        report "Fin de simulation : tous les scenarios ont ete joues";
        sim_done <= true;
        wait;
    end process p_stim;

end bench;
