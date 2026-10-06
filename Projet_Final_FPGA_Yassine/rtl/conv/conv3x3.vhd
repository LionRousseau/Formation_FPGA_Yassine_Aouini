--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : conv3x3.vhd
-- Description : Moteur de convolution 3x3 generique sur flux AXI4-Stream video
--               (PL-IP-004, PL-IP-005). Enveloppe window_gen (fenetre glissante,
--               bords a zero PO-05) puis realise :
--                 acc   = somme( KERNEL(i) * fenetre(i) )       (signe)
--                 res   = acc / 2**DIV_SH        (troncature vers zero)
--                 res   = |res|                  si DO_ABS
--                 tdata = borne de res a [0, 2**OUT_W - 1]
--
--               Parametrage :
--                 - gaussien  : KERNEL=C_KERNEL_GAUSS, DIV_SH=4, DO_ABS=false
--                 - laplacien : KERNEL=C_KERNEL_LAPL,  DIV_SH=0, DO_ABS=true (PO-06)
--
--               Gestion du back-pressure AXI4-Stream par gel global du pipeline
--               (global stall) : aucune donnee perdue ni dupliquee (TC-U-07).
--               Propagation de tuser (debut de trame) et tlast (fin de ligne)
--               alignes sur la sortie (ED-03).
--
--               v2 : sorties/entrees optionnelles (valeurs par defaut = v1.0) :
--                 - bypass   = '1' : la sortie est le pixel CENTRAL de la fenetre
--                   (noyau identite) au lieu du resultat du noyau. Meme latence,
--                   memes marqueurs : l'etage est court-circuite sans desaligner
--                   la chaine (demonstration avec / sans filtre).
--                 - m_center : pixel central registre, aligne sur m_tdata. C'est
--                   la valeur d'ENTREE de l'etage au pixel de sortie : elle permet
--                   de visualiser l'etage precedent sans ligne a retard.
--
--               v2 : VIDANGE DE FIN D'IMAGE. La fenetre glissante ne sort le
--                 resultat d'un pixel qu'apres IMG_W+3 avances : en v1.0, les
--                 IMG_W+3 derniers resultats d'une image restaient bloques
--                 jusqu'a l'arrivee de l'image SUIVANTE. Avec une source a trous
--                 entre images (DMA sequence, lance pendant la suppression
--                 verticale), l'affichage manquait la fin de l'image et restait
--                 decale d'environ 2 lignes. Desormais, apres le dernier pixel
--                 d'une image (compte a IMG_W*IMG_H depuis tuser), le moteur
--                 avance seul avec des BULLES (pixels invalides) tant que
--                 l'entree est vide, jusqu'a sortir tous les resultats. Les
--                 bulles ne produisent aucune sortie (validite suivie) et les
--                 voisins sous la derniere ligne sont deja forces a zero.
--                 La vidange s'arrete des le premier pixel de l'image suivante :
--                 aucune bulle n'est jamais inseree A L'INTERIEUR d'une image.
--                 Source continue (mire) : aucune bulle, comportement v1.0.
--
--               Latence entree->sortie : IMG_W + 3 avances
--                 = 1 ligne (line buffer) + 2 pixels (fenetre) + 1 (registre MAC).
--
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_pkg.all;

entity conv3x3 is
  generic (
    IN_W   : natural     := 8;
    OUT_W  : natural     := 8;
    KERNEL : kernel3x3_t := C_KERNEL_GAUSS;
    DIV_SH : natural     := 4;
    DO_ABS : boolean     := false;
    IMG_W  : natural     := C_IMG_WIDTH;
    IMG_H  : natural     := C_IMG_HEIGHT
  );
  port (
    clk       : in  std_logic;
    resetn    : in  std_logic;
    -- esclave AXI4-Stream (entree)
    s_tdata   : in  std_logic_vector(IN_W-1 downto 0);
    s_tvalid  : in  std_logic;
    s_tready  : out std_logic;
    s_tuser   : in  std_logic;                       -- debut de trame
    s_tlast   : in  std_logic;                       -- fin de ligne
    -- maitre AXI4-Stream (sortie)
    m_tdata   : out std_logic_vector(OUT_W-1 downto 0);
    m_tvalid  : out std_logic;
    m_tready  : in  std_logic;
    m_tuser   : out std_logic;
    m_tlast   : out std_logic;
    -- v2 (optionnels)
    bypass    : in  std_logic := '0';                -- '1' = noyau identite
    m_center  : out std_logic_vector(IN_W-1 downto 0) -- pixel central aligne
  );
end entity conv3x3;

architecture rtl of conv3x3 is
  signal en        : std_logic;
  signal s_ready_i : std_logic;

  -- sorties window_gen
  signal win     : window3x3_t;
  signal w_col   : unsigned(C_X_W-1 downto 0);
  signal w_row   : unsigned(C_Y_W-1 downto 0);
  signal w_valid : std_logic;
  signal w_sof   : std_logic;
  signal w_eol   : std_logic;

  -- registres de sortie (apres MAC)
  signal res_r   : unsigned(OUT_W-1 downto 0) := (others => '0');
  signal val_r   : std_logic := '0';
  signal sof_r   : std_logic := '0';
  signal eol_r   : std_logic := '0';
  signal ctr_r   : unsigned(IN_W-1 downto 0) := (others => '0');

  signal din_u   : unsigned(IN_W-1 downto 0);

  -- v2 : vidange de fin d'image
  constant NPIX    : natural := IMG_W * IMG_H;
  constant FLUSH_N : natural := IMG_W + 3;
  signal in_cnt    : natural range 0 to NPIX := 0;     -- pixels recus dans l'image
  signal flush_cnt : natural range 0 to FLUSH_N := 0;  -- avances restant a vider
  signal bub       : std_logic;                        -- avance a vide (bulle)
  signal adv       : std_logic;                        -- avance du pipeline
  signal sof_in    : std_logic;
begin

  din_u <= unsigned(s_tdata);

  ----------------------------------------------------------------------------
  -- Handshake AXI4-Stream : gel global.
  -- On accepte une entree quand l'aval est pret, ou quand on n'a pas de sortie
  -- valide a preserver. Le pipeline avance (en) a chaque entree acceptee.
  ----------------------------------------------------------------------------
  s_ready_i <= m_tready or (not val_r);
  s_tready  <= s_ready_i;
  en        <= s_tvalid and s_ready_i;

  -- v2 : bulle si vidange en cours, entree vide et aval disponible
  bub    <= '1' when (flush_cnt /= 0 and s_tvalid = '0' and s_ready_i = '1') else '0';
  adv    <= en or bub;
  sof_in <= s_tuser and s_tvalid;

  process(clk, resetn)
  begin
    if resetn = '0' then
      in_cnt    <= 0;
      flush_cnt <= 0;
    elsif rising_edge(clk) then
      if en = '1' then
        -- comptage des pixels de l'image (recale sur tuser)
        if s_tuser = '1' then
          in_cnt <= 1;
        elsif in_cnt < NPIX then
          in_cnt <= in_cnt + 1;
        end if;
      end if;
      if en = '1' and s_tuser = '0' and in_cnt = NPIX-1 then
        flush_cnt <= FLUSH_N;                  -- dernier pixel recu : vidange
      elsif en = '1' and s_tuser = '1' then
        flush_cnt <= 0;                        -- nouvelle image : jamais de bulle dedans
      elsif adv = '1' and flush_cnt /= 0 then
        flush_cnt <= flush_cnt - 1;            -- chaque avance (reelle ou bulle) compte
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Fenetre glissante.
  ----------------------------------------------------------------------------
  u_win : entity work.window_gen
    generic map (DATA_W => IN_W, IMG_W => IMG_W, IMG_H => IMG_H)
    port map (
      clk => clk, resetn => resetn, en => adv,
      din => din_u, din_sof => sof_in, din_valid => s_tvalid,
      win_o => win, col_o => w_col, row_o => w_row,
      valid_o => w_valid, sof_o => w_sof, eol_o => w_eol);

  ----------------------------------------------------------------------------
  -- Multiply-accumulate + division + valeur absolue + bornage, registre.
  ----------------------------------------------------------------------------
  process(clk, resetn)
    variable acc : integer;
    variable res : integer;
  begin
    if resetn = '0' then
      res_r <= (others => '0');
      val_r <= '0';
      sof_r <= '0';
      eol_r <= '0';
      ctr_r <= (others => '0');
    elsif rising_edge(clk) then
      if adv = '1' then
        -- avance : traitement d'un nouveau pixel (ou d'une bulle de vidange)
        acc := 0;
        for i in 0 to 8 loop
          acc := acc + KERNEL(i) * to_integer(win(i));
        end loop;
        res := acc / (2**DIV_SH);      -- troncature vers zero
        if DO_ABS then
          res := abs(res);
        end if;
        if bypass = '1' then
          res := to_integer(win(4));   -- noyau identite : pixel central
        end if;
        res := clamp_u(res, OUT_W);
        res_r <= to_unsigned(res, OUT_W);
        val_r <= w_valid;
        sof_r <= w_sof;
        eol_r <= w_eol;
        ctr_r <= resize(win(4), IN_W);
      elsif m_tready = '1' then
        -- pas de nouvelle entree mais l'aval a consomme : on desasserte tvalid
        -- (aucune duplication en cas de trou sur tvalid amont, TC-U-07)
        val_r <= '0';
      end if;
    end if;
  end process;

  m_tdata  <= std_logic_vector(res_r);
  m_tvalid <= val_r;
  m_tuser  <= sof_r;
  m_tlast  <= eol_r;
  m_center <= std_logic_vector(ctr_r);

end architecture rtl;
