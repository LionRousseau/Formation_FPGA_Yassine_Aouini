--------------------------------------------------------------------------------
-- TC-S-01 (equivalent simulation)  Mire vers ecran VGA (PL-IP-001 + PL-DISP-002)
-- Chaine tpg -> vga_stream_out. Verifie l'affichage d'une image stable :
--   - hors zone active, la sortie est noire ;
--   - en zone active, sur la premiere ligne (y=0, sans le carre mobile), les
--     barres de couleur apparaissent aux bonnes colonnes, tronquees en 4:4:4 ;
--   - le verrouillage de trame (genlock) s'etablit.
-- C'est la preuve en simulation du chemin d'affichage du lot 1 ; la validation
-- visuelle sur carte reste TC-S-01 proprement dit.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;
use work.vga_pkg.all;

entity tb_vga_display is
end entity;

architecture sim of tb_vga_display is
  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';

  signal s_td   : std_logic_vector(23 downto 0);
  signal s_tv, s_tr, s_tu, s_tl : std_logic;

  signal vr, vg, vb : std_logic_vector(3 downto 0);
  signal hs, vs, locked, act : std_logic;
  signal vx : unsigned(HC_W-1 downto 0);
  signal vy : unsigned(VC_W-1 downto 0);

  signal errors : integer := 0;
  signal nb_y0  : integer := 0;
  signal nb_bl  : integer := 0;
  signal done   : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  u_tpg : entity work.tpg
    port map (clk => clk, resetn => resetn,
      m_tdata => s_td, m_tvalid => s_tv, m_tready => s_tr, m_tuser => s_tu, m_tlast => s_tl);

  u_vga : entity work.vga_stream_out
    port map (clk => clk, resetn => resetn,
      s_tdata => s_td, s_tvalid => s_tv, s_tready => s_tr, s_tuser => s_tu, s_tlast => s_tl,
      vga_r => vr, vga_g => vg, vga_b => vb, vga_hsync => hs, vga_vsync => vs,
      locked_o => locked, active_o => act, x_o => vx, y_o => vy);

  stim : process
  begin
    resetn <= '0';
    wait for 53 ns; resetn <= '1';
    wait for 6 ms;
    done <= true; wait;
  end process;

  check : process(clk)
    variable xi   : integer;
    variable er, gr, br : std_logic_vector(3 downto 0);
    variable e    : integer := 0;
    variable ny0  : integer := 0;
    variable nbl  : integer := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' and locked = '1' then
        -- hors zone active : noir
        if act = '0' then
          if vr /= "0000" or vg /= "0000" or vb /= "0000" then
            report "TC-S-01 sortie non noire en blanking" severity warning; e := e + 1;
          end if;
          nbl := nbl + 1;
        else
          -- zone active, premiere ligne : barres de couleur
          if vy = 0 then
            xi := to_integer(vx);
            if    xi < 80  then er:="1111"; gr:="1111"; br:="1111";   -- blanc
            elsif xi < 160 then er:="1111"; gr:="1111"; br:="0000";   -- jaune
            elsif xi < 240 then er:="0000"; gr:="1111"; br:="1111";   -- cyan
            elsif xi < 320 then er:="0000"; gr:="1111"; br:="0000";   -- vert
            elsif xi < 400 then er:="1111"; gr:="0000"; br:="1111";   -- magenta
            elsif xi < 480 then er:="1111"; gr:="0000"; br:="0000";   -- rouge
            elsif xi < 560 then er:="0000"; gr:="0000"; br:="1111";   -- bleu
            else                er:="0000"; gr:="0000"; br:="0000";   -- noir
            end if;
            if vr /= er or vg /= gr or vb /= br then
              report "TC-S-01 barre incorrecte x=" & integer'image(xi) &
                     " got " & to_hstring(vr) & to_hstring(vg) & to_hstring(vb) severity warning;
              e := e + 1;
            end if;
            ny0 := ny0 + 1;
          end if;
        end if;
        errors <= e; nb_y0 <= ny0; nb_bl <= nbl;
      end if;
    end if;
  end process;

  verdict : process
  begin
    wait until done; wait for 1 ns;
    report "=== TC-S-01 sim (mire->VGA) : " & integer'image(errors) & " erreur(s), " &
           integer'image(nb_y0) & " pixels y=0 verifies, " &
           integer'image(nb_bl) & " pixels blanking verifies ===";
    assert errors = 0 report "TC-S-01 sim : ECHEC" severity failure;
    assert nb_y0 >= 640 report "TC-S-01 sim : ligne y=0 non couverte" severity failure;
    assert nb_bl > 0 report "TC-S-01 sim : blanking non observe" severity failure;
    report "TC-S-01 sim : SUCCES" severity note;
    wait;
  end process;
end architecture sim;
