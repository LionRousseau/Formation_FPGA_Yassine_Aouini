-- =============================================================================
-- AXI4-Stream Driver - format ImageJ
-- =============================================================================
-- Lit un fichier .txt au format ImageJ :
--   - Valeurs décimales (entiers 16 bits non signés)
--   - Séparées par des tabulations (\t, ASCII 9)
--   - Une ligne de l'image par ligne du fichier
--   - Pas de header, pas de TLAST explicite dans le fichier
--
-- TLAST est généré automatiquement :
--   - '1' sur le dernier pixel de chaque ligne (fin de \n)
--     si G_TLAST_END_OF_LINE = true (défaut)
--
-- Génériques :
--   G_FILE_PATH         : chemin vers le fichier ImageJ
--   G_DATA_WIDTH        : largeur de TDATA en bits (8, 16 ou 32)
--   G_INIT_DELAY        : cycles d'attente après reset avant la 1ère transaction
--   G_TLAST_END_OF_LINE : si TRUE, TLAST='1' sur le dernier pixel de chaque ligne
--   G_LOOP_COUNT        : nombre de fois que le fichier est rejoué (0 = infini)
-- =============================================================================

library IEEE;
use IEEE.Std_logic_1164.all;
use IEEE.Numeric_Std.all;

library STD;
use STD.textio.all;

entity axi4s_driver is
  generic (
    G_FILE_PATH         : string  := "stream_in.txt";
    G_DATA_WIDTH        : integer := 16;
    G_INIT_DELAY        : integer := 0;
    G_TLAST_END_OF_LINE : boolean := true;
    G_LOOP_COUNT        : integer := 0   -- 0 = boucle infinie
  );
  port (
    clk_i    : in  std_logic;
    rst_i    : in  std_logic;

    m_tvalid : out std_logic;
    m_tdata  : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
    m_tlast  : out std_logic;
    m_tready : in  std_logic;

    done_o      : out std_logic;
    frame_cnt_o : out integer;
    pixel_cnt_o : out integer
  );
end entity axi4s_driver;

architecture rtl of axi4s_driver is

  signal s_tvalid    : std_logic := '0';
  signal s_tdata     : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal s_tlast     : std_logic := '0';
  signal s_done      : std_logic := '0';
  signal s_frame_cnt : integer   := 0;
  signal s_pixel_cnt : integer   := 0;

begin

  m_tvalid    <= s_tvalid;
  m_tdata     <= s_tdata;
  m_tlast     <= s_tlast;
  done_o      <= s_done;
  frame_cnt_o <= s_frame_cnt;
  pixel_cnt_o <= s_pixel_cnt;

  p_drive : process

    file     f_stim    : text;
    variable v_line    : line;
    variable v_pix     : integer;
    variable v_good    : boolean;
    variable v_is_last : boolean;
    variable v_max_val : integer;
    variable v_loop_n  : integer := 0;  -- compteur de passages

    procedure read_dec_token(
      variable vl  : inout line;
      variable val : out   integer;
      variable ok  : out   boolean
    ) is
      variable c   : character;
      variable rd  : boolean;
      variable acc : integer;
      variable sta : boolean;
    begin
      acc := 0; sta := false; ok := false;
      loop
        if vl'length = 0 then
          if sta then val := acc; ok := true; end if;
          return;
        end if;
        read(vl, c, rd);
        if not rd then
          if sta then val := acc; ok := true; end if;
          return;
        end if;
        if character'pos(c) = 9 then          -- \t = séparateur
          if sta then val := acc; ok := true; end if;
          return;
        end if;
        if c >= '0' and c <= '9' then
          acc := acc * 10 + (character'pos(c) - character'pos('0'));
          sta := true;
        else
          if sta then val := acc; ok := true; return; end if;
        end if;
      end loop;
    end procedure;

  begin

    s_tvalid <= '0'; s_tlast <= '0';
    s_tdata  <= (others => '0');
    s_done   <= '0';
    s_frame_cnt <= 0; s_pixel_cnt <= 0;

    wait until rising_edge(clk_i) and rst_i = '0';

    for i in 1 to G_INIT_DELAY loop
      wait until rising_edge(clk_i);
    end loop;

    if G_DATA_WIDTH >= 32 then
      v_max_val := integer'high;
    else
      v_max_val := 2**G_DATA_WIDTH - 1;
    end if;

    -- -------------------------------------------------------------------------
    -- Boucle externe : rejoue le fichier G_LOOP_COUNT fois, ou indéfiniment
    -- si G_LOOP_COUNT = 0.
    -- -------------------------------------------------------------------------
    loop

      file_open(f_stim, G_FILE_PATH, READ_MODE);

      while not endfile(f_stim) loop

        readline(f_stim, v_line);
        if v_line'length = 0 then next; end if;

        loop
          read_dec_token(v_line, v_pix, v_good);
          exit when not v_good;

          if v_pix > v_max_val then v_pix := v_max_val; end if;

          v_is_last := (v_line'length = 0);

          s_tdata  <= std_logic_vector(to_unsigned(v_pix, G_DATA_WIDTH));
          s_tvalid <= '1';
          if G_TLAST_END_OF_LINE and v_is_last then
              s_tlast <= '1';
            else
              s_tlast <= '0';
            end if;

          loop
            wait until rising_edge(clk_i);
            exit when m_tready = '1';
          end loop;

          s_tvalid    <= '0';
          s_tlast     <= '0';
          s_pixel_cnt <= s_pixel_cnt + 1;

        end loop;

        s_frame_cnt <= s_frame_cnt + 1;

      end loop;

      file_close(f_stim);

      -- ----------------------------------------------------------------------
      -- Gestion du nombre de passages
      -- ----------------------------------------------------------------------
      v_loop_n := v_loop_n + 1;
      exit when (G_LOOP_COUNT /= 0) and (v_loop_n >= G_LOOP_COUNT);

    end loop;  -- boucle fichier

    s_done <= '1';
    wait;

  end process p_drive;

end architecture rtl;