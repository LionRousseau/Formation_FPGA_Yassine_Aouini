--------------------------------------------------------------------------------
-- TC-U-05  Binarisation et seuil (PL-IP-008 / PL-IP-009)
-- Balaye une rampe d'entree pour trois valeurs de seuil, dont 0 et la valeur
-- maximale. Verifie : sortie 0 strictement sous le seuil, 1 au seuil et au-dessus.
-- Verifie aussi que le seuil est verrouille en debut de trame : un changement en
-- cours de trame n'est pris en compte qu'a la trame suivante (image non corrompue).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tb_binarize is
end entity;

architecture sim of tb_binarize is
  constant NVAL : natural := 32;                         -- pixels par trame
  constant VMAX : natural := 2**C_RESP_W - 1;           -- 2047
  -- rampe couvrant toute la plage
  function ramp(i : integer) return integer is
  begin
    return (i * VMAX) / (NVAL-1);
  end function;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal thr    : unsigned(C_RESP_W-1 downto 0) := (others => '0');
  signal din    : std_logic_vector(C_RESP_W-1 downto 0) := (others => '0');
  signal dv, du, dl : std_logic := '0';
  signal dready : std_logic;
  signal bout   : std_logic_vector(0 downto 0);
  signal bv, bu, bl : std_logic;
  signal errors : integer := 0;
  signal done   : boolean := false;

  type thr_arr is array (0 to 2) of natural;
  constant THRS : thr_arr := (0, VMAX/2, VMAX);   -- seuils testes
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.binarize
    port map (clk => clk, resetn => resetn, thresh => thr,
      s_tdata => din, s_tvalid => dv, s_tready => dready,
      s_tuser => du, s_tlast => dl,
      m_tdata => bout, m_tvalid => bv, m_tuser => bu, m_tlast => bl,
      m_tready => '1');

  stim : process
  begin
    resetn <= '0'; dv <= '0'; du <= '0'; dl <= '0';
    wait for 23 ns; resetn <= '1';
    wait until rising_edge(clk);
    for f in 0 to 2 loop
      thr <= to_unsigned(THRS(f), C_RESP_W);      -- seuil de la trame
      for i in 0 to NVAL-1 loop
        din <= std_logic_vector(to_unsigned(ramp(i), C_RESP_W));
        dv  <= '1';
        if i = 0 then du <= '1'; else du <= '0'; end if;
        if i = NVAL-1 then dl <= '1'; else dl <= '0'; end if;
        -- perturbation : on modifie le seuil vif en cours de trame ; il ne doit
        -- PAS etre pris en compte avant la trame suivante.
        if i = NVAL/2 then thr <= to_unsigned(VMAX/4, C_RESP_W); end if;
        wait until rising_edge(clk);
      end loop;
    end loop;
    dv <= '0'; du <= '0'; dl <= '0';
    wait for 100 ns;
    done <= true; wait;
  end process;

  check : process(clk)
    variable frame_no : integer := -1;
    variable i        : integer := 0;
    variable expbit   : std_logic;
    variable err      : integer := 0;
    variable eff_thr  : integer;
  begin
    if rising_edge(clk) then
      if resetn = '1' and bv = '1' then
        if bu = '1' then frame_no := frame_no + 1; i := 0; end if;
        if frame_no >= 0 and frame_no <= 2 then
          eff_thr := THRS(frame_no);          -- seuil verrouille en debut de trame
          if ramp(i) >= eff_thr then expbit := '1'; else expbit := '0'; end if;
          if bout(0) /= expbit then
            report "TC-U-05 trame " & integer'image(frame_no) & " i=" & integer'image(i) &
                   " val=" & integer'image(ramp(i)) & " thr=" & integer'image(eff_thr) &
                   " got=" & std_logic'image(bout(0)) severity warning;
            err := err + 1;
          end if;
          errors <= err;
        end if;
        i := i + 1;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-05 (binarisation) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-U-05 : ECHEC" severity failure;
    report "TC-U-05 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
