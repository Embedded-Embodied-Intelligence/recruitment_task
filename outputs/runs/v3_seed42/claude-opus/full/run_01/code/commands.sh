cd /tmp/edabench_claude_tn82ql6n; ls; head -5 *.csv; wc -l *.csv; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv'); print(b.dtypes); print(b.describe(include='all').T.to_string())
for c in b.columns:
  if b[c].dtype==object and b[c].nunique()<50: print(c, b[c].value_counts(dropna=False).to_dict())
"

cd /tmp/edabench_claude_tn82ql6n; cat maintenance.csv | head -80; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv')
print(b.shift.value_counts().to_dict(), b.supplier_code.value_counts().to_dict())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id'); print(len(d)); print(d.head(10).to_string())
print('exact dup', b.duplicated().sum())
import numpy as np
print(np.histogram(b.mold_temp,bins=[-1,1,100,150,190,250,300,380,420,460]))
print(b.humidity_pct.value_counts().head(5), (b.humidity_pct<0).sum(), (b.humidity_pct>100).sum())
print(b.sort_values('units_produced').tail(8).to_string())
print(b.operator_id.value_counts().to_dict())
"

cd /tmp/edabench_claude_tn82ql6n; python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
print(b['shift'].value_counts().to_dict(), b.supplier_code.value_counts().to_dict())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id'); print(len(d)); print(d.head(8).to_string())
print('exact dup', b.duplicated().sum(), 'dup excluding?', b.drop(columns='batch_id').duplicated().sum())
print(np.histogram(b.mold_temp,bins=[-1,1,100,150,190,250,300,380,420,460]))
print(b.humidity_pct.value_counts().head(5), (b.humidity_pct<0).sum(), (b.humidity_pct>100).sum(), b.humidity_pct.isna().sum())
print(b.sort_values('units_produced').tail(8).to_string())
print(b.operator_id.value_counts().to_dict())
"

cd /tmp/edabench_claude_tn82ql6n; python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b['d']=pd.to_datetime(b.production_date)
b['m']=b.d.dt.to_period('M')
print(b.groupby(['line','m']).mold_temp.median().unstack(0))
print(b[b.mold_temp>300].groupby(['line','m']).size().unstack(0))
print(b.groupby('line').machine_age_years.describe())
print(np.histogram(b.machine_age_years,bins=20))
print(b[(b.line=='L1')&(b.d.between('2025-04-07','2025-04-21'))].groupby('production_date').mold_temp.median())
"

mkdir -p /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_tn82ql6n; cat > /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py <<'EOF'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
assert b.batch_id.is_unique
b['d']=pd.to_datetime(b.production_date)
b['shift']=b['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
b['supplier_code']=b.supplier_code.str.strip().str.upper()
s=pd.read_csv('suppliers.csv'); b=b.merge(s,on='supplier_code',how='left')
b.loc[b.humidity_pct<0,'humidity_pct']=np.nan
mt=b.mold_temp.astype(float).copy()
mt[mt<=1]=np.nan
f=b.line=='L3'; mt[f]=(mt[f]-32)*5/9
f1=(b.line=='L1')&(b.d>='2025-04-14'); mt[f1]-=8
b['mt']=mt
b['rate']=b.defective_units/b.units_produced
m=pd.read_csv('maintenance.csv',parse_dates=['date']); mc=m[m.event=='mold_cleaning']
def dsc(r):
    x=mc[(mc.line==r.line)&(mc.date<=r.d)].date.max(); return (r.d-x).days
b['dsc']=b.apply(dsc,axis=1)
b.to_pickle('/tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b.pkl')
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py; python3 -c "
import pandas as pd
b=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b.pkl')
print(len(b), b.humidity_pct.isna().sum(), b.defective_units.sum()/b.units_produced.sum(), b.mt.median(), b.mt.isna().sum())
print(b.groupby('line').mt.describe())
print(b[['rate','qc_inspection_min','rework_cost_eur','defective_units','units_produced']].corr().round(2))
print((b.rework_cost_eur/b.defective_units).describe())
print(b.dsc.describe())
"

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b.pkl')
b['w']=b.d.dt.to_period('W')
t=b.groupby(['w','line']).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).unstack()
print(t.round(3).to_string())
for c in ['shift','operator_id','supplier_name','line']: print(b.groupby(c).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
"

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b.pkl')
print(pd.crosstab(b.operator_id,b.line).to_string())
print(pd.crosstab(b.supplier_name,b.line))
print(b.groupby(b.d.dt.month)[['humidity_pct','ambient_temp_c','mt','cycle_time_s','dsc']].mean().round(1))
print(b[['humidity_pct','ambient_temp_c','mt','cycle_time_s','machine_age_years','dsc','rate']].corr().round(2))
"

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m1.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b.pkl').dropna(subset=['mt','humidity_pct']).copy()
b['ok']=b.units_produced-b.defective_units
b['mtc']=b.mt-210; b['hc']=b.humidity_pct-30
f='defective_units + ok ~ mtc + I(mtc**2) + C(supplier_name)*(hc + I(hc**2)) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(line) + dsc + C(operator_id)'
m=smf.glm(f,b,family=sm.families.Binomial()).fit(scale='X2')
print(m.summary())
EOF
python3 m1.py

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b.pkl').dropna(subset=['mt','humidity_pct']).copy()
b['ok']=b.units_produced-b.defective_units
b['mtc']=b.mt-210; b['hc']=b.humidity_pct-30
base='C(supplier_name)*(hc + I(hc**2)) + cycle_time_s + ambient_temp_c + C(shift) + C(dsc.clip(upper=30)//2) + mtc + I(mtc**2)'
for extra in ['', '+machine_age_years', '+C(line)', '+C(operator_id)', '+machine_age_years+C(line)', '+machine_age_years+C(operator_id)']:
    m=smf.glm('defective_units + ok ~ '+base+extra,b,family=sm.families.Binomial()).fit()
    print(extra, round(m.deviance,1), m.df_resid, m.params.filter(regex='age|mtc|ambient|cycle').round(4).to_dict())
m=smf.glm('defective_units + ok ~ '+base+'+machine_age_years+C(operator_id)',b,family=sm.families.Binomial()).fit()
print(m.params.filter(regex='dsc|shift|supp').round(3))
EOF
python3 m2.py

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m3.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
b=pd.read_pickle('b.pkl').dropna(subset=['mt','humidity_pct']).copy()
b['ok']=b.units_produced-b.defective_units
b['mtc']=b.mt-210; b['hc']=b.humidity_pct-30
terms=['C(supplier_name)*(hc + I(hc**2))','cycle_time_s','ambient_temp_c','C(shift)','dsc','mtc + I(mtc**2)','machine_age_years','C(line)','C(operator_id)']
fit=lambda t: smf.glm('defective_units + ok ~ '+'+'.join(t),b,family=sm.families.Binomial()).fit()
full=fit(terms); phi=full.pearson_chi2/full.df_resid; print('phi',phi)
for i,t in enumerate(terms):
    r=fit(terms[:i]+terms[i+1:]); ddf=r.df_resid-full.df_resid
    F=(r.deviance-full.deviance)/ddf/phi; print(t, ddf, round(F,2), stats.f.sf(F,ddf,full.df_resid))
for t in ['hc','I(hc**2)']:
    pass
# residuals over time
b['res']=full.resid_pearson
b['pred']=full.mu
b['w']=b.d.dt.to_period('W')
t=b.groupby(['w','line']).apply(lambda g:(g.defective_units.sum()/ (g.pred*g.units_produced).sum())).unstack()
print(t.round(2).to_string())
EOF
python3 m3.py

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m4.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('b.pkl').dropna(subset=['mt','humidity_pct']).copy()
b['ok']=b.units_produced-b.defective_units
b['mtc']=b.mt-210; b['hc']=b.humidity_pct-30
base='defective_units + ok ~ C(supplier_name)*(hc + I(hc**2)) + cycle_time_s + I(cycle_time_s**2)+ ambient_temp_c + C(shift) + dsc + mtc + I(mtc**2) + C(line)'
dates=pd.date_range('2025-06-01','2025-07-05')
out=[]
for dt in dates:
    b['step']=((b.line=='L2')&(b.d>=dt)).astype(int)
    m=smf.glm(base+'+step',b,family=sm.families.Binomial()).fit()
    out.append((dt.date(),round(m.deviance,1),round(m.params.step,3)))
for o in out: print(o)
print(sorted(b[(b.line=='L2')&(b.d.between('2025-06-08','2025-06-25'))].production_date.unique()))
EOF
python3 m4.py

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat >> m4.py <<'EOF'
b['step']=0
m=smf.glm(base,b[~((b.line=='L2')&(b.d>='2025-06-01'))],family=sm.families.Binomial()).fit()
b['pred']=m.predict(b)*b.units_produced
g=b[(b.line=='L2')&b.d.between('2025-06-01','2025-06-30')].groupby('production_date')[['defective_units','pred']].sum()
g['r']=g.defective_units/g.pred; print(g.round(2))
EOF
python3 m4.py | tail -30

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m5.py <<'EOF'
exec(open('m4.py').read().split('dates=')[0])
for cut in ['2025-06-12','2025-06-15','2025-06-16','2025-06-17']:
    b['step']=((b.line=='L2')&(b.d>=cut)).astype(int)
    m=smf.glm(base+'+step',b,family=sm.families.Binomial()).fit()
    print(cut, m.deviance, m.params.step)
m=smf.glm(base,b[~((b.line=='L2')&(b.d>='2025-06-10'))],family=sm.families.Binomial()).fit()
b['pred']=m.predict(b)*b.units_produced
g=b[(b.line=='L2')&b.d.between('2025-05-20','2025-06-25')].groupby('production_date')[['defective_units','pred']].sum()
g['r']=g.defective_units/g.pred; print(g.round(2).T.to_string())
EOF
python3 m5.py

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m6.py <<'EOF'
exec(open('m4.py').read().split('dates=')[0])
b['step']=((b.line=='L2')&(b.d>='2025-06-16')).astype(int)
f1=(b.line=='L1')&(b.d>='2025-04-14')
mt0=b.mt.copy()
for off in [-4,0,4,8,12]:
    b['mtc']=mt0-210; b.loc[f1,'mtc']-=off
    m=smf.glm(base+'+step',b,family=sm.families.Binomial()).fit()
    print(off, round(m.deviance,1))
b['mtc']=mt0-210
m=smf.glm(base+'+step',b,family=sm.families.Binomial()).fit()
b['pred']=m.mu*b.units_produced
b['mo']=b.d.dt.month
print(b.groupby(['mo','line']).apply(lambda g:g.defective_units.sum()/g.pred.sum()).unstack().round(2))
print(m.params.round(4))
EOF
python3 m6.py

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m7.py <<'EOF'
exec(open('m4.py').read().split('dates=')[0])
from scipy import stats
b['step']=((b.line=='L2')&(b.d>='2025-06-16')).astype(int)
terms=['C(supplier_name)*(hc + I(hc**2))','cycle_time_s + I(cycle_time_s**2)','ambient_temp_c','C(shift)','dsc','mtc + I(mtc**2)','machine_age_years','C(line)','C(operator_id)','step']
fit=lambda t,d=b: smf.glm('defective_units + ok ~ '+'+'.join(t),d,family=sm.families.Binomial()).fit()
full=fit(terms); phi=full.pearson_chi2/full.df_resid; print('phi',phi)
for i,t in enumerate(terms):
    r=fit(terms[:i]+terms[i+1:]); ddf=r.df_resid-full.df_resid
    if ddf: F=(r.deviance-full.deviance)/ddf/phi; print(t, ddf, round(F,2), stats.f.sf(F,ddf,full.df_resid))
# L4 only: age effect
for L in ['L1','L2','L3','L4']:
    m=fit([t for t in terms if t not in('C(line)','C(operator_id)','step')],b[b.line==L]); print(L, m.params.machine_age_years.round(4), m.bse.machine_age_years.round(4))
EOF
python3 m7.py 2>/dev/null

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m8.py <<'EOF'
exec(open('m7.py').read().split('full=')[0])
t2=[t for t in terms if t not in ('C(operator_id)','machine_age_years')]
m=fit(t2); b['pred']=m.mu*b.units_produced; b['lr']=np.log(b.rate/m.mu)
g=b.groupby(['line','operator_id']).agg(n=('lr','size'),obs=('defective_units','sum'),pred=('pred','sum'),mlr=('lr','mean'),se=('lr','sem'))
g['r']=g.obs/g.pred; print(g.round(3))
print(b.groupby('shift').lr.mean())
# robust: OLS on log ratio with operator, cluster by date
import statsmodels.formula.api as smf
o=smf.ols('lr ~ C(operator_id)',b).fit(); print(o.f_test(' + '.join([]) or np.eye(len(o.params))[1:]))
for L in ['L1','L2','L3','L4']:
    o=smf.ols('lr ~ C(operator_id)',b[b.line==L]).fit(); print(L,o.fvalue,o.f_pvalue)
EOF
python3 m8.py 2>/dev/null

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m9.py <<'EOF'
exec(open('m7.py').read().split('full=')[0])
t=['C(supplier_name)*(hc + I(hc**2))','cycle_time_s + I(cycle_time_s**2)','C(shift)','C(dsc)','mtc + I(mtc**2)','C(line)','step']
m=fit(t); print(m.params.filter(like='dsc').round(3).to_string())
print(b.groupby('dsc').size().to_dict())
t=['C(supplier_name)*bs(humidity_pct,df=5)','cycle_time_s + I(cycle_time_s**2)','C(shift)','dsc','mtc + I(mtc**2)','C(line)','step']
m=fit(t)
a=b[b.supplier_name=='Alpha']; print(a.humidity_pct.min(),a.humidity_pct.max())
g=pd.DataFrame({'humidity_pct':np.arange(10,70.1,0.5)})
ref=b.iloc[[0]]
res=[]
for h in g.humidity_pct:
    d=a.copy(); d['humidity_pct']=h; d['hc']=h-30
    res.append(m.predict(d).mean())
g['p']=res; print(g.iloc[::4].round(4).to_string()); print(g.loc[g.p.idxmin()])
EOF
python3 m9.py 2>/dev/null

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m10.py <<'EOF'
exec(open('m7.py').read().split('full=')[0])
a=b[b.supplier_name=='Alpha']
for hterm in ['hc + I(hc**2)','hc + I(hc**2) + I(hc**3)','hc + I(hc**2) + I(hc**3)+I(hc**4)']:
    t=['C(supplier_name)*('+hterm+')','cycle_time_s + I(cycle_time_s**2)','C(shift)','dsc','mtc + I(mtc**2)','C(line)','step']
    m=fit(t)
    hs=np.arange(12,72.01,0.1); res=[]
    for h in hs:
        d=a.copy(); d['humidity_pct']=h; d['hc']=h-30; res.append(m.predict(d).mean())
    res=np.array(res); print(hterm, m.deviance, round(hs[res.argmin()],1), res.min().round(4), res[[0,80,180,280,480]].round(4))
# binned check for Alpha
a2=a.copy(); m=fit(['C(supplier_name)','cycle_time_s + I(cycle_time_s**2)','C(shift)','dsc','mtc + I(mtc**2)','C(line)','step'],b)
b['pr']=m.mu*b.units_produced; a2=b[b.supplier_name=='Alpha']
print(a2.groupby(pd.cut(a2.humidity_pct,range(10,75,5))).apply(lambda g:pd.Series({'n':len(g),'r':g.defective_units.sum()/g.pr.sum()})).round(3))
EOF
python3 m10.py 2>/dev/null

cd /tmp/claude-0/-tmp-edabench-claude-tn82ql6n/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > m11.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
B=pd.read_pickle('b.pkl')
B['ok']=B.units_produced-B.defective_units
B['step']=((B.line=='L2')&(B.d>='2025-06-16')).astype(int)
B['mtc']=B.mt-210; B['hc']=B.humidity_pct-30
b=B.dropna(subset=['mt','humidity_pct'])
f='defective_units + ok ~ C(supplier_name)*(hc + I(hc**2)) + cycle_time_s + I(cycle_time_s**2) + C(shift) + dsc + mtc + I(mtc**2) + C(line) + step'
m=smf.glm(f,b,family=sm.families.Binomial()).fit()
# impute for prediction in full set
F=B.copy()
F['hc']=F.hc.fillna(F.groupby('supplier_name').hc.transform('median')); F['mtc']=F.mtc.fillna(F.groupby(['line', F.d.dt.month]).mtc.transform('median'))
base=m.predict(F)
print('actual',B.defective_units.sum()/B.units_produced.sum(), 'model', (base*F.units_produced).sum()/F.units_produced.sum())
for s in ['Alpha','Beta','Gamma']:
    d=F.copy(); d['supplier_name']=s; p=m.predict(d)
    print(s, (p*F.units_produced).sum()/F.units_produced.sum(), (F.defective_units*p/base).sum()/F.units_produced.sum())
d=F.copy(); d['dsc']=d.dsc%14; p=m.predict(d)
print('C3', (F.defective_units*p/base).sum()/F.units_produced.sum(), (p*F.units_produced).sum()/F.units_produced.sum(), (d.dsc!=F.dsc).sum())
# also using C(dsc) categorical
m2=smf.glm(f.replace('dsc','C(dsc)'),b,family=sm.families.Binomial()).fit()
b2=m2.predict(F); p2=m2.predict(d); print('C3 cat', (F.defective_units*p2/b2).sum()/F.units_produced.sum())
EOF
python3 m11.py 2>/dev/null
