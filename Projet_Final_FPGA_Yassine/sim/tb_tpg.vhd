--------------------------------------------------------------------------------
-- TC-U-02  Generateur de mire (PL-IP-001)
-- Simule deux trames consecutives. Verifie :
--   - la presence de l'element dynamique : le pixel en un point donne differe
--     d'une trame a l'autre (le carre mobile s'est deplace) ;
--   - le format et la cadence : 307200 pixels par trame, un tuser par trame (au
--     premier pixel), un tlast par ligne (au dernier pixel de chaque ligne),
--     480 lignes.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity tb_tpg is
end entity;

architecture sim of tb_tpg is
  constant IMG_W : natural := C_IMG_WIDTH;
  constant IMG_H : natural := C_IMG_HEIGHT;
  constant NPIX  : natural := IMG_W*IMG_H;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal td     : std_logic_vector(23 downto 0);
  signal tv, tr, tu, tl : std_logic;
  signal errors : integer := 0;
  signal done   : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';
  tr  <= '1';                                   -- aval toujours pret

  dut : entity work.tpg
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (clk => clk, resetn => resetn,
      m_tdata => td, m_tvalid => tv, m_tready => tr, m_tuser => tu, m_tlast => tl);

  stim : process
  begin
    resetn <= '0';
    wait for 23 ns; resetn <= '1';
    wait; -- le DUT tourne librement
  end process;

  check : process(clk)
    variable x, y       : integer := 0;
    variable frame_no   : integer := -1;
    variable pix_in_fr  : integer := 0;
    variable tlast_in_fr: integer := 0;
    variable err        : integer := 0;
    type cap_t is array (0 to 1) of std_logic_vector(23 downto 0);
    variable cap        : cap_t := (others => (others => '0'));
    variable captured   : boolean := false;
  begin
    if rising_edge(clk) then
      if resetn = '1' and tv = '1' and tr = '1' then
        -- reconstruction coordonnee
        if tu = '1' then
          -- verifie la trame precedente a la frontiere
          if frame_no >= 0 then
            if pix_in_fr /= NPIX then
              report "TC-U-02 pixels/trame = " & integer'image(pix_in_fr) severity warning; err := err+1;
            end if;
            if tlast_in_fr /= IMG_H then
              report "TC-U-02 tlast/trame = " & integer'image(tlast_in_fr) severity warning; err := err+1;
            end if;
          end if;
          frame_no := frame_no + 1; x := 0; y := 0; pix_in_fr := 0; tlast_in_fr := 0;
          if x /= 0 or y /= 0 then
            report "TC-U-02 tuser hors (0,0)" severity warning; err := err+1;
          end if;
        end if;

        pix_in_fr := pix_in_fr + 1;
        -- tlast doit coincider avec la fin de ligne
        if (tl = '1') /= (x = IMG_W-1) then
          report "TC-U-02 tlast incoherent a x=" & integer'image(x) severity warning; err := err+1;
        end if;
        if tl = '1' then tlast_in_fr := tlast_in_fr + 1; end if;

        -- capture d'un point sensible au deplacement du carre
        if x = 2 and y = 230 and frame_no >= 0 and frame_no <= 1 then
          cap(frame_no) := td;
          if frame_no = 1 then captured := true; end if;
        end if;

        -- avance coordonnee
        if x = IMG_W-1 then x := 0; y := y + 1; else x := x + 1; end if;

        -- fin de la 2e trame : verdict des captures
        if captured and frame_no = 1 and x = 3 and y = 230 then
          if cap(0) = cap(1) then
            report "TC-U-02 element dynamique absent : pixel (2,230) identique entre trames" severity warning;
            err := err + 1;
          end if;
          done <= true;
        end if;
        errors <= err;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-U-02 (generateur de mire) : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "TC-U-02 : ECHEC" severity failure;
    report "TC-U-02 : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
