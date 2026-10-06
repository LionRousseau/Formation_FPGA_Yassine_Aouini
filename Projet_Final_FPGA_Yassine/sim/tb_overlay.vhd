--------------------------------------------------------------------------------
-- TC-I-03  Alignement de l'overlay (PL-DISP-001 / ED-02)
-- Injecte une image RGB comportant un motif localise, active le mode B, capture
-- la trame de sortie. Verifie que chaque pixel colore se superpose EXACTEMENT a
-- la position attendue (masque calcule par la reference), sans decalage. Un
-- defaut de dimensionnement de la ligne a retard se traduirait par un decalage
-- flagrant du flux brut par rapport au masque : c'est le cas le plus discriminant.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;
use work.ref_pkg.all;

entity tb_overlay is
end entity;

architecture sim of tb_overlay is
  constant IMG_W  : natural := 12;
  constant IMG_H  : natural := 10;
  constant NPIX   : natural := IMG_W*IMG_H;
  constant THRESH : natural := 60;
  constant OVL    : std_logic_vector(23 downto 0) := x"00FF00";  -- vert fort

  -- source RGB : fond gris, impulsion brillante, arete
  function sR(r,c : integer) return integer is begin
    if r=5 and c=6 then return 255; end if;
    if c=9 then return 210; end if;
    return 90;
  end function;
  function sG(r,c : integer) return integer is begin
    if r=5 and c=6 then return 250; end if;
    if c=9 then return 40; end if;
    return 95;
  end function;
  function sB(r,c : integer) return integer is begin
    if r=5 and c=6 then return 245; end if;
    if c=9 then return 60; end if;
    return 100;
  end function;
  function pack(r,c : integer) return std_logic_vector is begin
    return std_logic_vector(to_unsigned(sR(r,c),8)) &
           std_logic_vector(to_unsigned(sG(r,c),8)) &
           std_logic_vector(to_unsigned(sB(r,c),8));
  end function;

  function luma(r,c : integer) return integer is begin
    return ref_luma(sR(r,c), sG(r,c), sB(r,c));
  end function;
  function luma_b(r,c : integer) return integer is begin
    if r<0 or r>=IMG_H or c<0 or c>=IMG_W then return 0; else return luma(r,c); end if;
  end function;
  function gref(r,c : integer) return integer is
    variable w,k : int3x3_t; variable i : integer := 0; begin
    for dr in -1 to 1 loop for dc in -1 to 1 loop
      w(i) := luma_b(r+dr,c+dc); i := i+1; end loop; end loop;
    k := (1,2,1, 2,4,2, 1,2,1);
    return ref_conv(w,k,4,false,8);
  end function;
  function gref_b(r,c : integer) return integer is begin
    if r<0 or r>=IMG_H or c<0 or c>=IMG_W then return 0; else return gref(r,c); end if;
  end function;
  function mask(r,c : integer) return std_logic is
    variable w,k : int3x3_t; variable i : integer := 0; variable lap : integer; begin
    for dr in -1 to 1 loop for dc in -1 to 1 loop
      w(i) := gref_b(r+dr,c+dc); i := i+1; end loop; end loop;
    k := (0,-1,0, -1,4,-1, 0,-1,0);
    lap := ref_conv(w,k,0,true,C_RESP_W);
    if lap >= THRESH then return '1'; else return '0'; end if;
  end function;
  function expected(r,c : integer) return std_logic_vector is begin
    if mask(r,c) = '1' then return OVL; else return pack(r,c); end if;
  end function;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal din    : std_logic_vector(23 downto 0) := (others => '0');
  signal dv, du, dl : std_logic := '0';
  signal dready : std_logic;
  signal mout   : std_logic_vector(23 downto 0);
  signal mv, mu, ml : std_logic;

  signal mval : unsigned(C_RESP_W-1 downto 0);
  signal mx   : unsigned(C_X_W-1 downto 0);
  signal my   : unsigned(C_Y_W-1 downto 0);
  signal ftk  : std_logic;

  signal errors : integer := 0;
  signal done   : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.processing_chain
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      threshold => to_unsigned(THRESH, C_RESP_W), mode => '1', ovl_color => OVL,
      s_tdata => din, s_tvalid => dv, s_tready => dready, s_tuser => du, s_tlast => dl,
      m_tdata => mout, m_tvalid => mv, m_tready => '1', m_tuser => mu, m_tlast => ml,
      max_val => mval, max_x => mx, max_y => my, frame_tick => ftk);

  stim : process
  begin
    resetn <= '0'; dv <= '0'; du <= '0'; dl <= '0';
    wait for 23 ns; resetn <= '1';
    wait until rising_edge(clk);
    for f in 0 to 2 loop
      for idx in 0 to NPIX-1 loop
        din <= pack(idx/IMG_W, idx mod IMG_W);
        dv  <= '1';
        if idx = 0 then du <= '1'; else du <= '0'; end if;
        if (idx mod IMG_W) = IMG_W-1 then dl <= '1'; else dl <= '0'; end if;
        wait until rising_edge(clk);
      end loop;
    end loop;
    dv <= '0'; du <= '0'; dl <= '0';
    wait for 600 ns;
    done <= true; wait;
  end process;

  check : process(clk)
    variable c, r     : integer := 0;
    variable frame_no : integer := -1;
    variable err      : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and mv = '1' then
        if mu = '1' then frame_no := frame_no + 1; c := 0; r := 0; end if;
        if frame_no = 1 then
          if mout /= expected(r, c) then
            report "TC-I-03 (c=" & integer'image(c) & ",r=" & integer'image(r) &
                   ") got=" & to_hstring(mout) & " exp=" & to_hstring(expected(r,c)) &
                   " mask=" & std_logic'image(mask(r,c)) severity warning;
            err := err + 1;
          end if;
          errors <= err;
        end if;
        if c = IMG_W-1 then c := 0; r := r + 1; else c := c + 1; end if;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-I-03 (alignement overlay) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-I-03 : ECHEC" severity failure;
    report "TC-I-03 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
