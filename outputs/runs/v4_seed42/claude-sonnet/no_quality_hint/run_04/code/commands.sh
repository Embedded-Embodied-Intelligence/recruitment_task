cd /tmp/edabench_claude_c0w8lb9m; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.describe().T)
for c in ['production_date','line','shift','operator_id','supplier_code']:
    print(b[c].value_counts(dropna=False).head(40))
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(b[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(b[c][x.isna()].value_counts(dropna=False).head())
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
print(pd.read_csv('maintenance.csv').event.value_counts())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.nunique())
b['d']=pd.to_datetime(b.production_date,format='ISO8601',errors='coerce')
m=b.d.isna(); b.loc[m,'d']=pd.to_datetime(b.production_date[m],format='%m/%d/%Y')
print(b.d.min(),b.d.max())
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sc']=b.supplier_code.str.strip().str.upper()
print(np.histogram(b.mold_temp,bins=[-1,0.01,50,100,150,180,200,220,240,260,300,350,400,500]))
print(b.humidity_pct.describe(), (b.humidity_pct<=0).sum(), b.humidity_pct.isna().sum(), (b.humidity_pct==-1).sum(),(b.humidity_pct>100).sum())
print(b.sort_values('humidity_pct').humidity_pct.head(200).value_counts().head())
print(pd.read_csv('maintenance.csv').query("event!='mold_cleaning'"))
print(b[b.mold_temp>300].groupby(['line']).d.agg(['min','max','count']))
print(b[b.mold_temp==0].groupby(['line']).d.agg(['min','max','count']))
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)
s=b.production_date
sl=s.str.contains('/')
p=s[sl].str.split('/',expand=True).astype(int)
b['fmt']='iso'
b.loc[sl,'fmt']='amb'
b.loc[sl&(p[0]>12).reindex(b.index,fill_value=False),'fmt']='dmy'
b.loc[sl&(p[1]>12).reindex(b.index,fill_value=False),'fmt']='mdy'
print(b.fmt.value_counts())
print(b.iloc[::150][['production_date','fmt']].T)
# is file sorted?
iso=pd.to_datetime(s.where(~sl),errors='coerce')
print(iso.is_monotonic_increasing, iso.dropna().is_monotonic_increasing)
print(b[sl].head(30)[['production_date','fmt','line']])
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_c0w8lb9m; cat >> $TMPDIR/c.py <<'E'
print(pd.crosstab(b.line,b.fmt))
E
python3 -I $TMPDIR/c.py | tail -8

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)
def pd_(r):
    s=r.production_date
    if '/' not in s: return pd.Timestamp(s)
    return pd.to_datetime(s,format='%m/%d/%Y' if r.line=='L1' else '%d/%m/%Y')
b['d']=b.apply(pd_,axis=1)
print(b.d.min(),b.d.max())
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sc']=b.supplier_code.str.strip().str.upper()
b['rate']=b.defective_units/b.units_produced
print(np.histogram(b.mold_temp,bins=[-1,0.01,50,100,150,180,200,220,240,260,300,350,400,500]))
print(b.humidity_pct.isna().sum(),(b.humidity_pct==-1).sum(),(b.humidity_pct<0).sum(),(b.humidity_pct>100).sum())
print(pd.read_csv('maintenance.csv').query("event!='mold_cleaning'"))
for k,g in b.groupby(b.mold_temp>300): print(k,g.groupby('line').d.agg(['min','max','count']))
print(b[b.mold_temp==0].groupby('line').d.agg(['min','max','count']))
print(b.groupby('line').mold_temp.describe())
print(b.groupby('line').cycle_time_s.describe())
b.to_pickle('/tmp/claude-0/b.pkl') if False else None
b.to_pickle('b.pkl')
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b.pkl')
print('A2',(b.humidity_pct.isna()|(b.humidity_pct<0)).sum(), b.humidity_pct.lt(0).sum())
print('A3',b.defective_units.sum()/b.units_produced.sum())
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp)
b.loc[b.mold_temp==0,'mt']=np.nan
print(b.groupby('line').mt.describe())
print('A4',b.mt.median())
l1=b[b.line=='L1']
print(l1.groupby(l1.d.dt.to_period('M')).mt.agg(['mean','median','std']))
print(l1[(l1.d>='2025-04-01')&(l1.d<'2025-04-30')].groupby('d').mt.mean())
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b.pkl')
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp)
b.loc[b.mold_temp==0,'mt']=np.nan
print(b.pivot_table(index=b.d.dt.to_period('M'),columns='line',values='mt'))
print(b.pivot_table(index=b.d.dt.to_period('M'),columns='line',values='ambient_temp_c'))
l1=b[b.line=='L1'].set_index('d').mt.resample('W').mean()
print(l1.loc['2025-03-01':'2025-05-15'])
import numpy as np
for l,g in b.groupby('line'):
    g=g.dropna(subset=['mt']); print(l,np.polyfit(g.ambient_temp_c,g.mt,1), np.corrcoef(g.ambient_temp_c,g.mt)[0,1])
E
python3 -I $TMPDIR/f.py

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b.pkl')
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp)
b.loc[b.mold_temp==0,'mt']=np.nan
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['ok']=b.units_produced-b.defective_units
b['dt']=b.d.dt.dayofyear
# ambient vs mt
for l,g in b.groupby('line'):
    g=g.dropna(subset=['mt'])
    X=pd.DataFrame({'a':g.ambient_temp_c,'post':g.post,'t':g.dt}); 
    print(l,smf.ols('mt~ambient_temp_c+post+dt',g).fit().params.round(3).to_dict())
print(b[['rate','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur']].corr().round(2))
g=b.dropna(subset=['mt','hum'])
f='ok+defective_units~mt+post+I(mt**2)+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(sc)'
r=smf.glm(f,g,family=sm.families.Binomial()).fit()
print(r.summary().tables[1])
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b.pkl')
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp)
b.loc[b.mold_temp==0,'mt']=np.nan
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
print(m.groupby('line').date.apply(lambda s:s.diff().dt.days.describe()[['count','mean','min','max']]).unstack())
def dsc(r):
    c=m[(m.line==r.line)&(m.date<=r.d)].date
    return (r.d-c.max()).days if len(c) else np.nan
b['dsc']=b.apply(dsc,axis=1)
print(b.dsc.describe(), b.dsc.isna().sum())
b.to_pickle('b2.pkl')
print(b.groupby(pd.cut(b.dsc,[-1,0,2,4,6,8,10,12,14,16,20,30,60,200])).apply(lambda g:pd.Series({'n':len(g),'r':g.defective_units.sum()/g.units_produced.sum()})))
E
python3 -I $TMPDIR/h.py

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['ok']=b.units_produced-b.defective_units
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['sup']=b.sc
g=b.dropna(subset=['mt','hum']).copy()
g=g[g.hum>=0]
def fit(f,d=g):
    return smf.glm('ok+defective_units~'+f,d,family=sm.families.Binomial()).fit(scale='X2')
f0='bs(mt,df=4)+bs(hum,df=4)+bs(cycle_time_s,df=4)+bs(dsc,df=5)+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(sup)+post'
r=fit(f0); print(r.summary().tables[1]); print(r.scale, r.deviance, r.df_resid)
E
python3 -I $TMPDIR/i.py 2>&1 | grep -v Warn | tail -70

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/j.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['ok']=b.units_produced-b.defective_units
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['sup']=b.sc
print(b.groupby('line').machine_age_years.describe())
print(b.groupby('sup')[['cycle_time_s']].mean())
g=b.dropna(subset=['mt','hum']).copy(); g=g[g.hum>=0]
g['mtc']=g.mt-7.1*g.post
def fit(f,d=g):
    return smf.glm('defective_units+ok~'+f,d,family=sm.families.Binomial()).fit(scale='X2')
f0='mtc+I(mtc**2)+hum+I(hum**2)+cycle_time_s+I(cycle_time_s**2)+dsc+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(sup)'
for ff in [f0,f0+'+post']:
    r=fit(ff); p=r.params; print(r.scale, r.deviance, p[[k for k in p.index if 'operator' not in k]].round(4).to_string()); print(r.pvalues['post'] if 'post' in r.pvalues else '')
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v Warn | tail -80

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/k.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['sup']=b.sc
g=b.dropna(subset=['mt','hum']).copy(); g=g[g.hum>=0]
g['mtc']=g.mt-7.1*g.post
g['y']=g.defective_units/g.units_produced
def fit(f,d=g):
    r=smf.glm('y~'+f,d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit()
    return r
f0='mtc+hum+I(hum**2)+cycle_time_s+dsc+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(sup)'
r=smf.glm('y~'+f0,g,family=sm.families.Binomial(),var_weights=g.units_produced).fit(cov_type='HC1')
p=pd.DataFrame({'c':r.params,'z':r.tvalues}); print(p[~p.index.str.contains('oper')].round(3))
print(r.deviance,r.pearson_chi2,r.df_resid)
r=smf.glm('y~'+f0.replace('+C(line)',''),g,family=sm.families.Binomial(),var_weights=g.units_produced).fit(cov_type='HC1')
p=pd.DataFrame({'c':r.params,'z':r.tvalues}); print(p[~p.index.str.contains('oper')].round(3))
E
python3 -I $TMPDIR/k.py 2>&1 | grep -v Warn | tail -60

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/l.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['sup']=b.sc
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['dev']=b.cycle_time_s-b.rec
print(b.groupby('sup').dev.describe())
g=b.dropna(subset=['mt','hum']).copy(); g=g[g.hum>=0]
g['mtc']=g.mt-7.1*g.post
g['y']=g.defective_units/g.units_produced
def fit(f,d=g):
    return smf.glm('y~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='mtc+hum+I(hum**2)+dev+dsc+machine_age_years+ambient_temp_c+C(line)+C(shift)+C(sup)'
r0=fit(base);print(r0.deviance,r0.scale)
p=pd.DataFrame({'c':r0.params,'z':r0.tvalues}); print(p.round(3))
# interactions
for add in ['C(sup):hum+C(sup):I(hum**2)','C(sup):dev','I(dev**2)','C(sup):I(dev**2)','C(operator_id)','I(mtc**2)','C(sup):mtc','dsc:C(line)','I(dsc**2)']:
    r=fit(base+'+'+add); print(add, round(r0.deviance-r.deviance,1), r.df_model-r0.df_model, round((r0.deviance-r.deviance)/(r.df_model-r0.df_model)/r.scale,2))
E
python3 -I $TMPDIR/l.py 2>&1 | grep -v Warn | tail -60

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/m.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b2.pkl')
b['sup']=b.sc
g=b[b.humidity_pct>=0].copy()
g['hb']=pd.cut(g.humidity_pct,[0,10,15,20,25,30,35,40,45,50,55,60,80])
t=g.groupby(['hb','sup'],observed=True).apply(lambda x:x.defective_units.sum()/x.units_produced.sum()).unstack()
print(t.round(4)); print(g.groupby('hb',observed=True).size())
print(b.groupby('line').apply(lambda x:x.groupby(pd.cut(x.dsc,[-1,2,5,8,11,14,17,21,40])).apply(lambda y:y.defective_units.sum()/y.units_produced.sum())).round(4))
print(b.groupby('shift').humidity_pct.mean(), b.groupby('shift').ambient_temp_c.mean(), b.groupby(['line','shift']).size())
E
python3 -I $TMPDIR/m.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/n.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['sup']=b.sc
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['dev']=b.cycle_time_s-b.rec
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['pre']=b.sup!='SP-01'
g=b.dropna(subset=['mt','hum']).copy(); g=g[g.hum>=0]
g['mtc']=g.mt-7.1*g.post
g['y']=g.defective_units/g.units_produced
g['dbin']=pd.cut(g.dsc,[-1,3,6,9,12,14,17,21,40]).astype(str)
def fit(f,d=g):
    return smf.glm('y~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='mtc+C(sup)*(hum+I(hum**2))+dev+machine_age_years+ambient_temp_c+C(line)+C(shift)'
r=fit(base+'+C(dbin)*C(line)');print(r.deviance,r.scale)
p=pd.DataFrame({'c':r.params,'z':r.tvalues}); print(p.round(3).to_string())
g['res']=r.resid_pearson/np.sqrt(r.scale)
w=g.groupby(['line',g.d.dt.to_period('M')]).res.mean().unstack(0); print(w.round(2))
E
python3 -I $TMPDIR/n.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/o.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['sup']=b.sc
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['dev']=b.cycle_time_s-b.rec
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
g=b.dropna(subset=['mt','hum']).copy(); g=g[g.hum>=0]
g['mtc']=g.mt-7.1*g.post
g['y']=g.defective_units/g.units_produced
g['dbin']=pd.cut(g.dsc,[-1,3,6,9,12,14,17,21,40]).astype(str)
def fit(f,d=g):
    return smf.glm('y~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='mtc+C(sup)*(hum+I(hum**2))+dev+ambient_temp_c+C(line)+C(shift)+C(dbin)'
r=fit(base);print(r.deviance,r.scale)
g['res']=r.resid_pearson/np.sqrt(r.scale)
g['pr']=r.fittedvalues
g['w']=g.d.dt.to_period('W-SUN').dt.start_time
for l in ['L1','L2','L3','L4']:
    x=g[g.line==l]
    a=x.groupby('w').apply(lambda y:(y.defective_units.sum()/ (y.pr*y.units_produced).sum()))
    print(l,a.round(2).values)
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
for l in ['L2','L3']: 
    d=m[m.line==l].date; print(l,[(x.strftime('%m-%d'),y) for x,y in zip(d,d.diff().dt.days)])
E
python3 -I $TMPDIR/o.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b2.pkl')
cols=['mt','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years','qc_inspection_min','units_produced','rate','rework_cost_eur']
b['rate']=b.defective_units/b.units_produced
b.loc[b.humidity_pct<0,'humidity_pct']=np.nan
for l,d0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    x=b[b.line==l]; x=x[(x.d>=pd.Timestamp(d0)-pd.Timedelta(days=42))&(x.d<pd.Timestamp(d0)+pd.Timedelta(days=42))]
    x['p']=x.d>=d0
    print(l);print(x.groupby('p')[cols].mean().round(3).T)
x=b[b.line=='L3'].set_index('d').sort_index()
print(x.loc['2025-07-10':'2025-07-31'].groupby('d').agg(r=('rate','mean'),n=('rate','size'),mt=('mt','mean'),dsc=('dsc','max')))
x=b[b.line=='L2'].set_index('d').sort_index()
print(x.loc['2025-06-08':'2025-06-24'].groupby('d').agg(r=('rate','mean'),n=('rate','size'),mt=('mt','mean'),dsc=('dsc','max')))
E
python3 -I $TMPDIR/p.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/q.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b2.pkl')
b['rate']=b.defective_units/b.units_produced
for l,d0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    x=b[b.line==l].copy(); x['p']=x.d>=d0
    print(l); print(pd.crosstab(x.operator_id,x.p).T); print(pd.crosstab(x.sc,x.p,normalize='columns').round(2)); print(pd.crosstab(x['shift'],x.p,normalize='columns').round(2))
    print(x.groupby(['p','sc']).apply(lambda y:y.defective_units.sum()/y.units_produced.sum()).unstack().round(4))
E
python3 -I $TMPDIR/q.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/r.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['sup']=b.sc
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['dev']=b.cycle_time_s-b.rec
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
g=b.dropna(subset=['mt','hum']).copy(); g=g[g.hum>=0]
g['mtc']=g.mt-7.1*g.post
g['y']=g.defective_units/g.units_produced
def fit(f,d=g):
    return smf.glm('y~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='mtc+C(sup)*(hum+I(hum**2))+dev+ambient_temp_c+C(line)+C(shift)+dsc+I(np.maximum(dsc-14,0))'
best={}
for l in ['L2','L3']:
    res=[]
    for t in pd.date_range('2025-03-01','2025-09-10',freq='D'):
        g['s']=((g.line==l)&(g.d>=t)).astype(int)
        r=fit(base+'+s'); res.append((r.deviance,t,r.params['s']))
    res.sort(); print(l,res[:4])
    best[l]=res[0][1]
for l in best: g['s_'+l]=((g.line==l)&(g.d>=best[l])).astype(int)
r=fit(base+'+s_L2+s_L3'); p=pd.DataFrame({'c':r.params,'z':r.tvalues});print(p.round(4),r.scale)
E
python3 -I $TMPDIR/r.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/s.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['rate']=b.defective_units/b.units_produced
b['p']=((b.line=='L2')&(b.d>='2025-06-15'))|((b.line=='L3')&(b.d>='2025-07-21'))
for y in ['qc_inspection_min','rework_cost_eur']:
  for l,g in b.groupby('line'):
    for p,h in g.groupby('p'):
        r=smf.ols(f'{y}~rate+units_produced+defective_units',h).fit(); print(y,l,p,len(h),r.params.round(3).to_dict(),round(r.rsquared,3))
E
python3 -I $TMPDIR/s.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/t.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['sup']=b.sc
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['dev']=b.cycle_time_s-b.rec
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['s2']=((b.line=='L2')&(b.d>='2025-06-15')).astype(int)
b['s3']=((b.line=='L3')&(b.d>='2025-07-21')).astype(int)
g=b.dropna(subset=['mt','hum']).copy(); g=g[g.hum>=0]
g['y']=g.defective_units/g.units_produced
def fit(f,d=g):
    return smf.glm('y~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='mt+post+C(sup)*(hum+I(hum**2))+dev+ambient_temp_c+C(line)+C(shift)+dsc+s2+s3'
r=fit(base);print(r.params[['mt','post','dsc']],r.tvalues[['mt','post']], 'implied offset',r.params['post']/r.params['mt'])
for off in [0,3,5,7,8,10]:
    g['mtc']=g.mt-off*g.post
    r=fit(base.replace('mt+post','mtc')); print(off,r.deviance)
# other terms
base2='mt+post+C(sup)*(hum+I(hum**2))+dev+C(line)+C(shift)+dsc+s2+s3'
r0=fit(base2)
for add in ['ambient_temp_c','machine_age_years','C(operator_id)','I(mt**2)','I(dev**2)','I(dsc**2)','C(sup):dev','C(sup):mt','C(shift):C(line)','C(sup)*I(hum**3)','C(line):dsc','C(line):mt','C(shift):dsc','qc_inspection_min' ]:
    r=fit(base2+'+'+add); k=r.df_model-r0.df_model
    print(add,k,round((r0.deviance-r.deviance)/k/r.scale,2), r.params.get(add,np.nan))
E
python3 -I $TMPDIR/t.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/u.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
g=b.dropna(subset=['mt']).copy()
# offset estimation: L1 vs others, ambient + month control
g['l1']=(g.line=='L1').astype(int)
x=g[g.line.isin(['L1','L2','L4'])]
r=smf.ols('mt~ambient_temp_c*C(line)+post',x).fit(); print(r.params.round(3).to_dict(), r.bse['post'])
r=smf.ols('mt~ambient_temp_c+C(line)+post+C(sc)+C(shift)',g[g.line!='L3']).fit(); print(r.params.round(3).to_dict(), r.bse['post'])
for off in [0,7,7.1,7.5,8]:
    m=np.where(g.post==1,g.mt-off,g.mt); print(off,np.median(m))
E
python3 -I $TMPDIR/u.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; cat > $TMPDIR/v.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['sup']=b.sc
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['dev']=b.cycle_time_s-b.rec
b['post']=((b.line=='L1')&(b.d>='2025-04-15')).astype(int)
b['s2']=((b.line=='L2')&(b.d>='2025-06-15')).astype(int)
b['s3']=((b.line=='L3')&(b.d>='2025-07-21')).astype(int)
b['mtc']=b.mt-8*b.post
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
g=b.dropna(subset=['mt','hum']).copy()
g['y']=g.defective_units/g.units_produced
def fit(f,d=g):
    return smf.glm('y~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
f='mtc+C(sup)*(hum+I(hum**2))+dev+C(line)+C(shift)+dsc+s2+s3'
r=fit(f); print(r.params.round(4).to_dict(), r.scale)
# operator check
r2=fit(f+'+C(operator_id)'); p=r2.params[[k for k in r2.params.index if 'oper' in k]]; print(p.round(3).values, r2.deviance, r.deviance)
# C1
for s in ['SP-01','SP-02','SP-03']:
    d=b.copy(); d['sup']=s; d['dev']=0.0
    # impute missing mt/hum with batch-level median-ish: use only complete rows
    d=d.dropna(subset=['mtc','hum'])
    p=r.predict(d); print(s, (p*d.units_produced).sum()/d.units_produced.sum())
# C2
pa=r.params
hs=np.arange(10,73,0.1)
d=g.iloc[[0]].copy()
tab=pd.concat([d]*len(hs),ignore_index=True); tab['hum']=hs; tab['sup']='SP-01'
pp=r.predict(tab); print('C2 quad', hs[np.argmin(pp.values)])
# spline check for Alpha only
a=g[g.sup=='SP-01']
ra=smf.glm('y~mtc+bs(hum,df=5)+dev+C(line)+C(shift)+dsc+s2+s3',a,family=sm.families.Binomial(),var_weights=a.units_produced).fit()
tab2=pd.concat([a.iloc[[0]]]*len(hs),ignore_index=True); tab2['hum']=hs
pp=ra.predict(tab2); print('C2 spline', hs[np.argmin(pp.values)])
ra=smf.glm('y~mtc+hum+I(hum**2)+dev+C(line)+C(shift)+dsc+s2+s3',a,family=sm.families.Binomial(),var_weights=a.units_produced).fit()
print('alpha only quad', -ra.params['hum']/2/ra.params['I(hum ** 2)'])
# C3
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def cf(row_line,dates):
    pass
res={}
for mode in ['reset','cap']:
    ncf=[]
    for l,x in b.groupby('line'):
        orig=sorted(m[m.line==l].date)
        aug=[];last=orig[0]; aug.append(last)
        end=pd.Timestamp('2025-10-01')
        oi=1
        while True:
            nxt_o=orig[oi] if oi<len(orig) else end+pd.Timedelta(days=100)
            nxt=last+pd.Timedelta(days=14)
            if nxt<nxt_o: last=nxt
            else: last=nxt_o; oi+=1
            aug.append(last)
            if last>end: break
        aug=pd.Series(sorted(set(aug)))
        for i,row in x.iterrows():
            c=aug[aug<=row.d].max(); ncf.append((i,(row.d-c).days))
    s=pd.Series(dict(ncf)); b['dsc_cf']=s
    if mode=='cap': b['dsc_cf']=np.minimum(b.dsc,14)
    d=b.dropna(subset=['mtc','hum']).copy()
    p0=r.predict(d); d2=d.copy(); d2['dsc']=d.dsc_cf; p1=r.predict(d2)
    ratio=(p1/p0)
    new=(d.defective_units*ratio).sum()
    # include rows with missing covariates unchanged-ish: apply mean ratio
    rest=b.loc[~b.index.isin(d.index)]
    new+=rest.defective_units.sum()*(new/d.defective_units.sum())
    print(mode,(d.dsc!=d.dsc_cf).sum(), new/b.units_produced.sum(), (d.defective_units.sum()+rest.defective_units.sum())/b.units_produced.sum())
E
python3 -I $TMPDIR/v.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_c0w8lb9m; python3 - <<'E'
import re
s=open('/tmp/claude-0/v.py').read() if False else None
E
sed -i "s/bs(hum,df=5)/cr(hum,df=5)/; s/tab2=pd.concat(\[a.iloc\[\[0\]\]\]\*len(hs),ignore_index=True); tab2\['hum'\]=hs/tab2=pd.concat([a.iloc[[0]]]*len(hs),ignore_index=True); tab2['hum']=hs/" $TMPDIR/v.py
python3 -I $TMPDIR/v.py 2>&1 | grep -v Warn | tail -12; cat /tmp/edabench_claude_c0w8lb9m/suppliers.csv
