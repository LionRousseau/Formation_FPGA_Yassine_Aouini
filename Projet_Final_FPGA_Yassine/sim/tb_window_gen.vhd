--------------------------------------------------------------------------------
-- Testbench de mise au point : window_gen
-- Verifie que la fenetre 3x3 exposee correspond, a chaque sortie valide, au
-- voisinage (borde a zero, PO-05) du pixel central signale par (col_o,row_o),
-- calcule de facon independante a partir de l'image source.
-- Sert a caler la constante COORD_DELAY. Verdict explicite en fin de simulation.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tb_window_gen is
end entity;

architecture sim of tb_window_gen is
  constant IMG_W : natural := 8;
  constant IMG_H : natural := 6;
  constant NPIX  : natural := IMG_W*IMG_H;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal en     : std_logic := '0';
  signal din    : unsigned(7 downto 0) := (others => '0');
  signal dsof   : std_logic := '0';
  signal dval   : std_logic := '0';

  signal win    : window3x3_t;
  signal col    : unsigned(C_X_W-1 downto 0);
  signal row    : unsigned(C_Y_W-1 downto 0);
  signal vld    : std_logic;
  signal sof_o  : std_logic;
  signal eol_o  : std_logic;

  -- Image source : valeur = 1 + (row*IMG_W + col) mod 250, motif de position.
  type img_t is array (0 to IMG_H-1, 0 to IMG_W-1) of integer;
  function make_img return img_t is
    variable im : img_t;
  begin
    for r in 0 to IMG_H-1 loop
      for c in 0 to IMG_W-1 loop
        im(r,c) := 1 + ((r*IMG_W + c) mod 250);
      end loop;
    end loop;
    return im;
  end function;
  constant IMG : img_t := make_img;

  -- Voisinage de reference, bords a zero.
  function ref_pix(r, c : integer) return integer is
  begin
    if r < 0 or r >= IMG_H or c < 0 or c >= IMG_W then
      return 0;
    else
      return IMG(r,c);
    end if;
  end function;

  signal errors : integer := 0;
  signal done   : boolean := false;
begin

  clk <= not clk after 5 ns when not done else '0';

  -- Stimuli : trois trames identiques. La premiere amorce le pipeline (line
  -- buffers), la deuxieme est verifiee en regime etabli, la troisieme vide.
  stim : process
  begin
    resetn <= '0';
    en <= '0'; dval <= '0'; dsof <= '0';
    wait for 23 ns;
    resetn <= '1';
    wait until rising_edge(clk);
    en <= '1';
    for frame in 0 to 2 loop
      for idx in 0 to NPIX-1 loop
        din  <= to_unsigned(IMG(idx/IMG_W, idx mod IMG_W), 8);
        dval <= '1';
        if idx = 0 then dsof <= '1'; else dsof <= '0'; end if;
        wait until rising_edge(clk);
      end loop;
    end loop;
    dval <= '0'; dsof <= '0';
    wait for 200 ns;
    done <= true;
    wait;
  end process;

  dut : entity work.window_gen
    generic map (DATA_W => 8, IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn, en => en,
      din => din, din_sof => dsof, din_valid => dval,
      win_o => win, col_o => col, row_o => row,
      valid_o => vld, sof_o => sof_o, eol_o => eol_o);

  -- Verification : on ne controle que la 2e trame (regime etabli). On compte
  -- les impulsions sof_o pour reperer les frontieres de trame.
  check : process(clk)
    variable c, r     : integer;
    variable exp      : window3x3_t;
    variable idx      : integer;
    variable frame_no : integer := -1;    -- incremente a chaque sof_o
    variable err_v    : integer := 0;
    variable checked  : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and vld = '1' then
        if sof_o = '1' then
          frame_no := frame_no + 1;
        end if;
        c := to_integer(col);
        r := to_integer(row);
        -- fenetre attendue, bords a zero
        idx := 0;
        for dr in -1 to 1 loop
          for dc in -1 to 1 loop
            exp(idx) := to_unsigned(ref_pix(r+dr, c+dc), 8);
            idx := idx + 1;
          end loop;
        end loop;
        if frame_no = 1 then       -- 2e trame uniquement
          checked := checked + 1;
          for i in 0 to 8 loop
            if win(i) /= exp(i) then
              report "MISMATCH frame" & integer'image(frame_no) &
                     " (c=" & integer'image(c) & ",r=" & integer'image(r) &
                     ") tap " & integer'image(i) &
                     " got=" & integer'image(to_integer(win(i))) &
                     " exp=" & integer'image(to_integer(exp(i)))
                     severity warning;
              err_v := err_v + 1;
            end if;
          end loop;
        end if;
        errors <= err_v;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done;
    wait for 1 ns;
    report "=== TB window_gen : " & integer'image(errors) & " erreur(s) sur la trame verifiee ===";
    assert errors = 0
      report "TC-U-06 (window_gen) : ECHEC" severity failure;
    report "TC-U-06 (window_gen) : SUCCES" severity note;
    wait;
  end process;

end architecture sim;
