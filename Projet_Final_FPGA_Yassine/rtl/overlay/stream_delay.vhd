--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : stream_delay.vhd
-- Description : Ligne a retard AXI4-Stream de DEPTH transferts (ED-02). Retarde
--               le flux video brut destine a l'overlay de la latence EXACTE de
--               la chaine de traitement, afin que le masque et le pixel brut
--               correspondant soient presentes ensemble a l'etage d'overlay.
--
--               Implementation : memoire circulaire (RAM) de (DEPTH-1) cases
--               suivie d'un registre de sortie draine. Contrairement a un grand
--               registre a decalage (qui, pour les grandes profondeurs, se mappe
--               en longue cascade de SRL au comportement non fiable), la RAM
--               s'infere en BRAM de facon deterministe et fidele a la simulation.
--               Comportement AXI4-Stream sans perte ni duplication meme en
--               presence de trous sur tvalid. tuser/tlast portes avec la donnee.
--               Latence totale = DEPTH transferts.
--
--               v2 : VIDANGE DE FIN D'IMAGE (generique NPIX > 0). Une ligne a
--               retard ne rend ses DEPTH derniers pixels qu'a l'arrivee de
--               pixels suivants : en fin d'image, la fin du flux brut restait
--               bloquee jusqu'a l'image suivante (meme defaut que conv3x3).
--               Apres le NPIX-ieme pixel d'une image, on avance avec des bulles
--               (cases invalides, tvalid=0) tant que l'entree est vide, jusqu'a
--               DEPTH avances ; arret des le premier pixel de l'image suivante.
--               NPIX = 0 : pas de vidange (comportement v1.0).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stream_delay is
  generic (
    DATA_W : natural := 24;
    DEPTH  : natural := 8;           -- latence en transferts (>= 1)
    NPIX   : natural := 0            -- v2 : pixels par image (0 = sans vidange)
  );
  port (
    clk      : in  std_logic;
    resetn   : in  std_logic;
    s_tdata  : in  std_logic_vector(DATA_W-1 downto 0);
    s_tvalid : in  std_logic;
    s_tready : out std_logic;
    s_tuser  : in  std_logic;
    s_tlast  : in  std_logic;
    m_tdata  : out std_logic_vector(DATA_W-1 downto 0);
    m_tvalid : out std_logic;
    m_tready : in  std_logic;
    m_tuser  : out std_logic;
    m_tlast  : out std_logic
  );
end entity stream_delay;

architecture rtl of stream_delay is
  constant W : natural := DATA_W + 3;          -- data + tuser + tlast + tvalid

  function pack(d : std_logic_vector; u, l, v : std_logic) return std_logic_vector is
  begin
    return d & u & l & v;
  end function;

  signal en      : std_logic;
  signal ready_i : std_logic;
  signal in_pk   : std_logic_vector(W-1 downto 0);

  -- registre de sortie draine
  signal out_data : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal out_user : std_logic := '0';
  signal out_last : std_logic := '0';
  signal out_val  : std_logic := '0';

  -- v2 : vidange de fin d'image
  signal in_cnt    : natural range 0 to NPIX := 0;
  signal flush_cnt : natural range 0 to DEPTH := 0;
  signal bub, adv  : std_logic;
begin
  in_pk    <= pack(s_tdata, s_tuser, s_tlast, s_tvalid);
  ready_i  <= m_tready or (not out_val);
  s_tready <= ready_i;
  en       <= s_tvalid and ready_i;
  bub      <= '1' when (NPIX > 0 and flush_cnt /= 0 and s_tvalid = '0' and ready_i = '1') else '0';
  adv      <= en or bub;

  gen_flush : if NPIX > 0 generate
    process(clk)
    begin
      if rising_edge(clk) then
        if resetn = '0' then
          in_cnt <= 0; flush_cnt <= 0;
        else
          if en = '1' then
            if s_tuser = '1' then in_cnt <= 1;
            elsif in_cnt < NPIX then in_cnt <= in_cnt + 1; end if;
          end if;
          if en = '1' and s_tuser = '0' and in_cnt = NPIX-1 then
            flush_cnt <= DEPTH;                -- dernier pixel de l'image
          elsif en = '1' and s_tuser = '1' then
            flush_cnt <= 0;                    -- nouvelle image : arret
          elsif adv = '1' and flush_cnt /= 0 then
            flush_cnt <= flush_cnt - 1;
          end if;
        end if;
      end if;
    end process;
  end generate;

  ----------------------------------------------------------------------------
  -- DEPTH = 1 : pas de memoire, seulement le registre de sortie.
  ----------------------------------------------------------------------------
  gen_one : if DEPTH <= 1 generate
    process(clk)
    begin
      if rising_edge(clk) then
        if resetn = '0' then
          out_data <= (others => '0'); out_user <= '0'; out_last <= '0'; out_val <= '0';
        elsif adv = '1' then
          out_data <= s_tdata; out_user <= s_tuser; out_last <= s_tlast; out_val <= s_tvalid;
        elsif m_tready = '1' then
          out_val <= '0';
        end if;
      end if;
    end process;
  end generate;

  ----------------------------------------------------------------------------
  -- DEPTH >= 2 : memoire circulaire de N = DEPTH-1 cases + registre de sortie.
  -- Lecture AVANT ecriture sur la meme case : ram(widx) fournit la valeur ecrite
  -- N cycles-en plus tot ; le registre de sortie ajoute 1 -> latence = DEPTH.
  ----------------------------------------------------------------------------
  gen_ram : if DEPTH > 1 generate
    constant N : natural := DEPTH - 1;
    type ram_t is array (0 to N-1) of std_logic_vector(W-1 downto 0);
    signal ram  : ram_t := (others => (others => '0'));
    signal widx : integer range 0 to N-1 := 0;
  begin
    process(clk)
    begin
      if rising_edge(clk) then
        if resetn = '0' then
          widx <= 0;
          out_data <= (others => '0'); out_user <= '0'; out_last <= '0'; out_val <= '0';
        elsif adv = '1' then
          -- lecture avant ecriture (la RHS utilise l'ancienne valeur de ram(widx))
          out_data <= ram(widx)(W-1 downto 3);
          out_user <= ram(widx)(2);
          out_last <= ram(widx)(1);
          out_val  <= ram(widx)(0);
          ram(widx) <= in_pk;
          if widx = N-1 then widx <= 0; else widx <= widx + 1; end if;
        elsif m_tready = '1' then
          out_val <= '0';
        end if;
      end if;
    end process;
  end generate;

  m_tdata  <= out_data;
  m_tuser  <= out_user;
  m_tlast  <= out_last;
  m_tvalid <= out_val;
end architecture rtl;
