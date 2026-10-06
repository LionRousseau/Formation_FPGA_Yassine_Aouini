--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : overlay.vhd
-- Description : Fusion du flux brut retarde et du masque binaire (PL-DISP-001).
--               Jointure AXI4-Stream de deux flux alignes :
--                 a = masque binaire (sortie chaine de traitement)
--                 b = pixel brut RGB retarde de la meme latence (ED-02)
--               Sortie RGB :
--                 mode A (naturel)  : pixel brut inchange
--                 mode B (overlay)  : si masque = 1, couleur forte ovl_color,
--                                     sinon pixel brut (PL-DISP-003)
--
--               v2 : selecteur de vue (registre VIEW) pour montrer chaque etage.
--                 view 0 : image brute (mode A) ou overlay (mode B), comme en v1.0
--                 view 1 : luminance (calculee sur le pixel brut retarde, aligne)
--                 view 2 : sortie du filtre gaussien (bande laterale)
--                 view 3 : reponse du laplacien, bornee a 255 (bande laterale)
--                 view 4 : masque binaire (blanc = point detecte), sans overlay
--               En vues 1 a 3, le mode B superpose aussi les points en couleur,
--               ce qui permet de voir l'overlay sur l'image de chaque etage.
--               Toutes les vues sont alignees par construction : les bandes
--               laterales voyagent avec le masque (flux a), la luminance est
--               recalculee sur le pixel brut du meme rang (flux b).
--
--               Jointure sans perte : une sortie est produite uniquement quand
--               les deux entrees sont valides ; chaque entree n'est consommee
--               que lorsque la sortie est acceptee et l'autre entree valide.
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity overlay is
  port (
    clk        : in  std_logic;
    resetn     : in  std_logic;
    mode       : in  std_logic;                           -- '0'=A, '1'=B
    ovl_color  : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    -- flux a : masque
    a_tdata    : in  std_logic_vector(0 downto 0);
    a_tvalid   : in  std_logic;
    a_tready   : out std_logic;
    a_tuser    : in  std_logic;
    a_tlast    : in  std_logic;
    -- flux b : pixel brut retarde
    b_tdata    : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    b_tvalid   : in  std_logic;
    b_tready   : out std_logic;
    b_tuser    : in  std_logic;
    b_tlast    : in  std_logic;
    -- sortie
    m_tdata    : out std_logic_vector(3*C_COMP_W-1 downto 0);
    m_tvalid   : out std_logic;
    m_tready   : in  std_logic;
    m_tuser    : out std_logic;
    m_tlast    : out std_logic;
    -- v2 (optionnels, valeurs par defaut = comportement v1.0)
    view       : in  std_logic_vector(2 downto 0) := "000";
    a_side     : in  std_logic_vector(15 downto 0) := (others => '0') -- [15:8] gaussien, [7:0] reponse
  );
end entity overlay;

architecture rtl of overlay is
  signal both_valid : std_logic;
  signal luma       : unsigned(C_LUMA_W-1 downto 0);
  signal base       : std_logic_vector(3*C_COMP_W-1 downto 0);
  signal hit        : std_logic;

  function gray(v : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    return v & v & v;
  end function;
begin
  both_valid <= a_tvalid and b_tvalid;

  m_tvalid <= both_valid;
  a_tready <= m_tready and b_tvalid;
  b_tready <= m_tready and a_tvalid;

  -- luminance du pixel brut (meme rang que le masque grace a la jointure)
  luma <= rgb_to_luma_f(unsigned(b_tdata(3*C_COMP_W-1 downto 2*C_COMP_W)),
                        unsigned(b_tdata(2*C_COMP_W-1 downto C_COMP_W)),
                        unsigned(b_tdata(C_COMP_W-1 downto 0)));

  -- image de fond selon la vue
  with view select base <=
    gray(std_logic_vector(luma))    when "001",
    gray(a_side(15 downto 8))       when "010",
    gray(a_side(7 downto 0))        when "011",
    (others => a_tdata(0))          when "100",   -- blanc / noir
    b_tdata                         when others;

  -- surlignage : mode B et point detecte, sauf en vue masque
  hit <= '1' when (mode = '1' and a_tdata(0) = '1' and view /= "100") else '0';

  -- selection du pixel de sortie
  m_tdata  <= ovl_color when hit = '1' else base;
  m_tuser  <= b_tuser;
  m_tlast  <= b_tlast;
end architecture rtl;
