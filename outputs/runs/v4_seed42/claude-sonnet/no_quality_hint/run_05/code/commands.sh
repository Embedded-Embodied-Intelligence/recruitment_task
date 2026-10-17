cd /tmp/edabench_claude_2yf11sr_; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
for c in ['line','shift','operator_id','supplier_code']: print(b[c].value_counts(dropna=False).to_dict())
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    n=pd.to_numeric(b[c],errors='coerce'); print(c,n.isna().sum(),n.describe().round(1).to_dict()); print(b[c][n.isna()].value_counts(dropna=False).head(5).to_dict())
print(b.production_date.str.len().value_counts())
print(b.production_date.sample(10).tolist())
E
python3 $TMPDIR/a.py; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_2yf11sr_; cat maintenance.csv | grep -v mold_cl; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv')
print(b.iloc[::150][['batch_id','production_date','line']])
m=pd.to_numeric(b.mold_temp)
print(m.round(-1).value_counts().sort_index().to_dict())
print(b.humidity_pct.round(-1).value_counts().sort_index().to_dict())
d=b[b.duplicated('batch_id',keep=False)].sort_values('batch_id');print(d.head(6).to_string())
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/prep.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)
s=b.production_date
iso=pd.to_datetime(s.where(s.str.contains('-')),errors='coerce')
# reference date by position: interpolate from ISO
pos=np.arange(len(b)); ref=pd.Series(iso.map(lambda x:x.value if pd.notna(x) else np.nan)).interpolate().bfill().ffill()
ref=pd.to_datetime(ref)
out=[]
for i,v in enumerate(s):
    if '-' in v: out.append(iso[i]);continue
    a,c,y=v.split('/');a=int(a);c=int(c)
    cands=[]
    for mo,dy in ((a,c),(c,a)):
        try: cands.append(pd.Timestamp(int(y),mo,dy))
        except: pass
    out.append(min(cands,key=lambda t:abs((t-ref[i]).days)))
b['date']=pd.Series(out)
print((b.date-ref).abs().dt.days.describe())
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['supplier_code']=b.supplier_code.str.strip().str.upper()
b['mt']=np.where(b.mold_temp>300,(b.mold_temp-32)*5/9,b.mold_temp); b.loc[b.mold_temp==0,'mt']=np.nan
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['rate']=b.defective_units/b.units_produced
b=b.merge(pd.read_csv('suppliers.csv'),on='supplier_code')
b.to_pickle('/tmp/edabench_claude_2yf11sr_/b.pkl')
E
python3 $TMPDIR/prep.py
cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b.pkl')
print(len(b),b.humidity_pct.isna().sum(),(b.humidity_pct<0).sum(),b.hum.isna().sum())
print(b.defective_units.sum()/b.units_produced.sum(), b.mt.median(), b.mt.isna().sum())
print(b.date.min(),b.date.max()); print(b.groupby('line').mt.describe())
print(b.humidity_pct[b.humidity_pct<=0].value_counts())
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
b=pd.read_pickle('b.pkl')
l1=b[b.line=='L1']; print(l1.groupby(l1.date>='2025-04-14').mt.describe())
print(b.groupby('supplier_name')[['rate','hum','mt','cycle_time_s','ambient_temp_c']].mean())
print(b[['rate','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur','units_produced']].corr().round(2).iloc[0])
b['wk']=b.date.dt.to_period('M')
print(b.pivot_table(index='wk',columns='line',values='rate').round(3))
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b.pkl')
b['m']=b.date.dt.to_period('M')
print(b.pivot_table(index='m',columns='line',values='mt').round(1))
l=b[b.line=='L1'].set_index('date').sort_index()
print(l.mt.resample('2W').mean().round(1).to_string())
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
b=pd.read_pickle('b.pkl')
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
print(smf.ols('mt~ambient_temp_c+C(line)+post+cycle_time_s+machine_age_years',b).fit().summary().tables[1])
b['ld']=np.log(b.rate)
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b.pkl')
b['pre']=((b.line=='L1')&(b.date<'2025-04-14')).astype(int)
b['amc']=b.mt+6.4*b.pre
b['good']=b.units_produced-b.defective_units
d=b.dropna(subset=['mt','hum']).copy()
def f(form,d=d):
    r=smf.glm(form,d,family=sm.families.Binomial()).fit(scale='X' ); return r
r=f('defective_units+good~mt+pre+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(supplier_name)+C(line)')
print(r.summary().tables[1])
r=f('defective_units+good~mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(supplier_name)+C(line)')
print(r.summary().tables[1])
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; sed -i "s/scale='X' /scale='x2'/" $TMPDIR/a.py; python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/prep2.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
b['dsc']=b.apply(ds,axis=1)
b['pre']=((b.line=='L1')&(b.date<'2025-04-14')).astype(int)
b.to_pickle('b2.pkl')
print(b.dsc.describe()); print(b.groupby('line').dsc.max())
print(m.groupby('line').date.apply(lambda x:x.diff().dt.days.describe()[['mean','max']]).unstack())
print(b.groupby(pd.cut(b.dsc,[-1,0,3,6,9,13,20,30,60])).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
E
python3 $TMPDIR/prep2.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['amc']=b.mt+6.4*b.pre
b['good']=b.units_produced-b.defective_units
b['over']=np.maximum(b.dsc-14,0)
b['over7']=np.maximum(b.dsc-7,0)
d=b.dropna(subset=['mt','hum']).copy()
def f(form,d=d):
    return smf.glm(form,d,family=sm.families.Binomial(),freq_weights=None).fit(cov_type='HC1') if False else smf.glm(form,d.assign(r=d.rate),family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
base='r~amc+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(supplier_name)+C(line)+operator_id'
for extra in ['+dsc','+over','+dsc+over','+over7+dsc']:
    r=f(base+extra);print(extra,r.deviance,r.scale)
r=f(base+'+dsc+over');print(r.summary().tables[1])
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b2.pkl')
print(b.groupby('line').machine_age_years.describe())
print(pd.crosstab(b.operator_id,b.line))
print(pd.crosstab(b.shift,b.line))
print(b.groupby('shift')[['hum','mt','ambient_temp_c','cycle_time_s']].mean())
print(b.groupby('line').machine_age_years.apply(lambda x:x.round(1).nunique()))
l=b[b.line=='L4'].sort_values('date');print(l[['date','machine_age_years']].iloc[::60])
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['amc']=b.mt+6.4*b.pre
b['over']=np.maximum(b.dsc-14,0)
d=b.dropna(subset=['mt','hum']).copy()
def f(form,d=d):
    return smf.glm(form,d.assign(r=d.rate),family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
base='r~amc+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(supplier_name)+dsc'
r=f(base);print(r.summary().tables[1],r.deviance)
r2=f(base+'+C(line)');print(r2.params.round(3).to_dict(),r2.deviance)
d['res']=r.resid_pearson
d['m']=d.date.dt.to_period('M')
print(d.pivot_table(index='m',columns='line',values='res').round(2))
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['amc']=b.mt+6.4*b.pre
d=b.dropna(subset=['mt','hum']).copy()
r=smf.ols('mt~ambient_temp_c+C(line)',d[d.date<'2025-04-01']).fit()
d['mres']=d.mt-r.predict(d)
d['w']=d.date.dt.to_period('M')
print(d.pivot_table(index='w',columns='line',values='mres').round(1))
print(d.pivot_table(index='w',columns='line',values='ambient_temp_c').round(1))
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['amc']=b.mt+6.4*b.pre
d=b.dropna(subset=['mt','hum']).copy()
form='r~amc+hum+I(hum**2)+cycle_time_s+ambient_temp_c+C(shift)+C(supplier_name)+dsc+C(line)'
r=smf.glm(form,d.assign(r=d.rate),family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
d['res']=d.rate-r.predict(d)
for L in ['L2','L3']:
    x=d[d.line==L].set_index('date').sort_index()
    print(L);print(x.res.resample('W').mean().round(3).loc['2025-05-01':'2025-09-10'].to_string())
    print(x.mt.sub(x.ambient_temp_c*0.89).resample('W').mean().round(1).loc['2025-05-01':'2025-07-10'].to_string())
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b2.pkl')
for L,a,z in [('L3','2025-07-01','2025-08-10'),('L2','2025-06-05','2025-07-05')]:
    x=b[(b.line==L)&(b.date>=a)&(b.date<=z)].set_index('date').sort_index()
    print(L);print(x.groupby(x.index.date)[['rate','qc_inspection_min','mt','units_produced']].mean().round(3).to_string())
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['post']=(b.date>='2025-07-21')
for L in ['L3','L1']:
    x=b[b.line==L]
    print(L,smf.ols('qc_inspection_min~rate+units_produced+post',x).fit().params.round(3).to_dict())
    print(x.groupby('post')[['qc_inspection_min','rate']].mean())
x=b[b.line=='L3'];x=x[x.post]
print(smf.ols('qc_inspection_min~rate',x).fit().params, smf.ols('qc_inspection_min~rate',b[(b.line=='L3')&~b.post]).fit().params)
# L2 changepoint
y=b[b.line=='L2'].set_index('date').sort_index()
y=y[['defective_units','units_produced']].groupby(level=0).sum()
best=[]
for t in pd.date_range('2025-05-20','2025-07-10'):
    a=y[y.index<t];c=y[y.index>=t]
    from scipy.stats import binom
    p0=y.defective_units.sum()/y.units_produced.sum()
    pa=a.defective_units.sum()/a.units_produced.sum();pc=c.defective_units.sum()/c.units_produced.sum()
    ll=binom.logpmf(a.defective_units,a.units_produced,pa).sum()+binom.logpmf(c.defective_units,c.units_produced,pc).sum()
    best.append((ll,t))
print(sorted(best)[-5:])
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
x=b[b.line=='L3'].set_index('date').sort_index()
r=smf.ols('mt~ambient_temp_c',x[x.index<'2025-05-01']).fit()
print((x.mt-r.predict(x)).resample('D').mean().loc['2025-05-10':'2025-05-30'].round(1).to_string())
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['l2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['l3s']=((d.line=='L3')&(d.date>='2025-05-20')).astype(int)
d['amc']=d.mt+6.4*d.pre
form='r~amc+hum+I(hum**2)+cycle_time_s+ambient_temp_c+machine_age_years+C(shift)+C(supplier_name)+dsc+C(line)+l2+pre+l3s'
r=smf.glm(form,d.assign(r=d.rate),family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
print(r.summary().tables[1])
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['l2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['amc']=d.mt+6.4*d.pre
d['ct']=d.cycle_time_s-d.recipe_cycle_time_s
print(d.groupby('supplier_name').ct.describe())
def f(form):
    return smf.glm(form,d.assign(r=d.rate),family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
base='r~amc+hum+I(hum**2)+cycle_time_s+C(shift)+dsc+C(line)+l2+pre'
for e in ['+C(supplier_name)','+C(supplier_name)*(hum+I(hum**2))','+C(supplier_name)+C(supplier_name):hum','+C(supplier_name)*cycle_time_s','+C(supplier_name)*amc','+C(supplier_name)*dsc','+C(operator_id)']:
    r=f(base+e);print(e,r.deviance,r.df_model,r.scale)
r=f(base+'+C(supplier_name)*(hum+I(hum**2))');print(r.summary().tables[1])
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['l2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['amc']=d.mt+6.4*d.pre
d['hb']=pd.cut(d.hum,[0,5,10,15,20,25,30,35,40,45,50,55,60,80])
base='r~amc+cycle_time_s+C(shift)+dsc+C(line)+l2+pre+C(hb)-1'
for s in ['Alpha','Beta','Gamma']:
    x=d[d.supplier_name==s]
    r=smf.glm(base,x.assign(r=x.rate),family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='x2')
    p=r.params.filter(like='hb');print(s,(p-p.min()).round(2).values, x.groupby('hb').size().values)
E
python3 $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['l2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['amc']=d.mt+6.4*d.pre
x=d[d.supplier_name=='Alpha']
print(x.hum.describe(), (x.hum<2).sum())
g=np.linspace(x.hum.min(),x.hum.max(),500)
for name,t in [('quad','hum+I(hum**2)'),('cub','hum+I(hum**2)+I(hum**3)'),('quart','hum+I(hum**2)+I(hum**3)+I(hum**4)'),('bs','bs(hum,df=6)'),('bs8','bs(hum,df=8)')]:
    r=smf.glm('r~amc+cycle_time_s+C(shift)+dsc+C(line)+l2+pre+'+t,x.assign(r=x.rate),family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='x2')
    nd=x.iloc[[0]*500].copy();nd['hum']=g
    p=r.predict(nd);print(name,g[p.values.argmin()],r.deviance)
E
python3 $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['l2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['amc']=d.mt+6.4*d.pre
x=d[d.supplier_name=='Alpha'].copy()
x['hb']=pd.cut(x.hum,np.arange(10,76,4))
r=smf.glm('r~amc+cycle_time_s+C(shift)+dsc+C(line)+l2+pre+C(hb)-1',x.assign(r=x.rate),family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='x2')
p=r.params.filter(like='hb');print(pd.DataFrame({'p':(p-p.min()).round(2).values,'n':x.groupby('hb',observed=False).size().reindex(range(0)) if False else x.hb.value_counts().sort_index().values[:len(p)]},index=p.index))
# also fit quad restricted 15-50
for lo,hi in [(12,50),(15,45),(12,72)]:
    y=x[(x.hum>=lo)&(x.hum<=hi)]
    r=smf.glm('r~amc+cycle_time_s+C(shift)+dsc+C(line)+l2+pre+hum+I(hum**2)',y.assign(r=y.rate),family=sm.families.Binomial(),var_weights=y.units_produced).fit(scale='x2')
    print(lo,hi,-r.params['hum']/(2*r.params['I(hum ** 2)']))
E
python3 $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['l2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['amc']=d.mt+6.4*d.pre
d['db']=pd.cut(d.dsc,[-1,0,2,4,6,8,10,12,14,16,18,20,24,28,40])
r=smf.glm('r~amc+cycle_time_s+C(shift)+C(line)+l2+pre+C(supplier_name)*(hum+I(hum**2))+C(db)',d.assign(r=d.rate),family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
print(r.params.filter(like='db').round(3).to_string(), d.db.value_counts().sort_index().values)
E
python3 $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_2yf11sr_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['l2']=((b.line=='L2')&(b.date>='2025-06-15')).astype(int)
b['l3q']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['amc']=b.mt+6.4*b.pre
b['over']=np.maximum(b.dsc-14,0)
print('A4',b.amc.median(), b.mt.median())
d=b.dropna(subset=['mt','hum']).copy()
form='r~amc+cycle_time_s+C(shift)+C(line)+l2+l3q+pre+C(supplier_name)*(hum+I(hum**2))+dsc+over'
r=smf.glm(form,d.assign(r=d.rate),family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
print(r.params.round(4).to_dict())
w=d.units_produced
def tot(x): return (r.predict(x)*w).sum()/w.sum()
print('base',tot(d),(d.defective_units.sum()/w.sum()))
sup=pd.read_csv('suppliers.csv').set_index('supplier_name')
for s in sup.index:
    x=d.copy();x['supplier_name']=s;x['cycle_time_s']=sup.loc[s,'recipe_cycle_time_s'];print(s,tot(x))
for k in [14]:
    x=d.copy();x['dsc']=x.dsc%k;x['over']=np.maximum(x.dsc-14,0);t=tot(x);print('C3',t,t/tot(d),d.defective_units.sum()/w.sum()*t/tot(d))
    x=d.copy();x['dsc']=np.minimum(x.dsc,k);x['over']=0;t=tot(x);print('cap',t/tot(d)*d.defective_units.sum()/w.sum())
print(d.defective_units.sum()/w.sum(), b.defective_units.sum()/b.units_produced.sum())
E
python3 $TMPDIR/a.py 2>&1|grep -v Warn
