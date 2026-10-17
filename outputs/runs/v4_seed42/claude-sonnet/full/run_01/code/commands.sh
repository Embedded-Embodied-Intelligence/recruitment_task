cd /tmp/edabench_claude_m_orgdjz; ls; for f in *.csv; do echo == $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_m_orgdjz; cat suppliers.csv; cat maintenance.csv | awk -F, '{print $2,$3,$4}' | sort | uniq -c | head -30; python3 -I - <<'E'
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
for c in ['production_date','line','shift','operator_id','supplier_code']:
    print(d[c].value_counts(dropna=False).head(25))
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    n=pd.to_numeric(d[c],errors='coerce')
    print(c,n.isna().sum(),n.describe().to_dict(), d[c][n.isna()].unique()[:10])
print(d.batch_id.duplicated().sum(), d.duplicated().sum())
E

cd /tmp/edabench_claude_m_orgdjz; grep sensor maintenance.csv; python3 -I - <<'E'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates()
print(len(d),d.batch_id.nunique())
s=d.production_date.str.contains('/')
print(s.sum())
a=pd.to_datetime(d.production_date.where(~s),errors='coerce')
b=pd.to_datetime(d.production_date.where(s),format='%m/%d/%Y',errors='coerce')
d['date']=a.fillna(b); print(d.date.isna().sum(),d.date.min(),d.date.max())
# check dd/mm possibility
print(d.production_date[s].str[:2].astype(int).max(), d.production_date[s].str[3:5].astype(int).max())
d['mt']=d.mold_temp
print(d.groupby('line').mt.describe())
print(d.humidity_pct.describe(), (d.humidity_pct<=0).sum(), d.humidity_pct.isna().sum(), (d.humidity_pct>100).sum())
print(np.sort(d.humidity_pct.dropna().unique())[:10])
print(d.mt.sort_values().head(40).values)
x=d[d.mt>300]; print(x.line.value_counts(), x.date.min(),x.date.max())
print(d[d.mt<100].groupby('line').size())
print(d.groupby('line').date.agg(['min','max']))
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates()
s=d.production_date.str.contains('/')
for f in ['%m/%d/%Y','%d/%m/%Y']:
    b=pd.to_datetime(d.production_date[s],format=f,errors='coerce')
    print(f,b.isna().sum(),b.min(),b.max())
h=d.humidity_pct
print(h.value_counts().head(5)); print((h<5).sum(), h[h<5].unique())
print(d.groupby('line').size())
m=pd.read_csv('maintenance.csv');print(m.date.min(),m.date.max())
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv')
p=d.production_date
iso=pd.to_datetime(p.where(~p.str.contains('/')),errors='coerce')
print(iso.notna().sum(), iso.is_monotonic_increasing, iso.dropna().is_monotonic_increasing)
print(iso.dropna().iloc[:3], iso.dropna().diff().dt.days.min())
mdy=pd.to_datetime(p,format='%m/%d/%Y',errors='coerce'); dmy=pd.to_datetime(p,format='%d/%m/%Y',errors='coerce')
print(d.iloc[:12][['production_date','line']])
print(((mdy.notna())&(dmy.notna())&(mdy!=dmy)).sum(), (mdy.isna()&dmy.notna()).sum(),(mdy.notna()&dmy.isna()).sum())
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv')
p=d.production_date
d['sl']=p.str.contains('/')
mdy=pd.to_datetime(p,format='%m/%d/%Y',errors='coerce'); dmy=pd.to_datetime(p,format='%d/%m/%Y',errors='coerce')
d['mdy_bad']=mdy.isna()&d.sl; d['dmy_bad']=dmy.isna()&d.sl
print(d.groupby('line')[['sl','mdy_bad','dmy_bad']].sum())
print(d.groupby(['line','supplier_code']).size().head(0))
print(d[d.sl].groupby('line').production_date.apply(lambda s:list(s[:3])))
E

cd /tmp/edabench_claude_m_orgdjz; mkdir -p $TMPDIR; cat > /tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py <<'E'
import pandas as pd, numpy as np
def load():
    d=pd.read_csv('batches.csv').drop_duplicates('batch_id').copy()
    p=d.production_date
    d['date']=np.where(d.line=='L4',pd.to_datetime(p,format='%d/%m/%Y',errors='coerce'),
        pd.to_datetime(p,format='%m/%d/%Y',errors='coerce'))
    iso=pd.to_datetime(p,format='%Y-%m-%d',errors='coerce')
    d['date']=pd.to_datetime(d['date']).fillna(iso)
    d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
    d['supplier_code']=d.supplier_code.str.strip().str.upper()
    s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code')
    d['mt']=d.mold_temp.where(d.mold_temp>50)
    d.loc[d.line=='L3','mt']=(d.loc[d.line=='L3','mt']-32)*5/9
    d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
    d['rate']=d.defective_units/d.units_produced
    return d
E
cd /tmp/edabench_claude_m_orgdjz; PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -I - <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
from prep import *
d=load()
print(len(d),d.date.isna().sum(),d.date.min(),d.date.max(),d.shift.isna().sum())
print(d.hum.isna().sum(), d.defective_units.sum()/d.units_produced.sum(), d.mt.median(), d.mt.isna().sum())
print(d.groupby('line').mt.describe())
print(d[d.line=='L1'].assign(m=lambda x:x.date.dt.to_period('M')).groupby('m').mt.agg(['mean','std',lambda s:(s.isna()).sum()]))
print(d.groupby('line').date.agg(['min','max']))
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
from prep import *
d=load()
print(len(d),d.date.isna().sum(),d.date.min(),d.date.max(),d['shift'].isna().sum())
print(d.hum.isna().sum(), d.defective_units.sum()/d.units_produced.sum(), d.mt.median(), d.mt.isna().sum())
print(d.groupby('line').mt.describe())
print(d[d.line=='L1'].assign(m=lambda x:x.date.dt.to_period('M')).groupby('m').mt.agg(['mean','std',lambda s:(s.isna()).sum()]))
print(d.groupby('line').date.agg(['min','max']))
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
from prep import *
d=load()
d['w']=d.date.dt.to_period('W')
t=d.pivot_table(index='w',columns='line',values='mt',aggfunc='mean').round(1)
r=d.pivot_table(index='w',columns='line',values='rate',aggfunc='mean').round(3)
print(pd.concat([t,r],axis=1).to_string())
E

cd /tmp/edabench_claude_m_orgdjz; cat >> /tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py <<'E'
def feats(d):
    m=pd.read_csv('maintenance.csv',parse_dates=['date']); m=m[m.event=='mold_cleaning']
    out=[]
    for ln,g in d.groupby('line'):
        c=m[m.line==ln].date.sort_values().values
        idx=np.searchsorted(c,g.date.values,side='right')-1   # cleaning before first shift => same day counts
        last=c[idx]; g=g.copy(); g['dsc']=(g.date.values-last).astype('timedelta64[D]').astype(int); out.append(g)
    return pd.concat(out).sort_index()
E
python3 -I - <<'E'
import sys; sys.path.insert(0,'/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
from prep import *
import statsmodels.formula.api as smf
d=feats(load())
print(d.dsc.describe())
d['cyc_dev']=d.cycle_time_s-d.recipe_cycle_time_s
d['post']=(d.date>='2025-04-14').astype(int)
d['L1pre']=((d.line=='L1')&(d.post==0)).astype(int)
d['L1post']=((d.line=='L1')&(d.post==1)).astype(int)
x=d.dropna(subset=['mt'])
r=smf.ols('mt~ambient_temp_c+C(line)+L1pre+L1post',x).fit(); print(r.params)
print(d.groupby('supplier_name')[['cyc_dev','hum']].describe().T.to_string())
d.to_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['nd']=d.units_produced-d.defective_units
for off in [0,6.4]:
    d['mta']=d.mt+np.where(d.L1pre==1,off,0)
    print('median',d.mta.median())
    x=d.dropna(subset=['mta','hum']).copy()
    f='nd+defective_units~'
    # use rate with freq weights
    m=smf.glm('rate~mta+I(mta**2)+hum+I(hum**2)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(supplier_name)+C(line)+dsc',x,family=sm.families.Binomial(),freq_weights=x.units_produced).fit()
    print(off,m.deviance)
    print(m.summary().tables[1].as_text()[:4000] if off==6.4 else '')
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
d['pd']=(d.pre_dried=='yes').astype(int)
x=d.dropna(subset=['mta','hum']).copy()
def fit(f,x=x):
    m=smf.glm(f,x,family=sm.families.Binomial(),freq_weights=x.units_produced).fit(scale='X2'); return m
for f in ['rate~mta+I(mta**2)+hum+I(hum**2)+C(supplier_name)+cyc_dev+I(cyc_dev**2)+machine_age_years+ambient_temp_c+C(shift)+C(line)+dsc',
 'rate~mta+I(mta**2)+(hum+I(hum**2))*C(supplier_name)+cyc_dev+I(cyc_dev**2)+machine_age_years+ambient_temp_c+C(shift)+C(line)+dsc']:
    m=fit(f); print(m.deviance,m.scale); print(m.summary().tables[1])
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
def b(col,bins,by=None):
    d['b']=pd.cut(d[col],bins)
    g=d.groupby(['b']+([by] if by else []),observed=True)
    r=(g.defective_units.sum()/g.units_produced.sum()).unstack() if by else g.defective_units.sum()/g.units_produced.sum()
    print(col);print(r.round(4).to_string())
b('hum',[0,15,20,25,30,35,40,45,50,55,60,80],'supplier_name')
b('mta',[150,195,200,205,210,215,220,225,230,245])
b('cyc_dev',[-15,-8,-4,-2,0,2,4,8,15])
b('machine_age_years',[0,3,5,7,9,12,25])
b('ambient_temp_c',[10,15,18,21,24,27,31])
b('dsc',[-1,2,5,8,11,14,20,40])
print(d.groupby('shift').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
g=d.groupby('operator_id');print((g.defective_units.sum()/g.units_produced.sum()).round(4).to_string())
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
print(pd.crosstab(d.operator_id,d.line).to_string())
print(d.groupby('line').machine_age_years.describe())
print(pd.crosstab(d['shift'],d.line))
print(d[['mta','hum','ambient_temp_c','cycle_time_s','machine_age_years','dsc']].corr().round(2))
d['bad']=d.defective_units; d['good']=d.units_produced-d.defective_units
x=d.dropna(subset=['mta','hum']).copy()
x['h']=x.hum-30; x['m']=x.mta-212
def fit(f):
    m=smf.glm('bad+good~'+f,x,family=sm.families.Binomial()).fit(scale='X2'); return m
m=fit('(h+I(h**2))*C(supplier_name)+m+I(m**2)+cyc_dev+I(cyc_dev**2)+machine_age_years+I(machine_age_years**2)+ambient_temp_c+C(shift)+C(operator_id)+C(line)+dsc')
print(m.scale,m.summary().tables[1])
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
d['bad']=d.defective_units; d['good']=d.units_produced-d.defective_units
x=d.dropna(subset=['mta','hum']).copy()
x['h']=x.hum-30; x['m']=x.mta-212
x['alpha']=(x.supplier_name=='Alpha').astype(int)
F='(h+I(h**2))*C(supplier_name)+m+I(m**2)+cyc_dev+I(cyc_dev**2)+ambient_temp_c+C(shift)+C(line)+dsc'
m=smf.glm('bad+good~'+F,x,family=sm.families.Binomial()).fit()
print(m.deviance,m.df_resid,m.pearson_chi2)
x['e']=m.predict(x)*x.units_produced
x['w']=x.date.dt.to_period('W')
t=x.groupby(['w','line']).apply(lambda g:g.bad.sum()/g.e.sum()).unstack().round(2)
print(t.to_string())
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['m']=d.date.dt.to_period('M')
print(d.pivot_table(index='m',columns='line',values='qc_inspection_min').round(1))
print(d.pivot_table(index='m',columns='line',values='dsc').round(1))
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
for l,g in m.groupby('line'): print(l,g.date.dt.strftime('%m-%d').tolist())
x=d[(d.line=='L3')&(d.date>='2025-07-10')&(d.date<='2025-08-05')].groupby('date').apply(lambda g:pd.Series({'r':g.defective_units.sum()/g.units_produced.sum(),'n':len(g)}))
print(x.T.round(3).to_string())
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['w']=d.date.dt.to_period('W')
for l in ['L2','L3']:
    g=d[d.line==l]
    print(l);print(g.groupby('w').agg(qc=('qc_inspection_min','mean'),r=('rate','mean'),n=('units_produced','mean'),rc=('rework_cost_eur','mean')).round(3).iloc[12:].T.to_string())
e=d[(d.line.isin(['L1','L4']))]
print(smf.ols('qc_inspection_min~units_produced+defective_units+rate',e).fit().params)
print(smf.ols('rework_cost_eur~units_produced+defective_units',e).fit().rsquared)
print(d[['qc_inspection_min','rate','units_produced','defective_units','rework_cost_eur']].corr().round(2))
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
d['bad']=d.defective_units; d['good']=d.units_produced-d.defective_units
x=d.dropna(subset=['mta','hum']).copy()
x['h']=x.hum-30; x['m']=x.mta-212
F='(h+I(h**2))*C(supplier_name)+m+I(m**2)+cyc_dev+I(cyc_dev**2)+ambient_temp_c+C(shift)+C(line)+dsc'
x=x[~((x.line=='L3')&(x.date>='2025-07-21'))]
base=smf.glm('bad+good~'+F,x,family=sm.families.Binomial()).fit()
best=[]
for dt in pd.date_range('2025-05-25','2025-07-10'):
    x['s']=((x.line=='L2')&(x.date>=dt)).astype(int)
    m=smf.glm('bad+good~'+F+'+s',x,family=sm.families.Binomial()).fit()
    best.append((m.deviance,dt.date(),m.params['s']))
print(sorted(best)[:5])
L=x[x.line=='L2'];print(L[(L.date>='2025-06-08')&(L.date<='2025-06-22')].groupby('date').apply(lambda g:g.bad.sum()/g.units_produced.sum()).round(3).to_string())
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
d['bad']=d.defective_units; d['good']=d.units_produced-d.defective_units
d['s2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s3']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['h']=d.hum-30; d['m']=d.mta-212; d['night']=(d['shift']=='Night').astype(int)
x=d.dropna(subset=['mta','hum']).copy()
G=lambda f:smf.glm('bad+good~'+f,x,family=sm.families.Binomial()).fit()
base='(h+I(h**2))*C(supplier_name)+m+I(m**2)+cyc_dev+I(cyc_dev**2)+ambient_temp_c+night+C(line)+dsc+s2+s3+machine_age_years'
m=G(base);print(m.deviance,m.pearson_chi2);print(m.summary().tables[1])
def lrt(extra,b=base):
    m2=G(b+extra);print(extra,round(m.deviance-m2.deviance,1) if b==base else '')
lrt('+C(operator_id)')
lrt('+cycle_time_s'); lrt('+I(cycle_time_s**2)')
lrt('+I(machine_age_years**2)')
lrt('+C(supplier_name):cyc_dev')
lrt('+I(dsc**2)')
lrt('+m:C(supplier_name)')
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
d['bad']=d.defective_units; d['good']=d.units_produced-d.defective_units
d['s2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s3']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['h']=d.hum-30; d['m']=d.mta-212; d['night']=(d['shift']=='Night').astype(int)
x=d.dropna(subset=['mta','hum']).copy()
G=lambda f,x=x:smf.glm('bad+good~'+f,x,family=sm.families.Binomial()).fit()
base='(h+I(h**2))*C(supplier_name)+m+cyc_dev+night+C(line)+dsc+s2+s3'
m=G(base+'+C(operator_id)+machine_age_years')
print(m.params.filter(like='operator').round(3).to_string()); print(m.params['machine_age_years'],m.bse['machine_age_years'])
for l in ['L1','L2','L3','L4']:
    y=x[x.line==l]; mm=G('h+I(h**2)+C(supplier_name)+m+cyc_dev+night+dsc+s2+s3+machine_age_years',y) if l in('L1','L4') else G('h+I(h**2)+C(supplier_name)+m+cyc_dev+night+dsc+machine_age_years'+('+s2' if l=='L2' else '+s3'),y)
    print(l,mm.params['machine_age_years'].round(4),mm.bse['machine_age_years'].round(4))
# age vs operator in L4
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
d['bad']=d.defective_units; d['good']=d.units_produced-d.defective_units
d['s2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s3']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['m']=d.mta-212; d['night']=(d['shift']=='Night').astype(int)
x=d.dropna(subset=['mta','hum']).copy()
for nm in ['Alpha','Beta','Gamma']:
    a=x[x.supplier_name==nm]
    base='m+cyc_dev+night+C(line)+dsc+s2+s3+'
    g=np.linspace(12.5,72,120)
    m=smf.glm('bad+good~'+base+'cr(hum,df=6)',a,family=sm.families.Binomial()).fit()
    p=a.iloc[[0]].copy(); rows=pd.concat([p]*len(g)); rows['hum']=g
    pr=m.predict(rows); print(nm,'spline min at',g[np.argmin(pr)].round(1), 'dev',m.deviance.round(1))
    print(' ',[ (round(h),round(v*100,2)) for h,v in zip(g[::10],pr.values[::10])])
    for hc in [30,35,40,45]:
        a=a.copy(); a['lo']=np.maximum(0,hc-a.hum)**2*0+np.maximum(0,hc-a.hum); 
    # hinge both sides grid
    best=None
    for L in range(20,46,1):
      for U in range(L,56,1):
        a2=a.assign(lo=np.maximum(0,L-a.hum)**2,hi=np.maximum(0,a.hum-U)**2)
        mm=smf.glm('bad+good~'+base+'lo+hi',a2,family=sm.families.Binomial()).fit()
        if best is None or mm.deviance<best[0]: best=(mm.deviance,L,U,mm.params['lo'],mm.params['hi'])
    print(' hinge',best)
E

cd /tmp/edabench_claude_m_orgdjz; python3 -I - <<'E' 2>&1 | grep -v Warn
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-m-orgdjz/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/d.pkl')
d['mta']=d.mt+np.where(d.L1pre==1,6.4,0)
d['bad']=d.defective_units; d['good']=d.units_produced-d.defective_units
d['s2']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s3']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['night']=(d['shift']=='Night').astype(int)
x=d.dropna(subset=['mta','hum']).copy()
x['m']=x.mta-212; x['h']=x.hum-30
B='(h+I(h**2))*C(supplier_name)+m+cyc_dev+night+C(line)+s2+s3+'
G=lambda f:smf.glm('bad+good~'+B+f,x,family=sm.families.Binomial()).fit()
for f in ['dsc','dsc+I(np.maximum(dsc-14,0))','dsc+I(np.maximum(dsc-7,0))','dsc+I(dsc**2)','dsc+I(np.maximum(dsc-14,0))+I(np.maximum(dsc-14,0)**2)']:
    r=G(f);print(f,round(r.deviance,1)); 
r=G('dsc'); print(r.params['dsc'])
# binned residual by dsc
x['e']=r.predict(x)*x.units_produced
x['b']=pd.cut(x.dsc,[-1,0,2,4,6,8,10,12,14,17,20,25,40])
print(x.groupby('b',observed=True).apply(lambda g:pd.Series({'o/e':g.bad.sum()/g.e.sum(),'n':len(g)})).round(3))
# counterfactual, imputed on all
A=d.copy()
A['hum']=A.hum.fillna(x.hum.median()); A['mta']=A.mta.fillna(A.groupby('line').mta.transform('median'))
A['m']=A.mta-212; A['h']=A.hum-30
p0=r.predict(A); A2=A.assign(dsc=A.dsc%14); p1=r.predict(A2)
print(p0.mul(A.units_produced).sum()/A.units_produced.sum(), p1.mul(A.units_produced).sum()/A.units_produced.sum())
tot=A.defective_units.sum()/A.units_produced.sum()
print('ratio approach',tot*p1.mul(A.units_produced).sum()/p0.mul(A.units_produced).sum())
# hinge version
r2=G('dsc+I(np.maximum(dsc-14,0))')
p0=r2.predict(A);p1=r2.predict(A2); print('hinge ratio',tot*p1.mul(A.units_produced).sum()/p0.mul(A.units_produced).sum())
# C1
for nm in ['Alpha','Beta','Gamma']:
    B_=A.copy(); B_['supplier_name']=nm; B_['cyc_dev']=0
    print(nm,r.predict(B_).mul(A.units_produced).sum()/A.units_produced.sum())
E
