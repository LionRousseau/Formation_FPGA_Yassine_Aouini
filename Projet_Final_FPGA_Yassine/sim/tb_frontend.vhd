--------------------------------------------------------------------------------
-- Integration front-end : DMA (modele) -> source_mux -> processing_chain
-- Prouve que la source memoire alimente la chaine de traitement de bout en bout
-- sans erreur de protocole : la sortie overlay est un flux video bien forme
-- (NPIX pixels par trame, un tuser par trame, un tlast par ligne) sur plusieurs
-- trames consecutives, et le suivi du maximum egrene bien une impulsion de fin
-- de trame. Complete les tests bit a bit TC-I-01/TC-I-03 par une preuve
-- d'assemblage du chemin memoire.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tb_frontend is
end entity;

architecture sim of tb_frontend is
  constant IMG_W : natural := 24;
  constant IMG_H : natural := 16;
  constant NPIX  : natural := IMG_W*IMG_H;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';

  signal dd : std_logic_vector(23 downto 0);
  signal dv, dr, du, dl : std_logic;
  signal sd : std_logic_vector(23 downto 0);
  signal sv, sr, su, sl : std_logic;
  signal od : std_logic_vector(23 downto 0);
  signal ov, oro, ou, ol : std_logic;
  signal mval : unsigned(C_RESP_W-1 downto 0);
  signal mx : unsigned(C_X_W-1 downto 0);
  signal my : unsigned(C_Y_W-1 downto 0);
  signal ftick : std_logic;

  signal errors  : integer := 0;
  signal nframes : integer := 0;
  signal nticks  : integer := 0;
  signal done    : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';
  oro <= '1';                                       -- aval affichage toujours pret

  -- source memoire (modele DMA)
  u_dma : entity work.dma_mm2s_model
    generic map (IMG_W => IMG_W, IMG_H => IMG_H, MARK => 120)
    port map (clk => clk, resetn => resetn, m_tdata => dd, m_tvalid => dv,
      m_tready => dr, m_tuser => du, m_tlast => dl);

  -- multiplexeur : source0 = DMA (sel = '0'). source1 laissee inactive.
  u_mux : entity work.source_mux
    port map (clk => clk, resetn => resetn, sel => '0',
      s0_tdata => dd, s0_tvalid => dv, s0_tready => dr, s0_tuser => du, s0_tlast => dl,
      s1_tdata => (others => '0'), s1_tvalid => '0', s1_tready => open,
      s1_tuser => '0', s1_tlast => '0',
      m_tdata => sd, m_tvalid => sv, m_tready => sr, m_tuser => su, m_tlast => sl,
      active_o => open);

  -- chaine de traitement + overlay
  u_chain : entity work.processing_chain
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      threshold => to_unsigned(40, C_RESP_W), mode => '1', ovl_color => x"00FF00",
      s_tdata => sd, s_tvalid => sv, s_tready => sr, s_tuser => su, s_tlast => sl,
      m_tdata => od, m_tvalid => ov, m_tready => oro, m_tuser => ou, m_tlast => ol,
      max_val => mval, max_x => mx, max_y => my, frame_tick => ftick);

  stim : process
  begin
    resetn <= '0'; wait for 33 ns; resetn <= '1';
    wait for 400 us;
    done <= true; wait;
  end process;

  check : process(clk)
    variable x, y     : integer := 0;
    variable frame_no : integer := -1;
    variable pixcnt   : integer := 0;
    variable eolcnt   : integer := 0;
    variable err      : integer := 0;
    variable nf, nt   : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' then
        if ftick = '1' then nt := nt + 1; nticks <= nt; end if;
        if ov = '1' and oro = '1' then
          if ou = '1' then
            if frame_no >= 0 then
              if pixcnt /= NPIX then
                report "tb_frontend pixels/trame=" & integer'image(pixcnt) severity warning; err := err+1;
              end if;
              if eolcnt /= IMG_H then
                report "tb_frontend tlast/trame=" & integer'image(eolcnt) severity warning; err := err+1;
              end if;
            end if;
            frame_no := frame_no + 1; x := 0; y := 0; pixcnt := 0; eolcnt := 0;
            nf := nf + 1; nframes <= nf;
          end if;
          pixcnt := pixcnt + 1;
          if (ol = '1') /= (x = IMG_W-1) then
            report "tb_frontend tlast incoherent x=" & integer'image(x) severity warning; err := err+1;
          end if;
          if ol = '1' then eolcnt := eolcnt + 1; end if;
          if x = IMG_W-1 then x := 0; y := y + 1; else x := x + 1; end if;
          errors <= err;
        end if;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== Front-end DMA->mux->chaine : " & integer'image(errors) & " erreur(s), " &
           integer'image(nframes) & " trames, " & integer'image(nticks) & " ticks max ===";
    assert errors = 0 report "tb_frontend : ECHEC" severity failure;
    assert nframes >= 3 report "tb_frontend : trop peu de trames" severity failure;
    assert nticks  >= 2 report "tb_frontend : suivi du maximum inactif" severity failure;
    report "tb_frontend : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
