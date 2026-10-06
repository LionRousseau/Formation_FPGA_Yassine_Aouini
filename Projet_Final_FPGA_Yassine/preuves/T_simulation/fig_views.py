import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image
plt.rcParams["font.family"]="DejaVu Sans"
F="/root/v2_work/sim_full/views_png/"; S="/root/v2_work/sim/views_png/"
items=[(F+"v0_A.png","VIEW 0, mode A : image naturelle"),(F+"v0_B.png","VIEW 0, mode B : overlay"),(F+"v1_luma.png","VIEW 1 : luminance"),
       (F+"v2_gauss.png","VIEW 2 : sortie du gaussien"),(F+"v3_resp.png","VIEW 3 : réponse du laplacien"),(F+"v4_mask.png","VIEW 4 : masque binaire")]
fig,axs=plt.subplots(2,3,figsize=(11,5.6))
for a,(f,t) in zip(axs.flat,items):
    a.imshow(Image.open(f)); a.set_title(t,fontsize=9,color="#1F3864"); a.axis("off")
fig.suptitle("Sorties du RTL v2 simulé en 640 x 480 sur le Rafale, seuil 30 : 0 pixel différent du modèle de référence pour chaque vue",fontsize=9.5,color="#1F3864")
plt.tight_layout(); plt.savefig("fig_views_640.png",dpi=130); plt.close()
fig,axs=plt.subplots(1,2,figsize=(9,3.6))
for a,(f,t) in zip(axs,[(S+"v0_B.png","Overlay avec gaussien"),(S+"v0_B_byp.png","Overlay sans gaussien (VIEW = 8)")]):
    a.imshow(Image.open(f),interpolation="nearest"); a.set_title(t,fontsize=9,color="#1F3864"); a.axis("off")
fig.suptitle("Effet du lissage (simulation 160 x 120, 0 pixel faux) : sans gaussien, davantage de points parasites",fontsize=9,color="#1F3864")
plt.tight_layout(); plt.savefig("fig_bypass.png",dpi=130); plt.close()
print("ok")
