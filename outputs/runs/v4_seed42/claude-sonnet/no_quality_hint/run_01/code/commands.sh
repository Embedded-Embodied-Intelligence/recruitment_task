cd /tmp/edabench_claude_l8253_m_; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.describe().T)
for c in ['shift','operator_id','supplier_code','line']: print(b[c].value_counts(dropna=False))
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
print(b.production_date.str[:3].value_counts().head(20))
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(b[c],errors='coerce'); print(c,x.isna().sum(),x.min(),x.median(),x.max()); print(b[c][x.isna()].value_counts(dropna=False).head())
E
python3 -I $TMPDIR/a.py; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/l.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
b=b.drop_duplicates()
print(len(b), b.batch_id.duplicated().sum())
s=b.production_date
iso=s.str.match(r'\d{4}-')
b['date']=pd.to_datetime(s.where(iso),errors='coerce').fillna(pd.to_datetime(s.where(~iso),format='%m/%d/%Y',errors='coerce'))
print(b.date.isna().sum(),b.date.min(),b.date.max())
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
print(b.mold_temp.describe()); print(np.histogram(b.mold_temp,bins=[-1,1,100,150,180,250,300,400,500]))
print(b[b.mold_temp<150].groupby('line').size(), b[b.mold_temp>300].groupby('line').size())
print(b[(b.mold_temp>300)].mold_temp.describe())
print(b[b.mold_temp==0].date.describe())
print((b.humidity_pct.isna()|(b.humidity_pct<0)).sum(), b.humidity_pct[b.humidity_pct<=0].value_counts())
print(b.humidity_pct.describe())
b.to_pickle('/tmp/edabench_claude_l8253_m_/../claude-0/b.pkl') if False else None
b.to_pickle('b.pkl')
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning'])
E
python3 -I $TMPDIR/l.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/l2.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
s=b.production_date
print(s[~s.str.match(r'\d{4}-')].head(20).tolist())
sl=s[s.str.contains('/')]
a=sl.str.split('/',expand=True).astype(int)
print((a[0]>12).sum(),(a[1]>12).sum(),len(a), a[2].unique())
iso=s[s.str.match(r'\d{4}-')]; print(len(iso), iso.min(), iso.max())
E
python3 -I $TMPDIR/l2.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/d.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
b=b.drop_duplicates().reset_index(drop=True)
s=b.production_date
def cands(x):
    if x[4]=='-': return [pd.Timestamp(x)]
    p,q,y=map(int,x.split('/'))
    c=[]
    for mo,d in ((p,q),(q,p)):
        if mo<=12:
            t=pd.Timestamp(y,mo,d)
            if pd.Timestamp('2025-01-06')<=t<=pd.Timestamp('2025-09-30'): c.append(t)
    return c
C=s.map(cands)
print(C.map(len).value_counts())
# unambiguous series
u=C.map(lambda c:c[0] if len(set(c))==1 else pd.NaT)
print(u.isna().sum(), u.dropna().is_monotonic_increasing)
uf=u.ffill().bfill()
out=[]
for i,c in enumerate(C):
    c=list(set(c)); out.append(min(c,key=lambda t:abs((t-uf[i]).days)))
b['date']=pd.Series(out)
print(b.date.is_monotonic_increasing, (b.date.diff().dt.days<0).sum())
b.to_pickle('b0.pkl')
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_l8253_m_; cat >> $TMPDIR/d.py <<'E'
d=u.dropna()
print((d.diff().dt.days<0).sum())
x=d[d.diff().dt.days<0].index[:5]; print(x)
print(b.production_date[x[0]-3:x[0]+3].tolist())
print(b.groupby(b.date.dt.day_name()).size())
E
python3 -I $TMPDIR/d.py | tail -15

cd /tmp/edabench_claude_l8253_m_; cat >> $TMPDIR/d.py <<'E'
ref=u.astype('int64').where(u.notna()).rolling(11,center=True,min_periods=1).median().ffill().bfill()
out=[]
for i,c in enumerate(C):
    c=list(set(c)); out.append(min(c,key=lambda t:abs(t.value-ref[i])))
b['date']=pd.Series(out)
print((b.date.diff().dt.days<0).sum(), (b.date.diff().dt.days.abs()>3).sum())
b.to_pickle('b0.pkl')
E
python3 -I $TMPDIR/d.py | tail -2

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/e.py <<'E'
import pandas as pd, numpy as np
b=pd.read_pickle('b0.pkl')
print(b[['production_date','date','line']].iloc[60:80])
print(b.date.diff().dt.days.abs().describe())
print(b[b.date.diff().dt.days.abs()>3][['production_date','date']].head(10))
print(b.groupby('date').size().describe())
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/f.py <<'E'
import pandas as pd, numpy as np
b=pd.read_pickle('b0.pkl')
b['sup']=b.supplier_code.str.strip().str.upper()
b['sh']=b['shift'].str.strip().str.upper().str[0]
b['rate']=b.defective_units/b.units_produced
print(b.groupby('line').mold_temp.apply(lambda x:(x>300).mean()))
l3=b[b.line=='L3']; print(l3.groupby(l3.date.dt.to_period('M')).mold_temp.apply(lambda x:(x>300).mean()))
mt=b.mold_temp.copy()
mt[mt==0]=np.nan
mt=mt.where(~(mt>300),(mt-32)/1.8)
b['mt']=mt
print(mt.median(), mt.describe())
for ln,g in b.groupby('line'):
    print(ln, g.groupby(g.date.dt.to_period('M')).mt.median().round(1).tolist())
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
print(b.hum.isna().sum(), b.defective_units.sum()/b.units_produced.sum())
print((b.defective_units>b.units_produced).sum())
b.to_pickle('b1.pkl')
E
python3 -I $TMPDIR/f.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/g.py <<'E'
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b1.pkl')
b['ok']=b.units_produced-b.defective_units
print(b[['rate','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur','units_produced']].corr().round(2)['rate'])
print(b.groupby('sup').rate.mean(), b.groupby('sh').rate.mean(), b.groupby('line').rate.mean())
print(b.groupby('operator_id').rate.mean().describe())
print(b.groupby('sup').cycle_time_s.describe())
d=b.dropna(subset=['mt','hum'])
f='rate~mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+sh+C(sup)+C(line)'
m=smf.glm('ok+defective_units~mt+hum+I(hum**2)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+sh+C(sup)+C(line)',d,family=sm.families.Binomial()) if False else None
m=smf.glm('rate~mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+sh+C(sup)+C(line)',d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit()
print(m.summary().tables[1])
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/h.py <<'E'
import pandas as pd, numpy as np
b=pd.read_pickle('b1.pkl')
print(pd.crosstab(b.operator_id,b.line).head(24))
print(b.groupby('line').machine_age_years.describe())
print(b.groupby('line').ambient_temp_c.describe())
print(pd.crosstab(b.sup,b.line)); print(pd.crosstab(b.sh,b.line))
print(b.groupby('sup').hum.describe())
b['m']=b.date.dt.month
print(b.groupby('m')[['ambient_temp_c','hum','mt','cycle_time_s']].mean())
print(b[['mt','hum','cycle_time_s','machine_age_years','ambient_temp_c']].corr().round(2))
print(b.groupby('line').apply(lambda g:g.groupby('m').rate.mean().round(3).tolist()))
E
python3 -I $TMPDIR/h.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/i.py <<'E'
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b1.pkl')
sp=pd.read_csv('suppliers.csv'); print(sp)
b=b.merge(sp[['supplier_code','pre_dried','recipe_cycle_time_s']].rename(columns={'supplier_code':'sup'}),on='sup')
b['dev']=b.cycle_time_s-b.recipe_cycle_time_s
b['t']=(b.date-b.date.min()).dt.days
b['ok']=b.units_produced-b.defective_units
b.to_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    m=smf.glm(f,d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit(scale='X' ,cov_type='HC0') if False else smf.glm('rate~'+f,d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit(scale='X')
    return m
m=fit('mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried)+C(pre_dried):hum+cycle_time_s+dev+machine_age_years+sh+C(sup)+C(line)+C(operator_id)')
print(m.summary().tables[1], m.scale)
E
python3 -I $TMPDIR/i.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_l8253_m_; python3 - <<'E'
import re
s=open('/tmp/claude-0/i.py').read() if False else None
E
sed -i "s/scale='X'/scale='x2'/; s/m=fit(.*/m=fit('mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried):hum+C(pre_dried):I(hum**2)+cycle_time_s+dev+machine_age_years+sh+C(sup)+C(line)+C(operator_id)')/" $TMPDIR/i.py; python3 -I $TMPDIR/i.py 2>&1 | grep -v -i warn | tail -50

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/h2.py <<'E'
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    return smf.glm('I(defective_units)+I(ok) ~ '.replace('I(defective_units)+I(ok)','ok+defective_units')+f,d,family=sm.families.Binomial()).fit(scale='x2')
m=fit('mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried):hum+C(pre_dried):I(hum**2)+cycle_time_s+dev+machine_age_years+sh+C(sup)+C(line)')
print(m.summary().tables[1], m.scale)
m=fit('mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried):hum+C(pre_dried):I(hum**2)+cycle_time_s+dev+machine_age_years+sh+C(sup)+C(operator_id)')
print(m.summary().tables[1], m.scale)
E
python3 -I $TMPDIR/h2.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/h2.py <<'E'
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from patsy import dmatrices
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    X=dmatrices('defective_units ~ '+f,d,return_type='dataframe')[1]
    y=np.c_[d.defective_units,d.ok]
    return sm.GLM(y,X,family=sm.families.Binomial()).fit(scale='x2')
if __name__=='__main__':
  for f in ['mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried):hum+C(pre_dried):I(hum**2)+cycle_time_s+dev+machine_age_years+sh+C(sup)+C(line)',
          'mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried):hum+C(pre_dried):I(hum**2)+cycle_time_s+dev+machine_age_years+sh+C(sup)+C(operator_id)']:
    m=fit(f); print(m.summary().tables[1], m.scale)
E
python3 -I $TMPDIR/h2.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/h3.py <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0')
from h2 import *
for f in ['mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried):hum+C(pre_dried):I(hum**2)+dev+I(dev**2)+machine_age_years+sh+C(sup)+C(line)',
          'mt+ambient_temp_c+hum+I(hum**2)+C(pre_dried):hum+C(pre_dried):I(hum**2)+dev+I(dev**2)+machine_age_years+sh+C(sup)+C(operator_id)']:
    m=fit(f); print(m.summary().tables[1], m.scale, m.pearson_chi2, m.df_resid)
E
python3 -I $TMPDIR/h3.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/j.py <<'E'
import pandas as pd, numpy as np
b=pd.read_pickle('b2.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']); m=m[m.event=='mold_cleaning']
print(m.groupby('line').date.apply(lambda s:s.sort_values().diff().dt.days.tolist()))
print(m.groupby('line').date.agg(['min','max','count']))
# days since last cleaning: cleaning before first shift so same-day counts as 0
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
b['dsc']=b.apply(ds,axis=1)
print(b.dsc.describe(), b.dsc.isna().sum())
b.to_pickle('b3.pkl')
print(b.groupby(pd.cut(b.dsc,[-1,0,2,5,8,11,14,17,20,25,30,60])).agg(rate=('rate','mean'),n=('rate','size')))
E
python3 -I $TMPDIR/j.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/k.py <<'E'
import pandas as pd, numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b3.pkl')
b['post']=(b.date>='2025-04-14').astype(int)
for ln,g in b.dropna(subset=['mt']).groupby('line'):
    for p,h in g.groupby('post'):
        r=smf.ols('mt~ambient_temp_c',h).fit(); print(ln,p,len(h),r.params.round(3).tolist(), round(r.resid.std(),2))
g=b[(b.line=='L1')].dropna(subset=['mt']).copy()
g['wk']=g.t//7
r=smf.ols('mt~ambient_temp_c',g).fit(); g['res']=r.resid
print(g.groupby(g.date.dt.to_period('W')).res.mean().round(1).to_string())
E
python3 -I $TMPDIR/k.py

cd /tmp/edabench_claude_l8253_m; cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/k2.py <<'E'
import pandas as pd, numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b3.pkl').dropna(subset=['mt'])
ref=b[b.line.isin(['L2','L4'])]
r=smf.ols('mt~ambient_temp_c',ref).fit(); print(r.params)
b['res']=b.mt-r.predict(b)
b['mo']=b.date.dt.to_period('M')
print(b.pivot_table(index='mo',columns='line',values='res').round(1))
x=b[b.line=='L1']; x=x[x.date.between('2025-03-01','2025-05-31')]
print(x.groupby(x.date.dt.to_period('W')).res.agg(['mean','size']).round(1))
E
python3 -I $TMPDIR/k2.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/k3.py <<'E'
import pandas as pd, numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b3.pkl').dropna(subset=['mt'])
ref=b[b.line.isin(['L2','L4'])]
r=smf.ols('mt~ambient_temp_c',ref).fit()
b['res']=b.mt-r.predict(b)
for ln in ['L1','L3']:
    x=b[b.line==ln].sort_values('date')
    best=None
    for d in x.date.unique():
        a=x[x.date<d].res; c=x[x.date>=d].res
        if len(a)<30 or len(c)<30: continue
        sse=((a-a.mean())**2).sum()+((c-c.mean())**2).sum()
        if best is None or sse<best[0]: best=(sse,d,a.mean(),c.mean())
    print(ln,best)
x=b[b.line=='L3']; print(x.groupby(x.date.dt.to_period('W')).res.mean().round(1)['2025-05':'2025-07'])
E
python3 -I $TMPDIR/k3.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/m.py <<'E'
import pandas as pd, numpy as np, statsmodels.api as sm
b=pd.read_pickle('b3.pkl')
b['L1p']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
b['L3p']=((b.line=='L3')&(b.date>='2025-05-19')).astype(int)
b['hum2']=b.hum**2
b['pdry']=(b.pre_dried=='yes').astype(int)
b['hp']=b.hum*b.pdry; b['h2p']=b.hum2*b.pdry
b['N']=(b.sh=='N').astype(int)
b['over']=(b.dsc-14).clip(lower=0)
d=b.dropna(subset=['mt','hum']).copy()
def G(cols,d=d,show=True):
    X=pd.get_dummies(d[cols],drop_first=True,dtype=float); X=sm.add_constant(X)
    m=sm.GLM(d.rate,X,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
    return m
base=['mt','ambient_temp_c','hum','hum2','hp','h2p','dev','machine_age_years','N','sup','line','dsc']
m=G(base); print(m.summary().tables[1],m.scale)
m=G(base+['L1p','L3p']); print(m.params[['L1p','L3p']],m.bse[['L1p','L3p']])
E
python3 -I $TMPDIR/m.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/n.py <<'E'
import pandas as pd, numpy as np
exec(open('/tmp/claude-0/m.py').read().split("def G")[0])
c=d[~((d.L1p==1)|(d.L3p==1))]
c['hb']=pd.cut(c.hum,[0,10,15,20,25,30,35,40,45,50,60,80])
print(c.pivot_table(index='hb',columns='sup',values='rate',aggfunc='mean').round(3))
c['cb']=pd.cut(c.dev,[-20,-6,-4,-2,-1,1,2,4,6,20])
print(c.pivot_table(index='cb',columns='sup',values='rate',aggfunc='mean').round(3))
c['mb']=pd.cut(c.mt,[180,200,205,210,215,220,225,245])
print(c.pivot_table(index='mb',columns='sup',values='rate',aggfunc='mean').round(3))
c['ab']=pd.cut(c.machine_age_years,[0,3,5,7,9,12,15,18,22])
print(c.pivot_table(index='ab',columns='line',values='rate',aggfunc='mean').round(3))
print(c.groupby(['line','sup']).rate.mean().unstack().round(3))
E
python3 -I $TMPDIR/n.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/o.py <<'E'
import pandas as pd, numpy as np
exec(open('/tmp/claude-0/m.py').read().split("base=")[0])
dd=b.dropna(subset=['hum']).copy()
b['hbin']=0
def H(d):
    d=d.copy()
    d['hlo']=(25-d.hum).clip(lower=0); d['hhi']=(d.hum-45).clip(lower=0)
    return d
for name,data,cols in [
 ('clean mt', d[(d.L1p==0)&(d.L3p==0)], ['mt','ambient_temp_c']),
 ('clean mt only', d[(d.L1p==0)&(d.L3p==0)], ['mt']),
 ('clean amb only', d[(d.L1p==0)&(d.L3p==0)], ['ambient_temp_c']),
 ('all amb only', dd, ['ambient_temp_c','L1p','L3p']),
 ('all mt+amb dummies', d, ['mt','ambient_temp_c','L1p','L3p']),
 ('all mt dummies', d, ['mt','L1p','L3p']),
]:
    x=H(data)
    m=G(cols+['hum','hum2','hp','h2p','dev','machine_age_years','N','sup','line','dsc'],x)
    print(name,len(x)); print(m.params[[c for c in cols]+['dsc','machine_age_years']].round(4).to_dict(), m.bse[cols].round(4).to_dict())
E
python3 -I $TMPDIR/o.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/p.py <<'E'
import pandas as pd, numpy as np
exec(open('/tmp/claude-0/m.py').read().split("base=")[0])
dd=b.dropna(subset=['hum']).copy()
cols=['ambient_temp_c','hum','hum2','hp','h2p','dev','machine_age_years','N','sup','line','dsc']
m=G(cols,dd)
dd['mu']=m.predict(sm.add_constant(pd.get_dummies(dd[cols],drop_first=True,dtype=float)))
dd['res']=(dd.defective_units-dd.mu*dd.units_produced)
dd['pr']=dd.res/np.sqrt(dd.mu*(1-dd.mu)*dd.units_produced)
print(dd.pr.std())
for ln,x in dd.groupby('line'):
    x=x.sort_values('date')
    best=None
    for dt in x.date.unique():
        a=x[x.date<dt].pr; c=x[x.date>=dt].pr
        if len(a)<40 or len(c)<40: continue
        sse=((a-a.mean())**2).sum()+((c-c.mean())**2).sum()
        if best is None or sse<best[0]: best=(sse,dt,a.mean(),c.mean(),len(a),len(c))
    print(ln,best, ((x.pr-x.pr.mean())**2).sum())
    print(x.groupby(x.date.dt.to_period('M')).pr.mean().round(2).tolist())
E
python3 -I $TMPDIR/p.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat >> $TMPDIR/p.py <<'E'
print('----')
x=dd[dd.line=='L2'].sort_values('date')
amb=~x.production_date.map(lambda s:False)
for dt in pd.date_range('2025-06-08','2025-06-30'):
    x['s']=(x.date>=dt).astype(float)
    X=sm.add_constant(x[['s']]); 
    # offset logit(mu)
    off=np.log(x.mu/(1-x.mu))
    mm=sm.GLM(x.rate,X,family=sm.families.Binomial(),var_weights=x.units_produced,offset=off).fit()
    print(dt.date(), round(mm.llf,1), round(mm.params['s'],3))
print(x[(x.date>='2025-06-14')&(x.date<='2025-06-24')][['production_date','date','rate','mu','pr','dsc']].to_string())
E
python3 -I $TMPDIR/p.py 2>&1 | sed -n '/----/,$p'

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/q.py <<'E'
import pandas as pd, numpy as np
exec(open('/tmp/claude-0/m.py').read().split("base=")[0])
from scipy import stats
cl=d[(d.L1p==0)&(d.L3p==0)].copy()
cl['dsc2']=(cl.dsc-14).clip(lower=0)
base=['mt','ambient_temp_c','hum','hum2','hp','h2p','dev','machine_age_years','N','sup','line','dsc','dsc2']
def run(data,cols,lab):
    m=G(cols,data); return m
def Fdrop(data,cols,drop):
    full=G(cols,data); red=G([c for c in cols if c not in drop],data)
    k=full.df_model-red.df_model
    F=((red.deviance-full.deviance)/k)/full.scale
    return round(F,2),k,round(1-stats.f.cdf(F,k,full.df_resid),4)
for nm,dat in [('clean',cl),('L2L4',cl[cl.line.isin(['L2','L4'])]),('L1L2L3pre',cl[cl.line!='L4'])]:
    cols=[c for c in base if (c!='line' or dat.line.nunique()>1) and (c!='sup' or True)]
    m=G(cols,dat)
    print(nm,len(dat),m.scale.round(2)); print(m.params.round(4).to_dict()); print(m.pvalues.round(4).to_dict())
dat=cl.copy()
dat['op']=dat.operator_id
print('operators within line', Fdrop(dat.assign(opd=dat.operator_id),base+['opd'],['opd']))
E
python3 -I $TMPDIR/q.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/r.py <<'E'
import pandas as pd, numpy as np
exec(open('/tmp/claude-0/m.py').read().split("base=")[0])
b['L2p']=((b.line=='L2')&(b.date>='2025-06-19')).astype(int)
d=b.dropna(subset=['mt','hum']).copy()
cl=d[(d.L1p==0)&(d.L3p==0)].copy()
cl['db']=pd.cut(cl.dsc,[-1,2,5,8,11,13,14,16,19,23,40]).astype(str)
base=['mt','ambient_temp_c','hum','hum2','hp','h2p','dev','N','sup','line','L2p']
m=G(base+['db'],cl); print(m.params.filter(like='db').round(3)); print(m.params.round(3).to_dict(), m.scale)
cl['dev2']=cl.dev**2
cl['dvb']=pd.cut(cl.dev,[-30,-8,-5,-3,-1,1,3,5,8,30]).astype(str)
m=G(base+['dsc','dvb'],cl); print(m.params.filter(like='dvb').round(3))
E
python3 -I $TMPDIR/r.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/s.py <<'E'
import pandas as pd, numpy as np
exec(open('/tmp/claude-0/m.py').read().split("base=")[0])
b['L2p']=((b.line=='L2')&(b.date>='2025-04-14')&False|(b.line=='L2')&(b.date>='2025-06-19')).astype(int)
d=b.dropna(subset=['mt','hum']).copy()
cl=d[(d.L1p==0)&(d.L3p==0)].copy()
edges=[0,15,20,25,30,35,40,45,50,55,60,80]
cl['hb']=pd.cut(cl.hum,edges).astype(str)
for sp in ['SP-01','SP-02','SP-03']:
    x=cl[cl.sup==sp]
    m=G(['mt','hb','dev','N','line','L2p','dsc'],x)
    p=m.params.filter(like='hb'); print(sp,len(x), m.scale.round(2)); print(p.round(3).to_dict())
E
python3 -I $TMPDIR/s.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat >> $TMPDIR/s.py <<'E'
print('---')
x=cl[cl.sup=='SP-01'].copy()
for deg in (2,3,4):
    cols=['mt','dev','N','line','L2p','dsc']
    x['h']=(x.hum-35)/10
    for k in range(1,deg+1): x[f'h{k}']=x.h**k
    m=G(cols+[f'h{k}' for k in range(1,deg+1)],x)
    g=np.linspace(12.1,72.3,2000); h=(g-35)/10
    f=sum(m.params[f'h{k}']*h**k for k in range(1,deg+1))
    print(deg,g[f.argmin()],m.llf if hasattr(m,'llf') else '', m.deviance)
# using all data incl. post dummies L1/L3 with mt dummies
x2=d[d.sup=='SP-01'].copy(); x2['h']=(x2.hum-35)/10; x2['h1']=x2.h; x2['h2']=x2.h**2
m=G(['mt','dev','N','line','L2p','dsc','h1','h2','L1p','L3p'],x2); print(-m.params['h1']/(2*m.params['h2'])*10+35, m.params[['L1p','L3p','mt']])
E
python3 -I $TMPDIR/s.py 2>&1 | sed -n '/---/,$p'

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/t.py <<'E'
import pandas as pd, numpy as np, statsmodels.api as sm
b=pd.read_pickle('b3.pkl')
b['L2p']=((b.line=='L2')&(b.date>='2025-06-19')).astype(int)
off={'L1':(pd.Timestamp('2025-04-14'),6.65),'L3':(pd.Timestamp('2025-05-19'),5.65)}
b['mtc']=b.mt
for ln,(dt,o) in off.items():
    b.loc[(b.line==ln)&(b.date>=dt),'mtc']-=o
print('A4 median corrected',b.mtc.median(),'uncorrected',b.mt.median(), b.mtc.notna().sum())
b['hum']=b.hum
b['N']=(b.sh=='N').astype(float)
b['L1p']=((b.line=='L1')&(b.date>='2025-04-14')).astype(float); b['L3p']=((b.line=='L3')&(b.date>='2025-05-19')).astype(float)
def design(df,sup=None,dev=None,dsc=None,hum=None):
    df=df.copy()
    if sup is not None: df['sup']=sup
    if dev is not None: df['dev']=dev
    if dsc is not None: df['dsc']=dsc
    if hum is not None: df['hum']=hum
    h=(df.hum-35)/10
    X=pd.DataFrame({'const':1.0,'mt':df.mtc,'dev':df.dev,'N':df.N,'dsc':df.dsc,'L2p':df.L2p},index=df.index)
    for l in ['L2','L3','L4']: X['line_'+l]=(df.line==l).astype(float)
    for s in ['SP-01','SP-02','SP-03']:
        i=(df.sup==s).astype(float)
        if s!='SP-01': X['sup_'+s]=i
        X['h_'+s]=h*i; X['h2_'+s]=h*h*i
    return X
if __name__=='__main__':
    d=b.dropna(subset=['mtc','hum']).copy()
    X=design(d)
    for extra in ([],['L1p','L3p']):
        XX=X.copy()
        for e in extra: XX[e]=d[e]
        m=sm.GLM(d.rate,XX,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
        print(m.params.round(4).to_dict()); print((m.params/m.bse).round(1).to_dict(), m.scale)
E
python3 -I $TMPDIR/t.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/u.py <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0')
from t import *
d=b.dropna(subset=['mtc','hum']).copy()
X=design(d)
m=sm.GLM(d.rate,X,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
d['mu']=m.predict(X)
d['off']=np.log(d.mu/(1-d.mu))
for ln in ['L1','L2','L3','L4']:
    x=d[d.line==ln].sort_values('date'); out=[]
    base=sm.GLM(x.rate,np.ones((len(x),1)),family=sm.families.Binomial(),var_weights=x.units_produced,offset=x.off).fit()
    for dt in sorted(x.date.unique())[20:-20]:
        s=(x.date>=dt).astype(float).values
        mm=sm.GLM(x.rate,np.c_[np.ones(len(x)),s],family=sm.families.Binomial(),var_weights=x.units_produced,offset=x.off).fit()
        out.append((mm.llf,dt,mm.params[1]))
    best=max(out); print(ln, best[1].date(), round(best[2],3), 'LR gain', round(best[0]-base.llf,0), 'scale',3.3, 'gain/scale',round((best[0]-base.llf)/3.3,1))
E
python3 -I $TMPDIR/u.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; sed -i 's/mm.params\[1\]/mm.params.iloc[1]/; s/np.c_\[np.ones(len(x)),s\]/np.c_[np.ones(len(x)),s]/' $TMPDIR/u.py; sed -i 's/mm=sm.GLM(x.rate,np.c_\[np.ones(len(x)),s\]/mm=sm.GLM(x.rate.values,np.c_[np.ones(len(x)),s]/' $TMPDIR/u.py; python3 -I $TMPDIR/u.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; sed -i 's/mm.params.iloc\[1\]/mm.params[1]/' $TMPDIR/u.py; python3 -I $TMPDIR/u.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat >> $TMPDIR/u.py <<'E'
print('=====')
x=d[d.line=='L3'].sort_values('date')
x['wk']=x.date.dt.to_period('W')
x['obs']=x.defective_units; x['exp']=x.mu*x.units_produced
g=x.groupby('wk').agg(obs=('obs','sum'),exp=('exp','sum'),u=('units_produced','sum'),mt=('mtc','mean'),raw=('mt','mean'),hum=('hum','mean'),dsc=('dsc','mean'),n=('rate','size'))
g['o/e']=g.obs/g.exp
print(g.loc['2025-06-23':'2025-09-30'].round(2).to_string())
E
python3 -I $TMPDIR/u.py 2>&1 | sed -n '/=====/,$p'

cd /tmp/edabench_claude_l8253_m_; cat >> $TMPDIR/u.py <<'E'
print('#####')
d['obs']=d.defective_units; d['exp']=d.mu*d.units_produced
d['half']=d.date.dt.to_period('M').astype(str)+np.where(d.date.dt.day<=15,'a','b')
print(d.groupby(['half','line'])[['obs','exp']].sum().assign(r=lambda z:z.obs/z.exp).r.unstack().round(2).to_string())
E
python3 -I $TMPDIR/u.py 2>&1 | sed -n '/#####/,$p'

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/v.py <<'E'
import pandas as pd, numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b3.pkl')
b['rc_per']=b.rework_cost_eur/b.defective_units
print(b[['rate','qc_inspection_min','rework_cost_eur','defective_units','units_produced']].corr().round(2))
print(smf.ols('rework_cost_eur~defective_units+units_produced',b).fit().params, smf.ols('rework_cost_eur~defective_units',b).fit().rsquared)
print(smf.ols('qc_inspection_min~rate+units_produced',b).fit().summary().tables[1])
for ln,dt in [('L3','2025-07-21'),('L2','2025-06-19')]:
    x=b[b.line==ln].copy(); x['post']=(x.date>=dt).astype(int)
    print(ln); print(x.groupby('post')[['rate','qc_inspection_min','rc_per','units_produced']].mean())
    print(smf.ols('qc_inspection_min~rate+post',x).fit().params.round(3).to_dict(), smf.ols('rework_cost_eur~defective_units+post',x).fit().params.round(3).to_dict())
E
python3 -I $TMPDIR/v.py

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/w.py <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0')
from t import *
d=b.dropna(subset=['mtc','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
for lab,col in [('corrected','mtc'),('raw','mt')]:
    dd=d.copy(); dd['mtc']=dd[col]
    X=design(dd); X['L1p']=dd.L1p; X['L3p']=dd.L3p
    m=sm.GLM(dd.rate,X,family=sm.families.Binomial(),var_weights=dd.units_produced).fit(scale='x2')
    print(lab,m.params[['mt','L1p','L3p','L2p','dsc']].round(4).to_dict(),(m.params/m.bse)[['L1p','L3p']].round(1).to_dict(),m.scale)
E
python3 -I $TMPDIR/w.py 2>&1 | grep -vi warn

cd /tmp/edabench_claude_l8253_m_; cat > $TMPDIR/x.py <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0')
from t import *
for o in (6.65,7.0):
    mt=b.mt.copy(); mt[(b.line=='L1')&(b.date>='2025-04-14')]-=o; print('A4',o,mt.median())
b['mtc']=b.mt; b.loc[(b.line=='L1')&(b.date>='2025-04-14'),'mtc']-=6.8
print('A4 final',b.mtc.median(), b.mtc.notna().sum())
fit=b.dropna(subset=['mtc','hum']); fit=fit[~((fit.line=='L3')&(fit.date>='2025-07-21'))]
X=design(fit)
m=sm.GLM(fit.rate,X,family=sm.families.Binomial(),var_weights=fit.units_produced).fit(scale='x2')
print(m.params.round(4).to_dict(), m.scale)
# impute missing covariates for prediction
a=b.copy()
a['mtc']=a.mtc.fillna(a.groupby('line').mtc.transform('median'))
a['hum']=a.hum.fillna(a.hum.median())
def P(**k): return m.predict(design(a,**k))
p0=P()
print('calib: pred',(p0*a.units_produced).sum()/a.units_produced.sum(),'actual',a.defective_units.sum()/a.units_produced.sum())
# C3
dsc_cf=a.dsc%14
p3=P(dsc=dsc_cf)
U=a.units_produced.sum()
print('C3 ratio',(a.defective_units*p3/p0).sum()/U,'resid-pres',(a.defective_units+a.units_produced*(p3-p0)).sum()/U, 'model',(p3*a.units_produced).sum()/U)
# max: dsc<=13 cap alt
p3b=P(dsc=a.dsc.clip(upper=14)); print('cap14',(a.defective_units*p3b/p0).sum()/U)
# C1
for s in ['SP-01','SP-02','SP-03']:
    p=P(sup=s,dev=0.0)
    print(s,'ratio',(a.defective_units*p/p0).sum()/U,'model',(p*a.units_produced).sum()/U)
E
python3 -I $TMPDIR/x.py 2>&1 | grep -vi warn
