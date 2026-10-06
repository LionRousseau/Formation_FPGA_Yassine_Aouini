--------------------------------------------------------------------------------
-- TC-U-09  Temporisation VGA (PL-DISP-002)
-- Mesure en simulation les durees des signaux hsync et vsync ainsi que des zones
-- actives. Verifie la conformite au standard 640x480 @ 60 : front porch, sync,
-- back porch, zone visible, total ligne et total trame, et la periode de trame
-- (16,67 ms a l'horloge pixel 25,175 MHz).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vga_pkg.all;

entity tb_vga_timing is
end entity;

architecture sim of tb_vga_timing is
  -- horloge pixel 25,175 MHz -> periode 39,72 ns -> demi-periode 19,86 ns
  constant HALF : time := 19860 ps;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal hsync, vsync, active, fbeg, lbeg : std_logic;
  signal hc, vc, xx, yy : unsigned(HC_W-1 downto 0);
  signal errors : integer := 0;
  signal done   : boolean := false;
begin
  clk <= not clk after HALF when not done else '0';

  dut : entity work.vga_timing
    port map (clk => clk, resetn => resetn, sync_lock => '0',
      hcount => hc, vcount => vc, x => xx, y => yy,
      hsync => hsync, vsync => vsync, active => active,
      frame_beg => fbeg, line_beg => lbeg);

  stim : process
  begin
    resetn <= '0';
    wait for 100 ns; resetn <= '1';
    wait; -- laisse tourner
  end process;

  -- mesure des durees sur une trame complete
  mon : process(clk)
    variable prev_hs, prev_vs, prev_act : std_logic := '1';
    variable hs_low   : integer := 0;
    variable act_run  : integer := 0;
    variable line_cnt : integer := 0;    -- cycles depuis line_beg
    variable frames   : integer := 0;
    variable lines    : integer := 0;    -- lignes dans la trame
    variable act_lines: integer := 0;    -- lignes contenant de l'actif
    variable vs_lines : integer := 0;    -- lignes ou vsync bas
    variable line_has_act : boolean := false;
    variable line_vs_low  : boolean := false;
    variable err      : integer := 0;
    variable t_fbeg   : time := 0 ns;
    variable measuring: boolean := false;
  begin
    if rising_edge(clk) then
      if resetn = '1' then
        -- 1. cloture de ligne sur line_beg (flags accumules AVANT ce cycle)
        if lbeg = '1' then
          if measuring then
            if line_cnt /= H_TOTAL then
              report "TC-U-09 total ligne = " & integer'image(line_cnt) & " (attendu 800)" severity warning;
              err := err + 1;
            end if;
            lines := lines + 1;
            if line_has_act then act_lines := act_lines + 1; end if;
            if line_vs_low  then vs_lines  := vs_lines  + 1; end if;
          end if;
          line_cnt := 0; line_has_act := false; line_vs_low := false;
        end if;

        -- 2. frontiere de trame
        if fbeg = '1' then
          frames := frames + 1;
          if frames = 1 then
            measuring := true; t_fbeg := now; lines := 0; act_lines := 0; vs_lines := 0;
          elsif frames = 2 then
            -- verifie la trame ecoulee
            if lines /= V_TOTAL then
              report "TC-U-09 lignes/trame = " & integer'image(lines) & " (attendu 525)" severity warning;
              err := err + 1;
            end if;
            if act_lines /= V_VISIBLE then
              report "TC-U-09 lignes actives = " & integer'image(act_lines) & " (attendu 480)" severity warning;
              err := err + 1;
            end if;
            if vs_lines /= V_SYNC then
              report "TC-U-09 lignes vsync bas = " & integer'image(vs_lines) & " (attendu 2)" severity warning;
              err := err + 1;
            end if;
            -- periode de trame : 16,67 ms +-1 %
            if (now - t_fbeg) < 16500 us or (now - t_fbeg) > 16850 us then
              report "TC-U-09 periode trame hors tolerance : " & time'image(now - t_fbeg) severity warning;
              err := err + 1;
            end if;
            done <= true;
          end if;
        end if;

        -- 3. accumulation du cycle courant (apres cloture ligne/trame)
        -- duree hsync bas
        if hsync = '0' then hs_low := hs_low + 1; end if;
        if prev_hs = '0' and hsync = '1' then
          if hs_low /= H_SYNC then
            report "TC-U-09 hsync bas = " & integer'image(hs_low) & " (attendu 96)" severity warning;
            err := err + 1;
          end if;
          hs_low := 0;
        end if;
        -- duree zone active par ligne
        if active = '1' then act_run := act_run + 1; line_has_act := true; end if;
        if prev_act = '1' and active = '0' then
          if act_run /= H_VISIBLE then
            report "TC-U-09 actif/ligne = " & integer'image(act_run) & " (attendu 640)" severity warning;
            err := err + 1;
          end if;
          act_run := 0;
        end if;
        if vsync = '0' then line_vs_low := true; end if;
        line_cnt := line_cnt + 1;

        prev_hs := hsync; prev_vs := vsync; prev_act := active;
        errors <= err;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-09 (temporisation VGA) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-U-09 : ECHEC" severity failure;
    report "TC-U-09 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
