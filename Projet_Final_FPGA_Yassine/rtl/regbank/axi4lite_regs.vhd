--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : axi4lite_regs.vhd
-- Description : Banc de registres AXI4-Lite pilote par la partie PS (planche
--               SCH-05). Regroupe le controle de la chaine et le retour de
--               donnees du suivi de maximum.
--
--   Offset  Nom          Acces  Contenu
--   0x00    MAX_VAL      RO     Reponse maximale (PL-IP-010, 32b, ext. de zero)
--   0x04    MAX_X        RO     Coordonnee X du maximum (PL-IP-010)
--   0x08    MAX_Y        RO     Coordonnee Y du maximum (PL-IP-010)
--   0x0C    THRESHOLD    RW     Seuil de binarisation (PL-IP-009), bits C_RESP_W
--   0x10    MODE         RW     bit0 = mode d'affichage A/B (PL-DISP-003)
--   0x14    SRC_SEL      RW     bit0 = source video (0=memoire,1=TPG) PL-IP-002/003
--   0x18    STATUS       RO     diagnostic (verrouillage, activite du flux)
--   0x1C    VIEW         RW     v2, demonstration des etages (hors SRS) :
--                                 bits 2:0 = vue (0 normale, 1 luminance,
--                                 2 gaussien, 3 reponse laplacien, 4 masque)
--                                 bit 3    = gaussien court-circuite (1)
--
--   Les entrees MAX_* sont echantillonnees sur frame_tick (fin de trame) afin de
--   presenter au PS un triplet coherent (latch de fin de trame, PO-08 : pas de
--   double buffer, lecture stable entre deux fins de trame).
--
--   Implementation AXI4-Lite standard, un seul mot par transaction, sans rafale.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity axi4lite_regs is
  generic (
    ADDR_W : natural := 5             -- 32 octets d'espace registre
  );
  port (
    -- horloge / reset AXI
    s_axi_aclk    : in  std_logic;
    s_axi_aresetn : in  std_logic;
    -- ecriture
    s_axi_awaddr  : in  std_logic_vector(ADDR_W-1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    -- lecture
    s_axi_araddr  : in  std_logic_vector(ADDR_W-1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    -- interface materielle
    max_val       : in  unsigned(C_RESP_W-1 downto 0);
    max_x         : in  unsigned(C_X_W-1 downto 0);
    max_y         : in  unsigned(C_Y_W-1 downto 0);
    frame_tick    : in  std_logic;
    status_in     : in  std_logic_vector(31 downto 0) := (others => '0');  -- 0x18 RO diagnostic
    threshold     : out unsigned(C_RESP_W-1 downto 0);
    mode          : out std_logic;
    src_sel       : out std_logic;
    -- v2
    view          : out std_logic_vector(2 downto 0);
    gauss_bypass  : out std_logic
  );
end entity axi4lite_regs;

architecture rtl of axi4lite_regs is
  -- registres RW
  signal reg_thresh : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_mode   : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_src    : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_view   : std_logic_vector(31 downto 0) := (others => '0');
  -- registres RO (echantillonnes en fin de trame)
  signal reg_maxval : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_maxx   : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_maxy   : std_logic_vector(31 downto 0) := (others => '0');

  -- machine AXI ecriture
  signal awready_i : std_logic := '0';
  signal wready_i  : std_logic := '0';
  signal bvalid_i  : std_logic := '0';
  signal awaddr_q  : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
  -- machine AXI lecture
  signal arready_i : std_logic := '0';
  signal rvalid_i  : std_logic := '0';
  signal rdata_i   : std_logic_vector(31 downto 0) := (others => '0');
begin
  s_axi_awready <= awready_i;
  s_axi_wready  <= wready_i;
  s_axi_bvalid  <= bvalid_i;
  s_axi_bresp   <= "00";              -- OKAY
  s_axi_arready <= arready_i;
  s_axi_rvalid  <= rvalid_i;
  s_axi_rdata   <= rdata_i;
  s_axi_rresp   <= "00";              -- OKAY

  threshold <= unsigned(reg_thresh(C_RESP_W-1 downto 0));
  mode      <= reg_mode(0);
  src_sel   <= reg_src(0);
  view         <= reg_view(2 downto 0);
  gauss_bypass <= reg_view(3);

  ----------------------------------------------------------------------------
  -- Echantillonnage coherent des registres de retour en fin de trame (PO-08).
  ----------------------------------------------------------------------------
  process(s_axi_aclk)
  begin
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn = '0' then
        reg_maxval <= (others => '0');
        reg_maxx   <= (others => '0');
        reg_maxy   <= (others => '0');
      elsif frame_tick = '1' then
        reg_maxval <= std_logic_vector(resize(max_val, 32));
        reg_maxx   <= std_logic_vector(resize(max_x, 32));
        reg_maxy   <= std_logic_vector(resize(max_y, 32));
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Canal d'ecriture AXI4-Lite.
  ----------------------------------------------------------------------------
  process(s_axi_aclk)
  begin
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn = '0' then
        awready_i <= '0'; wready_i <= '0'; bvalid_i <= '0';
        reg_thresh <= (others => '0');
        reg_mode   <= (others => '0');
        reg_src    <= (others => '0');
        reg_view   <= (others => '0');
      else
        -- capture de l'adresse
        if awready_i = '0' and s_axi_awvalid = '1' and s_axi_wvalid = '1' then
          awready_i <= '1';
          awaddr_q  <= s_axi_awaddr;
        else
          awready_i <= '0';
        end if;
        -- capture de la donnee et ecriture registre
        -- On decode sur l'adresse COURANTE (s_axi_awaddr, valide tant que
        -- awvalid='1') et non sur awaddr_q : ce dernier n'est mis a jour qu'au
        -- coup d'horloge suivant, il porterait donc l'adresse de la transaction
        -- PRECEDENTE (decalage d'un registre sur des ecritures consecutives).
        if wready_i = '0' and s_axi_awvalid = '1' and s_axi_wvalid = '1' then
          wready_i <= '1';
          case s_axi_awaddr(ADDR_W-1 downto 2) is
            when "011" => reg_thresh <= s_axi_wdata;   -- 0x0C
            when "100" => reg_mode   <= s_axi_wdata;   -- 0x10
            when "101" => reg_src    <= s_axi_wdata;   -- 0x14
            when "111" => reg_view   <= s_axi_wdata;   -- 0x1C (v2)
            when others => null;
          end case;
        else
          wready_i <= '0';
        end if;
        -- reponse d'ecriture
        if wready_i = '1' then
          bvalid_i <= '1';
        elsif s_axi_bready = '1' and bvalid_i = '1' then
          bvalid_i <= '0';
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Canal de lecture AXI4-Lite.
  ----------------------------------------------------------------------------
  process(s_axi_aclk)
  begin
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn = '0' then
        arready_i <= '0'; rvalid_i <= '0'; rdata_i <= (others => '0');
      else
        if arready_i = '0' and s_axi_arvalid = '1' then
          arready_i <= '1';
          case s_axi_araddr(ADDR_W-1 downto 2) is
            when "000" => rdata_i <= reg_maxval;   -- 0x00
            when "001" => rdata_i <= reg_maxx;      -- 0x04
            when "010" => rdata_i <= reg_maxy;      -- 0x08
            when "011" => rdata_i <= reg_thresh;    -- 0x0C
            when "100" => rdata_i <= reg_mode;      -- 0x10
            when "101" => rdata_i <= reg_src;       -- 0x14
            when "110" => rdata_i <= status_in;     -- 0x18 diagnostic (RO)
            when "111" => rdata_i <= reg_view;      -- 0x1C VIEW (v2)
            when others => rdata_i <= (others => '0');
          end case;
        else
          arready_i <= '0';
        end if;
        if arready_i = '1' then
          rvalid_i <= '1';
        elsif rvalid_i = '1' and s_axi_rready = '1' then
          rvalid_i <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
