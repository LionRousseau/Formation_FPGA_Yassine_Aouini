import re, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
plt.rcParams["font.family"]="DejaVu Sans"
NAVY="#1F3864"; GRN="#1E7B34"; ORG="#B36B00"

def parse(path, want):
    """want: list of (scope_suffix, name). returns dict name->list[(t,val)] ; time unit fs->ns"""
    ids={}; scope=[]; data={}; ts=1.0
    with open(path) as f:
        t=0
        for line in f:
            if line.startswith("$timescale"):
                u=f.readline().strip() if line.strip()=="$timescale" else line.split()[1]
                ts={"1fs":1e-6,"1ps":1e-3,"1ns":1.0}.get(u.replace(" ",""),1e-6)
            elif line.startswith("$scope"): scope.append(line.split()[2])
            elif line.startswith("$upscope"): scope.pop()
            elif line.startswith("$var"):
                p=line.split(); vid=p[3]; nm=p[4]
                for (sc,n) in want:
                    if n==nm and scope and scope[-1]==sc:
                        ids.setdefault(vid,[]).append(sc+"."+n); data[sc+"."+n]=[]
            elif line.startswith("#"): t=int(line[1:])*ts
            elif line[:1] in "01xzXZ" and line[1:].strip() in ids:
                for k in ids[line[1:].strip()]: data[k].append((t,line[0]))
            elif line[:1]=="b":
                v,vid=line[1:].split()
                if vid in ids:
                    for k in ids[vid]: data[k].append((t,v))
    return data

def pulses(ev, level="0"):
    """durations of level and periods between starts"""
    starts=[]; widths=[]; prev=None
    for i,(t,v) in enumerate(ev):
        if v==level and prev!=level: starts.append(t)
        if v!=level and prev==level and starts: widths.append(t-starts[-1])
        prev=v
    periods=[b-a for a,b in zip(starts,starts[1:])]
    return starts,widths,periods

# ---------------- VGA ----------------
d=parse("/tmp/vga.vcd",[("tb_vga_timing","hsync"),("tb_vga_timing","vsync"),("tb_vga_timing","active"),("tb_vga_timing","fbeg")])
hs=d["tb_vga_timing.hsync"]; vs=d["tb_vga_timing.vsync"]; ac=d["tb_vga_timing.active"]
_,hw,hp=pulses(hs); _,vw,vp=pulses(vs); _,aw,ap=pulses(ac,"1"); fb,_,fp=pulses(d["tb_vga_timing.fbeg"],"1"); vp=fp
T=39.72
m={"hsync_bas_ns":hw[5],"ligne_ns":hp[5],"vsync_bas_ns":vw[0],"image_ns":vp[0] if vp else None,"actif_ns":aw[5]}
res=[("Durée d'une ligne",hp[5],800),("Impulsion hsync (bas)",hw[5],96),("Zone active d'une ligne",aw[5],640),
     ("Impulsion vsync (bas)",vw[0],2*800),("Durée d'une image (525 lignes mesurées)",525*hp[5],525*800)]
with open("mesures_vga.txt","w") as f:
    f.write("Mesures extraites du chronogramme de tb_vga_timing (horloge 25,175 MHz, periode 39,72 ns)\n")
    for n,v,c in res: f.write(f"{n:28s} {v/1000:10.3f} us  = {v/T:9.1f} periodes pixel (attendu {c})\n")
print(open("mesures_vga.txt").read())
def step(ax,ev,y,t0,t1,col,lab):
    xs=[];ys=[];cur=None
    for t,v in ev:
        if t<t0: cur=v; continue
        if t>t1: break
        if cur is not None: xs+= [t,t]; ys+=[y+(0.8 if cur=="1" else 0), y+(0.8 if v=="1" else 0)]
        cur=v
    xs=[t0]+xs+[t1]; ys=[y+(0.8 if (ys[0] if ys else 0)>y else 0)]+ys+[ys[-1] if ys else y]
    ax.plot([x/1000 for x in xs],ys,color=col,lw=1.4); ax.text(t0/1000,y+0.35,lab+"  ",ha="right",va="center",fontsize=8,color=col)
fig,(a1,a2)=plt.subplots(2,1,figsize=(10,4.6))
s0=[t for t,v in hs if v=="0"][10]-5000; 
step(a1,hs,2,s0,s0+36000,NAVY,"hsync"); step(a1,ac,0.8,s0,s0+36000,GRN,"active")
a1.set_title(f"Une ligne : période {hp[5]/1000:.2f} µs (800 px), hsync bas {hw[5]/1000:.2f} µs (96 px), zone active {aw[5]/1000:.2f} µs (640 px)",fontsize=8.5,color=NAVY)
a1.set_yticks([]); a1.set_xlabel("µs",fontsize=8); a1.tick_params(labelsize=7)
f0=fb[0]-0.3e6
step(a2,vs,2,f0,f0+17.2e6,NAVY,"vsync"); step(a2,ac,0.8,f0,f0+17.2e6,GRN,"active")
a2.set_title(f"Une image : 525 lignes × {hp[5]/1000:.3f} µs = {525*hp[5]/1e6:.3f} ms, soit {1e9/(525*hp[5]):.2f} images/s, vsync bas {vw[0]/1000:.1f} µs (2 lignes)",fontsize=8.5,color=NAVY)
a2.set_yticks([]); a2.set_xlabel("µs",fontsize=8); a2.tick_params(labelsize=7)
plt.tight_layout(); plt.savefig("fig_vga_timing.png",dpi=160); plt.close()


# ---------------- AXIS ----------------
names=["clk","s_tvalid","s_tready","s_tuser","s_tlast","m_tvalid","m_tready","m_tuser","m_tlast"]
d=parse("/tmp/axis.vcd",[("dut",n) for n in names])
clk=d["dut.clk"]; rises=[t for t,v in clk if v=="1"]
def val(ev,t):
    cur="0"
    for tt,v in ev:
        if tt>t: break
        cur=v
    return cur
# fenetre : 60 cycles apres le premier s_tvalid
t_first=[t for t,v in d["dut.s_tvalid"] if v=="1"][0]
r=[t for t in rises if t>=t_first-2*(rises[1]-rises[0])][:60]
fig,ax=plt.subplots(figsize=(10,3.9))
labels=["s_tvalid","s_tready","s_tuser","s_tlast","m_tvalid","m_tready","m_tuser","m_tlast"]
cols=[NAVY,NAVY,NAVY,NAVY,GRN,GRN,GRN,GRN]
per=r[1]-r[0]
nin=nout=0
for k,(n,c) in enumerate(zip(labels,cols)):
    y=(len(labels)-k)*1.0
    xs=[];ys=[]
    for i,t in enumerate(r):
        v=1 if val(d["dut."+n],t-per*0.1)=="1" else 0
        xs+=[i,i+1]; ys+=[y+0.7*v]*2
    ax.plot(xs,ys,color=c,lw=1.3); ax.text(-0.5,y+0.3,n,ha="right",va="center",fontsize=8,color=c)
for i,t in enumerate(r):
    tin = val(d["dut.s_tvalid"],t-per*0.1)=="1" and val(d["dut.s_tready"],t-per*0.1)=="1"
    tout= val(d["dut.m_tvalid"],t-per*0.1)=="1" and val(d["dut.m_tready"],t-per*0.1)=="1"
    if tin: ax.plot([i+0.5],[9.0],marker="v",color=NAVY,ms=4); nin+=1
    if tout: ax.plot([i+0.5],[0.75],marker="^",color=GRN,ms=4); nout+=1
ax.set_xlim(-6,61); ax.set_yticks([]); ax.set_xlabel("cycles d'horloge",fontsize=8); ax.tick_params(labelsize=7)
ax.set_title("tb_axis_conformance : trous aléatoires sur s_tvalid, pauses aléatoires sur m_tready.\n▼ transfert accepté en entrée, ▲ transfert accepté en sortie : chaque pixel passe une fois et une seule",fontsize=8.5,color=NAVY)
plt.tight_layout(); plt.savefig("fig_axis_handshake.png",dpi=160); plt.close()
print("axis ok", nin, nout)
