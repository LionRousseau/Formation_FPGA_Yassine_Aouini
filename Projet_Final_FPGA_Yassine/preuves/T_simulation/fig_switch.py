import re, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
plt.rcParams["font.family"]="DejaVu Sans"
L=open("/root/v2_work/sim/preuves_logs/T_tb_switch_sys.log").read().splitlines()
rows=[]
for l in L:
    m=re.search(r"\): (.+) image (\d+) : (l_\w+)",l)
    if m: rows.append((m.group(1),int(m.group(2)),m.group(3)))
phases=[]
for p,k,lab in rows:
    if not phases or phases[-1][0]!=p: phases.append((p,[]))
    phases[-1][1].append(lab)
col={"l_dma":"#2F5597","l_mire":"#C55A11","l_autre":"#BFBFBF"}
fig,ax=plt.subplots(figsize=(10.5,2.6)); x=0
for p,labs in phases:
    if x>0:
        ax.plot([x,x],[-0.3,1.5],color="black",lw=1.2,ls="--")
    ax.text(x+len(labs)/2,1.3,p.replace("demarrage","démarrage").replace("(SRC_SEL=0)","\n(SRC_SEL = 0)").replace("bascule","bascule").replace(" vers ","\nvers "),ha="center",va="bottom",fontsize=7.5)
    for lab in labs:
        ax.add_patch(Rectangle((x+0.05,0),0.9,1,color=col[lab])); x+=1
ax.set_xlim(-0.5,x+0.5); ax.set_ylim(-0.6,2.4); ax.axis("off")
for i,(k,v) in enumerate([("image DMA exacte au pixel près","l_dma"),("mire exacte au pixel près","l_mire"),("autre (transition)","l_autre")]):
    ax.add_patch(Rectangle((i*14,-0.55),0.9,0.35,color=col[v])); ax.text(i*14+1.2,-0.38,k,fontsize=7.5,va="center")
ax.set_title("tb_switch_sys : classement de chaque image affichée ; tirets = écriture de SRC_SEL par transaction AXI4-Lite",fontsize=8.5,color="#1F3864")
plt.tight_layout(); plt.savefig("fig_switch_timeline.png",dpi=170); plt.close()
print(len(rows),[ (p,len(l)) for p,l in phases])
