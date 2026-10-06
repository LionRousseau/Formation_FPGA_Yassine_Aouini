--------------------------------------------------------------------------------
-- TC-U-03  Selection de source (PL-IP-002 init, PL-IP-003 a chaud)
-- Deux sources modelisees (MARK=34 = source1, MARK=17 = source0). sel commence a
-- 1 (source1) puis passe a 0 (source0) en cours de trame. Verifie :
--   - a l'initialisation la source diffusee correspond au registre sel ;
--   - apres ecriture a chaud, le basculement intervient a une frontiere de trame :
--     chaque trame de sortie est ENTIEREMENT issue d'une seule source (aucun pixel
--     corrompu, aucune trame spliced), et le changement de source coincide avec un
--     debut de trame (tuser).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.video_pkg.all;

entity tb_source_mux is
end entity;

architecture sim of tb_source_mux is
  constant IMG_W : natural := 16;
  constant IMG_H : natural := 8;
  constant NPIX  : natural := IMG_W*IMG_H;
  constant MARK0 : natural := 17;    -- source0 (DMA)
  constant MARK1 : natural := 34;    -- source1 (TPG)

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal sel    : std_logic := '1';  -- init : source1

  signal s0d, s1d, md : std_logic_vector(23 downto 0);
  signal s0v, s0r, s0u, s0l : std_logic;
  signal s1v, s1r, s1u, s1l : std_logic;
  signal mv, mr, mu, ml : std_logic;

  signal errors : integer := 0;
  signal saw_init : integer := -1;   -- mark de la 1ere trame diffusee
  signal saw_sw   : integer := 0;    -- 1 si on a vu une trame source0 apres le switch
  signal done   : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  u_s0 : entity work.dma_mm2s_model
    generic map (IMG_W => IMG_W, IMG_H => IMG_H, MARK => MARK0)
    port map (clk => clk, resetn => resetn, m_tdata => s0d, m_tvalid => s0v,
      m_tready => s0r, m_tuser => s0u, m_tlast => s0l);

  u_s1 : entity work.dma_mm2s_model
    generic map (IMG_W => IMG_W, IMG_H => IMG_H, MARK => MARK1)
    port map (clk => clk, resetn => resetn, m_tdata => s1d, m_tvalid => s1v,
      m_tready => s1r, m_tuser => s1u, m_tlast => s1l);

  dut : entity work.source_mux
    port map (clk => clk, resetn => resetn, sel => sel,
      s0_tdata => s0d, s0_tvalid => s0v, s0_tready => s0r, s0_tuser => s0u, s0_tlast => s0l,
      s1_tdata => s1d, s1_tvalid => s1v, s1_tready => s1r, s1_tuser => s1u, s1_tlast => s1l,
      m_tdata => md, m_tvalid => mv, m_tready => mr, m_tuser => mu, m_tlast => ml,
      active_o => open);

  sink : process
    variable a : positive := 91; variable b : positive := 13; variable rnd : real;
  begin
    mr <= '0'; wait until resetn = '1';
    loop
      uniform(a, b, rnd);
      if rnd > 0.25 then mr <= '1'; else mr <= '0'; end if;
      wait until rising_edge(clk); exit when done;
    end loop; wait;
  end process;

  stim : process
  begin
    resetn <= '0'; sel <= '1'; wait for 33 ns; resetn <= '1';
    wait for 40 us;
    sel <= '0';                       -- basculement a chaud en cours de trame
    wait for 60 us;
    done <= true; wait;
  end process;

  check : process(clk)
    variable frame_mark : integer := -1;
    variable pixcnt     : integer := 0;
    variable nframes    : integer := 0;
    variable err        : integer := 0;
    variable rr         : integer;
  begin
    if rising_edge(clk) then
      if resetn = '1' and mv = '1' and mr = '1' then
        rr := to_integer(unsigned(md(23 downto 16)));
        if mu = '1' then
          -- cloture de la trame precedente
          if frame_mark >= 0 and pixcnt /= NPIX then
            report "TC-U-03 trame incomplete : " & integer'image(pixcnt) & " pixels" severity warning;
            err := err + 1;
          end if;
          frame_mark := rr; pixcnt := 0; nframes := nframes + 1;
          if saw_init < 0 then saw_init <= rr; end if;   -- 1ere trame diffusee
          if rr = MARK0 then saw_sw <= 1; end if;         -- trame source0 vue
        end if;
        pixcnt := pixcnt + 1;
        -- homogeneite : tout pixel de la trame a le MARK de la trame
        if rr /= frame_mark then
          report "TC-U-03 trame NON homogene : pixel mark=" & integer'image(rr) &
                 " dans trame mark=" & integer'image(frame_mark) & " (splice)" severity warning;
          err := err + 1;
        end if;
        -- structure raster
        if (ml = '1') /= (to_integer(unsigned(md(15 downto 8))) = IMG_W-1) then
          report "TC-U-03 tlast incoherent" severity warning; err := err + 1;
        end if;
        errors <= err;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-03 (selection de source) : " & integer'image(errors) &
           " erreur(s), 1ere source=" & integer'image(saw_init) & " ===";
    assert errors = 0 report "TC-U-03 : ECHEC (trame corrompue)" severity failure;
    assert saw_init = MARK1 report "TC-U-03 : ECHEC (selection init incorrecte)" severity failure;
    assert saw_sw = 1 report "TC-U-03 : ECHEC (basculement a chaud non observe)" severity failure;
    report "TC-U-03 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
