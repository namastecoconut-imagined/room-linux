import numpy as np, wave, subprocess
R=48000
rng=np.random.default_rng(3)
def t(d): return np.arange(int(R*d))/R
def env(d,a=0.005,dec=6.0):
    x=t(d); return np.minimum(1,x/a)*np.exp(-x*dec)
def sine(f,d,a=0.005,dec=6,ph=0): x=t(d); return np.sin(2*np.pi*f*x+ph)*env(d,a,dec)
def place(parts,total):
    out=np.zeros(int(R*total)+R)
    for start,sig in parts:
        i=int(start*R); n=min(len(sig),len(out)-i); out[i:i+n]+=sig[:n]
    return out
IR=None
def reverb(x,wmix=0.25,dec=2.2,dur=1.6):
    global IR
    ir=rng.standard_normal(int(R*dur))*np.exp(-t(dur)*dec*2.3); ir/=np.sqrt((ir**2).sum())
    # lowpass the tail a bit
    k=np.ones(8)/8; ir=np.convolve(ir,k,'same')
    wet=np.convolve(x,ir); wet=np.pad(wet,(0,len(x)+len(ir)-len(wet)))
    y=np.concatenate([x,np.zeros(len(ir))])
    return y*(1-wmix)+wet*wmix
def mix(*xs):
    n=max(len(x) for x in xs); o=np.zeros(n)
    for x in xs: o[:len(x)]+=x
    return o
def norm(x,peak=0.5): return x/np.max(np.abs(x))*peak
def save(name,x):
    x=norm(x)
    with wave.open(name+'.wav','wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(R);w.writeframes((x*32767).astype('<i2').tobytes())

# ---- sets: wake, heard(processing), done, miss
def glass(f): return mix(sine(f,1.4,0.004,3.5),0.35*sine(f*2.76,0.8,0.002,7),0.15*sine(f*5.4,0.4,0.001,12))
def marimba(f): return mix(sine(f,0.7,0.002,9),0.5*sine(f*4,0.2,0.001,30),0.25*sine(f*10,0.06,0.0005,80))
def drop(f,bend=1.6):
    x=t(0.35); fr=f*(1+ (bend-1)*np.exp(-x*40)); ph=2*np.pi*np.cumsum(fr)/R
    return np.sin(ph)*env(0.35,0.002,14)
def breath(d=0.45,lo=600,hi=3000,up=True):
    n=rng.standard_normal(int(R*d)); x=t(d)
    # sweep bandpass by mixing two moving-average filtered versions crudely
    sig=np.convolve(n,np.ones(6)/6,'same')-np.convolve(n,np.ones(40)/40,'same')
    shape=np.sin(np.pi*x/d)**2
    return sig*shape*0.6
def pad(f,d=0.9): return mix(sine(f,d,0.12,2.5),0.5*sine(f*1.5,d,0.15,2.5),0.3*sine(f*2,d,0.2,3))
def kalimba(f): return mix(sine(f,1.0,0.002,5),0.3*sine(f*5.95,0.15,0.001,40),0.12*sine(f*2.01,0.6,0.002,8))

C5,E5,G5,A5,B5,D6,E6,G6=523.25,659.25,783.99,880,987.77,1174.66,1318.51,1567.98
sets={
 "A-glass":   [[(0,glass(E5)),(0.11,glass(B5))], [(0,glass(G5)*0.6)], [(0,glass(B5)),(0.12,glass(E6))], [(0,glass(E5)),(0.14,glass(C5))]],
 "B-marimba": [[(0,marimba(G5)),(0.09,marimba(D6))], [(0,marimba(D6)*0.6)], [(0,marimba(G5)),(0.08,marimba(B5)),(0.16,marimba(D6))], [(0,marimba(D6)),(0.12,marimba(A5))]],
 "C-drop":    [[(0,drop(E5,1.8)),(0.13,drop(B5,1.5))], [(0,drop(B5,1.3)*0.6)], [(0,drop(G5,1.5)),(0.1,drop(D6,1.4))], [(0,drop(A5,0.7))]],
 "D-breath":  [[(0,breath(0.5)*0.8),(0.12,pad(E5,1.0)*0.5)], [(0,breath(0.3)*0.5)], [(0,mix(pad(G5,1.1)*0.6,pad(B5,1.1)*0.4))], [(0,pad(A5*0.75,0.9)*0.5)]],
 "E-kalimba": [[(0,kalimba(E5)),(0.12,kalimba(A5))], [(0,kalimba(E6)*0.5)], [(0,kalimba(A5)),(0.11,kalimba(C5*2)),(0.22,kalimba(E6))], [(0,kalimba(A5)),(0.15,kalimba(E5))]],
}
names=["wake","heard","done","miss"]
for k,parts in sets.items():
    seq=[]
    for i,p in enumerate(parts):
        s=reverb(place(p,1.6),0.22)
        save(f"{k}-{names[i]}",s)
        s=norm(s,0.5); e=np.convolve(np.abs(s),np.ones(480)/480,'same'); last=np.nonzero(e>0.5*10**(-50/20))[0]
        s=s[:last[-1]+1] if len(last) else s
        seq.append(s); seq.append(np.zeros(int(R*0.7)))
    save(k+"-all",np.concatenate(seq))
