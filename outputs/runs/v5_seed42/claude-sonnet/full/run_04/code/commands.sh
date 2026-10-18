cd /tmp/edabench_claude_nks0nb5p; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_nks0nb5p; cat suppliers.csv; cat maintenance.csv | awk -F, '{print $2,$3}' | sort | uniq -c | head -20; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.describe().T)
for c in ['line','shift','operator_id','supplier_code']: print(d[c].value_counts(dropna=False))
print(d.batch_id.duplicated().sum(), d.duplicated().sum())
for c in ['mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','machine_age_years','ambient_temp_c']:
    x=pd.to_numeric(d[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(d[c][x.isna()].value_counts(dropna=False).head())
print(d.production_date.str.len().value_counts()); print(d.production_date.sample(15).tolist())
"

cd /tmp/edabench_claude_nks0nb5p; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
dd=d[d.batch_id.duplicated(keep=False)&~d.duplicated(keep=False)].sort_values('batch_id');print(len(dd));print(dd.head(12).to_string())
s=d.production_date
iso=s.str.contains('-'); print(iso.sum())
sl=s[~iso].str.split('/',expand=True).astype(int); print(sl.max())
m=pd.to_numeric(d.mold_temp); print(m.round(-1).value_counts().sort_index().to_string())
print(d[d.humidity_pct.isna()].shape, (pd.to_numeric(d.humidity_pct)<0).sum(), pd.to_numeric(d.humidity_pct).value_counts().head(3))
"; grep -n sensor maintenance.csv

cd /tmp/edabench_claude_nks0nb5p; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
s=d.production_date
d['fmt']='iso'
sl=s.str.contains('/')
a=s[sl].str.split('/',expand=True).astype(int)
f=pd.Series('amb',index=a.index); f[a[0]>12]='dmy'; f[a[1]>12]='mdy'
d.loc[sl,'fmt']=f
print(pd.crosstab(d.line,d.fmt))
print(d.duplicated(['batch_id','line']).sum(), d.duplicated().sum(), d.duplicated(['batch_id','line'],keep=False).sum())
x=d[d.duplicated(['batch_id','line'],keep=False)&~d.duplicated(keep=False)];print(x.sort_values('batch_id').to_string())
h=pd.to_numeric(d.humidity_pct); print(d[h==50.2].groupby('line').size(), d[h==50.2].production_date.head(10).tolist())
d['m']=pd.to_numeric(d.mold_temp); print(pd.crosstab(d.line,pd.cut(d.m,[-1,1,300,500])))
print(d[d.line=='L1'].assign(F=d.m>300).groupby(d.production_date).F.mean().head(0))
"

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates()
def pdate(r):
    s=r.production_date
    if '-' in s: return pd.Timestamp(s)
    a,b,y=map(int,s.split('/'))
    return pd.Timestamp(y,a,b) if r.line=='L1' else pd.Timestamp(y,b,a)
d['date']=d.apply(pdate,axis=1)
print(d.date.min(),d.date.max(),len(d))
for c in ['mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur']: d[c]=pd.to_numeric(d[c])
d['shift']=d['shift'].str.strip().str.lower().str[0].map({'d':'Day','n':'Night'})
d['sup']=d.supplier_code.str.strip().str.upper()
d['mt']=np.where(d.mold_temp>300,(d.mold_temp-32)*5/9,d.mold_temp); d.loc[d.mold_temp==0,'mt']=np.nan
h=d.humidity_pct
bad=h.isna()|(h<0)
st=d[h==50.2]; print(st.date.min(),st.date.max(),st.line.unique(), len(st))
l2=d[(d.line=='L2')&(d.date>=st.date.min())&(d.date<=st.date.max())]; print(len(l2),(l2.humidity_pct==50.2).sum())
bad2=bad|(h==50.2)
print(bad.sum(),bad2.sum())
print('A3',d.defective_units.sum()/d.units_produced.sum()); print('A4',d.mt.median(), d.mt.isna().sum())
d['rate']=d.defective_units/d.units_produced
d.to_pickle(__import__('os').environ['TMPDIR']+'/d.pkl')
print(d.groupby('line').mt.describe())
E
python3 $TMPDIR/p.py

cd /tmp/edabench_claude_nks0nb5p; python3 -c "
import pandas as pd
d=pd.read_pickle('$TMPDIR/d.pkl')
x=d[d.humidity_pct==50.2]; print(x.groupby('line').date.agg(['min','max','count']))
l=d[d.line=='L2'].sort_values('date'); print(l[l.humidity_pct==50.2].date.dt.to_period('W').value_counts().sort_index().to_string())
print(d[d.humidity_pct.between(50.1,50.3)].humidity_pct.value_counts())
"

cd /tmp/edabench_claude_nks0nb5p; python3 -c "
import pandas as pd,numpy as np
d=pd.read_pickle('$TMPDIR/d.pkl')
w=(d.line=='L2')&d.date.between('2025-03-03','2025-04-13')
print(w.sum(),(w&(d.humidity_pct==50.2)).sum())
bad=d.humidity_pct.isna()|(d.humidity_pct<0)|w
print('A2',bad.sum())
d['hv']=np.where(bad,np.nan,d.humidity_pct)
d.to_pickle('$TMPDIR/d.pkl')
l=d[d.line=='L1']; print(l.groupby(l.date.dt.to_period('M')).mt.agg(['mean','std']))
print(d.groupby(d.date.dt.to_period('M')).mt.mean())
# weekly rate by line
for ln,g in d.groupby('line'):
    w=g.groupby(g.date.dt.to_period('W')).apply(lambda x:x.defective_units.sum()/x.units_produced.sum())
    print(ln,w.round(3).values)
"

cd /tmp/edabench_claude_nks0nb5p; python3 -c "
import pandas as pd,numpy as np
d=pd.read_pickle('$TMPDIR/d.pkl')
l=d[d.line=='L1']
print(l.groupby(l.date.dt.to_period('W')).mt.mean().round(1).to_string())
for ln in ['L2','L3','L4']:
    g=d[d.line==ln]; print(ln,g.groupby(g.date.dt.to_period('M')).mt.mean().round(1).values)
"

cd /tmp/edabench_claude_nks0nb5p; python3 -c "
import pandas as pd,numpy as np,statsmodels.formula.api as smf
d=pd.read_pickle('$TMPDIR/d.pkl').dropna(subset=['mt'])
m=smf.ols('mt~ambient_temp_c+cycle_time_s',d).fit(); d['res']=m.resid; print(m.params)
for ln in ['L1','L2','L3','L4']:
    g=d[d.line==ln]; print(ln,g.groupby(g.date.dt.to_period('M')).res.mean().round(1).values)
print(d.groupby(d.date.dt.to_period('M')).ambient_temp_c.mean().round(1).values)
for ln in ['L1','L3']:
  g=d[d.line==ln]; print(g.groupby(g.date.dt.to_period('M')).ambient_temp_c.mean().round(1).values)
"

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/edabench_claude_nks0nb5p/'.replace('/tmp/edabench_claude_nks0nb5p/',__import__('os').environ['TMPDIR']+'/')+'d.pkl')
d['ok']=1-d.defective_units/d.units_produced
d['nd']=d.units_produced-d.defective_units
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
def fit(f,data):
    return smf.glm(f,data,family=sm.families.Binomial(),freq_weights=None).fit()
def g(f,data):
    m=smf.glm('I(defective_units/units_produced) ~ '+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(); return m
x=d.dropna(subset=['mt','hv'])
m=g('mt+hv+I(hv**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+C(line)',x)
print(m.summary().tables[1])
E
python3 $TMPDIR/m.py

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
print(d.groupby('line').machine_age_years.describe())
print(d.groupby('sup').cycle_time_s.describe())
print(d.groupby('sup').hv.describe())
print(pd.crosstab(d.sup,d.line))
print(d[['mt','hv','cycle_time_s','ambient_temp_c','machine_age_years','qc_inspection_min','rework_cost_eur','rate']].corr().round(2))
print(pd.crosstab(d.operator_id,d.line).head(30))
print(pd.crosstab(d['shift'],d.line))
E
python3 $TMPDIR/e.py

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
m=pd.read_csv('maintenance.csv'); print(m.dtypes); print(m[m.event!='mold_cleaning']);
m['date']=pd.to_datetime(m.date)
c=m[m.event=='mold_cleaning']
for ln,g in c.groupby('line'): print(ln,g.date.sort_values().dt.strftime('%m-%d').tolist(), g.date.sort_values().diff().dt.days.tolist())
E
python3 $TMPDIR/c.py

cd /tmp/edabench_claude_nks0nb5p; cat >> $TMPDIR/c.py <<'E'
d['dsc']=np.nan
for ln,g in c.groupby('line'):
    cd=np.sort(g.date.values)
    idx=d.line==ln
    dv=d.loc[idx,'date'].values
    pos=np.searchsorted(cd,dv,side='right')-1
    d.loc[idx,'dsc']=(dv-cd[pos]).astype('timedelta64[D]').astype(int)
print(d.dsc.describe())
d['b']=pd.cut(d.dsc,[-1,2,5,8,11,14,17,20,25,30,40,80])
r=d.groupby('b').apply(lambda x:pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()}));print(r)
print(d.groupby(['line','b']).apply(lambda x:x.defective_units.sum()/x.units_produced.sum()).unstack(0).round(3))
d.to_pickle(T+'/d.pkl')
E
python3 $TMPDIR/c.py 2>&1 | tail -40

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m2.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
d['y']=d.defective_units/d.units_produced
d['rec']=d.sup.map({'SP-01':30,'SP-02':30,'SP-03':36}); d['dev']=d.cycle_time_s-d.rec
d['night']=(d['shift']=='Night').astype(int)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['dscm']=d.dsc.clip(upper=14)
def g(f,x):
    return smf.glm('y ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
x=d.dropna(subset=['mt','hv']).copy()
base='mt+hv+I(hv**2)+cycle_time_s+ambient_temp_c+machine_age_years+night+C(sup)+C(line)+dsc'
for f in [base, base+'+post', base.replace('cycle_time_s','dev'), base+'+dev', base+'+dscm']:
    m=g(f,x); print(f, round(m.deviance,1), round(m.scale,2))
m=g(base+'+post',x); print(m.summary().tables[1])
E
python3 $TMPDIR/m2.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m3.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl').dropna(subset=['mt'])
for ln in ['L1','L2','L3','L4']:
    g=d[(d.line==ln)&(d.date<'2025-04-01')]
    print(ln,smf.ols('mt~ambient_temp_c',g).fit().params.round(2).tolist())
a=d[d.line!='L1']
m=smf.ols('mt~ambient_temp_c+C(line)',a[a.date<'2025-04-01']).fit();print(m.params)
d['res']=d.mt-m.predict(d)
for ln in ['L1','L2','L3','L4']:
    g=d[d.line==ln]; print(ln,g.groupby(g.date.dt.to_period('2W')).res.mean().round(1).values)
E
python3 $TMPDIR/m3.py

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m3.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl').dropna(subset=['mt'])
a=d[(d.line!='L1')&(d.date<'2025-04-01')]
m=smf.ols('mt~ambient_temp_c',a).fit()
d['res']=d.mt-m.predict(d)
for ln in ['L1','L2','L3','L4']:
    g=d[d.line==ln]; print(ln,g.groupby(g.date.dt.to_period('2W')).res.mean().round(1).values)
E
python3 $TMPDIR/m3.py

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m4.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
a=d[(d.line!='L1')&(d.date<'2025-04-01')].dropna(subset=['mt'])
mm=smf.ols('mt~ambient_temp_c',a).fit(); d['res']=d.mt-mm.predict(d)
l=d[d.line=='L3'].sort_values('date')
print(l[['date','res']].iloc[[i for i in range(0,len(l))]].query("date>'2025-05-25' and date<'2025-07-05'").assign(date=lambda x:x.date.dt.strftime('%m-%d')).groupby('date').res.mean().round(1).to_string())
E
python3 $TMPDIR/m4.py

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m5.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
d['y']=d.defective_units/d.units_produced
d['night']=(d['shift']=='Night').astype(int)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
x=d.dropna(subset=['mt','hv']).copy()
f='y ~ mt+hv+I(hv**2)+cycle_time_s+ambient_temp_c+night+C(sup)+C(line)+dsc+post'
m=smf.glm(f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
x['exp']=m.predict(x)*x.units_produced
x['pe']=x.defective_units-x.exp
for ln in ['L1','L2','L3','L4']:
    g=x[x.line==ln]; w=g.groupby(g.date.dt.to_period('2W')).apply(lambda z:z.defective_units.sum()/z.exp.sum()); print(ln,w.round(2).values)
E
python3 $TMPDIR/m5.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat >> $TMPDIR/m5.py <<'E'
print()
for ln in ['L1','L2','L3','L4']:
    g=x[x.line==ln].sort_values('date')
    best=None
    for dt in sorted(g.date.unique())[10:-10]:
        s=(g.date>=dt)
        a=g[s];b=g[~s]
        # poisson-ish LL of ratio change
        r1=a.defective_units.sum()/a.exp.sum(); r0=b.defective_units.sum()/b.exp.sum()
        ll=(a.defective_units.sum()*np.log(r1)-r1*a.exp.sum())+(b.defective_units.sum()*np.log(r0)-r0*b.exp.sum())
        if best is None or ll>best[0]: best=(ll,dt,r0,r1)
    print(ln,best)
    ll=g.defective_units.sum(); 
E
python3 $TMPDIR/m5.py 2>&1 | tail -5

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/q.py <<'E'
import pandas as pd,numpy as np,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
d['rc']=d.rework_cost_eur/d.defective_units
for ln,dt in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=d[d.line==ln]; g=g.assign(p=g.date>=dt)
    print(ln,g.groupby('p')[['qc_inspection_min','rc','rework_cost_eur','units_produced','defective_units','cycle_time_s','mt','hv','ambient_temp_c','dsc']].mean().T.round(2))
    print(g.groupby('p')['shift'].value_counts(normalize=True).round(2))
E
python3 $TMPDIR/q.py

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m6.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
d['y']=d.defective_units/d.units_produced
d['night']=(d['shift']=='Night').astype(int)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['l3q']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
# L3 mt changepoint
a=d[(d.line!='L1')&(d.date<'2025-04-01')].dropna(subset=['mt'])
mm=smf.ols('mt~ambient_temp_c',a).fit(); d['res']=d.mt-mm.predict(d)
g=d[(d.line=='L3')].dropna(subset=['res']).sort_values('date')
best=min(((((g[g.date<t].res-g[g.date<t].res.mean())**2).sum()+((g[g.date>=t].res-g[g.date>=t].res.mean())**2).sum(),t) for t in g.date.unique()[20:-20]))
print(best, g[g.date<best[1]].res.mean(), g[g.date>=best[1]].res.mean())
d['l3t']=((d.line=='L3')&(d.date>=best[1])).astype(int)
x=d.dropna(subset=['mt','hv']).copy()
f='y ~ mt+hv+I(hv**2)+cycle_time_s+ambient_temp_c+night+C(sup)+C(line)+dsc+post+l3q+l3t'
m=smf.glm(f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
print(m.summary().tables[1])
x.to_pickle(T+'/x.pkl')
E
python3 $TMPDIR/m6.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m7.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
from scipy.optimize import minimize
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
def fitd(p,ret=False):
    d1,d3=p
    x['mc']=x.mt-d1*x.post-d3*x.l3t
    f='y ~ mc+hv+I(hv**2)+cycle_time_s+ambient_temp_c+night+C(sup)+C(line)+dsc+l3q'
    m=smf.glm(f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
    return m if ret else m.deviance
r=minimize(fitd,[7,5],method='Nelder-Mead',options={'xatol':.1,'fatol':.1});print(r.x,r.fun)
m=fitd(r.x,True);print(m.params.round(4))
print(fitd([0,0]), fitd([7,5.5]))
E
python3 $TMPDIR/m7.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m8.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
x['mc']=x.mt-7*x.post-5.5*x.l3t
def fit(f):
    m=smf.glm('y ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(); return m
b='hv+I(hv**2)+night+C(sup)+C(line)+dsc+l3q'
for f in ['mc+cycle_time_s+ambient_temp_c','mc+cycle_time_s','mc+I(mc**2)+cycle_time_s','mc+I(mc**2)+cycle_time_s+I(cycle_time_s**2)+ambient_temp_c','mc+cycle_time_s+ambient_temp_c+post+l3t', 'mc+cycle_time_s+ambient_temp_c+machine_age_years']:
    m=fit(f+'+'+b);print(f,round(m.deviance,1),m.params[['mc','ambient_temp_c','post','l3t','machine_age_years','I(mc ** 2)'] if False else [k for k in m.params.index if k in('mc','ambient_temp_c','post','l3t','machine_age_years','I(mc ** 2)','cycle_time_s')]].round(4).to_dict())
x['mb']=pd.cut(x.mc,[0,200,205,210,215,220,225,230,260])
x['cb']=pd.cut(x.cycle_time_s,[0,24,27,30,33,36,39,50])
m=fit('C(mb)+C(cb)+ambient_temp_c+'+b);print(m.params.filter(like='mb').round(3).to_string(),m.params.filter(like='cb').round(3).to_string(),m.params['ambient_temp_c'])
E
python3 $TMPDIR/m8.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m9.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
x['mc']=x.mt-7*x.post-5.5*x.l3t
def fit(f):
    return smf.glm('y ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
b='mc+cycle_time_s+hv+I(hv**2)+night+C(sup)+C(line)+dsc+l3q'
l2=x[x.line=='L2'].sort_values('date')
res=[]
for t in pd.date_range('2025-05-20','2025-07-20'):
    x['r2']=((x.line=='L2')&(x.date>=t)).astype(int)
    m=fit(b+'+r2+ambient_temp_c');res.append((m.deviance,t,m.params['r2'],m.params['ambient_temp_c']))
print(min(res)); 
for r in res[::4]: print(r[1].date(),round(r[0],1))
t=min(res)[1]; x['r2']=((x.line=='L2')&(x.date>=t)).astype(int)
for f in ['+ambient_temp_c','','+ambient_temp_c+machine_age_years','+ambient_temp_c+C(operator_id)','+ambient_temp_c+post+l3t']:
    m=fit(b+'+r2'+f);print(f,round(m.deviance,1),m.params.filter(regex='^(mc|r2|ambient|machine|night|post|l3t)').round(4).to_dict())
print(x[x.line=='L2'].query("date>='2025-06-10' and date<='2025-06-22'")[['date','y','dsc']].sort_values('date').to_string())
E
python3 $TMPDIR/m9.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m10.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
from scipy import stats
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
x['mc']=x.mt-7*x.post-5.5*x.l3t
x['r2']=((x.line=='L2')&(x.date>='2025-06-16')).astype(int)
x['night']=(x['shift']=='Night').astype(int)
def fit(f):
    return smf.glm('y ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
full='mc+cycle_time_s+hv+I(hv**2)+night+C(sup)+C(line)+dsc+l3q+r2+ambient_temp_c+machine_age_years+C(operator_id)'
m=fit(full); disp=m.pearson_chi2/m.df_resid; print('disp',disp,m.df_resid)
for drop in ['mc','cycle_time_s','hv+I(hv**2)','night','ambient_temp_c','machine_age_years','C(operator_id)','C(sup)','dsc']:
    f=full.replace(drop+'+','').replace('+'+drop,'') if drop!='hv+I(hv**2)' else full.replace('hv+I(hv**2)+','')
    m0=fit(f); dd=m0.df_resid-m.df_resid
    F=(m0.deviance-m.deviance)/dd/disp; print(drop,round(F,2),dd,stats.f.sf(F,dd,m.df_resid))
# within-line machine age
for ln in ['L1','L2','L3','L4']:
    g=x[x.line==ln]
    mm=smf.glm('y ~ mc+cycle_time_s+hv+I(hv**2)+night+C(sup)+dsc+machine_age_years',g,family=sm.families.Binomial(),var_weights=g.units_produced).fit(scale='X2');print(ln,mm.params['machine_age_years'],mm.pvalues['machine_age_years'])
E
python3 $TMPDIR/m10.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m11.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
from scipy import stats
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
x['mc']=x.mt-7*x.post-5.5*x.l3t
x['r2']=((x.line=='L2')&(x.date>='2025-06-16')).astype(int)
x['night']=(x['shift']=='Night').astype(int)
def fit(f):
    return smf.glm('y ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
b='mc+cycle_time_s+night+C(sup)+C(line)+dsc+l3q+r2'
for f in ['+hv+I(hv**2)','+C(sup)*(hv+I(hv**2))','+C(sup)*(hv+I(hv**2))+ambient_temp_c','+C(sup)*(hv+I(hv**2))+C(sup):mc+C(sup):cycle_time_s+C(sup):night']:
    m=fit(b+f);print(f,round(m.deviance,1),round(m.pearson_chi2/m.df_resid,2),m.params.filter(regex='hv|ambient').round(4).to_dict())
E
python3 $TMPDIR/m11.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m12.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
x['mc']=x.mt-7*x.post-5.5*x.l3t
x['r2']=((x.line=='L2')&(x.date>='2025-06-16')).astype(int)
x['night']=(x['shift']=='Night').astype(int)
x['hb']=pd.cut(x.hv,list(range(10,80,5)))
for s in ['SP-01','SP-02','SP-03']:
    g=x[x.sup==s]
    m=smf.glm('y ~ 0+C(hb)+mc+cycle_time_s+night+C(line)+dsc+l3q+r2',g,family=sm.families.Binomial(),var_weights=g.units_produced).fit()
    print(s,round(m.deviance,1),len(g)); print(m.params.filter(like='hb').round(2).values, g.hb.value_counts().sort_index().values)
E
python3 $TMPDIR/m12.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m13.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
x['mc']=x.mt-7*x.post-5.5*x.l3t
x['r2']=((x.line=='L2')&(x.date>='2025-06-16')).astype(int)
x['night']=(x['shift']=='Night').astype(int)
g=x[x.sup=='SP-01'].copy()
hs=np.linspace(x.hv.min(),x.hv.max(),500)
rest='+mc+cycle_time_s+night+C(line)+dsc+l3q+r2'
for name,f in [('quad','hv+I(hv**2)'),('cubic','hv+I(hv**2)+I(hv**3)'),('cr4','cr(hv,df=4)'),('cr5','cr(hv,df=5)'),('cr6','cr(hv,df=6)'),('bs4','bs(hv,df=4)')]:
    m=smf.glm('y ~ '+f+rest,g,family=sm.families.Binomial(),var_weights=g.units_produced).fit()
    ref=g.iloc[[0]].copy()
    p=[]
    D=pd.concat([ref]*len(hs));D['hv']=hs
    pr=m.predict(D); print(name,round(m.deviance,1),hs[np.argmin(pr.values)].round(1))
print(g.hv.min(),g.hv.max())
# all suppliers: shared base + alpha hinge
for h1 in [30,35,40,45]:
    x['al']=(x.sup=='SP-01').astype(int); x['hh']=x.al*np.clip(x.hv-h1,0,None)
    m=smf.glm('y ~ hv+I(hv**2)+hh+C(sup)'+rest,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(); print(h1,round(m.deviance,1))
E
python3 $TMPDIR/m13.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat >> $TMPDIR/m13.py <<'E'
print('---')
for s in ['SP-02','SP-03']:
    h=x[x.sup==s]; m=smf.glm('y ~ hv+I(hv**2)'+rest,h,family=sm.families.Binomial(),var_weights=h.units_produced).fit(); print(s,-m.params['hv']/(2*m.params['I(hv ** 2)']))
res=[]
for h1 in range(10,36,2):
    x['hh']=x.al*np.clip(x.hv-h1,0,None)
    m=smf.glm('y ~ hv+I(hv**2)+hh+C(sup)'+rest,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
    D=x[x.sup=='SP-01'].iloc[[0]]; D=pd.concat([D]*len(hs)); D['hv']=hs; D['al']=1; D['hh']=np.clip(hs-h1,0,None)
    print(h1,round(m.deviance,1),hs[np.argmin(m.predict(D).values)].round(1))
E
python3 $TMPDIR/m13.py 2>&1 | grep -v -i warn | sed -n '/---/,$p'

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m14.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
x=pd.read_pickle(T+'/x.pkl')
x['mc']=x.mt-7*x.post-5.5*x.l3t
x['r2']=((x.line=='L2')&(x.date>='2025-06-16')).astype(int)
x['night']=(x['shift']=='Night').astype(int)
x['db']=pd.cut(x.dsc,[-1,0,2,4,6,8,10,12,14,16,18,22,26,30,40,80])
base='mc+cycle_time_s+night+C(sup)*(hv+I(hv**2))+C(line)+l3q+r2'
m=smf.glm('y ~ '+base+'+C(db)',x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
print(m.deviance, m.params.filter(like='db').round(3).to_string()); print(x.db.value_counts().sort_index().values)
for f in ['dsc','dsc+I(dsc**2)','np.log1p(dsc)','I(dsc.clip(upper=30))','I(dsc.clip(upper=14))+I((dsc-14).clip(lower=0))']:
    m=smf.glm('y ~ '+base+'+'+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(); print(f,round(m.deviance,1),m.params.filter(like='dsc').round(4).to_dict())
E
python3 $TMPDIR/m14.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat > $TMPDIR/m15.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
d['y']=d.defective_units/d.units_produced
d['night']=(d['shift']=='Night').astype(int)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['l3q']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['l3t']=((d.line=='L3')&(d.date>='2025-05-19')).astype(int)
d['r2']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['mc']=d.mt-7*d.post-5.5*d.l3t
d['dsc2']=d.dsc%14
d['dsc14']=d.dsc.clip(upper=14); 
x=d.dropna(subset=['mc','hv']).copy()
base='mc+cycle_time_s+night+C(sup)*(hv+I(hv**2))+C(line)+l3q+r2'
total=d.defective_units.sum(); U=d.units_produced.sum()
specs={'lin':'dsc','quad':'dsc+I(dsc**2)','clip30':'I(dsc.clip(upper=30))','pw':'I(dsc.clip(upper=14))+I((dsc-14).clip(lower=0))',
 'bins':'C(pd.cut(dsc,[-1,0,2,4,6,8,10,12,14,16,18,22,26,30,40,80]))'}
for k,f in specs.items():
    m=smf.glm('y ~ '+base+'+'+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
    x['dsc_o']=x.dsc
    p0=m.predict(x)
    x2=x.copy(); x2['dsc']=x.dsc%14; p1=m.predict(x2)
    # scale observed defects by odds ratio ratio
    new=(x.defective_units*(p1/p0)).sum()+0
    # full pop: apply same relative reduction to non-modelled rows
    red=1-((x.defective_units*(p1/p0)).sum()/x.defective_units.sum())
    rest=d.loc[~d.index.isin(x.index)]
    newtot=(x.defective_units*(p1/p0)).sum()+rest.defective_units.sum()*(1-red)
    print(k,round(m.deviance,1),'pred-based',round(((p1*x.units_produced).sum()+ (p0*x.units_produced).sum()*0)/x.units_produced.sum(),5),'scaled',round(newtot/U,5), 'orig',round(total/U,5),'red',round(red,4))
E
python3 $TMPDIR/m15.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_nks0nb5p; cat >> $TMPDIR/m15.py <<'E'
print('---C1')
m=smf.glm('y ~ '+base+'+'+specs['quad'],x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
rec={'SP-01':30,'SP-02':30,'SP-03':36}
for mode in ['shift','fixed']:
  for s in rec:
    x2=x.copy(); x2['sup']=s
    if mode=='shift': x2['cycle_time_s']=x.cycle_time_s-x.sup.map(rec)+rec[s]
    else: x2['cycle_time_s']=rec[s]
    p=m.predict(x2); print(mode,s,round((p*x.units_produced).sum()/x.units_produced.sum(),5))
print(m.params.filter(like='sup').round(3))
E
python3 $TMPDIR/m15.py 2>&1 | sed -n '/---C1/,$p'

cd /tmp/edabench_claude_nks0nb5p; cat >> $TMPDIR/m15.py <<'E'
print('---B1')
b2='mc+cycle_time_s+night+C(sup)*(hv+I(hv**2))+C(line)+l3q+r2+I(dsc+0)+I(dsc**2)'
x['post']=d.post; x['l3t']=d.l3t
for extra in ['','+ambient_temp_c','+ambient_temp_c+post+l3t','+ambient_temp_c+post+l3t+I(mc**2)','+ambient_temp_c+C(line):dsc']:
    m=smf.glm('y ~ '+b2+extra,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
    print(extra,round(m.deviance,1),m.params.filter(regex='ambient|post|l3t|mc').round(4).to_dict(), m.pvalues.get('ambient_temp_c'))
E
python3 $TMPDIR/m15.py 2>&1 | sed -n '/---B1/,$p'

cd /tmp/edabench_claude_nks0nb5p; cat >> $TMPDIR/m15.py <<'E'
print('---prof')
from scipy.optimize import minimize
def dev(p,ret=False):
    x['mc']=x.mt-p[0]*x.post-p[1]*x.l3t
    m=smf.glm('y ~ mc+cycle_time_s+night+C(sup)*(hv+I(hv**2))+C(line)+l3q+r2+dsc+I(dsc**2)',x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
    return m if ret else m.deviance
for p in [(0,0),(7,0),(7,5.5),(0,5.5),(10,0),(12,0),(14,0),(7,3),(7,8)]: print(p,round(dev(p),1))
r=minimize(dev,[7,3],method='Nelder-Mead',options={'xatol':.2,'fatol':.1});print(r.x,r.fun)
E
python3 $TMPDIR/m15.py 2>&1 | sed -n '/---prof/,$p'

cd /tmp/edabench_claude_nks0nb5p; sed -i 's/d\[.mc.\]=d.mt-7\*d.post-5.5\*d.l3t/d["mc"]=d.mt-7.5*d.post/' $TMPDIR/m15.py; sed -i '/---B1/,$d' $TMPDIR/m15.py; cat >> $TMPDIR/m15.py <<'E'
for o in [0,7,7.5,7.7]:
    print(o, (d.mt-o*d.post).median())
E
python3 $TMPDIR/m15.py 2>&1 | grep -v -i warn
