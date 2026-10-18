cd /tmp/edabench_claude_zhjoi9wv; ls; head -5 *.csv; wc -l *.csv; cat suppliers.csv

cd /tmp/edabench_claude_zhjoi9wv; cat maintenance.csv | head -80; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
for c in d.columns:
    print(c, d[c].nunique(), d[c].isna().sum(), d[c].value_counts().head(8).to_dict())
print(d.duplicated().sum(), d.batch_id.duplicated().sum())
"

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d[d.batch_id=='B-12345'])
dup=d[d.batch_id.duplicated(keep=False)].sort_values('batch_id')
print(dup.head(30).to_string())
full=d.duplicated(keep=False)
print(dup[~dup.duplicated(keep=False)].shape)
print(d.production_date[~d.production_date.str.match(r'\d{4}-')].str[:2].value_counts().head(20))
"

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
for l,g in d.groupby('line'):
    pd_=g.production_date
    print(l, pd_.str.match(r'\d{4}-').sum(), (~pd_.str.match(r'\d{4}-')).sum(), pd_[~pd_.str.match(r'\d{4}-')].head(3).tolist())
    print(pd.to_numeric(g.mold_temp,errors='coerce').describe().round(1).to_dict())
k=d.duplicated(['line','batch_id'],keep=False)
x=d[k]
print(len(x), x.drop_duplicates().shape, x.drop_duplicates(['line','batch_id']).shape)
xx=x.drop_duplicates(); print(xx[xx.duplicated(['line','batch_id'],keep=False)].sort_values('batch_id').to_string())
"

mkdir -p /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py <<'EOF'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates()
d['date']=pd.NaT
for l,fmt in [('L1','%m/%d/%Y'),('L4','%d/%m/%Y'),('L2','%Y-%m-%d'),('L3','%Y-%m-%d')]:
    m=d.line==l; d.loc[m,'date']=pd.to_datetime(d.loc[m,'production_date'],format=fmt)
d['date']=pd.to_datetime(d['date'])
s=d['shift'].str.strip().str.lower(); d['shift']=s.map({'day':'Day','d':'Day','night':'Night','n':'Night'})
d['supplier_code']=d.supplier_code.str.strip().str.upper()
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    d[c]=pd.to_numeric(d[c])
d.loc[d.mold_temp<=0,'mold_temp']=np.nan
m=d.line=='L3'; d.loc[m,'mold_temp']=(d.loc[m,'mold_temp']-32)*5/9
d['hum_raw']=d.humidity_pct
d.loc[(d.humidity_pct<0)|(d.humidity_pct>100),'humidity_pct']=np.nan
d['rate']=d.defective_units/d.units_produced
sup=pd.read_csv('suppliers.csv'); d=d.merge(sup,on='supplier_code',how='left')
d=d.sort_values(['line','date']).reset_index(drop=True)
d.to_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py; python3 -c "
import pandas as pd
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
print(len(d), d.shift.value_counts(dropna=False).to_dict(), d.supplier_name.value_counts(dropna=False).to_dict(), d.date.min(), d.date.max())
print(d.humidity_pct.isna().sum(), (d.hum_raw==50.2).sum(), d.groupby('line').apply(lambda g:(g.hum_raw==50.2).sum()))
print(d.hum_raw.describe())
print(d.defective_units.sum()/d.units_produced.sum())
print(d.mold_temp.median(), d.mold_temp.isna().sum())
d['m']=d.date.dt.to_period('M')
print(d.groupby(['line','m']).mold_temp.median().unstack(0).round(1))
print(d.groupby(['line','m']).rate.mean().unstack(0).round(3))
"

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
print(len(d), d['shift'].value_counts(dropna=False).to_dict(), d.supplier_name.value_counts(dropna=False).to_dict(), d.date.min(), d.date.max())
print(d.humidity_pct.isna().sum(), (d.hum_raw==50.2).sum(), d.groupby('line').apply(lambda g:(g.hum_raw==50.2).sum()))
print(d.hum_raw.describe())
print(d.defective_units.sum()/d.units_produced.sum())
print(d.mold_temp.median(), d.mold_temp.isna().sum())
d['m']=d.date.dt.to_period('M')
print(d.groupby(['line','m']).mold_temp.median().unstack(0).round(1))
print(d.groupby(['line','m']).rate.mean().unstack(0).round(3))
"

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
x=d[d.hum_raw==50.2]; print(x.groupby('line').date.agg(['min','max','count']))
l2=d[d.line=='L2']; print(l2[(l2.date>='2025-02-20')&(l2.date<='2025-04-10')][['date','hum_raw']].to_string())
" | head -80

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['wk']=d.date.dt.to_period('W')
t=d.groupby(['wk','line']).mold_temp.mean().unstack().round(1)
t['L1-oth']=t.L1-t[['L2','L4']].mean(1)
print(t.iloc[5:22])
print(d.groupby(['line']).ambient_temp_c.describe())
print(d[['mold_temp','ambient_temp_c','humidity_pct','cycle_time_s','machine_age_years','rate','qc_inspection_min','rework_cost_eur']].corr().round(2))
"

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
print(smf.ols('mold_temp~ambient_temp_c+C(line)+post',d).fit().params.round(2))
print(smf.ols('mold_temp~ambient_temp_c+C(line)+post+C(supplier_name)+machine_age_years',d).fit().summary().tables[1])
print(smf.ols('rework_cost_eur~defective_units+units_produced',d).fit().rsquared)
print(smf.ols('qc_inspection_min~defective_units+rate+units_produced',d).fit().summary().tables[1])
"

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
o=d[(d.line!='L1')]
m=smf.ols('mold_temp~ambient_temp_c',o).fit(); print(m.params)
d['res']=d.mold_temp-m.predict(d)
d['m']=d.date.dt.to_period('M')
print(d.groupby(['m','line']).res.median().unstack().round(2))
print(d[d.line=='L1'].groupby('post').res.median())
for off in [0,5,6,6.4,7,8]:
  x=d.copy(); x.loc[x.post==1,'mold_temp']-=off; print(off, x.mold_temp.median())
"

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/feat.py <<'EOF'
import pandas as pd, numpy as np
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
mt=pd.read_csv('maintenance.csv',parse_dates=['date'])
cl=mt[mt.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date.max()
    return (r.date-c).days
d['dsc']=d.apply(dsc,axis=1)
d.loc[(d.line=='L2')&(d.date>='2025-03-03')&(d.date<='2025-04-13')&(d.hum_raw==50.2),'humidity_pct']=np.nan
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['mold_raw']=d.mold_temp
d['ct_dev']=d.cycle_time_s-d.recipe_cycle_time_s
d['ok']=d.units_produced-d.defective_units
d.to_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/feat.py; python3 -c "
import pandas as pd
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
print(d.humidity_pct.isna().sum())
d['b']=pd.cut(d.dsc,[-1,3,7,10,14,18,21,28,40,80])
print(d.groupby('b').rate.agg(['mean','count']))
print(d.groupby('supplier_name')[['rate','cycle_time_s','ct_dev']].mean())
print(d.groupby(['supplier_name',pd.cut(d.humidity_pct,[0,15,25,35,45,55,80])]).rate.agg(['mean','count']).unstack(0))
print(d.groupby(['supplier_name',pd.cut(d.ct_dev,[-20,-4,-2,0,2,4,20])]).rate.agg(['mean','count']).unstack(0))
"

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/m1.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
print(pd.crosstab(d.line,d.supplier_name)); print(d.groupby('line').machine_age_years.describe())
x=d.dropna(subset=['mold_temp','humidity_pct']).copy()
f='defective_units + ok ~ I(mt-212)+I((mt-212)**2)+C(supplier_name)*(humidity_pct+I(humidity_pct**2))+ct_dev+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+dsc+C(line)'
for off in [0,4,6,7,8,10]:
    x['mt']=x.mold_raw-off*x.post
    m=smf.glm(f,x,family=sm.families.Binomial()).fit(); print(off, m.llf)
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/m1.py

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/m2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
d['mt']=d.mold_raw
x=d.dropna(subset=['mt','humidity_pct']).copy()
x['mtb']=pd.cut(x.mt,[150,200,205,210,215,220,225,230,260])
x['hb']=pd.cut(x.humidity_pct,[0,15,25,35,45,55,80])
x['db']=pd.cut(x.dsc,[-1,3,7,10,14,21,28,80])
x['ctb']=pd.cut(x.ct_dev,[-20,-4,-2,0,2,4,20])
x['ab']=pd.cut(x.machine_age_years,[0,3,5,7,10,14,17,25])
x['amb']=pd.cut(x.ambient_temp_c,[0,15,20,25,35])
f='defective_units + ok ~ C(mtb)+C(supplier_name)*C(hb)+C(ctb)+C(ab)+C(amb)+C(shift)+C(db)'
tr=x[(x.post==0)]
m=smf.glm(f,tr,family=sm.families.Binomial()).fit()
print(m.summary().tables[1])
x['pred']=m.predict(x)*x.units_produced
x['wk']=x.date.dt.to_period('2W')
g=x.groupby(['wk','line'])[['defective_units','pred']].sum()
print((g.defective_units/g.pred).unstack().round(2))
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/m2.py

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/m2.py <<'EOF'
x['r']=x.defective_units/x.pred
x['cpd']=x.rework_cost_eur/x.defective_units
x['qc']=x.qc_inspection_min
for l,a,b in [('L2','2025-06-05','2025-06-25'),('L3','2025-07-12','2025-07-30')]:
    y=x[(x.line==l)&(x.date>=a)&(x.date<=b)].groupby('date')[['r','cpd','qc']].mean().round(2); print(l); print(y)
x['m']=x.date.dt.to_period('M')
print(x.groupby(['m','line']).cpd.median().unstack().round(2))
print(x.groupby(['m','line']).qc.mean().unstack().round(2))
print(x.groupby(['m','line']).units_produced.mean().unstack().round(0))
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/m2.py | sed -n '/^L2$/,$p'

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
d['w']=d.date.dt.to_period('W')
y=d[d.line=='L2'].groupby('w')[['units_produced','defective_units','rate','rework_cost_eur','qc_inspection_min']].mean().round(3)
print(y.iloc[6:16])
print(d.groupby('line').units_produced.describe())
y=d[(d.line=='L2')&(d.units_produced>1000)]; print(y.date.agg(['min','max','count']))
"

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/cp.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
d['mt']=d.mold_raw
x=d.dropna(subset=['mt']).copy()
x['hum']=x.humidity_pct.fillna(x.humidity_pct.median()); x['hmiss']=x.humidity_pct.isna().astype(int)
f='defective_units + ok ~ bs(mt,4)+C(supplier_name)*bs(hum,4)+hmiss+ct_dev+C(I(machine_age_years>10))+ambient_temp_c+C(shift)+np.minimum(dsc,25)+post'
tr=x[~(((x.line=='L2')&(x.date>='2025-06-01'))|((x.line=='L3')&(x.date>='2025-07-15')))]
m=smf.glm(f,tr,family=sm.families.Binomial()).fit()
x['pred']=m.predict(x)*x.units_produced
l2=x[(x.line=='L2')].groupby('date')[['defective_units','pred']].sum()
best=[]
for c in l2.index[(l2.index>='2025-05-20')&(l2.index<='2025-07-10')]:
    a=l2[l2.index<c]; b=l2[l2.index>=c]
    ra=a.defective_units.sum()/a.pred.sum(); rb=b.defective_units.sum()/b.pred.sum()
    ll=(a.defective_units*np.log(ra)-a.pred*ra).sum()+(b.defective_units*np.log(rb)-b.pred*rb).sum()
    best.append((ll,c.date(),round(ra,3),round(rb,3)))
for b in sorted(best)[-6:]: print(b)
print((l2.defective_units/l2.pred).loc['2025-06-08':'2025-06-22'].round(2))
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/cp.py

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
d['mt']=d.mold_raw
bad=((d.line=='L2')&(d.date>='2025-06-16'))|((d.line=='L3')&(d.date>='2025-07-21'))|(d.post==1)
x=d[~bad].dropna(subset=['mt','humidity_pct']).copy()
print(len(x))
base='defective_units + ok ~ bs(mt,4)+C(supplier_name)*bs(humidity_pct,4)+ct_dev+np.minimum(dsc,25)+C(line)'
for extra in ['','+machine_age_years','+ambient_temp_c','+C(shift)','+C(operator_id)','+cycle_time_s']:
    m=smf.glm(base+extra,x,family=sm.families.Binomial()).fit()
    print(extra, round(m.llf,1), round(m.deviance,1), m.df_resid)
m=smf.glm(base+'+machine_age_years+ambient_temp_c+C(shift)',x,family=sm.families.Binomial()).fit()
print(m.params.filter(regex='age|ambient|shift|ct_dev|dsc|line'), m.bse.filter(regex='age|ambient|shift'))
print(pd.crosstab(x.operator_id,x['shift']).T)
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py <<'EOF'
for l in ['L1','L2','L3','L4']:
    y=x[x.line==l]
    m=smf.glm('defective_units + ok ~ bs(mt,4)+C(supplier_name)*bs(humidity_pct,4)+ct_dev+np.minimum(dsc,25)+C(shift)+machine_age_years+ambient_temp_c',y,family=sm.families.Binomial()).fit()
    print(l, m.params[['machine_age_years','ambient_temp_c','C(shift)[T.Night]']].round(4).tolist(), m.bse[['machine_age_years','ambient_temp_c']].round(4).tolist())
y=x[x.line=='L4']; print(y.groupby(pd.cut(y.machine_age_years,[0,10,12,14,16,18,20,25])).rate.agg(['mean','count']))
# nighttime: what differs?
print(x.groupby('shift')[['ambient_temp_c','mt','humidity_pct','ct_dev','dsc']].mean())
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py | tail -18

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py <<'EOF'
b2='defective_units + ok ~ bs(mt,4)+C(supplier_name)*bs(humidity_pct,4)+np.minimum(dsc,25)+C(line)+C(shift)'
for e in ['+ct_dev','+cycle_time_s','+ct_dev+cycle_time_s','+ct_dev+C(operator_id)','+bs(ct_dev,4)','+C(supplier_name)*ct_dev']:
    m=smf.glm(b2+e,x,family=sm.families.Binomial()).fit(); print(e, round(m.llf,1), m.df_resid)
m=smf.glm(b2+'+ct_dev+cycle_time_s',x,family=sm.families.Binomial()).fit(); print(m.params[['ct_dev','cycle_time_s']])
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py | tail -9

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py <<'EOF'
print(pd.crosstab(d.operator_id,d.line).T.to_string())
m=smf.glm(b2+'+ct_dev+C(operator_id)',x,family=sm.families.Binomial()).fit(); print(m.params.filter(regex='oper').round(3).to_string())
print(m.pearson_chi2/m.df_resid)
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b1.py | tail -30

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/off.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
bad=((d.line=='L2')&(d.date>='2025-06-16'))|((d.line=='L3')&(d.date>='2025-07-21'))
x=d[~bad].dropna(subset=['mold_raw','humidity_pct']).copy()
f='defective_units + ok ~ mt+I(mt**2)+C(supplier_name)*bs(humidity_pct,4)+ct_dev+np.minimum(dsc,25)+C(line)+C(shift)'
for off in range(0,13):
    x['mt']=x.mold_raw-off*x.post-212
    m=smf.glm(f,x,family=sm.families.Binomial()).fit(); print(off, round(m.llf,1), m.params[['mt','I(mt ** 2)']].round(4).tolist())
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/off.py

cd /tmp/edabench_claude_zhjoi9wv; python3 -c "
import pandas as pd
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
p=d.groupby(['date','line']).humidity_pct.mean().unstack(); print(p.corr().round(2))
print(d.groupby(d.date.dt.month).humidity_pct.agg(['mean','std']).round(1))
print(d[['humidity_pct','ambient_temp_c','mold_raw','ct_dev','dsc']].corr().round(2))
"

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
OFF=8
d['mt']=d.mold_raw-OFF*d.post
print('A4', d.mt.median(), 'with 6.5:', (d.mold_raw-6.5*d.post).median())
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['l3rec']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
x=d.dropna(subset=['mt','humidity_pct']).copy()
# dsc shape
f0='defective_units + ok ~ mt+C(supplier_name)*bs(humidity_pct,5)+ct_dev+C(line)+C(shift)+l2post+l3rec'
for e in ['+C(np.minimum(dsc,35))','+np.minimum(dsc,14)','+np.minimum(dsc,21)','+np.minimum(dsc,28)','+dsc']:
    m=smf.glm(f0+e,x,family=sm.families.Binomial()).fit(); print(e, round(m.llf,1))
m=smf.glm(f0+'+C(np.minimum(dsc,35))',x,family=sm.families.Binomial()).fit()
print(m.params.filter(regex='dsc').round(3).values)
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py <<'EOF'
for c in [25,30,32,35,40,50]:
    m=smf.glm(f0+f'+np.minimum(dsc,{c})',x,family=sm.families.Binomial()).fit(); print(c, round(m.llf,1), m.params.iloc[-1].round(4))
x['db']=pd.cut(x.dsc,[-1,13,20,27,34,41,48,55,62,70])
m=smf.glm(f0+'+C(db)',x,family=sm.families.Binomial()).fit(); print(m.params.filter(regex='db').round(3)); print(x.db.value_counts().sort_index())
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py | tail -28

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py <<'EOF'
m=smf.glm(f0,x,family=sm.families.Binomial()).fit()
x['pred']=m.predict(x)*x.units_produced
for l,a,b in [('L4','2025-01-01','2025-04-30'),('L1','2025-07-01','2025-08-20')]:
  y=x[(x.line==l)&(x.date>=a)&(x.date<=b)].copy(); y['wk']=y.date.dt.to_period('W')
  g=y.groupby('wk')[['defective_units','pred']].sum(); g['dsc']=y.groupby('wk').dsc.mean(); g['r']=g.defective_units/g.pred; print(l); print(g.round(2))
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py | sed -n '/^L4$/,$p'

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py <<'EOF'
for l in ['L1','L2','L3','L4']:
  y=x[(x.line==l)].copy(); 
  if l=='L4': y=y[(y.date<'2025-02-01')|(y.date>'2025-04-11')]
  g=y.groupby(pd.cut(y.dsc,[-1,3,7,10,14,21,28,35,80]))[['defective_units','pred']].sum(); print(l,(g.defective_units/g.pred).round(2).tolist())
y=x[(x.line=='L4')&(x.date>='2025-02-01')&(x.date<='2025-04-11')]
print(y.groupby(y.date.dt.to_period('W')).apply(lambda g: pd.Series({'n':len(g),'r':g.defective_units.sum()/g.pred.sum()})))
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final.py | tail -16

cd /tmp/edabench_claude_zhjoi9wv; cat > /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/f.pkl')
d['mt']=d.mold_raw-8*d.post
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['l3rec']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['gap4']=((d.line=='L4')&(d.date>'2025-02-14')&(d.date<'2025-04-11')).astype(int)
x=d[d.gap4==0].dropna(subset=['mt','humidity_pct']).copy()
print(x.dsc.max())
f0='defective_units + ok ~ mt+C(supplier_name)*bs(humidity_pct,5)+ct_dev+C(line)+C(shift)+l2post+l3rec'
for e in ['+C(dsc)','+dsc','+np.minimum(dsc,28)','+np.minimum(dsc,21)','+np.minimum(dsc,14)','+dsc+I(dsc**2)']:
    m=smf.glm(f0+e,x,family=sm.families.Binomial()).fit(); print(e, round(m.llf,1), m.df_model)
m=smf.glm(f0+'+C(dsc)',x,family=sm.families.Binomial()).fit(); print(m.params.filter(regex='dsc').round(3).values)
m=smf.glm(f0+'+dsc',x,family=sm.families.Binomial()).fit(); print(m.params.round(4).to_string(), m.pearson_chi2/m.df_resid)
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final2.py

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final2.py <<'EOF'
f=f0+'+dsc'
m=smf.glm(f,x,family=sm.families.Binomial()).fit()
# C2
g=pd.DataFrame({'humidity_pct':np.arange(x.humidity_pct.min(),x.humidity_pct.max()+0.01,0.1)})
base=x[x.supplier_name=='Alpha']
res=[]
for h in g.humidity_pct:
    z=base.copy(); z['humidity_pct']=h; res.append((m.predict(z)*z.units_produced).sum()/z.units_produced.sum())
g['p']=res; print('C2', g.loc[g.p.idxmin()].round(3).tolist(), x.humidity_pct.min(), x.humidity_pct.max())
print(g.iloc[::50].round(4).T)
# nonparametric check for Alpha
a=x[x.supplier_name=='Alpha']; print(a.groupby(pd.cut(a.humidity_pct,range(0,80,5))).apply(lambda q:q.defective_units.sum()/q.units_produced.sum()).round(4))
# C1
y=d.copy()
mr=smf.ols('mold_raw~ambient_temp_c+C(line)',d).fit()
y['mt']=y.mt.fillna(mr.predict(y))
y['l3rec']=0
hs=x.humidity_pct.sample(200,random_state=0).values
obs=y.humidity_pct.notna()
for s in ['Alpha','Beta','Gamma']:
    z=y.copy(); z['supplier_name']=s
    p=pd.Series(0.0,index=z.index)
    p[obs]=m.predict(z[obs])
    zm=z[~obs]; acc=0
    for h in hs:
        zz=zm.copy(); zz['humidity_pct']=h; acc=acc+m.predict(zz)
    p[~obs]=acc/len(hs)
    print('C1',s,(p*z.units_produced).sum()/z.units_produced.sum())
# C3
y=d.copy(); y['mt']=y.mt.fillna(mr.predict(y))
y2=y.copy(); y2['dsc']=y.dsc%14
r=np.exp(m.params['dsc']*(y2.dsc-y.dsc))  # approx; use logistic below
def pr(z):
    p=pd.Series(np.nan,index=z.index); ok=z.humidity_pct.notna(); p[ok]=m.predict(z[ok]); 
    zz=z[~ok].copy(); acc=0
    for h in hs: zz['humidity_pct']=h; acc=acc+m.predict(zz)
    p[~ok]=acc/len(hs); return p
p0=pr(y); p1=pr(y2)
ratio=p1/p0
for lab,rr in [('gap as logged',ratio),('gap unaffected',ratio.where(y.gap4==0,1.0))]:
    print('C3',lab,(y.defective_units*rr).sum()/y.units_produced.sum())
print('A3',y.defective_units.sum()/y.units_produced.sum())
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final2.py | sed -n '/C2/,$p'

cd /tmp/edabench_claude_zhjoi9wv; cat >> /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final2.py <<'EOF'
a=x[x.supplier_name=='Alpha']
for hf in ['humidity_pct+I(humidity_pct**2)','bs(humidity_pct,4)','bs(humidity_pct,6)','bs(humidity_pct,8)']:
    mm=smf.glm('defective_units + ok ~ mt+ct_dev+C(line)+C(shift)+l2post+l3rec+dsc+'+hf,a,family=sm.families.Binomial()).fit()
    gg=[]
    for h in np.arange(12.1,72.3,0.1):
        z=a.copy(); z['humidity_pct']=h; gg.append(((mm.predict(z)*z.units_produced).sum(),h))
    print(hf, round(min(gg)[1],1), round(mm.llf,1))
EOF
python3 /tmp/claude-0/-tmp-edabench-claude-zhjoi9wv/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/final2.py | tail -4
