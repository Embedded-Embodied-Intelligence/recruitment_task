cd /tmp/edabench_claude_hpkw7_gw; ls -la; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_hpkw7_gw; cat maintenance.csv | head -80; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.describe().T)
for c in ['line','shift','operator_id','supplier_code']: print(d[c].value_counts(dropna=False))
print(d.batch_id.duplicated().sum(), d.duplicated().sum())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
  x=pd.to_numeric(d[c],errors='coerce'); print(c, x.isna().sum(), d[c][x.isna()].unique()[:10], x.describe().round(2).to_dict())
print(d.production_date.str.len().value_counts()); print(d.production_date.sample(20,random_state=1).tolist())
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates()
print(len(d), d.batch_id.nunique())
d['fmt']=np.where(d.production_date.str.contains('-'),'iso','slash')
print(pd.crosstab(d.line,d.fmt))
s=d[d.fmt=='slash'].production_date.str.split('/',expand=True).astype(int)
print((s[0]>12).sum(),(s[1]>12).sum(), len(s))
print(pd.crosstab(d.loc[s.index,'line'], [s[0]>12, s[1]>12]))
print(np.histogram(d.mold_temp,bins=[-1,1,100,150,180,200,250,300,350,380,400,420,450,500]))
print(d.humidity_pct.value_counts().head()); print(np.histogram(d.humidity_pct.dropna(),bins=[-2,-0.5,0,5,10,80,101,1000]))
"

cd /tmp/edabench_claude_hpkw7_gw; mkdir -p $TMPDIR; cat > clean.py <<'EOF'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)
def pdate(r):
    s=r.production_date
    if '-' in s: return pd.to_datetime(s)
    return pd.to_datetime(s, format='%m/%d/%Y' if r.line=='L1' else '%d/%m/%Y')
d['date']=d.apply(pdate,axis=1)
d['shift']=d['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
d['supplier_code']=d.supplier_code.str.strip().str.upper()
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.mt>350,'mt']=(d.mt-32)*5/9
d['rate']=d.defective_units/d.units_produced
s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code',how='left')
EOF
python3 -c "
from clean import *
print(d.date.min(),d.date.max(), d['shift'].isna().sum(), d.supplier_name.isna().sum())
print('A2',d.hum.isna().sum(),'A3',d.defective_units.sum()/d.units_produced.sum(),'A4',d.mt.median())
d['F']=d.mold_temp>350
print(pd.crosstab(d.line,d.F)); print(d.groupby([d.line,d.date.dt.month]).mt.median().unstack())
print(d[['rate','qc_inspection_min','rework_cost_eur','defective_units','units_produced']].corr())
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from clean import *
pd.set_option('display.width',200)
for l in ['L1','L2']:
  x=d[d.line==l].set_index('date').sort_index()
  print(l); print(x.mt.resample('W').agg(['median','count']).loc['2025-03':'2025-05'].T.round(1))
  print(x.rate.resample('W').mean().round(4).values)
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from clean import *
pd.set_option('display.width',250); pd.set_option('display.max_columns',50)
x=d[d.line=='L1'].set_index('date').sort_index()
print(x.mt.resample('W').median().round(1).to_string())
print(d.groupby('line').mt.describe())
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from clean import *
import statsmodels.formula.api as smf
print(d[(d.line=='L3')&(d.mold_temp<350)][['date','mold_temp','mt']])
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L1']=(d.line=='L1').astype(int)
d['t']=(d.date-d.date.min()).dt.days
m=smf.ols('mt~post+C(line)+ambient_temp_c+C(supplier_code)+cycle_time_s+machine_age_years+C(shift)',d).fit(); print(m.params.round(3)); print(m.bse['post'])
m=smf.ols('mt~post+C(line)+C(date.dt.month)',d).fit(); print(m.params['post'],m.bse['post'])
print(d.groupby(['line',d.date>='2025-04-14']).ambient_temp_c.mean())
"

cd /tmp/edabench_claude_hpkw7_gw; cat >> clean.py <<'EOF'
mn=pd.read_csv('maintenance.csv',parse_dates=['date'])
cl=mn[mn.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date.max()
    return (r.date-c).days
d['dsc']=d.apply(dsc,axis=1)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['mt_c']=d.mt-6.4*d.post
d['ct_dev']=d.cycle_time_s-d.recipe_cycle_time_s
d['ok']=d.units_produced-d.defective_units
EOF
python3 -c "
from clean import *
print(d.dsc.describe())
print(d.groupby(pd.cut(d.dsc,[-1,3,7,10,14,18,22,30,60])).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
for v in ['mt_c','hum','ct_dev','cycle_time_s','machine_age_years','ambient_temp_c']:
  print(v, d.groupby(pd.qcut(d[v],8,duplicates='drop')).apply(lambda g:round(g.defective_units.sum()/g.units_produced.sum(),4)).values)
for v in ['shift','operator_id','supplier_name','line']:
  print(d.groupby(v).apply(lambda g:round(g.defective_units.sum()/g.units_produced.sum(),4)).to_dict())
print(d.groupby('supplier_name').cycle_time_s.describe())
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from clean import *
print(pd.crosstab(d.operator_id,d.line).T.to_string())
print(pd.crosstab(d.shift,d.line))
x=d[d.line=='L2'].groupby('date').apply(lambda g:g.defective_units.sum()/g.units_produced.sum())
print(x.loc['2025-04-25':'2025-06-10'].round(3).to_string())
"

cd /tmp/edabench_claude_hpkw7_gw; cat > fit.py <<'EOF'
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=d.dropna(subset=['mt_c','hum']).copy()
f='defective_units + ok ~ mt_c + I(mt_c**2) + hum*C(pre_dried) + I(hum**2)*C(pre_dried) + cycle_time_s + C(resin_grade) + machine_age_years + ambient_temp_c + C(shift) + C(line) + dsc + I(dsc**2)+ C(supplier_name)'
m=smf.glm(f,dd,family=sm.families.Binomial()).fit()
EOF
python3 -c "
from fit import *
print(m.summary())
dd['res']=(dd.defective_units-m.fittedvalues*dd.units_produced)
for l in ['L1','L2','L3','L4']:
  x=dd[dd.line==l].set_index('date').sort_index()
  r=x.res.resample('W').sum()/x.units_produced.resample('W').sum()
  print(l,(r*100).round(1).values)
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from fit import *
dd['res']=(dd.defective_units-m.fittedvalues*dd.units_produced)
d['rcpd']=d.rework_cost_eur/d.defective_units
d['qpu']=d.qc_inspection_min
for l,a,b in [('L2','2025-06-01','2025-06-25'),('L3','2025-07-10','2025-07-30')]:
  x=dd[(dd.line==l)&(dd.date>=a)&(dd.date<=b)].groupby('date').apply(lambda g:pd.Series({'res':g.res.sum()/g.units_produced.sum()*100,'n':len(g)}))
  print(l);print(x.round(2).T.to_string())
for l in ['L2','L3']:
  x=d[d.line==l].set_index('date').sort_index()
  print(l, x.rcpd.resample('W').median().round(2).values)
  print(l, x.qc_inspection_min.resample('W').median().round(1).values)
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from fit import *
import warnings; warnings.filterwarnings('ignore')
dates=sorted(dd[(dd.line=='L2')&(dd.date>='2025-06-01')&(dd.date<='2025-07-05')].date.unique())
dates3=sorted(dd[(dd.line=='L3')&(dd.date>='2025-07-15')&(dd.date<='2025-07-30')].date.unique())
best=[]
for c in dates:
  dd['s2']=((dd.line=='L2')&(dd.date>=c)).astype(int)
  dd['s3']=((dd.line=='L3')&(dd.date>='2025-07-21')).astype(int)
  mm=smf.glm(f+'+s2+s3',dd,family=sm.families.Binomial()).fit(); best.append((mm.llf,str(c)[:10],mm.params.s2))
for b in sorted(best)[-5:]: print(b)
best=[]
for c in dates3:
  dd['s3']=((dd.line=='L3')&(dd.date>=c)).astype(int)
  mm=smf.glm(f+'+s2+s3',dd,family=sm.families.Binomial()).fit(); best.append((mm.llf,str(c)[:10],mm.params.s3))
for b in sorted(best)[-3:]: print(b)
"

cd /tmp/edabench_claude_hpkw7_gw; cat >> fit.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
dd['s2']=((dd.line=='L2')&(dd.date>='2025-06-16')).astype(int)
dd['s3']=((dd.line=='L3')&(dd.date>='2025-07-21')).astype(int)
EOF
python3 -c "
from fit import *
base='defective_units + ok ~ bs(mt_c,4) + bs(hum,4)*C(pre_dried) + cycle_time_s + C(supplier_name) + bs(dsc,3) + C(line) + s2 + s3'
m0=smf.glm(base,dd,family=sm.families.Binomial()).fit()
print('base llf',m0.llf, m0.pearson_chi2/m0.df_resid)
for add in ['machine_age_years','ambient_temp_c','C(shift)','C(operator_id)','mt_c:C(line)','I(mt_c-mt)']:
  mm=smf.glm(base+'+'+add,dd,family=sm.families.Binomial()).fit()
  print(add, round(2*(mm.llf-m0.llf),1), mm.df_model-m0.df_model, mm.params.filter(like=add.split('(')[-1][:6]).round(3).to_dict() if 'oper' not in add else '')
for drop in ['cycle_time_s','bs(mt_c,4) + ','C(line) + ']:
  mm=smf.glm(base.replace(drop,''),dd,family=sm.families.Binomial()).fit(); print('drop',drop,round(2*(m0.llf-mm.llf),1))
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from fit import *
print(dd.groupby('line').machine_age_years.describe())
base='defective_units + ok ~ bs(mt_c,4) + bs(hum,4)*C(pre_dried) + cycle_time_s + C(supplier_name) + bs(dsc,3) + C(line) + s2 + s3 + C(shift)'
m0=smf.glm(base,dd,family=sm.families.Binomial()).fit(scale='X2')
print(m0.scale)
for off in [0,3,5,6.4,8,10,12]:
  dd['mt_c']=dd.mt-off*dd.post
  print(off, smf.glm(base,dd,family=sm.families.Binomial()).fit().llf)
dd['mt_c']=dd.mt-6.4*dd.post
mm=smf.glm(base+'+C(operator_id)',dd,family=sm.families.Binomial()).fit()
from scipy import stats
lr=2*(mm.llf-smf.glm(base,dd,family=sm.families.Binomial()).fit().llf)/m0.scale; print('op F-ish',lr, stats.chi2.sf(lr,18))
print(mm.params.filter(like='oper').round(3).to_string())
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from fit import *
base='defective_units + ok ~ bs(mt_c,4) + bs(hum,4)*C(pre_dried) + cycle_time_s + C(supplier_name) + bs(dsc,3) + s2 + s3 + C(shift)'
for add in ['C(line)','machine_age_years','bs(machine_age_years,4)','C(line)+machine_age_years','C(line)+bs(machine_age_years,4)','C(line)+C(operator_id)','C(operator_id)']:
  mm=smf.glm(base+'+'+add,dd,family=sm.families.Binomial()).fit()
  print(add, round(mm.llf,1), mm.df_model, round(mm.pearson_chi2/mm.df_resid,2))
mm=smf.glm(base+'+C(line)',dd,family=sm.families.Binomial()).fit(); print(mm.params.round(3).to_string())
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from fit import *
print(pd.crosstab(dd.operator_id,dd['shift']).T.to_string())
base='defective_units + ok ~ bs(mt_c,4) + bs(hum,4)*C(pre_dried) + cycle_time_s + C(supplier_name) + bs(dsc,3) + s2 + s3 + C(shift)+C(line)'
m0=smf.glm(base,dd,family=sm.families.Binomial()).fit()
m1=smf.glm(base+'+C(operator_id)',dd,family=sm.families.Binomial()).fit()
from scipy import stats
phi=m1.pearson_chi2/m1.df_resid; F=(m0.deviance-m1.deviance)/20/phi; print(F, stats.f.sf(F,20,m1.df_resid))
# permutation within line
import numpy as np; rng=np.random.default_rng(0); out=[]
for i in range(30):
  e=dd.copy(); e['operator_id']=e.groupby('line').operator_id.transform(lambda s: rng.permutation(s.values))
  out.append(m0.deviance-smf.glm(base+'+C(operator_id)',e,family=sm.families.Binomial()).fit().deviance)
print(m0.deviance-m1.deviance, np.percentile(out,[50,95,100]))
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from fit import *
import numpy as np
base='defective_units + ok ~ bs(mt_c,4) + bs(hum,4)*C(pre_dried) + cycle_time_s + C(supplier_name) + bs(dsc,3) + s2 + s3 + C(shift)+C(line)'
m=smf.glm(base,dd,family=sm.families.Binomial()).fit()
a=d.copy()
a['s2']=((a.line=='L2')&(a.date>='2025-06-16')).astype(int); a['s3']=((a.line=='L3')&(a.date>='2025-07-21')).astype(int)
a['mt_c']=a.mt_c.fillna(dd.mt_c.median()); a['hum']=a.hum.fillna(dd.hum.median())
a['hum']=a.hum.clip(dd.hum.min(),dd.hum.max()); a['mt_c']=a.mt_c.clip(dd.mt_c.min(),dd.mt_c.max())
s=pd.read_csv('suppliers.csv')
for _,r in s.iterrows():
  b=a.copy(); b['supplier_name']=r.supplier_name; b['pre_dried']=r.pre_dried; b['cycle_time_s']=r.recipe_cycle_time_s
  for s3 in [None,0]:
    if s3 is not None: b['s3']=0
    p=m.predict(b); print(r.supplier_name, s3, round((p*b.units_produced).sum()/b.units_produced.sum(),5))
al=dd[dd.supplier_name=='Alpha']; g=np.arange(dd.hum.min(),dd.hum.max(),0.5); res=[]
for h in g:
  b=al.copy(); b['hum']=h; res.append(m.predict(b).mean())
res=np.array(res); print('opt',g[res.argmin()], res.min()); print(np.c_[g,res][::6].round(4))
p0=m.predict(a); b=a.copy(); b['dsc']=b.dsc%14; p1=m.predict(b)
print('C3', (a.defective_units+a.units_produced*(p1-p0)).sum()/a.units_produced.sum(), (p1*a.units_produced).sum()/a.units_produced.sum(), (p0*a.units_produced).sum()/a.units_produced.sum())
print(dd.hum.min(),dd.hum.max())
"

cd /tmp/edabench_claude_hpkw7_gw; python3 -c "
from clean import *
print(d.mt.median(), d.mt_c.median(), d.mt_c.notna().sum())
import statsmodels.formula.api as smf
"
