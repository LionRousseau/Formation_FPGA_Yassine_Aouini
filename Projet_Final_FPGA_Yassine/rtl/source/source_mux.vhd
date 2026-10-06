--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : source_mux.vhd
-- Description : Multiplexeur de source video AXI4-Stream (PL-IP-002 selection a
--               l'initialisation, PL-IP-003 selection a chaud). Choisit entre
--               deux sources (par convention s0 = DMA memoire PL-IP-000, s1 =
--               generateur de mire TPG PL-IP-001) selon l'entree sel, pilotee
--               par un registre du PS.
--
--               Bascule PROPRE a la frontiere de trame : un changement de sel en
--               cours de trame n'est pris en compte qu'a la fin de la trame
--               courante, et la source retenue n'est diffusee qu'a partir de son
--               prochain debut de trame (tuser). Aucune trame corrompue ni
--               spliced, aucune perte de synchronisation (TC-U-03).
--
--               La source non selectionnee est drainee (tready = '1', donnees
--               ignorees) pour rester en regime continu ; en materiel, on peut
--               a la place inhiber son ap_start (voir DMA_INTEGRATION.md).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.video_pkg.all;

entity source_mux is
  port (
    clk       : in  std_logic;
    resetn    : in  std_logic;
    sel       : in  std_logic;                       -- 0 = s0 (DMA), 1 = s1 (TPG)
    -- source 0
    s0_tdata  : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    s0_tvalid : in  std_logic;
    s0_tready : out std_logic;
    s0_tuser  : in  std_logic;
    s0_tlast  : in  std_logic;
    -- source 1
    s1_tdata  : in  std_logic_vector(3*C_COMP_W-1 downto 0);
    s1_tvalid : in  std_logic;
    s1_tready : out std_logic;
    s1_tuser  : in  std_logic;
    s1_tlast  : in  std_logic;
    -- sortie
    m_tdata   : out std_logic_vector(3*C_COMP_W-1 downto 0);
    m_tvalid  : out std_logic;
    m_tready  : in  std_logic;
    m_tuser   : out std_logic;
    m_tlast   : out std_logic;
    -- observabilite (sonde ILA)
    active_o  : out std_logic                        -- source actuellement diffusee
  );
end entity source_mux;

architecture rtl of source_mux is
  signal cur     : std_logic := '0';   -- source actuellement diffusee
  signal waiting : std_logic := '1';   -- en attente du tuser de cur apres bascule

  -- signaux de la source active
  signal a_data  : std_logic_vector(3*C_COMP_W-1 downto 0);
  signal a_valid, a_user, a_last : std_logic;

  signal switch_now, start_now, fwd : std_logic;
begin
  -- multiplexage des signaux de la source active
  a_data  <= s0_tdata  when cur = '0' else s1_tdata;
  a_valid <= s0_tvalid when cur = '0' else s1_tvalid;
  a_user  <= s0_tuser  when cur = '0' else s1_tuser;
  a_last  <= s0_tlast  when cur = '0' else s1_tlast;

  -- Conditions de bascule :
  --   switch_now : on diffuse, la source active atteint un debut de trame et sel
  --                a change -> on ne diffuse pas cette trame, on bascule.
  --   start_now  : on attendait, la source active presente son tuser -> demarrage
  --                propre de la diffusion sur ce debut de trame.
  switch_now <= '1' when (waiting = '0' and a_valid = '1' and a_user = '1' and sel /= cur) else '0';
  -- start_now n'est arme que lorsque la source visee est deja selectionnee (cur=sel),
  -- pour ne jamais demarrer la diffusion sur la mauvaise source pendant un retarget.
  start_now  <= '1' when (waiting = '1' and a_valid = '1' and a_user = '1' and sel = cur) else '0';
  fwd        <= '1' when ((waiting = '0' and switch_now = '0') or start_now = '1') else '0';

  -- Sortie : diffusion de la source active si fwd, sinon rien.
  m_tdata  <= a_data;
  m_tvalid <= a_valid when fwd = '1' else '0';
  m_tuser  <= a_user  when fwd = '1' else '0';
  m_tlast  <= a_last  when fwd = '1' else '0';

  -- readys : la source active recoit m_tready quand on diffuse, sinon elle est
  -- drainee ('1'). La source non active est toujours drainee.
  s0_tready <= m_tready when (cur = '0' and fwd = '1') else '1';
  s1_tready <= m_tready when (cur = '1' and fwd = '1') else '1';

  active_o <= cur;

  process(clk, resetn)
  begin
    if resetn = '0' then
      cur     <= '0';
      waiting <= '1';
    elsif rising_edge(clk) then
      if waiting = '0' then
        if switch_now = '1' then
          cur     <= sel;      -- bascule a la frontiere de trame
          waiting <= '1';
        end if;
      else
        -- Le retarget est prioritaire : on ne demarre jamais sur la mauvaise
        -- source. start_now (arme seulement si sel=cur) valide le demarrage.
        if sel /= cur then
          cur <= sel;          -- retarget tant qu'aucune trame n'a demarre
        elsif start_now = '1' then
          waiting <= '0';      -- diffusion demarree sur un debut de trame propre
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
