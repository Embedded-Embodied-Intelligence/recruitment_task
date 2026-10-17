cd /tmp/edabench_claude_3e2b14e3; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_3e2b14e3; cat suppliers.csv; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.nunique())
for c in ['production_date','line','shift','operator_id','supplier_code']:
    print(b[c].value_counts(dropna=False).head(30))
for c in b.columns[6:]:
    x=pd.to_numeric(b[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(b[c][x.isna()].value_counts(dropna=False).head())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id'); print(len(d)); print(d.head(10).to_string())
E
python3 -I $TMPDIR/a.py; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_3e2b14e3; grep -n sensor maintenance.csv; cat > $TMPDIR/b.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b), b.batch_id.nunique())
def pd_(s):
    return pd.to_datetime(s,format='%Y-%m-%d',errors='coerce').fillna(pd.to_datetime(s,format='%m/%d/%Y',errors='coerce'))
b['date']=pd_(b.production_date); print(b.date.isna().sum(),b.date.min(),b.date.max())
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
print(b.humidity_pct.describe(), (b.humidity_pct<=0).sum(), b.humidity_pct.isna().sum(), (b.humidity_pct>100).sum())
print(b.humidity_pct.sort_values().head(8).tolist())
print(np.histogram(b.mold_temp,bins=[-1,1,100,150,180,200,220,240,260,300,350,400,450,500]))
b['mt']=b.mold_temp
print(b[b.mold_temp<150].mold_temp.describe())
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
print(b.groupby([b.date.dt.to_period('M'),'line']).mold_temp.median().unstack())
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/c.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
s=b.production_date[b.production_date.str.contains('/')]
p=s.str.split('/',expand=True).astype(int)
print(len(s),(p[0]>12).sum(),(p[1]>12).sum(), p[2].unique())
print(b[b.production_date.str.contains('/')].head(20)[['production_date','line']])
# ordering
print(b.production_date.head(40).tolist())
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/c.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
s=b[b.production_date.str.contains('/')].copy()
p=s.production_date.str.split('/',expand=True).astype(int)
s['a']=p[0];s['b']=p[1]
print(s.groupby('line').agg(n=('a','size'),amax=('a','max'),bmax=('b','max')))
print(b.groupby('line').production_date.apply(lambda x:x.str.contains('/').mean()))
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/d.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates('batch_id')
def pdt(r):
    s=r.production_date
    if '/' in s: return pd.to_datetime(s,format='%m/%d/%Y' if r.line=='L1' else '%d/%m/%Y')
    return pd.to_datetime(s)
b['date']=b.apply(pdt,axis=1)
print(b.date.min(),b.date.max())
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
print('A2',b.hum.isna().sum())
print('A3',b.defective_units.sum()/b.units_produced.sum())
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
print(b.mt.describe())
print('A4',b.mt.median())
print(b.groupby([b.date.dt.to_period('M'),'line']).mt.median().unstack())
b['rate']=b.defective_units/b.units_produced
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
# L1 around sensor
l=b[b.line=='L1'].sort_values('date')
print(l.groupby(l.date.dt.to_period('W')).agg(mt=('mt','median'),r=('rate','mean')).loc['2025-03':'2025-05'])
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/e.py <<'E'
import pandas as pd, numpy as np, os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
import statsmodels.formula.api as smf
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
m=smf.ols('mt~ambient_temp_c+C(line)+post+C(sup)+machine_age_years+cycle_time_s',b.dropna(subset=['mt'])).fit()
print(m.summary().tables[1])
l=b[b.line=='L1'];l=l.assign(post=l.date>='2025-04-14')
print(l.groupby('post')[['mt','ambient_temp_c','cycle_time_s']].mean())
print(b.groupby('line').ambient_temp_c.mean())
print(b.groupby(b.date.dt.to_period('M')).ambient_temp_c.mean())
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/f.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
b['nd']=b.units_produced-b.defective_units
b['dev']=b.mt-b.mt.mean()
f='nd+defective_units~ hum+I(hum**2)+mt+I(mt**2)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+C(line)+post'
d=b.dropna(subset=['mt','hum'])
d=d.assign(y=d.rate)
m=smf.glm('rate~hum+I(hum**2)+mt+I(mt**2)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)+post+C(operator_id)',d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit()
print(m.summary().tables[1])
E
python3 -I $TMPDIR/f.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/g.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['cd']=b.cycle_time_s-b.rec
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
print(b.groupby('sup')[['cycle_time_s','cd','hum','mt']].agg(['mean','std']))
print(b.groupby('line')[['rate']].mean(), b.groupby('shift').rate.mean(), b.groupby('sup').rate.mean())
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    return smf.glm(f,d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit(scale='X2')
m=fit('rate~C(sup)*(hum+I(hum**2))+mt+I(mt**2)+cd+I(cd**2)+machine_age_years+ambient_temp_c+C(shift)+C(line)+C(operator_id)')
print(m.summary().tables[1]); print(m.scale)
E
python3 -I $TMPDIR/g.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/g.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['cd']=b.cycle_time_s-b.rec
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
b['nd']=b.units_produced-b.defective_units
d=b.dropna(subset=['mt','hum']).copy()
def fit(f):
    m=smf.glm('nd+defective_units~'+f,d,family=sm.families.Binomial()).fit(scale='X2'); return m
import sys
m=fit('C(sup)*(hum+I(hum**2))+mt+I(mt**2)+cd+I(cd**2)+machine_age_years+ambient_temp_c+C(shift)+C(line)+C(operator_id)')
print(m.summary().tables[1]); print(m.scale)
E
python3 -I $TMPDIR/g.py 2>&1 | grep -v -i Warn

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/g.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['cd']=b.cycle_time_s-b.rec
b['nd']=b.units_produced-b.defective_units
b['mtc']=b.mt-213; b['ageq']=b.machine_age_years
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    y=np.column_stack([d.defective_units,d.nd])
    m=smf.glm('y~'+f,d.assign(y=list(y)) if False else d,family=sm.families.Binomial()).fit(scale='X2'); return m
import patsy
def fit(f,d=d):
    Y,X=patsy.dmatrices('rate~'+f,d)
    return sm.GLM(np.asarray(Y)[:,0],X,family=sm.families.Binomial(),var_weights=d.units_produced.values).fit(scale='X2'),X.design_info.column_names
for f in ['C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+cd+I(cd**2)+machine_age_years+ambient_temp_c+C(shift)+C(line)+C(operator_id)']:
    m,n=fit(f)
    print(pd.DataFrame({'c':m.params,'z':m.tvalues},index=n).round(3)); print(m.scale)
E
python3 -I $TMPDIR/g.py 2>&1 | grep -v -i Warn

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/h.py <<'E'
import pandas as pd, numpy as np, os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
print(pd.crosstab(b.operator_id,b.line))
print(pd.crosstab(b['shift'],b.line))
print(pd.crosstab(b.sup,b.line))
print(b.groupby('shift')[['hum','ambient_temp_c','mt','cycle_time_s','machine_age_years']].mean())
print(b.groupby('line')[['hum','mt','cycle_time_s','machine_age_years']].mean())
E
python3 -I $TMPDIR/h.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/i.py <<'E'
import pandas as pd, numpy as np, os, patsy
import statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['cd']=b.cycle_time_s-b.rec
b['mtc']=b.mt-213
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    Y,X=patsy.dmatrices('rate~'+f,d)
    return sm.GLM(np.asarray(Y)[:,0],X,family=sm.families.Binomial(),var_weights=d.units_produced.values).fit(scale='X2'),X.design_info.column_names
base='C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+cd+I(cd**2)+ambient_temp_c+C(shift)'
for extra in ['C(line)+machine_age_years','C(line)','machine_age_years','C(line)+machine_age_years+C(operator_id)','C(line)+C(operator_id)']:
    m,n=fit(base+'+'+extra); print(extra,m.deviance/m.scale if 0 else m.pearson_chi2, m.df_resid)
    if 'operator' not in extra: print(pd.DataFrame({'c':m.params,'z':m.tvalues},index=n).round(3).loc[['machine_age_years','ambient_temp_c','C(shift)[T.N]','mtc','cd']  if 'machine_age_years' in extra else ['ambient_temp_c','C(shift)[T.N]','mtc','cd']])
E
python3 -I $TMPDIR/i.py 2>&1 | grep -v -i Warn

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/j.py <<'E'
import pandas as pd, numpy as np, os, patsy
import statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
mt=pd.read_csv('maintenance.csv',parse_dates=['date']); mt=mt[mt.event=='mold_cleaning']
print(mt.groupby('line').date.apply(lambda s:s.sort_values().diff().dt.days.tolist()))
print(mt.groupby('line').date.agg(['min','max','count']))
b=b.sort_values('date')
out=[]
for l,g in b.groupby('line'):
    c=mt[mt.line==l][['date']].rename(columns={'date':'cd_'}).sort_values('cd_')
    g=pd.merge_asof(g.sort_values('date'),c,left_on='date',right_on='cd_',direction='backward')
    out.append(g)
b=pd.concat(out); b['dsc']=(b.date-b.cd_).dt.days
print(b.dsc.describe(), b.dsc.isna().sum())
b.to_pickle(os.environ['TMPDIR']+'/b2.pkl')
print(b.groupby('dsc').agg(n=('rate','size'),r=('rate','mean'),d=('defective_units','sum'),u=('units_produced','sum')).assign(w=lambda x:x.d/x.u).w.round(4).to_string())
E
python3 -I $TMPDIR/j.py 2>&1

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/k.py <<'E'
import pandas as pd, numpy as np, os, patsy
import statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['cd']=b.cycle_time_s-b.rec
b['mtc']=b.mt-213
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    Y,X=patsy.dmatrices('rate~'+f,d)
    return sm.GLM(np.asarray(Y)[:,0],X,family=sm.families.Binomial(),var_weights=d.units_produced.values).fit(scale='X2'),X.design_info.column_names
base='C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+cd+I(cd**2)+ambient_temp_c+C(shift)+C(line)'
for k in [0,4,6,8,10,12,14]:
    d['h']=np.maximum(d.dsc-k,0)
    m,n=fit(base+'+h'); print(k,round(m.pearson_chi2),m.params[n.index('h')],m.tvalues[n.index('h')])
d['h']=np.maximum(d.dsc-8,0)
m,n=fit(base+'+h'); 
d['res']=d.rate-m.predict(patsy.dmatrix(base+'+h',d)); 
d['pr']=m.predict(patsy.dmatrix(base+'+h',d))
r=d.assign(w=d.units_produced*(d.rate-d.pr),e=d.units_produced*d.pr)
print(r.groupby(['line',r.date.dt.to_period('M')]).apply(lambda g:g.w.sum()/g.e.sum()).unstack(0).round(2))
E
python3 -I $TMPDIR/k.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_3e2b14e3; cat >> $TMPDIR/k.py <<'E'
print('-----')
d['h']=d.dsc
m,n=fit(base+'+h'); d['pr']=m.predict(patsy.dmatrix(base+'+h',d))
print(pd.DataFrame({'c':m.params,'z':m.tvalues},index=n).round(3))
r=d.assign(w=d.units_produced*(d.rate-d.pr),e=d.units_produced*d.pr)
for l in ['L1','L2','L3','L4']:
    g=r[r.line==l]
    print(l);print(g.groupby(g.date.dt.to_period('W')).apply(lambda g:g.w.sum()/g.e.sum()).round(2).to_string())
E
python3 -I $TMPDIR/k.py 2>&1 | grep -v -i warn | sed -n '/-----/,$p'

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/l.py <<'E'
import pandas as pd, numpy as np, os
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
b['cpd']=b.rework_cost_eur/b.defective_units
for l,a,z in [('L2','2025-06-01','2025-07-01'),('L3','2025-07-08','2025-08-05')]:
    g=b[(b.line==l)&(b.date>=a)&(b.date<z)]
    print(g.groupby('date').agg(n=('rate','size'),r=('rate','mean'),q=('qc_inspection_min','mean'),cpd=('cpd','mean'),hum=('hum','mean'),mt=('mt','mean'),dsc=('dsc','mean')).round(3).to_string())
for l in ['L2','L3']:
    g=b[b.line==l]; print(l, g.groupby(g.date.dt.to_period('M'))[['qc_inspection_min','cpd']].mean().round(2).T)
E
python3 -I $TMPDIR/l.py

cd /tmp/edabench_claude_3e2b14e3; cat >> $TMPDIR/k.py <<'E'
print('=====')
g=r[r.line=='L2']
best=[]
for dt in pd.date_range('2025-06-05','2025-06-25'):
    gg=g.assign(s=(g.date>=dt).astype(int))
    Y,X=patsy.dmatrices('rate~s+offset_',gg.assign(offset_=0),return_type='dataframe')
    mm=sm.GLM(gg.rate.values,np.column_stack([np.ones(len(gg)),gg.s]),family=sm.families.Binomial(),var_weights=gg.units_produced.values,offset=np.log(gg.pr/(1-gg.pr)).values).fit()
    print(dt.date(),round(mm.llf,2),round(mm.params[1],3))
E
python3 -I $TMPDIR/k.py 2>&1 | sed -n '/=====/,$p'

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/m.py <<'E'
import pandas as pd, numpy as np, os
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
b['cpd']=b.rework_cost_eur/b.defective_units
g=b[~((b.line=='L3')&(b.date>='2025-07-21'))]
print(g[['qc_inspection_min','rework_cost_eur','cpd','rate','defective_units','units_produced','hum','mt','cycle_time_s','ambient_temp_c','machine_age_years']].corr().round(2).iloc[:3])
print(g.groupby(pd.qcut(g.rate,8)).qc_inspection_min.mean())
E
python3 -I $TMPDIR/m.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/n.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
d=b.dropna(subset=['mt'])
for w in [21,42,70,400]:
    g=d[(d.date>=pd.Timestamp('2025-04-14')-pd.Timedelta(days=w))&(d.date<pd.Timestamp('2025-04-14')+pd.Timedelta(days=w))]
    m=smf.ols('mt~ambient_temp_c+C(line)+post',g).fit(); print(w,m.params['post'],m.bse['post'])
# L1 only, interaction
l=d[d.line=='L1'].assign(post=lambda x:(x.date>='2025-04-14').astype(int))
m=smf.ols('mt~ambient_temp_c*post',l).fit(); print(m.params.round(3), m.bse.round(3).tolist())
# other lines slope
for L in ['L2','L3','L4']:
    print(L,smf.ols('mt~ambient_temp_c',d[d.line==L]).fit().params.round(3).tolist())
# step test dates
g=d[d.line=='L1'].sort_values('date')
res=smf.ols('mt~ambient_temp_c',d[d.line!='L1']).fit()
g['r']=g.mt-res.predict(g)
print(g.groupby(g.date.dt.to_period('W')).r.mean().loc['2025-03':'2025-05'].round(1))
E
python3 -I $TMPDIR/n.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/o.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
d=b.dropna(subset=['mt'])
res=smf.ols('mt~ambient_temp_c',d[d.line.isin(['L2','L4'])]).fit()
for L in ['L3','L4','L2']:
    g=d[d.line==L].copy(); g['r']=g.mt-res.predict(g)
    print(L,g.groupby(g.date.dt.to_period('W')).r.mean().round(1).values.tolist())
g=d[d.line=='L3']; print(g.mold_temp.describe())
print(np.corrcoef(g.ambient_temp_c,g.mold_temp))
print(smf.ols('mold_temp~ambient_temp_c+I(ambient_temp_c**2)',g).fit().params)
E
python3 -I $TMPDIR/o.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/p.py <<'E'
import pandas as pd, numpy as np, os, patsy
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
d=b.dropna(subset=['mt'])
res=smf.ols('mt~ambient_temp_c',d[d.line.isin(['L2','L4'])]).fit()
g=d[d.line=='L3'].copy(); g['r']=g.mt-res.predict(g)
g=g.sort_values('date')
for dt in pd.date_range('2025-05-08','2025-05-30'):
    a=g[g.date<dt].r; c=g[g.date>=dt].r
    print(dt.date(), round(((a-a.mean())**2).sum()+((c-c.mean())**2).sum()), round(c.mean()-a.mean(),2))
E
python3 -I $TMPDIR/p.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/q.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
d=b.dropna(subset=['mt']).copy()
d['t']=(d.date-pd.Timestamp('2025-01-06')).dt.days
for L in ['L2','L3','L4']:
    g=d[d.line==L]
    print(L,smf.ols('mt~ambient_temp_c+I(ambient_temp_c**2)',g).fit().params.round(3).tolist(), smf.ols('mt~ambient_temp_c+t',g).fit().params.round(3).tolist(),smf.ols('mt~ambient_temp_c+t',g).fit().rsquared)
# ambient vs time
print(d.groupby(d.date.dt.to_period('W')).ambient_temp_c.mean().round(1).values.tolist())
E
python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/r.py <<'E'
import pandas as pd, numpy as np, os
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
d=b.dropna(subset=['mt']).copy()
print(d.mt.median())
post=(d.line=='L1')&(d.date>='2025-04-14')
for o in [5,6,6.4]:
    print(o,(d.mt-o*post).median(), (d.mt+o*((d.line=='L1')&~post)).median())
E
python3 -I $TMPDIR/r.py

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/s.py <<'E'
import pandas as pd, numpy as np, os, patsy
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b2.pkl')
b['rec']=b.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
b['cd']=b.cycle_time_s-b.rec
# L1 sensor offset
d0=b.dropna(subset=['mt'])
ref=smf.ols('mt~ambient_temp_c',d0[d0.line.isin(['L2','L4'])]).fit()
l1=d0[d0.line=='L1']; r=l1.mt-ref.predict(l1)
off=r[l1.date>='2025-04-14'].mean()-r[l1.date<'2025-04-14'].mean(); print('offset',off, r[l1.date<'2025-04-14'].mean())
post1=(b.line=='L1')&(b.date>='2025-04-14')
b['mta']=b.mt-off*post1
print('A4 median adj',b.mta.median())
b['mtc']=b.mta-213
b['l2post']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['l3art']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b.to_pickle(os.environ['TMPDIR']+'/b3.pkl')
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    Y,X=patsy.dmatrices('rate~'+f,d)
    return sm.GLM(np.asarray(Y)[:,0],X,family=sm.families.Binomial(),var_weights=d.units_produced.values).fit(scale='X2'),X.design_info.column_names
base='C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+cd+I(cd**2)+ambient_temp_c+machine_age_years+C(shift)+C(line)+l2post+l3art+dsc'
m0,n=fit(base); print(pd.DataFrame({'c':m0.params,'z':m0.tvalues},index=n).round(4)); print(m0.pearson_chi2,m0.df_resid)
def drop(term_regex_f):
    m,_=fit(term_regex_f); 
    df=m0.df_resid; 
    return m
tests={'mold':'C(sup)*(hum+I(hum**2))+cd+I(cd**2)+ambient_temp_c+machine_age_years+C(shift)+C(line)+l2post+l3art+dsc',
'hum':'mtc+I(mtc**2)+C(sup)+cd+I(cd**2)+ambient_temp_c+machine_age_years+C(shift)+C(line)+l2post+l3art+dsc',
'cycle':'C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+ambient_temp_c+machine_age_years+C(shift)+C(line)+l2post+l3art+dsc',
'age':'C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+cd+I(cd**2)+ambient_temp_c+C(shift)+C(line)+l2post+l3art+dsc',
'amb':'C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+cd+I(cd**2)+machine_age_years+C(shift)+C(line)+l2post+l3art+dsc',
'shift':'C(sup)*(hum+I(hum**2))+mtc+I(mtc**2)+cd+I(cd**2)+ambient_temp_c+machine_age_years+C(line)+l2post+l3art+dsc',
}
from scipy import stats
disp=m0.scale
for k,f in tests.items():
    m,_=fit(f); dd=m0.df_resid  ; q=m.df_resid-m0.df_resid
    F=((m.pearson_chi2-m0.pearson_chi2)/q)/disp  # approx
    print(k,q,round(F,2),stats.f.sf(F,q,m0.df_resid))
m1,n1=fit(base+'+C(operator_id)'); q=m0.df_resid-m1.df_resid; F=((m0.pearson_chi2-m1.pearson_chi2)/q)/m1.scale; print('operator',q,F,stats.f.sf(F,q,m1.df_resid))
E
python3 -I $TMPDIR/s.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_3e2b14e3; cat >> $TMPDIR/s.py <<'E'
print('-----')
m1,n1=fit(base.replace('C(line)','C(line)')+'+C(operator_id)')
s=pd.DataFrame({'c':m1.params,'z':m1.tvalues},index=n1).round(3); print(s[s.index.str.contains('operator')])
# operator effect by line with line-specific reference: fit per line
for L in ['L1','L2','L3','L4']:
    g=d[d.line==L]
    f='C(sup)+hum+I(hum**2)+mtc+cd+C(shift)+dsc+l2post+l3art'
    a,_=fit(f,g); bb,_=fit(f+'+C(operator_id)',g); q=a.df_resid-bb.df_resid
    F=((a.pearson_chi2-bb.pearson_chi2)/q)/bb.scale; print(L,q,round(F,2),stats.f.sf(F,q,bb.df_resid))
E
python3 -I $TMPDIR/s.py 2>&1 | sed -n '/-----/,$p'

cd /tmp/edabench_claude_3e2b14e3; cat >> $TMPDIR/s.py <<'E'
print('=====')
for L in ['L1','L2','L3','L4']:
    g=d[d.line==L]; print(L,g.machine_age_years.describe()[['mean','std','min','max']].round(2).tolist())
    f='C(sup)+hum+I(hum**2)+mtc+cd+C(shift)+dsc+l2post+l3art+machine_age_years'
    a,nn=fit(f,g); print(a.params[-1],a.tvalues[-1])
E
python3 -I $TMPDIR/s.py 2>&1 | sed -n '/=====/,$p'

cd /tmp/edabench_claude_3e2b14e3; cat >> $TMPDIR/s.py <<'E'
print('#####')
fa='C(sup)*(hum+I(hum**2))+mtc+cd+C(shift)+C(line)+l2post+l3art+dsc'
fb=fa.replace('+cd','+cycle_time_s')
fc=fa+'+cycle_time_s'
for f in [fa,fb,fc]:
    m,n=fit(f); print(round(m.pearson_chi2,1), m.llf if 0 else '', pd.Series(m.params,index=n)[['cd' if 'cd' in f else 'cycle_time_s']].tolist() )
m,n=fit(fc); print(pd.DataFrame({'c':m.params,'z':m.tvalues},index=n).round(4))
E
python3 -I $TMPDIR/s.py 2>&1 | sed -n '/#####/,$p'

cd /tmp/edabench_claude_3e2b14e3; cat > $TMPDIR/t.py <<'E'
import pandas as pd, numpy as np, os, patsy
import statsmodels.api as sm
from scipy.special import expit, logit
b=pd.read_pickle(os.environ['TMPDIR']+'/b3.pkl')
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=d):
    Y,X=patsy.dmatrices('rate~'+f,d)
    return sm.GLM(np.asarray(Y)[:,0],X,family=sm.families.Binomial(),var_weights=d.units_produced.values).fit(scale='X2')
base='C(sup)*(hum+I(hum**2))+mtc+cd+C(shift)+C(line)+l2post+l3art'
# dsc shape
for extra in ['dsc','dsc+I(dsc**2)','dsc+I(np.maximum(dsc-14,0))','dsc+I(np.maximum(dsc-10,0))']:
    m=fit(base+'+'+extra); print(extra,round(m.pearson_chi2,1),m.params[-2:].round(4).tolist())
m=fit(base+'+dsc'); print(m.params['dsc'] if hasattr(m.params,'index') else m.params[-1])
beta=m.params[-1]
# C3
for ext in ['dsc','dsc+I(dsc**2)']:
    mm=fit(base+'+'+ext)
    d['p']=mm.fittedvalues
    cf=d.assign(dsc=d.dsc%14)
    X=patsy.dmatrix(base+'+'+ext,cf); d['pc']=mm.predict(X)
    # also full-sample
    ratio=(d.pc*d.units_produced).sum()/(d.p*d.units_produced).sum()
    # apply odds scaling to observed defects
    o=logit(d.p); oc=logit(d.pc)
    print(ext,'ratio',ratio,'rate_pred actual',(d.p*d.units_produced).sum()/d.units_produced.sum(),'obs complete',d.defective_units.sum()/d.units_produced.sum())
    # all rows
    a=b.copy(); 
    d_=d.copy(); d_['rr']=d_.pc/d_.p
    tot=(d_.defective_units*d_.rr).sum()+ (b[~b.batch_id.isin(d.batch_id)].defective_units.values*np.exp(mm.params[-1]*(b[~b.batch_id.isin(d.batch_id)].dsc%14-b[~b.batch_id.isin(d.batch_id)].dsc))).sum()
    print('C3 est',tot/b.units_produced.sum())
E
python3 -I $TMPDIR/t.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_3e2b14e3; cat >> $TMPDIR/t.py <<'E'
print('######')
m=fit(base+'+dsc')
X0=patsy.dmatrix(base+'+dsc',d)
for s,nm in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    c=d.assign(sup=s,cd=0,l3art=0)
    p=m.predict(patsy.dmatrix(base+'+dsc',c,return_type='dataframe')) if False else m.predict(patsy.build_design_matrices([X0.design_info],c)[0])
    print(nm,(p*d.units_produced).sum()/d.units_produced.sum(), p.mean())
# C2
a=d[d.sup=='SP-01']
ma=fit('hum+I(hum**2)+mtc+cd+C(shift)+C(line)+l2post+l3art+dsc',a)
pa=ma.params; print(pa[:3], 'vertex',-pa[1]/(2*pa[2]) if False else None)
import numpy as np
nm=['Intercept']+['x']*0
Y,X=patsy.dmatrices('rate~hum+I(hum**2)+mtc+cd+C(shift)+C(line)+l2post+l3art+dsc',a); names=X.design_info.column_names
pp=dict(zip(names,ma.params)); print(pp['hum'],pp['I(hum ** 2)'],-pp['hum']/(2*pp['I(hum ** 2)']))
# grid with full model
grid=np.arange(a.hum.min(),a.hum.max(),0.5)
tot=[]
for h in grid:
    c=a.assign(hum=h,l3art=0); p=ma.predict(patsy.build_design_matrices([X.design_info],c)[0]); tot.append((p*a.units_produced).sum()/a.units_produced.sum())
print(grid[np.argmin(tot)],a.hum.min(),a.hum.max())
# pooled full model
pf=dict(zip(patsy.dmatrices('rate~'+base+'+dsc',d)[1].design_info.column_names,m.params)); print(-pf['hum']/(2*pf['I(hum ** 2)']))
# nonparametric: binned alpha rate
a2=a.assign(hb=pd.cut(a.hum,np.arange(-0,80,5)))
print(a2.groupby('hb').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).round(4))
E
python3 -I $TMPDIR/t.py 2>&1 | sed -n '/######/,$p' | grep -v -i warn
