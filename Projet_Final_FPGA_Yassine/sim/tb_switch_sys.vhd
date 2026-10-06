--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : tb_switch_sys.vhd
-- Description : Banc SYSTEME de la bascule de source a chaud (PL-IP-003) sur le
--               module video complet (video_subsystem_step2) : registres
--               AXI4-Lite, sequenceur DMA, multiplexeur, chaine, genlock VGA.
--
--               Un modele de DMA (protocole ap_ctrl_hs : s0_start / s0_idle)
--               produit une trame dont chaque pixel depend de sa position
--               (R = 8x, G = 16y, B = 0x50) : le moindre decalage est detecte.
--               La mire interne a un motif connu (8 barres).
--
--               Le banc ecrit SRC_SEL par de vraies transactions AXI4-Lite,
--               plusieurs fois (DMA -> mire -> DMA -> mire -> DMA), et classe
--               chaque image affichee : DMA exact, MIRE exacte, ou AUTRE.
--               Exigences verifiees :
--                 - apres chaque bascule, l'image demandee apparait EXACTE
--                   (au pixel pres) en au plus MAX_LAT images ;
--                 - puis elle reste exacte (image stable, sans decalage).
--               Ce banc detecte l'interblocage sequenceur/multiplexeur corrige
--               par mux_active (bascule vers la mire -> ecran noir).
--
--               A compiler avec sim/vga_pkg_mid.vhd (format 32x16).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
library work;
use work.video_pkg.all;
use work.vga_pkg.all;

entity tb_switch_sys is
  generic (DEBUG : boolean := false);
end entity;

architecture sim of tb_switch_sys is
  constant W : integer := H_VISIBLE;
  constant H : integer := V_VISIBLE;
  constant N : integer := W*H;
  constant MAX_LAT : integer := 4;             -- images tolerees pour basculer
  constant FR_PER_PHASE : integer := 10;       -- images observees par phase

  signal clk : std_logic := '0';
  signal resetn : std_logic := '0';
  signal done : boolean := false;

  -- AXI4-Lite
  signal awaddr, araddr : std_logic_vector(4 downto 0) := (others => '0');
  signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
  signal awready, wready, bvalid, arready, rvalid : std_logic;
  signal wdata, rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal bresp, rresp : std_logic_vector(1 downto 0);

  -- DMA
  signal s0_tdata : std_logic_vector(23 downto 0);
  signal s0_tvalid, s0_tready, s0_tuser, s0_tlast, s0_start, s0_idle : std_logic;
  signal busy : std_logic := '0';
  signal px   : integer := 0;

  -- VGA
  signal vga_r, vga_g, vga_b : std_logic_vector(VGA_COMP_W-1 downto 0);
  signal hs, vs : std_logic;


  -- classement des images
  type label_t is (L_DMA, L_MIRE, L_AUTRE);
  signal frame_count : integer := 0;
  signal last_label  : label_t := L_AUTRE;
  signal new_frame   : boolean := false;

  function mire_rgb(x : integer) return std_logic_vector is
  begin
    case (x*8)/W is
      when 0 => return x"FFF";  when 1 => return x"FF0";
      when 2 => return x"0FF";  when 3 => return x"0F0";
      when 4 => return x"F0F";  when 5 => return x"F00";
      when 6 => return x"00F";  when others => return x"000";
    end case;
  end function;

  function dma_rgb(x, y : integer) return std_logic_vector is
    variable r, g : unsigned(7 downto 0);
  begin
    r := to_unsigned((8*x) mod 256, 8);
    g := to_unsigned((16*y) mod 256, 8);
    return std_logic_vector(r(7 downto 4)) & std_logic_vector(g(7 downto 4)) & x"5";
  end function;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.video_subsystem_step2
    generic map (IMG_W => W, IMG_H => H)
    port map (
      clk => clk, resetn => resetn, s_axi_aclk => clk, s_axi_aresetn => resetn,
      s_axi_awaddr => awaddr, s_axi_awvalid => awvalid, s_axi_awready => awready,
      s_axi_wdata => wdata, s_axi_wstrb => "1111", s_axi_wvalid => wvalid,
      s_axi_wready => wready, s_axi_bresp => bresp, s_axi_bvalid => bvalid,
      s_axi_bready => bready, s_axi_araddr => araddr, s_axi_arvalid => arvalid,
      s_axi_arready => arready, s_axi_rdata => rdata, s_axi_rresp => rresp,
      s_axi_rvalid => rvalid, s_axi_rready => rready,
      s0_tdata => s0_tdata, s0_tvalid => s0_tvalid, s0_tready => s0_tready,
      s0_tuser => s0_tuser, s0_tlast => s0_tlast,
      s0_start => s0_start, s0_idle => s0_idle,
      vga_r => vga_r, vga_g => vga_g, vga_b => vga_b, vga_hsync => hs, vga_vsync => vs);

  -- modele DMA ap_ctrl_hs : demarre sur s0_start au repos, produit N pixels au
  -- rythme de s0_tready, puis revient au repos (ap_idle = 1).
  process(clk)
  begin
    if rising_edge(clk) then
      if resetn = '0' then
        busy <= '0'; px <= 0;
      elsif busy = '0' then
        if s0_start = '1' then busy <= '1'; px <= 0; end if;
      elsif s0_tready = '1' then
        if px = N-1 then busy <= '0'; else px <= px + 1; end if;
      end if;
    end if;
  end process;
  s0_tvalid <= busy;
  s0_tdata  <= std_logic_vector(to_unsigned((8*(px mod W)) mod 256, 8))
             & std_logic_vector(to_unsigned((16*(px / W)) mod 256, 8)) & x"50";
  s0_tuser  <= '1' when (busy = '1' and px = 0) else '0';
  s0_tlast  <= '1' when (busy = '1' and (px mod W) = W-1) else '0';
  s0_idle   <= not busy;

  -- classement de chaque image affichee (zone active complete)
  classify : process(clk)
    -- observation interne (noms externes VHDL-2008, declares apres l'instance)
    alias hc     is <<signal .tb_switch_sys.dut.u_vga.hc_i : unsigned(HC_W-1 downto 0)>>;
    alias vc     is <<signal .tb_switch_sys.dut.u_vga.vc_i : unsigned(HC_W-1 downto 0)>>;
    alias active is <<signal .tb_switch_sys.dut.u_vga.active_i : std_logic>>;
    variable n_act, n_dma, n_mire : integer := 0;
    variable dbg_msg : line := new string'("aucun");
    variable x, y : integer;
    variable pixv : std_logic_vector(11 downto 0);
  begin
    if rising_edge(clk) then
      new_frame <= false;
      if resetn = '1' then
        if hc = 0 and vc = 0 and n_act > 0 then
          -- fin d'image : verdict
          if n_dma = N and n_act = N then last_label <= L_DMA;
          elsif n_mire = N and n_act = N then last_label <= L_MIRE;
          else last_label <= L_AUTRE; end if;
          if DEBUG then
            report "  dbg : actifs=" & integer'image(n_act) & " dma_ok=" & integer'image(n_dma)
                 & " mire_ok=" & integer'image(n_mire) & " 1er ecart " & dbg_msg.all;
          end if;
          frame_count <= frame_count + 1;
          new_frame <= true;
          n_act := 0; n_dma := 0; n_mire := 0;
        end if;
        if active = '1' then
          x := to_integer(hc); y := to_integer(vc);
          pixv := vga_r & vga_g & vga_b;
          n_act := n_act + 1;
          if pixv = dma_rgb(x, y) then n_dma := n_dma + 1;
          elsif n_act - n_dma = 1 then
            deallocate(dbg_msg);
            dbg_msg := new string'("x=" & integer'image(x) & " y=" & integer'image(y)
                       & " obtenu=" & to_hstring(pixv) & " attendu=" & to_hstring(dma_rgb(x, y)));
          end if;
          if pixv = mire_rgb(x) then n_mire := n_mire + 1; end if;
        end if;
      end if;
    end if;
  end process;

  stim : process
    variable errors : natural := 0;

    procedure axi_write(a : natural; d : natural) is
    begin
      wait until rising_edge(clk);
      awaddr <= std_logic_vector(to_unsigned(a, 5));
      wdata <= std_logic_vector(to_unsigned(d, 32));
      awvalid <= '1'; wvalid <= '1'; bready <= '1';
      loop wait until rising_edge(clk); exit when wready = '1'; end loop;
      awvalid <= '0'; wvalid <= '0';
      loop wait until rising_edge(clk); exit when bvalid = '1'; end loop;
      bready <= '0';
    end procedure;

    -- observe FR_PER_PHASE images ; exige l'image 'want' exacte au plus tard a
    -- l'image MAX_LAT, puis exacte sans interruption jusqu'a la fin de la phase
    procedure phase(name : string; want : label_t) is
      variable first_ok : integer := -1;
      variable breaks   : integer := 0;
    begin
      for k in 1 to FR_PER_PHASE loop
        wait until new_frame;
        wait until rising_edge(clk);
        report name & " image " & integer'image(k) & " : " & label_t'image(last_label);
        if last_label = want then
          if first_ok < 0 then first_ok := k; end if;
        elsif first_ok >= 0 then
          breaks := breaks + 1;
        end if;
      end loop;
      if first_ok < 0 or first_ok > MAX_LAT then
        report name & " : ECHEC, image attendue (" & label_t'image(want)
             & ") non obtenue en " & integer'image(MAX_LAT) & " images" severity warning;
        errors := errors + 1;
      elsif breaks > 0 then
        report name & " : ECHEC, image instable apres bascule" severity warning;
        errors := errors + 1;
      else
        report name & " : OK, " & label_t'image(want) & " exacte des l'image "
             & integer'image(first_ok) & " et stable";
      end if;
    end procedure;
  begin
    resetn <= '0'; wait for 100 ns; resetn <= '1';
    phase("demarrage (SRC_SEL=0)", L_DMA);
    axi_write(16#14#, 1); phase("bascule 1 vers mire", L_MIRE);
    axi_write(16#14#, 0); phase("bascule 2 vers DMA", L_DMA);
    axi_write(16#14#, 1); phase("bascule 3 vers mire", L_MIRE);
    axi_write(16#14#, 0); phase("bascule 4 vers DMA", L_DMA);
    report "=== tb_switch_sys : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "tb_switch_sys : ECHEC" severity failure;
    report "tb_switch_sys : SUCCES";
    done <= true;
    wait;
  end process;
end architecture;
