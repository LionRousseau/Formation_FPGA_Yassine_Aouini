-- MUTANT DE TEST (contre-epreuve C2, anomalie FA-04) : sequenceur DMA cale sur
-- src_sel au lieu de mux_active (ligne 262). NE PAS SYNTHETISER : sert uniquement a
-- verifier que tb_switch_sys detecte l interblocage (run_preuves.sh).
--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : video_subsystem_step2.vhd
-- Description : Sous-systeme video, destine a etre reference comme module dans le
--               block design (a cote du PS7 et, a l'etape 3, de l'IP DMA). Il
--               regroupe, dans un unique domaine d'horloge (clk = horloge pixel
--               25 MHz) :
--
--                 s0 (DMA) --\
--                             source_mux --> processing_chain --> vga_stream_out
--                 mire (TPG) -/                    |
--                                          axi4lite_regs (esclave AXI4-Lite,
--                                          pilote par le PS7)
--
--               NOTE : l'entite garde le nom video_subsystem_step2 (le block
--               design le reference sous ce nom), mais l'architecture porte
--               desormais la fonctionnalite complete de l'etape 3 : l'entree s0
--               du multiplexeur (source memoire, PL-IP-000) est EXPOSEE en ports
--               externes ; c'est le flux AXI4-Stream de l'IP DMA (STR_video_out)
--               qui l'alimente dans le block design. La mire (TPG) reste interne
--               sur s1. Le PS choisit la source par le registre SRC_SEL :
--                 SRC_SEL = 0 -> image memoire (DMA)   [PL-IP-000]
--                 SRC_SEL = 1 -> mire (TPG)            [PL-IP-001]
--
--               Le banc de registres, la chaine et l'etage VGA partagent clk et
--               resetn (chemin video mono-horloge, sans franchissement de domaine).
--               L'esclave AXI4-Lite est cadence par clk : dans le block design,
--               relier s_axi_aclk / M_AXI_GP0_ACLK / ap_clk du DMA a cette meme
--               horloge pixel.
--
--               Couleur d'overlay : vert (mode B du SRS).
--
--               v2 (demonstration des etages, hors SRS) : registre VIEW en 0x1C.
--                 bits 2:0 = vue affichee (0 normale, 1 luminance, 2 gaussien,
--                            3 reponse laplacien, 4 masque binaire)
--                 bit 3    = filtre gaussien court-circuite
--               Ports de l'entite inchanges : aucune retouche du block design.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;
use work.vga_pkg.all;

entity video_subsystem_step2 is
  generic (
    IMG_W : natural := C_IMG_WIDTH;
    IMG_H : natural := C_IMG_HEIGHT
  );
  port (
    -- horloge pixel (25 MHz) et reset du chemin video
    clk           : in  std_logic;
    resetn        : in  std_logic;
    -- horloge / reset de l'esclave AXI4-Lite. Dans le block design, relier
    -- s_axi_aclk a la MEME horloge pixel que clk, et s_axi_aresetn au meme reset :
    -- le chemin est mono-horloge (pas de franchissement de domaine). Ces ports
    -- distincts existent pour que l'integrateur d'IP associe sans ambiguite
    -- l'interface AXI a son horloge.
    s_axi_aclk    : in  std_logic;
    s_axi_aresetn : in  std_logic;
    -- esclave AXI4-Lite (banc de registres SCH-05)
    s_axi_awaddr  : in  std_logic_vector(4 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(4 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    -- entree source memoire (flux AXI4-Stream de l'IP DMA), sur s0.
    -- A l'etape 3, relier STR_video_out du DMA a ces ports dans le block design.
    s0_tdata      : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    s0_tvalid     : in  std_logic;
    s0_tready     : out std_logic;
    s0_tuser      : in  std_logic;
    s0_tlast      : in  std_logic;
    -- controle de la lecture DMA une image a la fois (cf. conseil formateur) :
    -- s0_start pilote ap_start de l'IP DMA, s0_idle lit son ap_idle. La lecture
    -- d'une trame est lancee pendant la suppression verticale et n'est relancee
    -- qu'une fois la precedente terminee ; sur la mire, aucune lecture.
    -- Relier dans le block design : s0_start -> DMA/ap_start, DMA/ap_idle -> s0_idle.
    s0_start      : out std_logic;
    s0_idle       : in  std_logic := '1';
    -- sortie Pmod VGA
    vga_r         : out std_logic_vector(VGA_COMP_W-1 downto 0);
    vga_g         : out std_logic_vector(VGA_COMP_W-1 downto 0);
    vga_b         : out std_logic_vector(VGA_COMP_W-1 downto 0);
    vga_hsync     : out std_logic;
    vga_vsync     : out std_logic
  );
end entity video_subsystem_step2;

architecture rtl of video_subsystem_step2 is

  -- couleur de surlignage des points detectes (vert, mode B)
  constant OVL_GREEN : std_logic_vector(3*C_COMP_W-1 downto 0) := x"00FF00";

  -- flux mire (TPG), sur s1
  signal tpg_tdata  : std_logic_vector(3*C_COMP_W-1 downto 0);
  signal tpg_tvalid, tpg_tready, tpg_tuser, tpg_tlast : std_logic;

  -- flux en sortie du multiplexeur de source
  signal mux_tdata  : std_logic_vector(3*C_COMP_W-1 downto 0);
  signal mux_tvalid, mux_tready, mux_tuser, mux_tlast : std_logic;

  -- flux d'affichage en sortie de chaine
  signal ch_tdata   : std_logic_vector(3*C_COMP_W-1 downto 0);
  signal ch_tvalid, ch_tready, ch_tuser, ch_tlast : std_logic;

  -- controle et retour (banc de registres <-> materiel)
  signal threshold  : unsigned(C_RESP_W-1 downto 0);
  signal mode_bit   : std_logic;
  signal src_sel    : std_logic;
  signal max_val    : unsigned(C_RESP_W-1 downto 0);
  signal max_x      : unsigned(C_X_W-1 downto 0);
  signal max_y      : unsigned(C_Y_W-1 downto 0);
  signal frame_tick : std_logic;
  -- v2 : demonstration des etages
  signal view_sel     : std_logic_vector(2 downto 0);
  signal gauss_bypass : std_logic;

  -- Observabilite (diagnostic), lisible dans le registre 0x18.
  signal sig_locked, sig_active : std_logic;
  signal st_seen_locked, st_seen_tvalid, st_seen_tuser : std_logic := '0';
  signal st_seen_live, st_seen_nonblack                : std_logic := '0';
  signal status_word : std_logic_vector(31 downto 0);

  -- Re-verrouillage de l'affichage lors d'une bascule de source (PL-IP-003).
  -- On surveille la source REELLEMENT diffusee par le multiplexeur (active_o),
  -- et non SRC_SEL, car le mux ne bascule qu'a la frontiere de trame : ainsi le
  -- re-verrouillage se declenche pile quand la nouvelle source devient active,
  -- et l'etage VGA se cale sur SON prochain debut de trame.
  signal mux_active   : std_logic;
  signal mux_active_q : std_logic := '0';
  signal resync_i     : std_logic;

  -- Sequenceur de lecture DMA une image a la fois, cale sur la trame (conseil
  -- formateur). vblank_i = suppression verticale de l'affichage.
  signal vblank_i   : std_logic;
  type dma_st_t is (D_WAIT, D_LAUNCH, D_RUN);
  signal dma_st     : dma_st_t := D_WAIT;
  signal s0_start_r : std_logic := '0';

begin

  ----------------------------------------------------------------------------
  -- Source : generateur de mire (PL-IP-001), sur s1
  ----------------------------------------------------------------------------
  u_tpg : entity work.tpg
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn,
      m_tdata => tpg_tdata, m_tvalid => tpg_tvalid, m_tready => tpg_tready,
      m_tuser => tpg_tuser, m_tlast => tpg_tlast);

  ----------------------------------------------------------------------------
  -- Multiplexeur de source (PL-IP-002/003)
  --   s0 = DMA memoire (externe, PL-IP-000)   -> SRC_SEL = 0
  --   s1 = mire interne (PL-IP-001)           -> SRC_SEL = 1
  ----------------------------------------------------------------------------
  u_srcmux : entity work.source_mux
    port map (
      clk => clk, resetn => resetn, sel => src_sel,
      -- s0 : flux du DMA memoire
      s0_tdata => s0_tdata, s0_tvalid => s0_tvalid, s0_tready => s0_tready,
      s0_tuser => s0_tuser, s0_tlast => s0_tlast,
      -- s1 : mire interne
      s1_tdata => tpg_tdata, s1_tvalid => tpg_tvalid, s1_tready => tpg_tready,
      s1_tuser => tpg_tuser, s1_tlast => tpg_tlast,
      -- sortie
      m_tdata => mux_tdata, m_tvalid => mux_tvalid, m_tready => mux_tready,
      m_tuser => mux_tuser, m_tlast => mux_tlast,
      active_o => mux_active);

  ----------------------------------------------------------------------------
  -- Impulsion de re-verrouillage : un coup d'horloge quand la source diffusee
  -- par le multiplexeur change (front sur active_o).
  ----------------------------------------------------------------------------
  process(clk, resetn)
  begin
    if resetn = '0' then
      mux_active_q <= '0';
    elsif rising_edge(clk) then
      mux_active_q <= mux_active;
    end if;
  end process;
  resync_i <= mux_active xor mux_active_q;

  ----------------------------------------------------------------------------
  -- Chaine de traitement (coeur du projet)
  ----------------------------------------------------------------------------
  u_chain : entity work.processing_chain
    generic map (IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn,
      threshold => threshold, mode => mode_bit, ovl_color => OVL_GREEN,
      s_tdata => mux_tdata, s_tvalid => mux_tvalid, s_tready => mux_tready,
      s_tuser => mux_tuser, s_tlast => mux_tlast,
      m_tdata => ch_tdata, m_tvalid => ch_tvalid, m_tready => ch_tready,
      m_tuser => ch_tuser, m_tlast => ch_tlast,
      max_val => max_val, max_x => max_x, max_y => max_y,
      frame_tick => frame_tick,
      view => view_sel, gauss_bypass => gauss_bypass);

  ----------------------------------------------------------------------------
  -- Etage de sortie VGA (PL-DISP-002), genlock sur le flux
  ----------------------------------------------------------------------------
  u_vga : entity work.vga_stream_out
    port map (
      clk => clk, resetn => resetn,
      resync => resync_i,
      s_tdata => ch_tdata, s_tvalid => ch_tvalid, s_tready => ch_tready,
      s_tuser => ch_tuser, s_tlast => ch_tlast,
      vga_r => vga_r, vga_g => vga_g, vga_b => vga_b,
      vga_hsync => vga_hsync, vga_vsync => vga_vsync,
      vblank_o => vblank_i,
      locked_o => sig_locked, active_o => sig_active, x_o => open, y_o => open);

  ----------------------------------------------------------------------------
  -- Sequenceur de lecture DMA (conseil formateur) : lance la lecture d'UNE image
  -- entiere pendant la suppression verticale, et ne relance qu'une fois la trame
  -- precedente FINIE (s0_idle). Sur la mire (src_sel=1), aucune lecture : le DMA
  -- reste au repos (mux_active=1). Protocole ap_ctrl_hs : on leve ap_start (s0_start), le coeur
  -- demarre (ap_idle tombe), on relache ; on attend la fin (ap_idle remonte).
  --   D_WAIT  : au repos ; en memoire, pendant le blanking et coeur au repos,
  --             on lance. (Le DMA finit sa trame en fin de zone active, soit au
  --             debut du blanking suivant : on relance alors immediatement dans
  --             ce meme blanking, d'ou UNE image par trame, sans saut. Pas de
  --             double-lancement : une fois lance, le coeur reste occupe toute la
  --             trame, donc s0_idle=0 jusqu'au blanking d'apres.)
  --   D_LAUNCH: ap_start haut jusqu'a ce que le coeur ait demarre (idle=0).
  --   D_RUN   : lecture en cours ; on attend la fin (idle=1), puis retour D_WAIT.
  ----------------------------------------------------------------------------
  process(clk, resetn)
  begin
    if resetn = '0' then
      dma_st <= D_WAIT;
      s0_start_r <= '0';
    elsif rising_edge(clk) then
      case dma_st is
        when D_WAIT =>
          s0_start_r <= '0';
          -- On se cale sur la source REELLEMENT affichee (mux_active), et non sur
          -- src_sel : quand le PS demande la mire, le mux ne bascule qu'a la
          -- frontiere de trame et a besoin d'un dernier SOF du DMA. Garder le DMA
          -- actif tant que mux_active=0 evite l'interblocage (mux fige, ecran noir).
          if src_sel = '0' and vblank_i = '1' and s0_idle = '1' then
            s0_start_r <= '1';
            dma_st <= D_LAUNCH;
          end if;
        when D_LAUNCH =>
          s0_start_r <= '1';
          if s0_idle = '0' then       -- le coeur a pris en compte le demarrage
            s0_start_r <= '0';
            dma_st <= D_RUN;
          end if;
        when D_RUN =>
          s0_start_r <= '0';
          if s0_idle = '1' then       -- lecture de la trame terminee
            dma_st <= D_WAIT;         -- relance possible des ce blanking
          end if;
      end case;
    end if;
  end process;

  s0_start <= s0_start_r;

  ----------------------------------------------------------------------------
  -- Observabilite : latch d'evenements de l'etage VGA pour diagnostic (0x18).
  --   bit0 = verrouille (live)          bit1 = a ete verrouille
  --   bit2 = chaine a produit tvalid    bit3 = chaine a produit un debut de trame
  --   bit4 = pixel vivant sorti (locked+active+tvalid)
  --   bit5 = pixel vivant NON NOIR sorti
  ----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if resetn = '0' then
        st_seen_locked  <= '0'; st_seen_tvalid <= '0'; st_seen_tuser <= '0';
        st_seen_live    <= '0'; st_seen_nonblack <= '0';
      else
        if ch_tvalid = '1' then st_seen_tvalid <= '1'; end if;
        if ch_tvalid = '1' and ch_tuser = '1' then st_seen_tuser <= '1'; end if;
        if sig_locked = '1' then st_seen_locked <= '1'; end if;
        if sig_locked = '1' and sig_active = '1' and ch_tvalid = '1' then
          st_seen_live <= '1';
          if ch_tdata /= (ch_tdata'range => '0') then st_seen_nonblack <= '1'; end if;
        end if;
      end if;
    end if;
  end process;

  status_word <= (0 => sig_locked, 1 => st_seen_locked, 2 => st_seen_tvalid,
                  3 => st_seen_tuser, 4 => st_seen_live, 5 => st_seen_nonblack,
                  others => '0');

  ----------------------------------------------------------------------------
  -- Banc de registres AXI4-Lite (SCH-05), cadence par l'horloge pixel
  ----------------------------------------------------------------------------
  u_regs : entity work.axi4lite_regs
    generic map (ADDR_W => 5)
    port map (
      s_axi_aclk => s_axi_aclk, s_axi_aresetn => s_axi_aresetn,
      s_axi_awaddr => s_axi_awaddr, s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready, s_axi_wdata => s_axi_wdata,
      s_axi_wstrb => s_axi_wstrb, s_axi_wvalid => s_axi_wvalid,
      s_axi_wready => s_axi_wready, s_axi_bresp => s_axi_bresp,
      s_axi_bvalid => s_axi_bvalid, s_axi_bready => s_axi_bready,
      s_axi_araddr => s_axi_araddr, s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready, s_axi_rdata => s_axi_rdata,
      s_axi_rresp => s_axi_rresp, s_axi_rvalid => s_axi_rvalid,
      s_axi_rready => s_axi_rready,
      max_val => max_val, max_x => max_x, max_y => max_y,
      frame_tick => frame_tick, status_in => status_word,
      threshold => threshold, mode => mode_bit, src_sel => src_sel,
      view => view_sel, gauss_bypass => gauss_bypass);

end architecture rtl;
