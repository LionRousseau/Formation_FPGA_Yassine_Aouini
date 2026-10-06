--------------------------------------------------------------------------------
-- TC-U-04b  Filtre laplacien (PL-IP-007, cf PO-01)
-- Meme image de test que TC-U-04a. Verifie : zone uniforme -> sortie 0 ;
-- impulsion -> reproduction du noyau ; arete -> reponse forte ; valeur absolue
-- prise avant sortie (PO-06) ; bords a zero (PO-05). Egalite bit a bit avec
-- ref_conv. 2e trame verifiee (regime etabli).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;
use work.ref_pkg.all;

entity tb_laplacian is
end entity;

architecture sim of tb_laplacian is
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
  function src_bordered(r, c : integer) return integer is
  begin
    if r < 0 or r >= IMG_H or c < 0 or c >= IMG_W then return 0;
    else return src(r,c); end if;
  end function;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal din    : std_logic_vector(7 downto 0) := (others => '0');
  signal dv, du, dl : std_logic := '0';
  signal dready : std_logic;
  signal yout   : std_logic_vector(C_RESP_W-1 downto 0);
  signal yv, yu, yl : std_logic;
  signal errors : integer := 0;
  signal done   : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.laplacian_filter
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      s_tdata => din, s_tvalid => dv, s_tready => dready,
      s_tuser => du, s_tlast => dl,
      m_tdata => yout, m_tvalid => yv, m_tready => '1',
      m_tuser => yu, m_tlast => yl);

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
    wait for 300 ns;
    done <= true; wait;
  end process;

  check : process(clk)
    variable c, r     : integer := 0;
    variable frame_no : integer := -1;
    variable win, ker : int3x3_t;
    variable idx      : integer;
    variable exp      : integer;
    variable err      : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and yv = '1' then
        if yu = '1' then frame_no := frame_no + 1; c := 0; r := 0; end if;
        if frame_no = 1 then
          idx := 0;
          for dr in -1 to 1 loop
            for dc in -1 to 1 loop
              win(idx) := src_bordered(r+dr, c+dc);
              idx := idx + 1;
            end loop;
          end loop;
          ker := (0,-1,0, -1,4,-1, 0,-1,0);
          exp := ref_conv(win, ker, 0, true, C_RESP_W);
          if to_integer(unsigned(yout)) /= exp then
            report "TC-U-04b (c=" & integer'image(c) & ",r=" & integer'image(r) &
                   ") got=" & integer'image(to_integer(unsigned(yout))) &
                   " exp=" & integer'image(exp) severity warning;
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
    report "=== TC-U-04b (laplacien) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-U-04b : ECHEC" severity failure;
    report "TC-U-04b : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
