--------------------------------------------------------------------------------
-- TC-I-01  Chaine de traitement complete (PL-IP-006, PL-IP-007, PL-IP-008 chaines)
-- Injecte une trame en luminance, capture la sortie binaire, compare au resultat
-- de la procedure de reference appliquee a la meme trame (gaussien, puis
-- laplacien du gaussien, puis seuillage). Egalite bit a bit sur la zone utile.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;
use work.ref_pkg.all;

entity tb_chain is
end entity;

architecture sim of tb_chain is
  constant IMG_W : natural := 12;
  constant IMG_H : natural := 10;
  constant NPIX  : natural := IMG_W*IMG_H;
  constant THRESH : natural := 60;

  function src(r, c : integer) return integer is
  begin
    if r = 5 and c = 6 then return 255; end if;      -- impulsion
    if r = 2 and c = 2 then return 0;   end if;
    if c = 9 then return 210; end if;                -- arete
    if r = 7 then return 150; end if;                -- bande horizontale
    return 90;
  end function;
  function src_b(r, c : integer) return integer is
  begin
    if r<0 or r>=IMG_H or c<0 or c>=IMG_W then return 0; else return src(r,c); end if;
  end function;

  -- gaussien de reference en (r,c), bords a zero
  function gref(r, c : integer) return integer is
    variable w, k : int3x3_t; variable i : integer := 0;
  begin
    for dr in -1 to 1 loop for dc in -1 to 1 loop
      w(i) := src_b(r+dr, c+dc); i := i + 1;
    end loop; end loop;
    k := (1,2,1, 2,4,2, 1,2,1);
    return ref_conv(w, k, 4, false, 8);
  end function;
  function gref_b(r, c : integer) return integer is
  begin
    if r<0 or r>=IMG_H or c<0 or c>=IMG_W then return 0; else return gref(r,c); end if;
  end function;

  -- laplacien du gaussien puis seuillage -> bit attendu
  function bref(r, c : integer) return std_logic is
    variable w, k : int3x3_t; variable i : integer := 0; variable lap : integer;
  begin
    for dr in -1 to 1 loop for dc in -1 to 1 loop
      w(i) := gref_b(r+dr, c+dc); i := i + 1;
    end loop; end loop;
    k := (0,-1,0, -1,4,-1, 0,-1,0);
    lap := ref_conv(w, k, 0, true, C_RESP_W);
    if lap >= THRESH then return '1'; else return '0'; end if;
  end function;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal din    : std_logic_vector(7 downto 0) := (others => '0');
  signal dv, du, dl : std_logic := '0';
  signal dready : std_logic;

  -- gaussien -> laplacien
  signal g_d : std_logic_vector(7 downto 0);
  signal g_v, g_r, g_u, g_l : std_logic;
  -- laplacien -> binar
  signal l_d : std_logic_vector(C_RESP_W-1 downto 0);
  signal l_v, l_r, l_u, l_l : std_logic;
  -- binar -> sortie
  signal b_d : std_logic_vector(0 downto 0);
  signal b_v, b_u, b_l : std_logic;

  signal errors : integer := 0;
  signal done   : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  u_g : entity work.gaussian_filter generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      s_tdata => din, s_tvalid => dv, s_tready => dready, s_tuser => du, s_tlast => dl,
      m_tdata => g_d, m_tvalid => g_v, m_tready => g_r, m_tuser => g_u, m_tlast => g_l);

  u_l : entity work.laplacian_filter generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      s_tdata => g_d, s_tvalid => g_v, s_tready => g_r, s_tuser => g_u, s_tlast => g_l,
      m_tdata => l_d, m_tvalid => l_v, m_tready => l_r, m_tuser => l_u, m_tlast => l_l);

  u_b : entity work.binarize
    port map (clk => clk, resetn => resetn, thresh => to_unsigned(THRESH, C_RESP_W),
      s_tdata => l_d, s_tvalid => l_v, s_tready => l_r, s_tuser => l_u, s_tlast => l_l,
      m_tdata => b_d, m_tvalid => b_v, m_tready => '1', m_tuser => b_u, m_tlast => b_l);

  stim : process
  begin
    resetn <= '0'; dv <= '0'; du <= '0'; dl <= '0';
    wait for 23 ns; resetn <= '1';
    wait until rising_edge(clk);
    for f in 0 to 2 loop
      for idx in 0 to NPIX-1 loop
        din <= std_logic_vector(to_unsigned(src(idx/IMG_W, idx mod IMG_W), 8));
        dv  <= '1';
        if idx = 0 then du <= '1'; else du <= '0'; end if;
        if (idx mod IMG_W) = IMG_W-1 then dl <= '1'; else dl <= '0'; end if;
        wait until rising_edge(clk);
      end loop;
    end loop;
    dv <= '0'; du <= '0'; dl <= '0';
    wait for 400 ns;
    done <= true; wait;
  end process;

  check : process(clk)
    variable c, r     : integer := 0;
    variable frame_no : integer := -1;
    variable err      : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and b_v = '1' then
        if b_u = '1' then frame_no := frame_no + 1; c := 0; r := 0; end if;
        if frame_no = 1 then
          if b_d(0) /= bref(r, c) then
            report "TC-I-01 (c=" & integer'image(c) & ",r=" & integer'image(r) &
                   ") got=" & std_logic'image(b_d(0)) &
                   " exp=" & std_logic'image(bref(r,c)) severity warning;
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
    report "=== TC-I-01 (chaine complete) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-I-01 : ECHEC" severity failure;
    report "TC-I-01 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
