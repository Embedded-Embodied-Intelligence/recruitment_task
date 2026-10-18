cd /tmp/edabench_claude_lf2q_a96; ls; head -5 *.csv; wc -l *.csv; cat suppliers.csv; head -30 maintenance.csv

cd /tmp/edabench_claude_lf2q_a96; tail -42 maintenance.csv; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
for c in d.columns:
    print(c, d[c].nunique(), d[c].isna().sum(), d[c].value_counts().head(8).to_dict())
print(d.duplicated().sum(), d.batch_id.duplicated().sum())
print(d[d.batch_id.duplicated(keep=False)].sort_values('batch_id').head(30).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
d=d.drop_duplicates()
print(len(d), d.duplicated(['batch_id','line']).sum(), d.duplicated(['batch_id']).sum())
x=d[d.duplicated(['batch_id','line'],keep=False)].sort_values('batch_id'); print(x.to_string())
pd_=d.production_date
import re
print(pd_[pd_.str.contains('/')].str.split('/').str[0].astype(int).max(), pd_[pd_.str.contains('/')].str.split('/').str[1].astype(int).max())
d['fmt']=pd_.str.contains('-').map({True:'iso',False:'slash'})
d['a']=pd_.str.split('/').str[0]
print(d.groupby(['line','fmt']).size())
s=d[d.fmt=='slash']; print(s.groupby('line').apply(lambda g:(g.a.astype(int).max(), g.production_date.str.split('/').str[1].astype(int).max())))
"

cd /tmp/edabench_claude_lf2q_a96; mkdir -p an; cat > an/clean.py <<'EOF'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv',dtype=str)
for c in d.columns: d[c]=d[c].str.strip()
d=d.drop_duplicates()
d['supplier_code']=d.supplier_code.str.upper()
d['shift']=d['shift'].str.lower().str[0].map({'d':'Day','n':'Night'})
def pdt(r):
    s=r.production_date
    if r.line=='L1': return pd.to_datetime(s,format='%m/%d/%Y')
    if r.line=='L4': return pd.to_datetime(s,format='%d/%m/%Y')
    return pd.to_datetime(s,format='%Y-%m-%d')
d['date']=d.apply(pdt,axis=1)
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    d[c]=pd.to_numeric(d[c])
d=d.drop_duplicates()
s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code',how='left')
d['rate']=d.defective_units/d.units_produced
EOF
python3 -c "
exec(open('an/clean.py').read())
print(len(d), d.duplicated(['batch_id','line']).sum(), d.supplier_name.isna().sum(), d.shift.value_counts())
print(d.describe().T.to_string())
print(d.groupby('line').mold_temp.describe())
print(d.date.min(), d.date.max())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/clean.py').read())
print(len(d), d.duplicated(['batch_id','line']).sum(), d.supplier_name.isna().sum(), d['shift'].value_counts())
print(d.describe().T.to_string())
print(d.groupby('line').mold_temp.describe())
print(d.date.min(), d.date.max())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/clean.py').read())
d['m']=d.date.dt.to_period('M')
v=d[d.mold_temp>0]
print(v.pivot_table(index='m',columns='line',values='mold_temp',aggfunc='median'))
l1=v[v.line=='L1']; print(l1.groupby(l1.date<'2025-04-14').mold_temp.describe())
h=d[d.humidity_pct==50.2]; print(h.groupby(['line','m']).size().unstack(0))
print(d.groupby('line').humidity_pct.apply(lambda x:(x==-1).sum()), d.groupby('line').humidity_pct.apply(lambda x:x.isna().sum()))
print(d[d.humidity_pct==50.2].sort_values('date')[['line','date','humidity_pct']].head(3), d[d.humidity_pct==50.2].sort_values('date').tail(3)[['line','date']])
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/clean.py').read())
v=d[d.mold_temp>0].copy()
v.loc[v.line=='L3','mold_temp']=(v.mold_temp-32)*5/9
v['w']=v.date.dt.to_period('W')
p=v.pivot_table(index='w',columns='line',values='mold_temp',aggfunc='mean').round(1)
print(p.iloc[8:22])
print(d[(d.line=='L2')&(d.date>='2025-02-25')&(d.date<='2025-04-20')].groupby('date').humidity_pct.apply(lambda x:list(x)).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; cat >> an/clean.py <<'EOF'
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.mt-32)*5/9
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d.loc[(d.line=='L2')&(d.date>='2025-03-03')&(d.date<='2025-04-13')&(d.humidity_pct==50.2),'hum']=np.nan
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
mc=m[m.event=='mold_cleaning']
def dsc(r):
    x=mc[(mc.line==r.line)&(mc.date<=r.date)].date
    return (r.date-x.max()).days if len(x) else np.nan
d['dsc']=d.apply(dsc,axis=1)
d['opn']=d.operator_id
EOF
python3 -c "
exec(open('an/clean.py').read())
print(m.event.value_counts()); print(m[m.event!='mold_cleaning'])
print('A1',len(d),'A2',d.hum.isna().sum(),'A3',d.defective_units.sum()/d.units_produced.sum(),'A4',d.mt.median())
print(d[['rate','defective_units','qc_inspection_min','rework_cost_eur','units_produced','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','dsc']].corr().round(2).to_string())
print((d.rework_cost_eur/d.defective_units).describe())
print(d.groupby('line').dsc.describe())
print(d.groupby('line').operator_id.unique())
print(d.groupby('line').machine_age_years.describe())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['ctd']=d.cycle_time_s-d.recipe_cycle_time_s
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
x=d.dropna(subset=['mt','hum'])
f='rate ~ mt + I(mt**2) + hum*C(supplier_name) + I(hum**2)*C(supplier_name) + ctd + I(ctd**2) + machine_age_years + ambient_temp_c + C(shift) + C(line) + dsc + l1post'
r=smf.wls(f,x,weights=x.units_produced).fit(); print(r.summary().tables[1])
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/clean.py').read())
import statsmodels.formula.api as smf
d['post']=(d.date>='2025-04-14').astype(int)
r=smf.ols('mt~ambient_temp_c+C(line)*post',d).fit(); print(r.params.round(2))
d['w']=d.date.dt.to_period('2W')
print(d.pivot_table(index='w',columns='line',values='rate',aggfunc='mean').round(3).to_string())
print(d.pivot_table(index='w',columns='line',values='qc_inspection_min',aggfunc='mean').round(1).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/clean.py').read())
x=d[(d.line=='L3')&(d.date>='2025-07-10')&(d.date<='2025-07-30')].sort_values('date')
print(x[['date','qc_inspection_min','rate','units_produced']].to_string())
x=d[(d.line=='L2')&(d.date>='2025-05-25')&(d.date<='2025-07-05')].groupby('date')[['rate','hum','dsc','mt','cycle_time_s','ambient_temp_c']].mean()
print(x.round(3).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/clean.py').read())
d['m']=d.date.dt.to_period('M')
print(pd.crosstab([d.line,d.m],d.supplier_name).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; cat > an/m.py <<'EOF'
exec(open('an/clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['ctd']=d.cycle_time_s-d.recipe_cycle_time_s
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['l3qc']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['ok']=d.units_produced-d.defective_units
def fit(f,x):
    return smf.glm(f,x,family=sm.families.Binomial(),freq_weights=None,var_weights=None).fit() if False else smf.glm('defective_units + ok ~ '+f,x,family=sm.families.Binomial()).fit()
EOF
python3 -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['mt','hum'])
x=x[x.l3qc==0]
x['mtc']=x.mt-215
r=fit('mtc+I(mtc**2)+l1post+C(line)+hum+I(hum**2)+C(supplier_name)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+dsc+C(operator_id)',x)
print(r.summary().tables[1]); print(r.pearson_chi2/r.df_resid)
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum']).copy()
x['mtc']=x.mt-215
base=x[(x.l3qc==0)&(x.l1post==0)&~((x.line=='L2')&(x.date>='2025-06-01'))].dropna(subset=['mt'])
f='mtc+I(mtc**2)+C(line)+hum+I(hum**2)+C(supplier_name)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+dsc+C(operator_id)'
r=fit(f,base); print(r.params.filter(regex='^(mtc|I|hum|cyc|mach|amb|dsc|C\(sh|C\(su|C\(li)').round(4)); print(r.pearson_chi2/r.df_resid)
x=x.dropna(subset=['mt'])
x['res']=np.log(x.rate/(1-x.rate))-r.predict(x,which='linear')
x['w']=x.date.dt.to_period('W')
print(x.pivot_table(index='w',columns='line',values='res',aggfunc='mean').round(2).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt']).copy(); x['mtc']=x.mt-215
base=x[(x.l3qc==0)&(x.l1post==0)&~((x.line=='L2')&(x.date>='2025-06-01'))]
f='mtc+I(mtc**2)+C(line)+hum+I(hum**2)+C(supplier_name)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+dsc+C(operator_id)'
r=fit(f,base)
y=d[d.line=='L2'].copy(); y['mtc']=y.mt-215; y['hum']=y.hum.fillna(base.hum.median()); y['mtc']=y.mtc.fillna(0)
y['res']=np.log(y.rate/(1-y.rate))-r.predict(y,which='linear')
g=y[(y.date>='2025-06-01')&(y.date<='2025-06-30')].groupby('date').res.agg(['mean','count']).round(2); print(g.to_string())
# changepoint scan
y=y.sort_values('date'); best=[]
for dt in pd.date_range('2025-05-01','2025-08-01'):
    a=y[y.date<dt].res; b=y[y.date>=dt].res
    best.append((((a-a.mean())**2).sum()+((b-b.mean())**2).sum(),dt))
print(sorted(best)[:5])
"

cd /tmp/edabench_claude_lf2q_a96; cat >> an/m.py <<'EOF'
d['l2s']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['mtc']=d.mt-215
EOF
python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l1post==0)]
full='mtc+I(mtc**2)+C(line)+l2s+hum+I(hum**2)+C(supplier_name)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+dsc+C(operator_id)'
r=fit(full,x); s=r.pearson_chi2/r.df_resid; print('scale',s)
print(r.params.filter(regex='^(mtc|I|hum|cyc|mach|amb|dsc|l2s)').round(4), r.bse.filter(regex='^(mtc|I|hum|cyc|mach|amb|dsc|l2s)').round(4))
for drop in ['C(operator_id)','C(shift)','ambient_temp_c','machine_age_years','dsc','cycle_time_s']:
    f=full.replace('+'+drop,'')
    r2=fit(f,x); print(drop, round((r2.deviance-r.deviance)/s,1), r.df_model-r2.df_model)
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l1post==0)].copy()
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,80]); x['db']=pd.cut(x.dsc,[-1,0,3,7,10,14,18,25,35,70]); x['mb']=pd.cut(x.mtc,[-40,-15,-10,-5,0,5,10,15,40]); x['cb']=pd.cut(x.cycle_time_s,[0,24,27,30,33,36,39,42,50])
f='C(mb)+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+C(cb)+C(db)+ambient_temp_c+C(shift)'
r=fit(f,x); print(r.pearson_chi2/r.df_resid); print(r.params.round(3).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l1post==0)].copy()
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
f='mtc+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)'
r=fit(f,x)
x['res']=np.log(x.rate/(1-x.rate))-r.predict(x,which='linear')
x['db']=pd.cut(x.dsc,[-1,0,2,4,6,8,10,12,14,16,18,20,24,28,35,45,70])
print(x.pivot_table(index='db',columns='line',values='res',aggfunc='mean').round(2))
print(x.pivot_table(index='db',columns='line',values='res',aggfunc='count'))
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l1post==0)].copy()
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
f='mtc+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)'
r=fit(f,x)
x['res']=np.log(x.rate/(1-x.rate))-r.predict(x,which='linear')
y=x[(x.line=='L4')&(x.date>='2025-01-01')&(x.date<='2025-04-25')]
g=y.groupby('date').agg(res=('res','mean'),dsc=('dsc','first'),n=('res','size'))
g['roll']=g.res.rolling(5,center=True,min_periods=1).mean()
print(g.round(2).to_string())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l1post==0)].copy()
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
f='mtc+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)'
r=fit(f,x)
x['res']=np.log(x.rate/(1-x.rate))-r.predict(x,which='linear')
y=x[(x.line=='L4')&(x.date>='2025-02-15')&(x.date<='2025-04-10')].copy()
t=(y.date-pd.Timestamp('2025-02-01')).dt.days
out=[]
for P in range(8,25):
  for ph in range(P):
    s=((t-ph)%P)
    c=np.corrcoef(s,y.res)[0,1]; out.append((round(c,3),P,ph))
print(sorted(out)[-8:])
print('n',len(y))
# baseline: within non-gap data, corr of res with dsc for dsc<=14
z=x[(x.dsc<=14)]; print(np.corrcoef(z.dsc,z.res)[0,1])
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l1post==0)].copy()
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
for cap in [10,12,14,16,18,20,22,25,28,32,40,70]:
  for knot in [0,5,7]:
    x['dd']=x.dsc.clip(knot,cap)
    r=fit('mtc+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dd',x)
    print(cap,knot,round(r.deviance,1),round(r.params.dd,4))
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l1post==0)].copy()
x=x[~((x.line=='L4')&(x.date>'2025-02-14')&(x.date<'2025-04-11'))]
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
for cap in [14,16,18,20,22,25,28,32,40]:
    x['dd']=x.dsc.clip(0,cap)
    r=fit('mtc+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dd',x)
    print(cap,round(r.deviance,1),round(r.params.dd,4))
print(len(x), (x.dsc>20).sum())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)].copy()
x.loc[x.l1post==1,'mtc']=x.mtc-7.5
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
r=fit('mtc+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)',x)
x['res']=np.log(x.rate/(1-x.rate))-r.predict(x,which='linear')
x['db']=pd.cut(x.dsc,[-1,3,7,11,15,20,25,30,40,70])
x['per']=np.where(x.date<'2025-02-15','a',np.where(x.date<'2025-04-11','gap',np.where(x.date<'2025-07-29','b','c')))
print(x.pivot_table(index='db',columns=['line','per'],values='res',aggfunc='mean').round(2).to_string())
print(x.pivot_table(index='db',columns=['line','per'],values='res',aggfunc='count').to_string())
"

cd /tmp/edabench_claude_lf2q_a96; cat >> an/m.py <<'EOF'
d['l4gap']=((d.line=='L4')&(d.date>'2025-02-14')&(d.date<'2025-04-11')).astype(int)
d['hb']=pd.cut(d.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
EOF
python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l4gap==0)].copy()
for off in [0,4,6,7,8,9,10,12,14]:
    x['m2']=x.mtc-off*x.l1post
    r=fit('m2+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dsc',x)
    r2=fit('m2+C(line)+l2s+C(hb):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dsc+l1post',x)
    print(off,round(r.deviance,1),round(r.params.m2,4), round(r2.params.l1post,3))
"

cd /tmp/edabench_claude_lf2q_a96; cat >> an/m.py <<'EOF'
d['mtA']=d.mt-8*d.l1post
d['mtc']=d.mtA-215
EOF
python3 -W ignore -c "
exec(open('an/m.py').read())
print('A4', d.mtA.median(), d.mt.median())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l4gap==0)].copy()
base='mtc+C(line)+l2s+bs(hum,df=5):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dsc'
r=fit(base,x); s=r.pearson_chi2/r.df_resid; print('scale',s, r.deviance)
for add in ['ambient_temp_c','machine_age_years','C(operator_id)','I(mtc**2)','I(cycle_time_s**2)','I(dsc**2)','C(supplier_name):cycle_time_s','C(supplier_name):mtc','I(cycle_time_s-recipe_cycle_time_s)']:
    r2=fit(base+'+'+add,x); print(add, round((r.deviance-r2.deviance)/s,1), r2.df_model-r.df_model, r2.params.filter(like=add.split('(')[-1][:6]).round(4).to_dict() if 'C(' not in add else '')
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
x=x[(x.l3qc==0)&(x.l4gap==0)].copy()
base='mtc+l2s+bs(hum,df=5):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dsc+C(operator_id)-1'
r=fit(base,x); s=r.pearson_chi2/r.df_resid
p=r.params.filter(like='operator'); se=r.bse.filter(like='operator')*np.sqrt(s)
print(pd.DataFrame({'p':p.round(3),'se':se.round(3)}).to_string())
print(pd.crosstab(d.operator_id,d['shift']).T.to_string())
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
fitd=x[(x.l3qc==0)&(x.l4gap==0)].copy()
for hf in ['bs(hum,df=5)','hum+I(hum**2)','bs(hum,df=7)']:
  f='mtc+C(line)+l2s+('+hf+'):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dsc'
  r=fit(f,fitd)
  res={}
  for s,ct in [('Alpha',30),('Beta',30),('Gamma',36)]:
    y=x.copy(); y['supplier_name']=s; y['cycle_time_s']=ct
    res[s]=round((r.predict(y)*y.units_produced).sum()/y.units_produced.sum(),4)
  # Alpha humidity curve
  g=np.arange(np.ceil(d.hum.min()),np.floor(d.hum.max())+0.1,0.5)
  a=fitd[fitd.supplier_name=='Alpha']
  curve=[]
  for h in g:
    y=a.copy(); y['hum']=h; curve.append((r.predict(y)*y.units_produced).sum()/y.units_produced.sum())
  curve=np.array(curve)
  print(hf,res,'opt',g[curve.argmin()], 'range',d.hum.min(),d.hum.max(), curve[::10].round(4))
"

cd /tmp/edabench_claude_lf2q_a96; python3 -W ignore -c "
exec(open('an/m.py').read())
x=d.dropna(subset=['hum','mt'])
fitd=x[(x.l3qc==0)&(x.l4gap==0)].copy()
r=fit('mtc+C(line)+l2s+bs(hum,df=5):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dsc',fitd)
r2=fit('mtc+C(line)+l2s+(hum+I(hum**2)):C(supplier_name)+C(supplier_name)+cycle_time_s+C(shift)+dsc',fitd)
b=r2.params; print('alpha vertex', -b['hum:C(supplier_name)[Alpha]']/(2*b['I(hum ** 2):C(supplier_name)[Alpha]']), 'dsc',r.params.dsc)
y=d.copy(); y['hum']=y.hum.fillna(fitd.hum.median()); y['mtc']=y.mtc.fillna(fitd.mtc.median())
p0=r.predict(y); y2=y.copy(); y2['dsc']=np.where(y.l4gap==1,y.dsc,y.dsc%14); p1=r.predict(y2)
for name,adj in [('L4gap unchanged',1),]:
  e=(y.defective_units*p1/p0).sum()/y.units_produced.sum(); print(name,e)
y3=y.copy(); y3['dsc']=y.dsc%14; p3=r.predict(y3); print('all mod14',(y.defective_units*p3/p0).sum()/y.units_produced.sum())
# additive version
e=(y.defective_units + y.units_produced*(p1-p0)).sum()/y.units_produced.sum(); print('additive',e)
print('obs',y.defective_units.sum()/y.units_produced.sum(), (y.dsc>=14).sum(), ((y.dsc>=14)&(y.l4gap==0)).sum())
"
