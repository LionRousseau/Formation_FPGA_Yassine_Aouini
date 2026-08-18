-- Ce testbench verifie deux choses distinctes :
--
--   A) que la cadence n'est jamais perturbee par le bouton.
--
--   B) qu'un appui, quelle que soit sa duree, ne produit qu'un seul
--      clignotement vert.
--
-- Scenarios : 1 - repos, aucun appui                  -> aucun vert
--             2 - appui maintenu sur 5 periodes       -> 1 seul vert
--             3 - relachement puis nouvel appui       -> 1 vert de plus
--             4 - appui pendant la phase allumee      -> vert sur la fin de phase
--             5 - balayage de tous les instants d'appui possibles
--             6 - exclusivite des deux LED, en permanence
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity tb_q6_blink_oneshot is
end tb_q6_blink_oneshot;

architecture bench of tb_q6_blink_oneshot is

    
    constant C_CLK_PERIOD : time     := 8 ns;
    -- valeur minuscule pour que la simulation montre plusieurs periodes
    constant C_NB_COUPS   : positive := 8;
    -- duree d'une phase (allumee ou eteinte) et d'un cycle complet
    constant C_PHASE      : time     := C_NB_COUPS * C_CLK_PERIOD;   -- 64 ns
    constant C_PERIODE    : time     := 2 * C_PHASE;                 -- 128 ns

    signal clk      : std_logic := '0';
    signal resetn   : std_logic := '0';
    signal bouton_0 : std_logic := '0';
    signal led0_r   : std_logic;
    signal led0_g   : std_logic;

    signal led_union : std_logic;          -- LED allumee, toutes couleurs confondues
    signal u_prev    : std_logic := '0';
    signal g_prev    : std_logic := '0';
    signal nb_vert   : natural   := 0;     -- nombre d'allumages verts observes
    signal nb_cycles : natural   := 0;     -- compteur de cycles entre deux basculements
    signal check_on  : boolean   := false; -- active la verification de cadence
    signal sim_done  : boolean   := false;

begin

    uut : entity work.q6_blink_oneshot
        generic map (
            NB_COUPS_HORLOGE => C_NB_COUPS
        )
        port map (
            clk      => clk,
            resetn   => resetn,
            bouton_0 => bouton_0,
            led0_r   => led0_r,
            led0_g   => led0_g
        );

    led_union <= led0_r or led0_g;

    ------------------------------------------------------------------
    -- Horloge
    ------------------------------------------------------------------
    p_clk : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for C_CLK_PERIOD / 2;
            clk <= '1';
            wait for C_CLK_PERIOD / 2;
        end loop;
        wait;
    end process p_clk;

    ------------------------------------------------------------------
    -- A) Moniteur de cadence : verifie que led_union bascule exactement
    --    toutes les C_NB_COUPS periodes d'horloge, en permanence.
    ------------------------------------------------------------------
    p_cadence : process (clk)
    begin
        if rising_edge(clk) then
            if (led_union /= u_prev) then
                if check_on then
                    assert nb_cycles = C_NB_COUPS
                        report "CADENCE PERTURBEE : phase de " & integer'image(nb_cycles)
                             & " cycles au lieu de " & integer'image(C_NB_COUPS)
                        severity error;
                end if;
                nb_cycles <= 1;
            else
                nb_cycles <= nb_cycles + 1;
            end if;
            u_prev <= led_union;
        end if;
    end process p_cadence;

    ------------------------------------------------------------------
    -- Comptage des allumages verts
    ------------------------------------------------------------------
    p_compte : process (clk)
    begin
        if rising_edge(clk) then
            if (led0_g = '1' and g_prev = '0') then
                nb_vert <= nb_vert + 1;
            end if;
            g_prev <= led0_g;
        end if;
    end process p_compte;

    ------------------------------------------------------------------
    -- 6) Exclusivite : les deux LED ne doivent jamais etre allumees ensemble
    ------------------------------------------------------------------
    p_exclusivite : process (clk)
    begin
        if rising_edge(clk) then
            assert not (led0_r = '1' and led0_g = '1')
                report "ERREUR : led0_r et led0_g allumees simultanement"
                severity error;
        end if;
    end process p_exclusivite;

    ------------------------------------------------------------------
    -- Stimuli
    ------------------------------------------------------------------
    p_stim : process

        variable v_ref : natural;

        procedure appui(nb_cycles_appui : in natural) is
        begin
            wait until rising_edge(clk);
            wait for 3 ns;
            bouton_0 <= '1';
            for i in 1 to nb_cycles_appui loop
                wait until rising_edge(clk);
            end loop;
            wait for 3 ns;
            bouton_0 <= '0';
        end procedure appui;

    begin
        -- Reset initial
        bouton_0 <= '0';
        resetn   <= '1';
        wait for 4 * C_CLK_PERIOD;
        resetn   <= '0';

        wait for C_PERIODE;
        check_on <= true;          -- la cadence est desormais surveillee

        ----------------------------------------------------------------
        -- Scenario 1 : repos, aucun appui
        ----------------------------------------------------------------
        report "Scenario 1 : repos, aucun appui";
        v_ref := nb_vert;
        wait for 3 * C_PERIODE;
        assert nb_vert = v_ref
            report "Scenario 1 : un vert est apparu sans appui"
            severity error;

        ----------------------------------------------------------------
        -- Scenario 2 : appui maintenu sur 5 periodes completes
        ----------------------------------------------------------------
        report "Scenario 2 : appui maintenu";
        v_ref := nb_vert;
        appui(5 * 2 * C_NB_COUPS);
        wait for 2 * C_PERIODE;
        assert nb_vert = v_ref + 1
            report "Scenario 2 : le maintien du bouton ne donne pas exactement un vert"
            severity error;

        ----------------------------------------------------------------
        -- Scenario 3 : relachement puis nouvel appui
        ----------------------------------------------------------------
        report "Scenario 3 : nouvel appui apres relachement";
        v_ref := nb_vert;
        appui(2);
        wait for 3 * C_PERIODE;
        assert nb_vert = v_ref + 1
            report "Scenario 3 : le nouvel appui n'a pas produit de vert"
            severity error;

        ----------------------------------------------------------------
        -- Scenario 4 : appui pendant la phase allumee
        ----------------------------------------------------------------
        report "Scenario 4 : appui pendant la phase allumee";
        v_ref := nb_vert;
        wait until led_union = '1';
        wait for 2 * C_CLK_PERIOD;
        appui(2);
        wait for 3 * C_PERIODE;
        assert nb_vert = v_ref + 1
            report "Scenario 4 : l'appui en cours d'allumage n'a pas produit un vert unique"
            severity error;

        ----------------------------------------------------------------
        -- Scenario 5 : balayage de toutes les phases d'appui possibles
        ----------------------------------------------------------------
        report "Scenario 5 : balayage des instants d'appui";
        for k in 0 to 2 * C_NB_COUPS - 1 loop
            v_ref := nb_vert;
            wait for k * C_CLK_PERIOD;
            appui(2);
            wait for 3 * C_PERIODE;
            assert nb_vert = v_ref + 1
                report "Balayage : decalage de " & integer'image(k)
                     & " cycles, nombre de verts incorrect"
                severity error;
        end loop;

        report "Fin de simulation : tous les scenarios ont ete joues";
        sim_done <= true;
        wait;
    end process p_stim;

end bench;
