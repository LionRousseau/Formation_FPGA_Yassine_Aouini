--------------------------------------------------------------------------------
-- TC-U-07  Conformite AXI4-Stream (PL-IP-005 / ED-03)
-- Applique des desassertions aleatoires de tready en aval et des trous aleatoires
-- sur tvalid en amont d'un etage de convolution. Verifie :
--   - aucune donnee perdue ni dupliquee (chaque pixel de la trame verifiee sort
--     exactement une fois, dans le bon ordre raster) ;
--   - valeur de sortie conforme a la reference (gaussien) ;
--   - tuser marque le premier pixel de trame, tlast le dernier de chaque ligne ;
--   - aucun transfert (tvalid et tready simultanement vrais) n'est ignore.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.video_pkg.all;
use work.ref_pkg.all;

entity tb_axis_conformance is
end entity;

architecture sim of tb_axis_conformance is
  constant IMG_W : natural := 10;
  constant IMG_H : natural := 8;
  constant NPIX  : natural := IMG_W*IMG_H;

  function src(r, c : integer) return integer is
  begin
    if r = 4 and c = 5 then return 255; end if;
    if r = 1 and c = 1 then return 0;   end if;
    if c = 8 then return 200; end if;
    return 100;
  end function;
  function src_b(r, c : integer) return integer is
  begin
    if r<0 or r>=IMG_H or c<0 or c>=IMG_W then return 0; else return src(r,c); end if;
  end function;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal din    : std_logic_vector(7 downto 0) := (others => '0');
  signal dv, du, dl : std_logic := '0';
  signal dready : std_logic;
  signal yout   : std_logic_vector(7 downto 0);
  signal yv, yu, yl : std_logic;
  signal yready : std_logic := '0';

  signal errors  : integer := 0;
  signal seen_c  : integer := 0;
  signal done    : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.gaussian_filter
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      s_tdata => din, s_tvalid => dv, s_tready => dready, s_tuser => du, s_tlast => dl,
      m_tdata => yout, m_tvalid => yv, m_tready => yready, m_tuser => yu, m_tlast => yl);

  --------------------------------------------------------------------------
  -- Amont : trous aleatoires sur tvalid, pixel maintenu jusqu'a acceptation.
  --------------------------------------------------------------------------
  stim : process
    variable seed1 : positive := 77;
    variable seed2 : positive := 12;
    variable rnd   : real;
  begin
    resetn <= '0'; dv <= '0'; du <= '0'; dl <= '0';
    wait for 23 ns; resetn <= '1';
    wait until rising_edge(clk);
    for f in 0 to 2 loop
      for idx in 0 to NPIX-1 loop
        -- trous aleatoires avant de presenter le pixel
        loop
          uniform(seed1, seed2, rnd);
          exit when rnd > 0.35;
          dv <= '0'; du <= '0'; dl <= '0';
          wait until rising_edge(clk);
        end loop;
        din <= std_logic_vector(to_unsigned(src(idx/IMG_W, idx mod IMG_W), 8));
        dv  <= '1';
        if idx = 0 then du <= '1'; else du <= '0'; end if;
        if (idx mod IMG_W) = IMG_W-1 then dl <= '1'; else dl <= '0'; end if;
        -- maintien jusqu'a acceptation
        loop
          wait until rising_edge(clk);
          exit when dready = '1';
        end loop;
      end loop;
    end loop;
    dv <= '0'; du <= '0'; dl <= '0';
    -- laisser vidanger
    for k in 0 to 400 loop wait until rising_edge(clk); end loop;
    done <= true; wait;
  end process;

  --------------------------------------------------------------------------
  -- Aval : desassertions aleatoires de tready.
  --------------------------------------------------------------------------
  sink : process
    variable seed1 : positive := 5;
    variable seed2 : positive := 9;
    variable rnd   : real;
  begin
    yready <= '0';
    wait until resetn = '1';
    loop
      uniform(seed1, seed2, rnd);
      if rnd > 0.4 then yready <= '1'; else yready <= '0'; end if;
      wait until rising_edge(clk);
      exit when done;
    end loop;
    wait;
  end process;

  --------------------------------------------------------------------------
  -- Verification : chaque transfert accepte, ordre raster, valeur, unicite.
  --------------------------------------------------------------------------
  check : process(clk)
    variable c, r     : integer := 0;
    variable frame_no : integer := -1;
    variable win, ker : int3x3_t;
    variable idx      : integer;
    variable exp      : integer;
    variable err      : integer := 0;
    variable cnt      : integer := 0;
    type seen_t is array (0 to NPIX-1) of boolean;
    variable seen     : seen_t := (others => false);
  begin
    if rising_edge(clk) then
      if resetn = '1' and yv = '1' and yready = '1' then   -- transfert accepte
        -- reconstruction de la coordonnee
        if yu = '1' then frame_no := frame_no + 1; c := 0; r := 0; end if;
        -- verification tlast : doit marquer la fin de ligne
        if (yl = '1') /= (c = IMG_W-1) then
          report "TC-U-07 tlast incoherent a (c=" & integer'image(c) &
                 ",r=" & integer'image(r) & ")" severity warning;
          err := err + 1;
        end if;
        if frame_no = 1 then
          -- valeur de reference (gaussien)
          idx := 0;
          for dr in -1 to 1 loop
            for dc in -1 to 1 loop
              win(idx) := src_b(r+dr, c+dc); idx := idx + 1;
            end loop;
          end loop;
          ker := (1,2,1, 2,4,2, 1,2,1);
          exp := ref_conv(win, ker, 4, false, 8);
          if to_integer(unsigned(yout)) /= exp then
            report "TC-U-07 valeur (c=" & integer'image(c) & ",r=" & integer'image(r) &
                   ") got=" & integer'image(to_integer(unsigned(yout))) &
                   " exp=" & integer'image(exp) severity warning;
            err := err + 1;
          end if;
          -- unicite : ce pixel ne doit pas avoir deja ete vu
          if seen(r*IMG_W + c) then
            report "TC-U-07 DUPLICATION pixel (c=" & integer'image(c) &
                   ",r=" & integer'image(r) & ")" severity warning;
            err := err + 1;
          end if;
          seen(r*IMG_W + c) := true;
          cnt := cnt + 1;
          seen_c <= cnt;
        end if;
        if c = IMG_W-1 then c := 0; r := r + 1; else c := c + 1; end if;
      end if;
      errors <= err;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-07 (conformite AXI4-Stream) : " & integer'image(errors) &
           " erreur(s), " & integer'image(seen_c) & "/" & integer'image(NPIX) &
           " pixels recus ===";
    assert errors = 0 report "TC-U-07 : ECHEC (erreurs)" severity failure;
    assert seen_c = NPIX report "TC-U-07 : ECHEC (pixels manquants/perdus)" severity failure;
    report "TC-U-07 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
