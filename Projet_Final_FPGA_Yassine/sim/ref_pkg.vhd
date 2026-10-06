--------------------------------------------------------------------------------
-- Projet      : SoC Tracking (Deverne)
-- Fichier     : ref_pkg.vhd  (NON SYNTHETISABLE, banc de test uniquement)
-- Description : Procedures de reference des cas de test, calculees de facon
--               INDEPENDANTE de la partie synthetisable (cf PV section 5.1).
--               Les testbenches comparent la sortie du composant sous test a ces
--               references par assertion. L'independance du code de reference est
--               ce qui donne sa valeur probante a la comparaison.
--
--               L'arithmetique entiere (division euclidienne, troncature) est
--               reproduite a l'identique de la description materielle afin que
--               les seuls ecarts detectes soient de vrais defauts (PV 5.1).
-- Norme       : VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ref_pkg is

  type int3x3_t is array (0 to 8) of integer;  -- fenetre / noyau en entiers

  -- Luminance de reference (ED-01 / PO-04), decalages dyadiques.
  function ref_luma(r, g, b : integer) return integer;

  -- Convolution de reference : somme(k*p), division par 2**shift (troncature
  -- vers zero), valeur absolue optionnelle, bornage a [0, 2**out_w - 1].
  function ref_conv(win, kern : int3x3_t; shift : natural;
                    do_abs : boolean; out_w : natural) return integer;

  -- Bornage non signe.
  function ref_clamp(v : integer; w : natural) return integer;

end package ref_pkg;

package body ref_pkg is

  function ref_clamp(v : integer; w : natural) return integer is
    variable m : integer := 2**w - 1;
  begin
    if v < 0 then return 0;
    elsif v > m then return m;
    else return v; end if;
  end function;

  function ref_luma(r, g, b : integer) return integer is
    variable y : integer;
  begin
    -- Y = 5/16 R + 9/16 G + 2/16 B, realise par decalages
    y := (r/4) + (r/16) + (g/2) + (g/16) + (b/8);
    return ref_clamp(y, 8);
  end function;

  function ref_conv(win, kern : int3x3_t; shift : natural;
                    do_abs : boolean; out_w : natural) return integer is
    variable acc : integer := 0;
    variable res : integer;
  begin
    for i in 0 to 8 loop
      acc := acc + kern(i) * win(i);
    end loop;
    if acc >= 0 then
      res := acc / (2**shift);
    else
      res := -((-acc) / (2**shift));
    end if;
    if do_abs then res := abs(res); end if;
    return ref_clamp(res, out_w);
  end function;

end package body ref_pkg;
