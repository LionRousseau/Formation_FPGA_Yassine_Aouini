--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : video_pkg.vhd
-- Description : Package commun de la chaine de traitement video.
--               Regroupe les constantes de format d'image, les conventions
--               AXI4-Stream video (tuser = debut de trame, tlast = fin de ligne,
--               ED-03), la definition generique d'un noyau de convolution 3x3
--               et les realisations arithmetiques de reference (luminance PO-04).
--
--               Ces fonctions sont utilisees par la partie synthetisable ; les
--               testbenches recalculent la reference de facon INDEPENDANTE dans
--               ref_pkg.vhd afin que la comparaison ait une valeur probante.
--
-- Cible       : Zynq-7000, Cora Z7-10 (xc7z010clg400-1)
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package video_pkg is

  ----------------------------------------------------------------------------
  -- Format d'image (PO-03 : RGB 8 bits par composante)
  ----------------------------------------------------------------------------
  constant C_IMG_WIDTH   : natural := 640;   -- pixels par ligne
  constant C_IMG_HEIGHT  : natural := 480;   -- lignes par trame
  constant C_PIXELS      : natural := C_IMG_WIDTH * C_IMG_HEIGHT; -- 307200

  constant C_COMP_W      : natural := 8;      -- bits par composante couleur
  constant C_LUMA_W      : natural := 8;      -- bits de luminance / niveau de gris

  -- Largeur de la reponse du laplacien avant seuillage.
  -- Bornes theoriques d'un laplacien [0 -1 0; -1 4 -1; 0 -1 0] sur entree 8 bits :
  -- +-1020 (PO-02). Apres valeur absolue (PO-06) : 0..1020, tient sur 11 bits.
  constant C_RESP_W      : natural := 11;     -- reponse |laplacien| non signee
  constant C_ACC_W       : natural := 14;     -- accumulateur signe interne conv

  -- Largeur des compteurs de coordonnees (0..639, 0..479)
  constant C_X_W         : natural := 11;     -- 0..2047 (couvre 639)
  constant C_Y_W         : natural := 11;     -- 0..2047 (couvre 479)

  ----------------------------------------------------------------------------
  -- Types utilitaires
  ----------------------------------------------------------------------------
  -- Coefficients d'un noyau 3x3, en lecture ligne par ligne :
  --   k(0) k(1) k(2)
  --   k(3) k(4) k(5)
  --   k(6) k(7) k(8)
  type kernel3x3_t is array (0 to 8) of integer;

  -- Fenetre 3x3 de pixels non signes, meme ordre que le noyau.
  type window3x3_t is array (0 to 8) of unsigned(C_COMP_W-1 downto 0);

  ----------------------------------------------------------------------------
  -- Noyaux de la specification
  ----------------------------------------------------------------------------
  -- Gaussien (PL-IP-006), somme des poids = 16, sortie = somme/16.
  constant C_KERNEL_GAUSS : kernel3x3_t := (1, 2, 1,
                                            2, 4, 2,
                                            1, 2, 1);
  constant C_GAUSS_DIV_SH : natural := 4;   -- division par 16 = decalage de 4

  -- Laplacien (PL-IP-007, cf PO-01 : c'est bien un laplacien, non le critere de
  -- Harris). Pas de division, valeur absolue prise ensuite (PO-06).
  constant C_KERNEL_LAPL  : kernel3x3_t := ( 0, -1,  0,
                                            -1,  4, -1,
                                             0, -1,  0);
  constant C_LAPL_DIV_SH  : natural := 0;   -- pas de division

  ----------------------------------------------------------------------------
  -- Realisation de la conversion RGB -> luminance (ED-01 / PO-04)
  --
  -- BT.601 : Y = 0.299 R + 0.587 G + 0.114 B, approximee par decalages afin
  -- d'eviter tout multiplieur. Coefficients dyadiques retenus :
  --   R : 1/4 + 1/16 = 5/16  = 0.3125
  --   G : 1/2 + 1/16 = 9/16  = 0.5625
  --   B : 1/8        = 2/16  = 0.1250
  -- Somme des poids = 16/16 = 1, donc le blanc reste dans la plage 8 bits.
  --   Y = (R>>2)+(R>>4) + (G>>1)+(G>>4) + (B>>3)
  -- Le calcul est fait sur entiers non signes puis borne a 255.
  ----------------------------------------------------------------------------
  function rgb_to_luma_f (r, g, b : unsigned(C_COMP_W-1 downto 0))
    return unsigned;

  ----------------------------------------------------------------------------
  -- Reference arithmetique de la convolution 3x3.
  -- Calcule somme(k*p) sur une fenetre, applique un decalage a droite
  -- (division par 2**shift, troncature vers zero cote materiel), option
  -- valeur absolue, puis borne au domaine [0, 2**out_w - 1].
  -- Utilisee par la partie synthetisable comme repere ; les TB en ont une
  -- copie independante.
  ----------------------------------------------------------------------------
  function conv3x3_ref (win   : window3x3_t;
                        kern  : kernel3x3_t;
                        shift : natural;
                        do_abs: boolean;
                        out_w : natural) return integer;

  ----------------------------------------------------------------------------
  -- Borne un entier au domaine non signe [0, 2**w - 1].
  ----------------------------------------------------------------------------
  function clamp_u (v : integer; w : natural) return integer;

end package video_pkg;


package body video_pkg is

  function clamp_u (v : integer; w : natural) return integer is
    variable vmax : integer := 2**w - 1;
  begin
    if v < 0 then
      return 0;
    elsif v > vmax then
      return vmax;
    else
      return v;
    end if;
  end function;

  function rgb_to_luma_f (r, g, b : unsigned(C_COMP_W-1 downto 0))
    return unsigned is
    variable ri, gi, bi, y : integer;
  begin
    ri := to_integer(r);
    gi := to_integer(g);
    bi := to_integer(b);
    -- decalages entiers (troncature) identiques a la realisation materielle
    y := (ri/4) + (ri/16) + (gi/2) + (gi/16) + (bi/8);
    y := clamp_u(y, C_LUMA_W);
    return to_unsigned(y, C_LUMA_W);
  end function;

  function conv3x3_ref (win   : window3x3_t;
                        kern  : kernel3x3_t;
                        shift : natural;
                        do_abs: boolean;
                        out_w : natural) return integer is
    variable acc : integer := 0;
    variable res : integer;
  begin
    for i in 0 to 8 loop
      acc := acc + kern(i) * to_integer(win(i));
    end loop;
    -- division par 2**shift, troncature vers zero
    if acc >= 0 then
      res := acc / (2**shift);
    else
      res := -((-acc) / (2**shift));
    end if;
    if do_abs then
      res := abs(res);
    end if;
    return clamp_u(res, out_w);
  end function;

end package body video_pkg;
