--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : tb_regs_view.vhd
-- Description : Banc v2 du banc de registres AXI4-Lite. Verifie :
--                 - ecriture/relecture du nouveau registre VIEW (0x1C) et ses
--                   sorties (vue bits 2:0, court-circuit gaussien bit 3) ;
--                 - absence d'effet de bord sur THRESHOLD, MODE, SRC_SEL
--                   (ecritures consecutives, cf. ancien bug de decalage) ;
--                 - relecture de STATUS (0x18) inchangee.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.video_pkg.all;

entity tb_regs_view is end entity;

architecture sim of tb_regs_view is
  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';
  signal awaddr, araddr : std_logic_vector(4 downto 0) := (others => '0');
  signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
  signal awready, wready, bvalid, arready, rvalid : std_logic;
  signal wdata, rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal bresp, rresp : std_logic_vector(1 downto 0);
  signal threshold : unsigned(C_RESP_W-1 downto 0);
  signal mode, src_sel, gauss_bypass : std_logic;
  signal view : std_logic_vector(2 downto 0);
  signal done : boolean := false;
begin
  clk <= not clk after 5 ns when not done else '0';

  dut : entity work.axi4lite_regs
    generic map (ADDR_W => 5)
    port map (
      s_axi_aclk => clk, s_axi_aresetn => rstn,
      s_axi_awaddr => awaddr, s_axi_awvalid => awvalid, s_axi_awready => awready,
      s_axi_wdata => wdata, s_axi_wstrb => "1111", s_axi_wvalid => wvalid,
      s_axi_wready => wready, s_axi_bresp => bresp, s_axi_bvalid => bvalid,
      s_axi_bready => bready, s_axi_araddr => araddr, s_axi_arvalid => arvalid,
      s_axi_arready => arready, s_axi_rdata => rdata, s_axi_rresp => rresp,
      s_axi_rvalid => rvalid, s_axi_rready => rready,
      max_val => to_unsigned(0, C_RESP_W), max_x => to_unsigned(0, C_X_W),
      max_y => to_unsigned(0, C_Y_W), frame_tick => '0',
      status_in => x"0000003F",
      threshold => threshold, mode => mode, src_sel => src_sel,
      view => view, gauss_bypass => gauss_bypass);

  stim : process
    variable errors : natural := 0;

    procedure axi_write(a : natural; d : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      awaddr <= std_logic_vector(to_unsigned(a, 5)); wdata <= d;
      awvalid <= '1'; wvalid <= '1'; bready <= '1';
      loop
        wait until rising_edge(clk);
        exit when wready = '1';
      end loop;
      awvalid <= '0'; wvalid <= '0';
      loop
        wait until rising_edge(clk);
        exit when bvalid = '1';
      end loop;
      bready <= '0';
    end procedure;

    procedure axi_read(a : natural; d : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      araddr <= std_logic_vector(to_unsigned(a, 5)); arvalid <= '1'; rready <= '1';
      loop
        wait until rising_edge(clk);
        exit when arready = '1';
      end loop;
      arvalid <= '0';
      loop
        wait until rising_edge(clk);
        exit when rvalid = '1';
      end loop;
      d := rdata;
      rready <= '0';
    end procedure;

    procedure check(name : string; got, exp : std_logic_vector) is
    begin
      if got /= exp then
        report name & " : obtenu " & to_hstring(got) & " attendu " & to_hstring(exp)
          severity warning;
        errors := errors + 1;
      end if;
    end procedure;

    variable d : std_logic_vector(31 downto 0);
  begin
    rstn <= '0'; wait for 50 ns; rstn <= '1';
    -- valeurs au reset
    check("VIEW au reset", view & gauss_bypass, "0000");

    -- ecritures consecutives sur tous les registres RW
    axi_write(16#0C#, x"0000001E");      -- THRESHOLD = 30
    axi_write(16#10#, x"00000001");      -- MODE B
    axi_write(16#14#, x"00000001");      -- mire
    axi_write(16#1C#, x"0000000B");      -- vue 3 + gaussien court-circuite
    wait until rising_edge(clk);
    check("sortie threshold", std_logic_vector(threshold), std_logic_vector(to_unsigned(30, C_RESP_W)));
    check("sortie mode", (0 => mode), "1");
    check("sortie src_sel", (0 => src_sel), "1");
    check("sortie view", view, "011");
    check("sortie gauss_bypass", (0 => gauss_bypass), "1");

    axi_read(16#0C#, d); check("relecture 0x0C", d, x"0000001E");
    axi_read(16#10#, d); check("relecture 0x10", d, x"00000001");
    axi_read(16#14#, d); check("relecture 0x14", d, x"00000001");
    axi_read(16#18#, d); check("relecture 0x18", d, x"0000003F");
    axi_read(16#1C#, d); check("relecture 0x1C", d, x"0000000B");

    -- chaque vue, gaussien actif
    for v in 0 to 4 loop
      axi_write(16#1C#, std_logic_vector(to_unsigned(v, 32)));
      wait until rising_edge(clk);
      check("vue " & integer'image(v), view & gauss_bypass,
            std_logic_vector(to_unsigned(v, 3)) & '0');
    end loop;
    -- les autres registres n'ont pas bouge
    check("THRESHOLD intact", std_logic_vector(threshold), std_logic_vector(to_unsigned(30, C_RESP_W)));
    check("MODE intact", (0 => mode), "1");
    check("SRC_SEL intact", (0 => src_sel), "1");

    report "=== tb_regs_view : " & integer'image(errors) & " erreur(s) ===";
    assert errors = 0 report "tb_regs_view : ECHEC" severity failure;
    report "tb_regs_view : SUCCES";
    done <= true;
    wait;
  end process;
end architecture;
