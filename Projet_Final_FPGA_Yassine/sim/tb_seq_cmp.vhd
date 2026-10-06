--------------------------------------------------------------------------------
-- tb_seq_cmp : compare l'ancienne FSM (avec D_HOLD) et la nouvelle (sans), avec
-- un modele DMA cadence qui FINIT en fin de zone active (= debut du blanking),
-- condition reelle. On compte les trames "noires" (DMA non occupe pendant la
-- zone active) pour chaque FSM. Attendu : ancienne > 0 (saut de trame), nouvelle = 0.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity tb_seq_cmp is end entity;

architecture sim of tb_seq_cmp is
  constant TOTAL  : integer := 1000;
  constant ACTIVE : integer := 800;
  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';
  signal done : boolean := false;

  signal phase : integer := 0;
  signal vblank : std_logic := '0';

  -- variante ancienne (D_HOLD)
  type st4 is (W,L,R,H);
  signal s_old : st4 := W;
  signal start_old : std_logic := '0';
  signal busy_old : std_logic := '0';
  signal px_old : integer := 0;
  signal black_old : integer := 0;
  signal seen_old : std_logic := '0';

  -- variante nouvelle
  type st3 is (W,L,R);
  signal s_new : st3 := W;
  signal start_new : std_logic := '0';
  signal busy_new : std_logic := '0';
  signal px_new : integer := 0;
  signal black_new : integer := 0;
  signal seen_new : std_logic := '0';

  signal fr : integer := 0;
begin
  clk <= not clk after 5 ns when not done else '0';

  -- afficheur synthetique
  process(clk)
  begin
    if rising_edge(clk) then
      if rstn='0' then phase<=0;
      elsif phase=TOTAL-1 then phase<=0; else phase<=phase+1; end if;
    end if;
  end process;
  vblank <= '1' when phase>=ACTIVE else '0';

  -- modele DMA ancienne FSM : consomme 1 px/cycle en zone active quand occupe
  process(clk)
  begin
    if rising_edge(clk) then
      if rstn='0' then busy_old<='0'; px_old<=0;
      elsif busy_old='0' then
        if start_old='1' then busy_old<='1'; px_old<=0; end if;
      else
        if vblank='0' then                       -- consomme en zone active
          if px_old=ACTIVE-1 then busy_old<='0'; else px_old<=px_old+1; end if;
        end if;
      end if;
    end if;
  end process;

  -- ANCIENNE FSM (avec D_HOLD)
  process(clk)
  begin
    if rising_edge(clk) then
      if rstn='0' then s_old<=W; start_old<='0';
      else
        case s_old is
          when W => start_old<='0';
                    if vblank='1' and busy_old='0' then start_old<='1'; s_old<=L; end if;
          when L => start_old<='1';
                    if busy_old='1' then start_old<='0'; s_old<=R; end if;
          when R => start_old<='0';
                    if busy_old='0' then s_old<=H; end if;
          when H => start_old<='0';
                    if vblank='0' then s_old<=W; end if;
        end case;
      end if;
    end if;
  end process;

  -- modele DMA nouvelle FSM
  process(clk)
  begin
    if rising_edge(clk) then
      if rstn='0' then busy_new<='0'; px_new<=0;
      elsif busy_new='0' then
        if start_new='1' then busy_new<='1'; px_new<=0; end if;
      else
        if vblank='0' then
          if px_new=ACTIVE-1 then busy_new<='0'; else px_new<=px_new+1; end if;
        end if;
      end if;
    end if;
  end process;

  -- NOUVELLE FSM (sans D_HOLD)
  process(clk)
  begin
    if rising_edge(clk) then
      if rstn='0' then s_new<=W; start_new<='0';
      else
        case s_new is
          when W => start_new<='0';
                    if vblank='1' and busy_new='0' then start_new<='1'; s_new<=L; end if;
          when L => start_new<='1';
                    if busy_new='1' then start_new<='0'; s_new<=R; end if;
          when R => start_new<='0';
                    if busy_new='0' then s_new<=W; end if;
        end case;
      end if;
    end if;
  end process;

  -- mesure : par trame, le DMA a-t-il ete occupe pendant la zone active ?
  process(clk)
  begin
    if rising_edge(clk) then
      if rstn='0' then
        seen_old<='0'; seen_new<='0'; black_old<=0; black_new<=0; fr<=0;
      else
        if vblank='0' then
          if busy_old='1' then seen_old<='1'; end if;
          if busy_new='1' then seen_new<='1'; end if;
        end if;
        if phase=TOTAL-1 then           -- fin de trame
          if fr>=2 and seen_old='0' then black_old<=black_old+1; end if;
          if fr>=2 and seen_new='0' then black_new<=black_new+1; end if;
          seen_old<='0'; seen_new<='0'; fr<=fr+1;
        end if;
      end if;
    end if;
  end process;

  stim : process
  begin
    rstn<='0'; wait for 100 ns; rstn<='1';
    wait for 200 us;            -- ~20 trames
    report "trames noires ANCIENNE FSM (D_HOLD) = " & integer'image(black_old);
    report "trames noires NOUVELLE FSM        = " & integer'image(black_new);
    assert black_old > 0 report "diagnostic non reproduit ?!" severity warning;
    assert black_new = 0 report "ECHEC: la nouvelle FSM saute encore des trames" severity error;
    report "SUCCES: nouvelle FSM = 0 trame noire (ancienne en avait " & integer'image(black_old) & ")";
    done<=true; wait;
  end process;
end architecture sim;
