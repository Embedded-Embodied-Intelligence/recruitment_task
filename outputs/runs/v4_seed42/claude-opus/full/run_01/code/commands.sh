cd /tmp/edabench_claude_11gjv2e7; ls; head -5 *.csv; wc -l *.csv; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv'); print(b.dtypes); print(b.describe(include='all').T.to_string())
print(pd.read_csv('suppliers.csv').to_string()); m=pd.read_csv('maintenance.csv'); print(m.head(20)); print(m.describe(include='all').T)"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv'); m=pd.read_csv('maintenance.csv')
print(m[m.event!='mold_cleaning']); print(m.to_string())
for c in ['shift','supplier_code','line','operator_id']: print(b[c].value_counts())
print(b.production_date.str[:3].value_counts().head(20))
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id'); print(d.head(10).to_string()); print(d.drop(columns='batch_id').duplicated().sum(), len(d))
print(b.mold_temp.round(-1).value_counts().sort_index().to_string())
print(b.humidity_pct.value_counts().head()); print((b.humidity_pct<=0).sum(), (b.humidity_pct>100).sum())
"

cd /tmp/edabench_claude_11gjv2e7; mkdir -p work; cat > work/clean.py <<'EOF'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
assert b.batch_id.is_unique
def pdt(s):
    return pd.to_datetime(s, format='%Y-%m-%d') if '-' in s else pd.to_datetime(s, format='%m/%d/%Y')
b['date']=b.production_date.map(pdt)
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['supplier_code']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['mt']=b.mold_temp.where(b.mold_temp>0)
b['F']=b.mt>300
b.loc[b.F,'mt']=(b.loc[b.F,'mt']-32)*5/9
b['rate']=b.defective_units/b.units_produced
s=pd.read_csv('suppliers.csv'); b=b.merge(s,on='supplier_code',how='left')
b.to_pickle('work/b.pkl')
EOF
python3 work/clean.py; python3 -c "
import pandas as pd; b=pd.read_pickle('work/b.pkl')
print(len(b), b.hum.isna().sum(), b.defective_units.sum()/b.units_produced.sum(), b.mt.median())
print(b.date.min(), b.date.max())
print(b.groupby(['line',b.date.dt.month]).F.mean().unstack().round(2))
print(b.groupby(['line',b.date.dt.month]).mt.median().unstack().round(1))
print(b[['rate','qc_inspection_min','rework_cost_eur','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','units_produced']].corr().round(2))
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd; b=pd.read_csv('batches.csv')
s=b.production_date
sl=s[s.str.contains('/')]
p=sl.str.split('/',expand=True).astype(int)
print(((p[0]>12)).sum(), (p[1]>12).sum(), ((p[0]<=12)&(p[1]<=12)).sum())
print(s.iloc[1000:1040].tolist())
"

cd /tmp/edabench_claude_11gjv2e7; cat > work/clean.py <<'EOF'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)
assert b.batch_id.is_unique
s=b.production_date
iso=pd.to_datetime(s.where(s.str.contains('-')),format='%Y-%m-%d')
mdy=pd.to_datetime(s.where(s.str.contains('/')),format='%m/%d/%Y',errors='coerce')
dmy=pd.to_datetime(s.where(s.str.contains('/')),format='%d/%m/%Y',errors='coerce')
known=iso.fillna(mdy.where(dmy.isna())).fillna(dmy.where(mdy.isna()))
ref=known.ffill().bfill()
amb=known.isna()
pick=np.where((mdy-ref).abs()<=(dmy-ref).abs(),mdy,dmy)
b['date']=known.where(~amb,pd.Series(pick,index=b.index))
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['supplier_code']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['mt']=b.mold_temp.where(b.mold_temp>0)
b['F']=b.mt>300
b.loc[b.F,'mt']=(b.loc[b.F,'mt']-32)*5/9
b['rate']=b.defective_units/b.units_produced
s=pd.read_csv('suppliers.csv'); b=b.merge(s,on='supplier_code',how='left')
b.to_pickle('work/b.pkl')
EOF
python3 work/clean.py; python3 -c "
import pandas as pd; b=pd.read_pickle('work/b.pkl')
print(len(b), b.hum.isna().sum(), b.defective_units.sum()/b.units_produced.sum(), b.mt.median())
print(b.date.min(), b.date.max(), (b.date.diff().dt.days<0).sum(), b.date.diff().dt.days.abs().max())
print(b.groupby(['line',b.date.dt.month]).F.mean().unstack().round(2))
print(b.groupby(['line',b.date.dt.month]).mt.median().unstack().round(1))
print(b.groupby(['line',b.date.dt.month]).rate.mean().unstack().round(3))
print(b[['rate','qc_inspection_min','rework_cost_eur','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','units_produced']].corr().round(2))
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd; b=pd.read_pickle('work/b.pkl')
d=b.date.diff().dt.days
i=d[(d<0)|(d>3)].index
for j in i[:15]: print(b.loc[j-2:j+1,['production_date','date']].values.tolist())
print(b.tail(70).production_date.tolist())
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd; b=pd.read_pickle('work/b.pkl')
d=b.date.diff().dt.days
i=d[(d<0)|(d>3)].index
for j in i[:15]: print(b.loc[j-2:j+1,['production_date','date']].values.tolist())
print(b.tail(70).production_date.tolist())
"

cd /tmp/edabench_claude_11gjv2e7; python3 - <<'EOF'
import re
src=open('work/clean.py').read()
src=src.replace("b=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)\nassert b.batch_id.is_unique\n","b=pd.read_csv('batches.csv')\n")
src=src.replace("ref=known.ffill().bfill()","ref=pd.to_datetime(known.astype('int64').where(known.notna()).rolling(15,center=True,min_periods=1).median())")
src=src.replace("b['date']=known.where(~amb,pd.Series(pick,index=b.index))\n",
"b['date']=known.where(~amb,pd.Series(pick,index=b.index))\nb['dist']=(b.date-ref).abs()\nb=b.sort_values('dist').drop_duplicates('batch_id').sort_index().drop(columns='dist').reset_index(drop=True)\nassert len(b)==3000\n")
open('work/clean.py','w').write(src)
EOF
python3 work/clean.py; python3 -c "
import pandas as pd; b=pd.read_pickle('work/b.pkl')
print(len(b), b.hum.isna().sum(), b.defective_units.sum()/b.units_produced.sum(), b.mt.median())
d=b.date.diff().dt.days; print(b.date.min(), b.date.max(), (d<0).sum(), d.min(), d.max())
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd; b=pd.read_pickle('work/b.pkl')
d=b.date.diff().dt.days
for j in d[(d<0)].index[:8]: print(b.loc[j-2:j+1,['batch_id','production_date','date']].values.tolist())
print(b[b.date<'2025-01-06'])
"

cd /tmp/edabench_claude_11gjv2e7; python3 - <<'EOF'
src=open('work/clean.py').read()
old=src[src.index("ref="):src.index("b['dist']")]
new='''kn=known.dropna()
def ref_at(i):
    w=kn[(kn.index>=i-10)&(kn.index<=i+10)]
    return w.sort_values().iloc[len(w)//2]
ref=pd.Series([ref_at(i) for i in b.index],index=b.index)
amb=known.isna()
pick=[m if abs((m-r).days)<=abs((d-r).days) else d for m,d,r in zip(mdy,dmy,ref)]
b['date']=known.where(~amb,pd.Series(pick,index=b.index))
'''
src=src.replace(old,new)
open('work/clean.py','w').write(src)
EOF
cat work/clean.py; python3 work/clean.py; python3 -c "
import pandas as pd; b=pd.read_pickle('work/b.pkl')
print(len(b), b.hum.isna().sum(), b.defective_units.sum()/b.units_produced.sum(), b.mt.median())
d=b.date.diff().dt.days; print(b.date.min(), b.date.max(), (d<0).sum(), d.min(), d.max())
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, statsmodels.formula.api as smf; b=pd.read_pickle('work/b.pkl')
b['post']=(b.date>='2025-04-14').astype(int)
b['L1post']=((b.line=='L1')&(b.post==1)).astype(int)
r=smf.ols('mt~ambient_temp_c+C(line)+post+L1post+cycle_time_s+C(supplier_code)',b).fit(); print(r.summary().tables[1])
b['wk']=b.date.dt.to_period('W')
b['res']=b.mt-smf.ols('mt~ambient_temp_c',b).fit().predict(b)
print(b.groupby(['wk','line']).res.mean().unstack().round(1).iloc[8:20])
print(b.groupby(['line','post']).mt.std())
"

cd /tmp/edabench_claude_11gjv2e7; cat > work/feat.py <<'EOF'
import pandas as pd, numpy as np
b=pd.read_pickle('work/b.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
cl=m[m.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date
    return (r.date-c.max()).days
b['dsc']=b.apply(dsc,axis=1)
b['cdev']=b.cycle_time_s-b.recipe_cycle_time_s
b['L1post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
b['ok']=b.units_produced-b.defective_units
b.to_pickle('work/f.pkl')
EOF
python3 work/feat.py; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm; b=pd.read_pickle('work/f.pkl')
print(b.dsc.describe())
b['mtc']=b.mt-6.17*b.L1post
d=b.dropna(subset=['mtc','hum'])
f='rate~mtc+I(mtc**2)+hum*C(supplier_name)+I(hum**2)*C(supplier_name)+cdev+I(cdev**2)+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+dsc+C(line)+units_produced'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(); print(r.summary().tables[1])
print(np.corrcoef(b.qc_inspection_min,b.defective_units)[0,1],np.corrcoef(b.rework_cost_eur,b.defective_units)[0,1], (b.rework_cost_eur/b.defective_units).describe())
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np; b=pd.read_pickle('work/f.pkl')
print(b.groupby('line')[['machine_age_years','units_produced','qc_inspection_min','rate','dsc']].describe().T.round(2).to_string())
print(pd.crosstab(b.operator_id,b.line).to_string())
print(pd.crosstab(b.line,b.shift))
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm; b=pd.read_pickle('work/f.pkl')
b['mtc']=b.mt-6.17*b.L1post
d=b.dropna(subset=['mtc','hum']).copy()
f='rate~mtc+I(mtc**2)+hum*C(supplier_name)+I(hum**2)*C(supplier_name)+cdev+I(cdev**2)+machine_age_years+ambient_temp_c+C(shift)+dsc'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
d['res']=np.log(d.rate/(1-d.rate))-r.predict(d,which='linear')
d['wk']=d.date.dt.to_period('W').dt.start_time.dt.strftime('%m-%d')
pd.set_option('display.width',250)
print(pd.concat([d.groupby(['wk','line']).res.mean().unstack().round(2), d.groupby(['wk','line']).qc_inspection_min.mean().unstack().round(1),(d.groupby(['wk','line']).units_produced.mean().unstack()/10).round(0)],axis=1).to_string())
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm; b=pd.read_pickle('work/f.pkl')
b['mtc']=b.mt-6.17*b.L1post
d=b.dropna(subset=['mtc','hum']).copy()
f='rate~mtc+I(mtc**2)+hum*C(supplier_name)+I(hum**2)*C(supplier_name)+cdev+I(cdev**2)+machine_age_years+ambient_temp_c+C(shift)+dsc'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
d['res']=np.log(d.rate/(1-d.rate))-r.predict(d,which='linear')
for L,a,z in [('L2','2025-06-05','2025-06-25'),('L3','2025-07-10','2025-07-28')]:
  x=d[(d.line==L)&(d.date>=a)&(d.date<=z)]
  print(x.groupby('date').agg(res=('res','mean'),qc=('qc_inspection_min','mean'),n=('res','size')).round(2).to_string())
print(smf.ols('qc_inspection_min~defective_units+units_produced+C(line)',b[b.date<'2025-06-01']).fit().summary().tables[1])
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm; b=pd.read_pickle('work/f.pkl')
b['L2post']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['L3post']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
L1pre=((b.line=='L1')&(b.date<'2025-04-14')).astype(int)
for nm,mt in [('raw',b.mt),('post-6',b.mt-6.17*b.L1post),('pre+6',b.mt+6.17*L1pre)]:
  b['m']=mt; print(nm, mt.median())
  d=b.dropna(subset=['m','hum'])
  for ld in ['','+C(line)']:
    f='rate~m+I(m**2)+hum*C(supplier_name)+I(hum**2)*C(supplier_name)+cdev+I(cdev**2)+machine_age_years+ambient_temp_c+C(shift)+dsc+L2post+L3post'+ld
    r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
    print(ld, round(r.deviance,1), r.params[['m','I(m ** 2)','ambient_temp_c','machine_age_years']].round(4).to_dict(), -r.params['m']/2/r.params['I(m ** 2)'])
"

cd /tmp/edabench_claude_11gjv2e7; cat > work/model.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
b=pd.read_pickle('work/f.pkl')
b['L2post']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['L3post']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['m']=b.mt-6.17*b.L1post
b.to_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy()
terms={'mold_temp':['m','I(m**2)'],'humidity_pct':['hum*C(supplier_name)','I(hum**2)*C(supplier_name)'],'cycle_time_s':['cdev','I(cdev**2)'],
'machine_age_years':['machine_age_years'],'ambient_temp_c':['ambient_temp_c'],'operator_id':['C(operator_id)'],'shift':['C(shift)']}
base=['C(supplier_name)','dsc','L2post','L3post','C(line)']
def fit(ts):
    return smf.glm('rate~'+'+'.join(ts),d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
full=fit(base+sum(terms.values(),[]))
print('dispersion',full.scale)
for k,v in terms.items():
    red=fit(base+sum([t for kk,t in terms.items() if kk!=k],[]))
    df=full.df_model-red.df_model
    F=(red.deviance-full.deviance)/df/full.scale
    print(k,df,round(F,2),stats.f.sf(F,df,full.df_resid))
print(full.summary().tables[1])
EOF
python3 work/model.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm; b=pd.read_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy()
f='rate~C(supplier_name)+dsc+L2post+L3post+C(line)+C(shift)+cdev'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
d['res']=np.log(d.rate/(1-d.rate))-r.predict(d,which='linear')
d['hb']=(d.hum//5*5)
print(d.groupby(['hb','supplier_name']).res.agg(['mean','size']).unstack().round(2).to_string())
d['mb']=d.m.round(0)//3*3
print(d.groupby('mb').res.agg(['mean','size']).round(2).to_string())
d['cb']=d.cdev.round()
print(d.groupby(['cb','supplier_name']).res.agg(['mean','size']).unstack().round(2).to_string())
print(d.groupby('dsc').res.agg(['mean','size']).round(2).to_string())
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm; b=pd.read_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy()
f='rate~C(supplier_name)*(hum+I(hum**2))+m+L2post+L3post+C(line)+C(shift)'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
d['res']=np.log(d.rate/(1-d.rate))-r.predict(d,which='linear')
print(d.groupby(d.dsc.clip(upper=26)//2*2).res.agg(['mean','size']).round(2).T.to_string())
d['cb']=d.cdev.round()//2*2
print(d.groupby(['cb','supplier_name']).res.mean().unstack().round(2).T.to_string())
d['cb']=d.cycle_time_s.round()//2*2
print(d.groupby(['cb','supplier_name']).res.mean().unstack().round(2).T.to_string())
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm; from scipy import stats; b=pd.read_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy()
base='rate~C(supplier_name)*(hum+I(hum**2))+m+cdev+dsc+L2post+L3post+C(line)+C(shift)+machine_age_years+ambient_temp_c'
fit=lambda f,x: smf.glm(f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
r0=fit(base,d); r1=fit(base+'+C(operator_id)',d)
print(r0.deviance, r0.df_resid, r0.pearson_chi2/r0.df_resid, r1.deviance, r1.pearson_chi2/r1.df_resid)
# residual diagnostics
d['res']=(d.rate-r0.mu)/np.sqrt(r0.mu*(1-r0.mu)/d.units_produced)
print(d.groupby('line').res.agg(['mean','var']))
print(d.groupby(pd.qcut(d.units_produced,5)).res.var())
print(d.groupby(['line','operator_id']).res.mean().round(2).to_string())
print(d.groupby(['line','shift']).res.mean().round(2))
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf; from scipy import stats; b=pd.read_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy()
d['y']=np.log((d.defective_units+.5)/(d.ok+.5))
base='y~C(supplier_name)*(hum+I(hum**2))+m+cdev+dsc+L2post+L3post+C(line)+C(shift)+machine_age_years+ambient_temp_c'
r0=smf.ols(base,d).fit(); 
# variance: binomial part + batch RE
v=1/(d.defective_units+.5)+1/(d.ok+.5)
s2=max(np.var(r0.resid)-v.mean(),0); print('tau2',s2)
w=1/(v+s2)
r0=smf.wls(base,d,weights=w).fit(); r1=smf.wls(base+'+C(operator_id)',d,weights=w).fit()
print(r1.compare_f_test(r0))
print(r0.params.round(4).to_string())
for t in ['machine_age_years','ambient_temp_c','C(shift)','m']:
  rr=smf.wls(base.replace('+'+t,''),d,weights=w).fit(); print(t, r0.compare_f_test(rr)[1])
"

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf; b=pd.read_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy()
d['y']=np.log((d.defective_units+.5)/(d.ok+.5))
v=1/(d.defective_units+.5)+1/(d.ok+.5); d['w']=1/(v+0.054)
base='y~C(supplier_name)*(hum+I(hum**2))+m+cdev+dsc+L2post+L3post+C(shift)+machine_age_years+ambient_temp_c'
r=smf.wls(base+'+C(line)',d,weights=d.w).fit(); print(r.pvalues[['m','cdev','dsc','machine_age_years','ambient_temp_c']])
for L in ['L1','L2','L3','L4']:
  x=d[d.line==L]; rr=smf.wls(base.replace('+L2post','').replace('+L3post','') + ('+L2post' if L=='L2' else '')+('+L3post' if L=='L3' else ''),x,weights=x.w).fit()
  print(L, rr.params[['machine_age_years','m','ambient_temp_c']].round(4).to_dict(), rr.bse['machine_age_years'].round(4))
"

cd /tmp/edabench_claude_11gjv2e7; cat > work/cf.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('work/g.pkl')
# impute humidity / mold temp for counterfactual prediction
print('hum corr same day across batches:', b.groupby('date').hum.transform('std').mean(), b.hum.std())
b['hum_i']=b.hum.fillna(b.groupby('date').hum.transform('mean')).fillna(b.hum.mean())
b['m_i']=b.m.fillna(b.groupby(['line','date']).m.transform('mean')).fillna(b.groupby('line').m.transform('mean'))
d=b.dropna(subset=['m','hum']).copy()
d['y']=np.log((d.defective_units+.5)/(d.ok+.5))
v=1/(d.defective_units+.5)+1/(d.ok+.5); d['w']=1/(v+0.054)
f='y~C(supplier_name)*(hum+I(hum**2))+m+cdev+dsc+L2post+L3post+C(shift)+C(line)'
r=smf.wls(f,d,weights=d.w).fit()
g=smf.glm(f.replace('y~','rate~'),d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
X=b.assign(hum=b.hum_i,m=b.m_i)
for mod,nm in [(r,'wls'),(g,'glm')]:
    eta0=mod.predict(X,which='linear') if nm=='glm' else mod.predict(X)
    lo=np.log(b.rate/(1-b.rate))  # observed logit (rates never 0)
    for keep in [True,False]:
        out={}
        for s in ['Alpha','Beta','Gamma']:
            Z=X.assign(supplier_name=s, cdev=X.cdev if keep else 0)
            Z0=X.assign(cdev=X.cdev if keep else 0)
            e1=mod.predict(Z,which='linear') if nm=='glm' else mod.predict(Z)
            e0=mod.predict(Z0,which='linear') if nm=='glm' else mod.predict(Z0)
            p=1/(1+np.exp(-(lo+e1-eta0)))
            out[s]=round((p*b.units_produced).sum()/b.units_produced.sum(),5)
        print(nm,'keep cdev' if keep else 'cdev=0',out)
    # C2
    hs=np.linspace(b.hum.min(),b.hum.max(),2001)
    pa=mod.params
    a=pa['hum']; q=pa['I(hum ** 2)']; print(nm,'alpha opt hum',-a/2/q)
    # C3
    bd=mod.params['dsc']; dn=b.dsc%14
    p=1/(1+np.exp(-(lo+bd*(dn-b.dsc))))
    print(nm,'C3',(p*b.units_produced).sum()/b.units_produced.sum(), 'beta',bd)
print(b.hum.min(),b.hum.max())
EOF
python3 work/cf.py

cd /tmp/edabench_claude_11gjv2e7; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf; b=pd.read_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy(); d=d[d.supplier_name=='Alpha']
d['y']=np.log((d.defective_units+.5)/(d.ok+.5))
v=1/(d.defective_units+.5)+1/(d.ok+.5); d['w']=1/(v+0.054)
r=smf.wls('y~bs(hum,df=6)+m+cdev+dsc+L2post+L3post+C(shift)+C(line)',d,weights=d.w).fit()
hs=np.arange(12.5,72,0.5); X=d.iloc[[0]*len(hs)].assign(hum=hs)
p=r.predict(X); print(hs[np.argmin(p)]); print(pd.Series(np.round(p.values-p.min(),3),index=hs).iloc[::4].to_string())
"
