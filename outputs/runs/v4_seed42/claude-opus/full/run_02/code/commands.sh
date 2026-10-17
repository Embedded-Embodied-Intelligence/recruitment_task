cd /tmp/edabench_claude_qg9j6c2_; ls; head -5 *.csv; wc -l *.csv; cat suppliers.csv; head -20 maintenance.csv

cd /tmp/edabench_claude_qg9j6c2_; cat maintenance.csv | awk -F, '{print $3,$4}' | sort | uniq -c; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.describe().T)
for c in ['line','shift','operator_id','supplier_code']: print(d[c].value_counts(dropna=False))
print(d.batch_id.duplicated().sum(), d.duplicated().sum())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
  x=pd.to_numeric(d[c],errors='coerce'); print(c, d[c][x.isna()].unique()[:10], x.describe().round(2).to_dict())
print(d.production_date.str.len().value_counts()); print(d.production_date.sample(20,random_state=1).tolist())
"

cd /tmp/edabench_claude_qg9j6c2_; grep sensor maintenance.csv; python3 -c "
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates()
print(len(d), d.batch_id.nunique())
p=d.production_date
iso=p.str.match(r'\d{4}-')
sl=p[~iso].str.split('/',expand=True).astype(int)
print(pd.crosstab(d.line[~iso], (sl[0]>12).map({True:'DMY',False:'?'})+(sl[1]>12).map({True:'MDY',False:'?'})))
print(pd.crosstab(d.line, iso))
mt=d.mold_temp; print(np.histogram(mt,bins=[-1,1,100,150,180,200,250,300,350,400,450,500]))
print(d.humidity_pct.value_counts().head(), (d.humidity_pct>100).sum(), (d.humidity_pct<0).sum())
"

cd /tmp/edabench_claude_qg9j6c2_; cat > $TMPDIR/load.py <<'EOF'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates().copy()
p=d.production_date
dt=pd.to_datetime(p.where(d.line.isin(['L2','L3'])),format='%Y-%m-%d',errors='coerce')
dt=dt.fillna(pd.to_datetime(p.where(d.line=='L1'),format='%m/%d/%Y',errors='coerce'))
dt=dt.fillna(pd.to_datetime(p.where(d.line=='L4'),format='%d/%m/%Y',errors='coerce'))
d['date']=dt
d['shift']=d['shift'].str.strip().str.lower().str[0].map({'d':'Day','n':'Night'})
d['supplier_code']=d.supplier_code.str.strip().str.upper()
s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code',how='left')
d['rate']=d.defective_units/d.units_produced
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['mt_raw']=d.mold_temp.replace(0,np.nan)
EOF
python3 -c "
exec(open('$TMPDIR/load.py').read())
print(d.date.isna().sum(), d.date.min(), d.date.max())
d['F']=d.mt_raw>350
print(pd.crosstab([d.line,d.date>='2025-04-14'],d.F))
print(d[d.F].groupby('line').date.agg(['min','max']))
print(d.groupby('line').mt_raw.describe())
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
d['mt']=np.where(d.line=='L3',(d.mt_raw-32)*5/9,d.mt_raw)
d['m']=d.date.dt.to_period('M')
print(d.pivot_table(index='m',columns='line',values='mt',aggfunc='mean').round(1))
print(d.pivot_table(index='m',columns='line',values='rate',aggfunc='mean').round(4))
l1=d[d.line=='L1']; print(l1.groupby(l1.date>='2025-04-14')[['mt','rate']].mean())
print(d.mt.median(), d.mt.notna().sum(), d.hum.isna().sum())
print(d.defective_units.sum()/d.units_produced.sum())
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
d['mt']=np.where(d.line=='L3',(d.mt_raw-32)*5/9,d.mt_raw)
d['w']=d.date.dt.to_period('W')
x=d.pivot_table(index='w',columns='line',values='mt',aggfunc='mean').round(1)
x['L1-oth']=x.L1-x[['L2','L4']].mean(1)
print(x.iloc[5:25])
l1=d[(d.line=='L1')&(d.date.between('2025-04-01','2025-04-30'))].sort_values('date'); print(l1[['date','mt','ambient_temp_c']].to_string())
" | head -90

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
d['mt']=np.where(d.line=='L3',(d.mt_raw-32)*5/9,d.mt_raw)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
print(smf.ols('mt~ambient_temp_c+C(line)+post+cycle_time_s+C(supplier_code)+machine_age_years+hum+C(shift)',d).fit().summary().tables[1])
print(d.groupby('line')[['ambient_temp_c','machine_age_years']].describe().T)
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
d['mt']=np.where(d.line=='L3',(d.mt_raw-32)*5/9,d.mt_raw)
o=d[d.line!='L1']
f=smf.ols('mt~ambient_temp_c+C(line)',o).fit(); print(f.params)
l1=d[d.line=='L1'].copy(); l1['res']=l1.mt-f.params.Intercept-f.params.ambient_temp_c*l1.ambient_temp_c
print(l1.groupby(l1.date.dt.to_period('M')).res.agg(['mean','std']))
o=o.assign(res=o.mt-f.predict(o)); print(o.groupby([o.date.dt.to_period('M'),'line']).res.mean().unstack().round(2))
"

cd /tmp/edabench_claude_qg9j6c2_; cat >> $TMPDIR/load.py <<'EOF'
d['mt']=np.where(d.line=='L3',(d.mt_raw-32)*5/9,d.mt_raw)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
m=pd.read_csv('maintenance.csv',parse_dates=['date']); mc=m[m.event=='mold_cleaning']
d=d.sort_values('date').reset_index(drop=True)
d['last_clean']=pd.NaT
for l,g in mc.groupby('line'):
    idx=d.line==l
    r=pd.merge_asof(d.loc[idx,['date']].reset_index(),g[['date']].rename(columns={'date':'cd'}).sort_values('cd'),left_on='date',right_on='cd',direction='backward')
    d.loc[r['index'],'last_clean']=r.cd.values
d['dsc']=(d.date-d.last_clean).dt.days
d['ct_dev']=d.cycle_time_s-d.recipe_cycle_time_s
EOF
python3 -c "
exec(open('$TMPDIR/load.py').read())
print(d.dsc.describe()); print(mc.groupby('line').date.apply(lambda s:s.diff().dt.days.describe()))
print(d.groupby(pd.cut(d.dsc,[-1,3,7,10,14,17,20,25,40])).rate.agg(['mean','count']))
print(d.groupby('supplier_name')[['rate','cycle_time_s','ct_dev','hum']].mean())
print(d[['rate','qc_inspection_min','rework_cost_eur','defective_units','units_produced']].corr().round(2))
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
f=smf.ols('y~mt+I(mt**2)+(hum+I(hum**2))*C(supplier_name)+ct_dev+I(ct_dev**2)+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+dsc+C(line)',e).fit()
print(f.summary().tables[1]); print(f.rsquared)
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
print(pd.crosstab(d.operator_id,d.line).T.to_string())
print(pd.crosstab(d.shift,d.line))
print(d.groupby('line').date.apply(lambda s: s.diff().dt.days.max()))
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
f=smf.ols('y~mt+I(mt**2)+(hum+I(hum**2))*C(supplier_name)+ct_dev+machine_age_years+ambient_temp_c+C(shift)+dsc',e).fit()
print(f.params.round(4))
e['r']=f.resid
x=e.pivot_table(index=e.date.dt.to_period('W'),columns='line',values='r',aggfunc='mean').round(2); print(x.to_string())
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
f=smf.ols('y~mt+I(mt**2)+(hum+I(hum**2))*C(supplier_name)+ct_dev+machine_age_years+ambient_temp_c+C(shift)+dsc',e[e.date<'2025-06-01']).fit()
e['r']=e.y-f.predict(e)
for l,a,b in [('L2','2025-06-05','2025-06-25'),('L3','2025-07-12','2025-07-30')]:
  g=e[(e.line==l)&e.date.between(a,b)]; print(g.groupby('date')[['r','qc_inspection_min','units_produced','rate']].mean().round(3))
print(e.pivot_table(index=e.date.dt.to_period('M'),columns='line',values=['qc_inspection_min','units_produced'],aggfunc='mean').round(1))
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
f=smf.ols('y~mt+I(mt**2)+(hum+I(hum**2))*C(supplier_name)+ct_dev+machine_age_years+ambient_temp_c+C(shift)+dsc',e[e.date<'2025-06-01']).fit()
g=e[e.line=='L2'].copy(); g['r']=g.y-f.predict(g)
best=[]
for dt in sorted(g.date.unique()):
  if dt<pd.Timestamp('2025-05-01') or dt>pd.Timestamp('2025-08-01'): continue
  a=g.r[g.date<dt]; b=g.r[g.date>=dt]; best.append((((a-a.mean())**2).sum()+((b-b.mean())**2).sum(),dt))
print(sorted(best)[:5])
print(g[g.date.between('2025-06-12','2025-06-18')][['date','shift','r','rate']])
"

cd /tmp/edabench_claude_qg9j6c2_; cat >> $TMPDIR/load.py <<'EOF'
d['l2reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['l3qc']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
EOF
python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
for dl in [-4,0,3,5,6,7,8,10]:
  e['m2']=e.mt-dl*e.post
  f=smf.ols('y~bs(m2,df=5)+(hum+I(hum**2))*C(supplier_name)+ct_dev+machine_age_years+ambient_temp_c+C(shift)+dsc+l2reg+l3qc',e).fit()
  print(dl, round(f.ssr,2), round(e[e.line=='L1'].groupby('post').apply(lambda g:f.resid[g.index].mean()).diff().iloc[-1],3))
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
e['m2']=e.mt-6.4*e.post
e['mb']=pd.cut(e.m2,[180,195,200,205,210,215,220,225,230,240])
f=smf.ols('y~C(mb)+(hum+I(hum**2))*C(supplier_name)+ct_dev+machine_age_years+ambient_temp_c+C(shift)+dsc+l2reg+l3qc',e).fit()
print(f.params.round(3)); print(e.mb.value_counts().sort_index())
e['hb']=pd.cut(e.hum,range(0,80,5))
f=smf.ols('y~bs(m2,df=4)+C(hb):C(supplier_name)+C(supplier_name)+ct_dev+machine_age_years+ambient_temp_c+C(shift)+dsc+l2reg+l3qc',e).fit()
print(f.params.filter(like='hb').round(3).to_string())
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
e['m2']=e.mt-6.4*e.post
base='y~m2+bs(hum,df=5)*C(supplier_name)+ct_dev+ambient_temp_c+C(shift)+dsc+l2reg+l3qc'
f0=smf.ols(base+'+C(line)',e).fit()
f1=smf.ols(base+'+C(line)+machine_age_years',e).fit()
f2=smf.ols(base+'+C(operator_id)',e).fit()
f3=smf.ols(base+'+C(operator_id)+machine_age_years',e).fit()
print(f1.params['machine_age_years'],f1.bse['machine_age_years'])
print(f3.params['machine_age_years'],f3.bse['machine_age_years'])
print(f2.compare_f_test(f0)); print(f0.params.filter(regex='line|ambient|m2|ct_dev|shift|dsc'))
f4=smf.ols(base+'+machine_age_years',e).fit(); print(f4.params['machine_age_years'], f1.compare_f_test(f4))
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d[d.l3qc==0]
print(smf.ols('qc_inspection_min~defective_units+units_produced+rate+mt+hum+C(shift)+C(line)',e).fit().summary().tables[1])
print(smf.ols('rework_cost_eur~defective_units+units_produced',e).fit().params, (e.rework_cost_eur/e.defective_units).describe())
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
print(d.hum.describe(), d.mt.isna().sum())
f=smf.ols('mt~ambient_temp_c+C(line)+post',d).fit(); print(f.params.post, f.bse.post)
f=smf.ols('mt~ambient_temp_c*C(line)+post',d).fit(); print(f.params.post)
for o in [0,6,6.36,7]: print(o, (d.mt-o*d.post).median())
"

cd /tmp/edabench_claude_qg9j6c2_; python3 -c "
exec(open('$TMPDIR/load.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy()
e['y']=np.log(e.rate/(1-e.rate))
e['m2']=e.mt-6.4*e.post
e['db']=pd.cut(e.dsc,[-1,0,2,4,6,8,10,12,14,16,18,20,24,28,40])
f=smf.ols('y~m2+bs(hum,df=5)*C(supplier_name)+cycle_time_s+C(shift)+C(db)+l2reg+l3qc+C(line)',e).fit()
print(f.params.filter(like='db').round(3)); print(e.db.value_counts().sort_index())
"

cd /tmp/edabench_claude_qg9j6c2_; cat > $TMPDIR/model.py <<'EOF'
exec(open('/tmp/claude-0/-tmp-edabench-claude-qg9j6c2-/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/load.py'.replace('/tmp/claude-0/-tmp-edabench-claude-qg9j6c2-/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad',__import__('os').environ['TMPDIR'])).read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['m2']=d.mt-6.4*d.post
d['mon']=d.date.dt.to_period('M')
d['m2i']=d.m2.fillna(d.groupby(['line','mon']).m2.transform('median'))
d['humi']=d.hum.fillna(d.groupby('date').hum.transform('median')).fillna(d.groupby('mon').hum.transform('median'))
e=d.dropna(subset=['m2','hum'])
form='rate~m2i+bs(humi,df=5,lower_bound=10,upper_bound=75)*C(supplier_name)+cycle_time_s+C(shift)+dsc+l2reg+l3qc+C(line)'
F=smf.glm(form,e,family=sm.families.Binomial(),var_weights=e.units_produced).fit(scale='X2')
def total(df):
    p=F.predict(df); base=F.predict(d)
    return (d.defective_units+(p-base)*d.units_produced).sum()/d.units_produced.sum(), (p*d.units_produced).sum()/d.units_produced.sum()
EOF
python3 -c "
exec(open('$TMPDIR/model.py').read())
print(F.params.filter(regex='m2i|cycle|shift|dsc|l2|l3|line').round(4))
print('obs',d.defective_units.sum()/d.units_produced.sum(), total(d))
for s,ct in [('Alpha',30),('Beta',30),('Gamma',36)]:
  x=d.copy(); x['supplier_name']=s; x['cycle_time_s']=ct; print(s,total(x))
  x=d.copy(); x['supplier_name']=s; x['cycle_time_s']=d.cycle_time_s-d.recipe_cycle_time_s+ct; print(' keepdev',s,total(x))
x=d.copy(); x['dsc']=d.dsc%14; print('C3',total(x))
a=d[d.supplier_name=='Alpha']
for h in np.arange(12,73,1):
  x=a.copy(); x['humi']=h; print(h, round((F.predict(x)*x.units_produced).sum()/x.units_produced.sum(),5), end='; ')
"
