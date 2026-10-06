-- =============================================================================
-- AXI4-Stream Monitor -- format ImageJ, capture multi-images
-- =============================================================================
-- Observe le flux AXI4-S en sortie de l'UUT et ecrit chaque image capturee
-- dans un fichier .txt numerote :
--   G_FILE_BASENAME & "_0.txt", "_1.txt", "_2.txt" ...
--
-- Chaque fichier contient une image au format ImageJ :
--   - Valeurs decimales (entiers non signes)
--   - Separees par des tabulations (ASCII 9)
--   - Une ligne de l'image par ligne du fichier
--
-- Sequencement :
--   1. Attente fin de reset
--   2. Pour chaque image (de 0 a G_NB_IMAGES-1) :
--        a. Ouverture du fichier numerote
--        b. Capture de G_IMG_HEIGHT lignes de G_IMG_WIDTH pixels
--        c. Fermeture du fichier
--   3. Levee de done_o apres la derniere image
--
-- Fin de ligne : par comptage (G_IMG_WIDTH) ou via TLAST (G_IMG_WIDTH = 0).
-- Fin d'image  : par comptage (G_IMG_HEIGHT) ou infini (G_IMG_HEIGHT = 0).
-- Fin globale  : apres G_NB_IMAGES images, ou sur timeout si G_NB_IMAGES = 0.
--
-- Synchronisation sur le debut de trame (G_SYNC_ON_SOF = true) :
--   Sans elle, la capture demarre au premier TVALID venu et decoupe par simple
--   comptage : le cadrage est arbitraire, et tout pixel perdu en amont decale
--   definitivement le fichier produit sans qu'aucune trace n'en subsiste.
--   Avec elle, le monitor jette les pixels jusqu'au premier s_tuser = '1', puis
--   verifie a chaque trame que le SOF retombe bien sur le pixel 0. Tout ecart
--   est rapporte en clair, avec sa position : c'est cette mesure qui chiffre le
--   nombre de pixels reellement perdus.
--
-- Generiques :
--   G_FILE_BASENAME : prefixe commun des fichiers (ex: "stream_out")
--                     produit stream_out_0.txt, stream_out_1.txt ...
--   G_DATA_WIDTH    : largeur de TDATA en bits (8, 16 ou 32)
--   G_IMG_WIDTH     : pixels par ligne (0 = detection via TLAST)
--   G_IMG_HEIGHT    : lignes par image  (0 = capture infinie par image)
--   G_NB_IMAGES     : nombre d'images a capturer (0 = infini)
--   G_TIMEOUT_CY    : cycles sans transaction avant fermeture (0 = desactive)
--   G_SYNC_ON_SOF   : si TRUE, cadrer la capture sur s_tuser (SOF) et signaler
--                     tout desalignement ; si FALSE, ancien comportement
-- =============================================================================

library IEEE;
use IEEE.Std_logic_1164.all;
use IEEE.Numeric_Std.all;

library STD;
use STD.textio.all;

entity axi4s_monitor is
  generic (
    G_FILE_BASENAME : string  := "stream_out";
    G_DATA_WIDTH    : integer := 16;
    G_IMG_WIDTH     : integer := 1280;
    G_IMG_HEIGHT    : integer := 100;
    G_NB_IMAGES     : integer := 1;
    G_TIMEOUT_CY    : integer := 10000;
    G_SYNC_ON_SOF   : boolean := false
  );
  port (
    clk_i    : in  std_logic;
    rst_i    : in  std_logic;    -- reset actif haut

    s_tvalid : in  std_logic;
    s_tdata  : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
    s_tlast  : in  std_logic;
    s_tuser  : in  std_logic := '0';   -- SOF : '1' sur le premier pixel de trame
    s_tready : out std_logic;

    done_o      : out std_logic;  -- '1' apres capture de toutes les images
    img_cnt_o   : out integer;    -- indice de l'image en cours
    line_cnt_o  : out integer;    -- lignes capturees dans l'image courante
    pixel_cnt_o : out integer     -- pixels totaux captures
  );
end entity axi4s_monitor;

architecture rtl of axi4s_monitor is

  signal s_done      : std_logic := '0';
  signal s_img_cnt   : integer   := 0;
  signal s_line_cnt  : integer   := 0;
  signal s_pixel_cnt : integer   := 0;

  -- Copie interne de s_tready : un port de mode "out" n'est pas lisible en
  -- VHDL-93, or la capture doit tester le handshake complet et non TVALID seul.
  signal s_tready_int : std_logic := '1';

begin

  s_tready_int <= '1';
  s_tready     <= s_tready_int;
  done_o      <= s_done;
  img_cnt_o   <= s_img_cnt;
  line_cnt_o  <= s_line_cnt;
  pixel_cnt_o <= s_pixel_cnt;

  -- ---------------------------------------------------------------------------
  -- Processus principal
  -- ---------------------------------------------------------------------------
  p_monitor : process

    file     f_out         : text;
    variable v_line        : line;
    variable v_timeout     : integer;
    variable v_col         : integer;
    variable v_lines_done  : integer;
    variable v_img_idx     : integer;
    variable v_end_of_line : boolean;
    variable v_pix_val     : integer;

    -- Cadrage sur le SOF (G_SYNC_ON_SOF)
    variable v_synced      : boolean := false;  -- premier SOF rencontre
    variable v_dropped     : integer := 0;      -- pixels jetes avant cadrage
    variable v_misalign    : integer := 0;      -- nombre de SOF hors position

    -- Construit le nom de fichier : G_FILE_BASENAME & "_" & img_idx & ".txt"
    -- VHDL-93 ne permet pas de convertir integer->string directement en
    -- concatenation ; on construit l'indice chiffre par chiffre (max 9999).
    function build_filename(basename : string; idx : integer) return string is
      variable n    : integer := idx;
      variable d3   : integer;
      variable d2   : integer;
      variable d1   : integer;
      variable d0   : integer;
      variable c3   : character;
      variable c2   : character;
      variable c1   : character;
      variable c0   : character;
      constant DIGITS : string := "0123456789";
    begin
      d3 := n / 1000;          n := n mod 1000;
      d2 := n / 100;           n := n mod 100;
      d1 := n / 10;
      d0 := n mod 10;
      c3 := DIGITS(d3 + 1);
      c2 := DIGITS(d2 + 1);
      c1 := DIGITS(d1 + 1);
      c0 := DIGITS(d0 + 1);
      -- Supprimer les zeros de tete (garder au moins un chiffre)
      if d3 > 0 then
        return basename & "_" & c3 & c2 & c1 & c0 & ".txt";
      elsif d2 > 0 then
        return basename & "_" & c2 & c1 & c0 & ".txt";
      elsif d1 > 0 then
        return basename & "_" & c1 & c0 & ".txt";
      else
        return basename & "_" & c0 & ".txt";
      end if;
    end function;

  begin

    s_done      <= '0';
    s_img_cnt   <= 0;
    s_line_cnt  <= 0;
    s_pixel_cnt <= 0;

    -- Attente fin de reset (actif haut)
    wait until rising_edge(clk_i) and rst_i = '0';

    v_img_idx := 0;

    -- =========================================================================
    -- Boucle sur les images
    -- =========================================================================
    image_loop : loop

      -- Condition de sortie : nombre d'images atteint (0 = infini)
      exit image_loop when (G_NB_IMAGES > 0) and (v_img_idx >= G_NB_IMAGES);

      -- Ouverture du fichier de l'image courante
      file_open(f_out, build_filename(G_FILE_BASENAME, v_img_idx), WRITE_MODE);

      s_img_cnt  <= v_img_idx;
      s_line_cnt <= 0;

      v_col        := 0;
      v_lines_done := 0;
      v_timeout    := 0;

      -- -----------------------------------------------------------------------
      -- Boucle de capture d'une image
      -- -----------------------------------------------------------------------
      capture_loop : loop

        wait until rising_edge(clk_i);

        -- Timeout
        if G_TIMEOUT_CY > 0 then
          if s_tvalid = '0' then
            v_timeout := v_timeout + 1;
            if v_timeout >= G_TIMEOUT_CY then
              if v_col > 0 then
                writeline(f_out, v_line);
              end if;
              exit capture_loop;
            end if;
          else
            v_timeout := 0;
          end if;
        end if;

        -- Capture sur handshake complet (TVALID et TREADY)
        if s_tvalid = '1' and s_tready_int = '1' then

          v_timeout := 0;

          -- -------------------------------------------------------------------
          -- Cadrage initial : jeter tout ce qui precede le premier SOF, sans
          -- quoi le decoupage en lignes demarre a une position arbitraire.
          -- -------------------------------------------------------------------
          if G_SYNC_ON_SOF and not v_synced then
            if s_tuser = '1' then
              v_synced := true;
              report "[MON] Cadrage sur le premier SOF apres "
                     & integer'image(v_dropped) & " pixel(s) jetes."
                     severity note;
            else
              v_dropped := v_dropped + 1;
              next capture_loop;
            end if;

          -- -------------------------------------------------------------------
          -- Controle d'alignement : une fois cadre, chaque SOF doit retomber
          -- sur le pixel 0 de la trame. Tout ecart chiffre les pixels perdus
          -- ou surnumeraires introduits en amont.
          -- -------------------------------------------------------------------
          elsif G_SYNC_ON_SOF and s_tuser = '1'
                and not (v_col = 0 and v_lines_done = 0) then
            v_misalign := v_misalign + 1;
            report "[MON] DESALIGNEMENT image " & integer'image(v_img_idx)
                   & " : SOF recu ligne " & integer'image(v_lines_done)
                   & " colonne " & integer'image(v_col)
                   & ", soit " & integer'image(v_lines_done * G_IMG_WIDTH + v_col)
                   & " pixel(s) d'ecart sur la trame attendue."
                   severity warning;
          end if;

          v_pix_val := to_integer(unsigned(s_tdata));

          -- Separateur tabulation (sauf premier pixel de la ligne)
          if v_col > 0 then
            write(v_line, character'val(9));
          end if;

          write(v_line, v_pix_val);
          v_col := v_col + 1;

          s_pixel_cnt <= s_pixel_cnt + 1;

          -- Detection fin de ligne
          if G_IMG_WIDTH > 0 then
            v_end_of_line := (v_col >= G_IMG_WIDTH);
          else
            v_end_of_line := (s_tlast = '1');
          end if;

          if v_end_of_line then
            writeline(f_out, v_line);
            v_lines_done := v_lines_done + 1;
            s_line_cnt   <= v_lines_done;
            v_col        := 0;

            -- Fin de l'image courante
            if G_IMG_HEIGHT > 0 and v_lines_done >= G_IMG_HEIGHT then
              exit capture_loop;
            end if;
          end if;

        end if;

      end loop capture_loop;

      -- Fermeture du fichier de l'image courante
      file_close(f_out);

      v_img_idx := v_img_idx + 1;

    end loop image_loop;

    s_done <= '1';

    if G_SYNC_ON_SOF then
      if v_misalign = 0 then
        report "[MON] Capture terminee : " & integer'image(v_img_idx)
               & " image(s), aucun desalignement de SOF."
               severity note;
      else
        report "[MON] Capture terminee : " & integer'image(v_img_idx)
               & " image(s), " & integer'image(v_misalign)
               & " desalignement(s) de SOF."
               severity warning;
      end if;
    end if;

    wait;
  end process p_monitor;

end architecture rtl;
