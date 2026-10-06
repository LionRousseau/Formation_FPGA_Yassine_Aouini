--------------------------------------------------------------------------------
-- TC-U-08  Suivi du maximum (PL-IP-010)
-- Injecte une trame contenant un maximum unique en position connue, puis une
-- trame avec deux maxima egaux. Verifie : valeur et coordonnees correctes dans
-- le repere image ; mise a jour des registres uniquement en fin de trame ;
-- regle de departage deterministe (1ere occurrence en ordre raster).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tb_max_tracker is
end entity;

architecture sim of tb_max_tracker is
  constant IMG_W : natural := 16;
  constant IMG_H : natural := 8;
  constant NPIX  : natural := IMG_W*IMG_H;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal din    : std_logic_vector(C_RESP_W-1 downto 0) := (others => '0');
  signal dv, ds : std_logic := '0';
  signal mval   : unsigned(C_RESP_W-1 downto 0);
  signal mx     : unsigned(C_X_W-1 downto 0);
  signal my     : unsigned(C_Y_W-1 downto 0);
  signal ftick  : std_logic;
  signal errors : integer := 0;
  signal done   : boolean := false;

  -- valeur d'un pixel des trames de test
  function vA(idx : integer) return integer is
  begin
    if idx = 3*IMG_W + 5 then return 500; else return 0; end if;   -- max unique (5,3)
  end function;
  function vB(idx : integer) return integer is
  begin
    if idx = 1*IMG_W + 2 then return 500; end if;                  -- (2,1)
    if idx = 4*IMG_W + 7 then return 500; end if;                  -- (7,4)
    return 0;
  end function;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.max_tracker
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      in_data => din, in_valid => dv, in_ready => '1', in_sof => ds,
      max_val => mval, max_x => mx, max_y => my, frame_tick => ftick);

  stim : process
  begin
    resetn <= '0'; dv <= '0'; ds <= '0';
    wait for 23 ns; resetn <= '1';
    wait until rising_edge(clk);
    -- trame A
    for idx in 0 to NPIX-1 loop
      din <= std_logic_vector(to_unsigned(vA(idx), C_RESP_W));
      dv  <= '1'; if idx = 0 then ds <= '1'; else ds <= '0'; end if;
      wait until rising_edge(clk);
    end loop;
    -- trame B
    for idx in 0 to NPIX-1 loop
      din <= std_logic_vector(to_unsigned(vB(idx), C_RESP_W));
      dv  <= '1'; if idx = 0 then ds <= '1'; else ds <= '0'; end if;
      wait until rising_edge(clk);
    end loop;
    -- trame C (declenche le latch de la trame B) : quelques pixels suffisent
    for idx in 0 to 4 loop
      din <= (others => '0');
      dv  <= '1'; if idx = 0 then ds <= '1'; else ds <= '0'; end if;
      wait until rising_edge(clk);
    end loop;
    dv <= '0'; ds <= '0';
    wait for 60 ns;
    done <= true; wait;
  end process;

  check : process(clk)
    variable tick_no : integer := 0;
    variable err     : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and ftick = '1' then
        tick_no := tick_no + 1;
        if tick_no = 1 then          -- fin de trame A
          if not (mval = 500 and mx = 5 and my = 3) then
            report "TC-U-08 trame A : got val=" & integer'image(to_integer(mval)) &
                   " x=" & integer'image(to_integer(mx)) &
                   " y=" & integer'image(to_integer(my)) & " exp 500,5,3" severity warning;
            err := err + 1;
          end if;
        elsif tick_no = 2 then       -- fin de trame B (departage : 1ere occurrence)
          if not (mval = 500 and mx = 2 and my = 1) then
            report "TC-U-08 trame B : got val=" & integer'image(to_integer(mval)) &
                   " x=" & integer'image(to_integer(mx)) &
                   " y=" & integer'image(to_integer(my)) & " exp 500,2,1" severity warning;
            err := err + 1;
          end if;
        end if;
        errors <= err;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-08 (suivi max) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-U-08 : ECHEC" severity failure;
    report "TC-U-08 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
