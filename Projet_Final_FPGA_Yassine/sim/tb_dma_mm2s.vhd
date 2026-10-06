--------------------------------------------------------------------------------
-- TC-U-01  DMA et lecture memoire (PL-IP-000)
-- Verifie la relecture d'une image depuis la memoire : le flux de sortie du DMA
-- restitue les pixels dans l'ordre raster attendu, le nombre de pixels par trame
-- est correct, TUSER marque le premier pixel de l'image et TLAST le dernier de
-- chaque ligne. Back-pressure aleatoire en aval. Deux trames verifiees
-- (l'image etant statique, elles sont identiques).
--
-- Note : le critere de cadence 60 images/s (periode 16,67 ms) depend de l'horloge
-- pixel et releve du test sur carte ; ici on prouve l'exactitude et l'ordre.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.video_pkg.all;

entity tb_dma_mm2s is
end entity;

architecture sim of tb_dma_mm2s is
  constant IMG_W : natural := 16;
  constant IMG_H : natural := 8;
  constant NPIX  : natural := IMG_W*IMG_H;
  constant MARK  : natural := 129;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal td     : std_logic_vector(23 downto 0);
  signal tv, tu, tl : std_logic;
  signal tr     : std_logic := '0';
  signal errors : integer := 0;
  signal seen   : integer := 0;
  signal done   : boolean := false;

  function exp_pix(xi, yi : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(MARK mod 256, 8)) &
           std_logic_vector(to_unsigned(xi  mod 256, 8)) &
           std_logic_vector(to_unsigned(yi  mod 256, 8));
  end function;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.dma_mm2s_model
    generic map (IMG_W => IMG_W, IMG_H => IMG_H, MARK => MARK)
    port map (clk => clk, resetn => resetn,
      m_tdata => td, m_tvalid => tv, m_tready => tr, m_tuser => tu, m_tlast => tl);

  -- aval : tready aleatoire
  sink : process
    variable s1 : positive := 41;
    variable s2 : positive := 7;
    variable rnd : real;
  begin
    tr <= '0';
    wait until resetn = '1';
    loop
      uniform(s1, s2, rnd);
      if rnd > 0.3 then tr <= '1'; else tr <= '0'; end if;
      wait until rising_edge(clk);
      exit when done;
    end loop;
    wait;
  end process;

  stim : process
  begin
    resetn <= '0'; wait for 33 ns; resetn <= '1';
    wait for 60 us;
    done <= true; wait;
  end process;

  check : process(clk)
    variable x, y     : integer := 0;
    variable frame_no : integer := -1;
    variable pixcnt   : integer := 0;
    variable eolcnt   : integer := 0;
    variable err      : integer := 0;
    variable cnt      : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and tv = '1' and tr = '1' then     -- transfert accepte
        -- suivi de coordonnee via SOF
        if tu = '1' then
          if frame_no >= 0 then
            if pixcnt /= NPIX then
              report "TC-U-01 pixels/trame=" & integer'image(pixcnt) severity warning; err := err+1;
            end if;
            if eolcnt /= IMG_H then
              report "TC-U-01 tlast/trame=" & integer'image(eolcnt) severity warning; err := err+1;
            end if;
          end if;
          frame_no := frame_no + 1; x := 0; y := 0; pixcnt := 0; eolcnt := 0;
        end if;
        pixcnt := pixcnt + 1;
        -- donnee
        if td /= exp_pix(x, y) then
          report "TC-U-01 data (x=" & integer'image(x) & ",y=" & integer'image(y) &
                 ") got=" & to_hstring(td) & " exp=" & to_hstring(exp_pix(x,y)) severity warning;
          err := err + 1;
        end if;
        -- tlast coherent
        if (tl = '1') /= (x = IMG_W-1) then
          report "TC-U-01 tlast incoherent x=" & integer'image(x) severity warning; err := err+1;
        end if;
        if tl = '1' then eolcnt := eolcnt + 1; end if;
        -- tuser coherent
        if (tu = '1') /= (x = 0 and y = 0) then
          report "TC-U-01 tuser incoherent (x=" & integer'image(x) & ",y=" & integer'image(y) & ")" severity warning; err := err+1;
        end if;
        if frame_no = 1 then cnt := cnt + 1; end if;
        -- avance coordonnee
        if x = IMG_W-1 then x := 0; y := y + 1; else x := x + 1; end if;
        errors <= err; seen <= cnt;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-01 (DMA lecture memoire) : " & integer'image(errors) &
           " erreur(s), trame verifiee = " & integer'image(seen) & " pixels ===";
    assert errors = 0 report "TC-U-01 : ECHEC" severity failure;
    assert seen = NPIX report "TC-U-01 : trame incomplete" severity failure;
    report "TC-U-01 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
