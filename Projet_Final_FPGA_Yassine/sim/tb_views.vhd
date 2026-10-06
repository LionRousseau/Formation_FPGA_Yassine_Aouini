--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : tb_views.vhd
-- Description : Banc v2 de la chaine de traitement avec vues de demonstration.
--               Lit une image RGB (un pixel "r g b" par ligne), la presente en
--               continu sur NFRAMES trames (avec trous sur tvalid et contre-
--               pression sur tready pour eprouver le gel global et le transport
--               des bandes laterales), et ecrit la trame de sortie OUTFRAME
--               (un pixel hexadecimal RRGGBB par ligne).
--               La verification pixel par pixel est faite par check_views.py
--               contre un modele de reference independant.
--               Parametres : VIEW (0..4), BYPASS (gaussien court-circuite),
--               MODE (0 = A, 1 = B overlay), THR (seuil).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.video_pkg.all;

entity tb_views is
  generic (
    IMG_W    : natural := 160;
    IMG_H    : natural := 120;
    VIEW     : natural := 0;
    BYPASS   : natural := 0;
    MODE     : natural := 1;
    THR      : natural := 30;
    NFRAMES  : natural := 3;
    OUTFRAME : natural := 1;               -- 0 = premiere trame de sortie
    IN_FILE  : string  := "in_rgb.txt";
    OUT_FILE : string  := "out.txt"
  );
end entity;

architecture sim of tb_views is
  constant NPIX : natural := IMG_W*IMG_H;
  type img_t is array (0 to NPIX-1) of std_logic_vector(23 downto 0);

  impure function load return img_t is
    file f     : text open read_mode is IN_FILE;
    variable l : line;
    variable r, g, b : integer;
    variable im : img_t;
  begin
    for i in 0 to NPIX-1 loop
      readline(f, l); read(l, r); read(l, g); read(l, b);
      im(i) := std_logic_vector(to_unsigned(r,8)) & std_logic_vector(to_unsigned(g,8))
             & std_logic_vector(to_unsigned(b,8));
    end loop;
    return im;
  end function;
  constant SRC : img_t := load;

  signal clk    : std_logic := '0';
  signal resetn : std_logic := '0';
  signal done   : boolean := false;

  signal s_tdata  : std_logic_vector(23 downto 0) := (others => '0');
  signal s_tvalid, s_tready, s_tuser, s_tlast : std_logic := '0';
  signal m_tdata  : std_logic_vector(23 downto 0);
  signal m_tvalid, m_tready, m_tuser, m_tlast : std_logic;
  signal max_val  : unsigned(C_RESP_W-1 downto 0);
  signal max_x    : unsigned(C_X_W-1 downto 0);
  signal max_y    : unsigned(C_Y_W-1 downto 0);
  signal ftick    : std_logic;

  signal cyc : natural := 0;
  function to_sl(n : natural) return std_logic is
  begin
    if n = 1 then return '1'; else return '0'; end if;
  end function;
  constant MODE_B   : std_logic := to_sl(MODE);
  constant BYPASS_B : std_logic := to_sl(BYPASS);
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.processing_chain
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn,
      threshold => to_unsigned(THR, C_RESP_W),
      mode => MODE_B,
      ovl_color => x"00FF00",
      s_tdata => s_tdata, s_tvalid => s_tvalid, s_tready => s_tready,
      s_tuser => s_tuser, s_tlast => s_tlast,
      m_tdata => m_tdata, m_tvalid => m_tvalid, m_tready => m_tready,
      m_tuser => m_tuser, m_tlast => m_tlast,
      max_val => max_val, max_x => max_x, max_y => max_y, frame_tick => ftick,
      view => std_logic_vector(to_unsigned(VIEW, 3)),
      gauss_bypass => BYPASS_B);

  process(clk) begin
    if rising_edge(clk) then cyc <= cyc + 1; end if;
  end process;

  -- contre-pression aval : tready bas 1 cycle sur 7
  m_tready <= '0' when (cyc mod 7) = 3 else '1';

  -- source : NFRAMES trames, trou sur tvalid 1 cycle sur 11 (maitre AXI4-S
  -- conforme : un beat presente reste stable tant qu'il n'est pas accepte)
  src_p : process(clk)
    variable idx : natural := 0;
    variable fr  : natural := 0;
  begin
    if rising_edge(clk) then
      if resetn = '1' then
        if s_tvalid = '1' and s_tready = '1' then
          if idx = NPIX-1 then idx := 0; fr := fr + 1; else idx := idx + 1; end if;
        end if;
        if s_tvalid = '0' or s_tready = '1' then
          if fr >= NFRAMES or (cyc mod 11) = 5 then
            s_tvalid <= '0';
          else
            s_tvalid <= '1';
            s_tdata  <= SRC(idx);
            if idx = 0 then s_tuser <= '1'; else s_tuser <= '0'; end if;
            if (idx mod IMG_W) = IMG_W-1 then s_tlast <= '1'; else s_tlast <= '0'; end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- capture de la trame de sortie OUTFRAME
  cap_p : process(clk)
    file fo : text open write_mode is OUT_FILE;
    variable l : line;
    variable ofr : integer := -1;
    variable n   : natural := 0;
  begin
    if rising_edge(clk) then
      if m_tvalid = '1' and m_tready = '1' then
        if m_tuser = '1' then ofr := ofr + 1; n := 0; end if;
        if ofr = OUTFRAME and n < NPIX then
          hwrite(l, m_tdata); writeline(fo, l);
          n := n + 1;
          if n = NPIX then
            report "tb_views : trame " & integer'image(OUTFRAME) & " capturee ("
                   & integer'image(NPIX) & " pixels), max=" & integer'image(to_integer(max_val));
            done <= true;
          end if;
        end if;
      end if;
    end if;
  end process;

  process begin
    resetn <= '0'; wait for 50 ns; resetn <= '1';
    wait until done or cyc > NFRAMES*NPIX*3 + 100000;
    assert done report "tb_views : ECHEC, trame de sortie incomplete" severity failure;
    wait;
  end process;
end architecture;
