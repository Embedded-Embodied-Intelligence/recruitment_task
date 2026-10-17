ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('==',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    if df[c].nunique()<40: print(vc.to_dict())
    else: print(df[c].sample(12,random_state=1).tolist())
print('dup batch_id rows', df.batch_id.duplicated().sum(), 'full dup rows', df.duplicated().sum())
"
echo; cat maintenance.csv | awk -F, '{print $3, $4}' | sort | uniq -c

python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
d=df.production_date
pat=d.map(lambda s: 'iso' if re.fullmatch(r'\d{4}-\d{2}-\d{2}',s) else ('slash_ab' if re.fullmatch(r'\d{2}/\d{2}/\d{4}',s) else 'other:'+s))
print(pat.value_counts())
sl=d[pat=='slash_ab']
a=sl.str[:2].astype(int); b=sl.str[3:5].astype(int)
print('first>12',(a>12).sum(),'second>12',(b>12).sum(),'both<=12',((a<=12)&(b<=12)).sum())
print(pd.crosstab(df.line[pat=='slash_ab'], (a>12)))
print(pd.crosstab(df.line[pat=='iso'], pat[pat=='iso']).head())
print(df.line[pat=='slash_ab'].value_counts())
print(sorted(df.line.unique()))
"
echo ---; python3 -c "
import pandas as pd
m=pd.read_csv('maintenance.csv')
print(m.to_string())
" | head -100

python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
s=df.production_date
sl=s.str.fullmatch(r'\d{2}/\d{2}/\d{4}')
x=df[sl].copy()
x['a']=x.production_date.str[:2].astype(int); x['b']=x.production_date.str[3:5].astype(int)
print(x.groupby('line').agg(a_max=('a','max'),b_max=('b','max'),a_gt12=('a',lambda v:(v>12).sum()),b_gt12=('b',lambda v:(v>12).sum())))
def p(r):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}',r.production_date): return pd.Timestamp(r.production_date)
    a,b,y=r.production_date.split('/')
    if r.line=='L4': return pd.Timestamp(int(y),int(b),int(a))
    return pd.Timestamp(int(y),int(a),int(b))
df['date']=df.apply(p,axis=1)
print(df.date.min(), df.date.max())
print(df.groupby('line').date.agg(['min','max','count']))
# check ISO lines: are there any ISO dates on L1/L4?
print(pd.crosstab(df.line, s.str.contains('-')))
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
bad={}
for c in num:
    v=pd.to_numeric(df[c],errors='coerce')
    bad[c]=df[c][v.isna()].value_counts().to_dict()
    print(c, 'non-numeric:',bad[c], ' desc:', v.describe()[['min','25%','50%','75%','max']].round(2).tolist())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
for c in ['mold_temp','humidity_pct','units_produced','defective_units','cycle_time_s','machine_age_years']:
    df[c]=pd.to_numeric(df[c],errors='coerce')
print('humidity <0 or >100:', ((df.humidity_pct<0)|(df.humidity_pct>100)).sum(), df.humidity_pct[df.humidity_pct<0].tolist())
print('humidity dist', df.humidity_pct.describe().round(2).to_dict())
print('mold zeros', (df.mold_temp==0).sum(), df.mold_temp[df.mold_temp<100].value_counts().to_dict())
print('mold_temp histogram bins'); print(pd.cut(df.mold_temp,[0,1,100,150,180,190,200,210,220,230,240,250,300,350,400,500]).value_counts().sort_index())
print('defective>units', (df.defective_units>df.units_produced).sum(), 'units<=0', (df.units_produced<=0).sum())
print(df.groupby('line').mold_temp.describe().round(1))
print(pd.cut(df.mold_temp,[0,100,150,200,250,300,350,400,500]).groupby(df.line).value_counts().unstack())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['humidity_raw']=df.humidity_pct
df['hum']=pd.to_numeric(df.humidity_pct,errors='coerce')
print('humidity blank', (df.humidity_raw=='').sum(), 'sentinel -1', (df.hum==-1).sum(), 'other invalid', ((df.hum<0)|(df.hum>100)).sum()-(df.hum==-1).sum())
print('missing or invalid total', (df.hum.isna()|(df.hum<0)|(df.hum>100)).sum())
print(df.groupby('line').apply(lambda g: pd.Series({'mold_zero':(pd.to_numeric(g.mold_temp)==0).sum(),'hum_bad':(g.hum.isna()|(g.hum<0)).sum()})))
def p(r):
    if '-' in r.production_date: return pd.Timestamp(r.production_date)
    a,b,y=r.production_date.split('/')
    return pd.Timestamp(int(y),int(b),int(a)) if r.line=='L4' else pd.Timestamp(int(y),int(a),int(b))
df['date']=df.apply(p,axis=1)
df['mold']=pd.to_numeric(df.mold_temp)
v=df[(df.mold>0)]
v=v.assign(mold_c=np.where(v.line=='L3',(v.mold-32)*5/9,v.mold))
print('L3 mold C by month:'); print(v[v.line=='L3'].groupby(v.date.dt.month).mold_c.describe().round(1))
l1=v[v.line=='L1']
print('L1 mold by side of 2025-04-14'); print(l1.groupby(l1.date>=pd.Timestamp('2025-04-14')).mold.describe().round(2))
print('L1 mold by week'); print(l1.groupby(l1.date.dt.to_period('M')).mold.agg(['mean','median','std','count']).round(2))
for L in ['L2','L4']:
    g=v[v.line==L]; print(L, g.groupby(g.date.dt.to_period('M')).mold.agg(['mean','std']).round(2).T)
"

mkdir -p "$TMPDIR" 2>/dev/null; SP=/tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; mkdir -p $SP; cat > $SP/clean.py <<'EOF'
import pandas as pd, numpy as np

SRC = '/tmp/edabench_claude_cv1rg2ec'

def load_raw():
    return pd.read_csv(f'{SRC}/batches.csv', dtype=str, keep_default_na=False)

def parse_date(row):
    s = row.production_date
    if '-' in s:
        return pd.Timestamp(s)
    a, b, y = s.split('/')
    # L1 writes MM/DD/YYYY, L4 writes DD/MM/YYYY (verified against the date window)
    return pd.Timestamp(int(y), int(b), int(a)) if row.line == 'L4' else pd.Timestamp(int(y), int(a), int(b))

def load():
    raw = load_raw()
    n_raw = len(raw)
    df = raw.drop_duplicates().copy()
    n_dedup = len(df)
    df['date'] = df.apply(parse_date, axis=1)
    df['shift'] = df['shift'].str.strip().str.lower().map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
    df['supplier_code'] = df['supplier_code'].str.strip().str.upper()
    for c in ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'cycle_time_s', 'units_produced',
              'defective_units', 'qc_inspection_min', 'rework_cost_eur']:
        df[c] = pd.to_numeric(df[c], errors='coerce')
    df['humidity_raw'] = df['humidity_pct']
    hum = pd.to_numeric(df['humidity_pct'], errors='coerce')
    df['humidity_pct'] = hum.where((hum >= 0) & (hum <= 100))
    # mold temp: L3 reports Fahrenheit, zero is a missing reading
    mold = df['mold_temp'].where(df['mold_temp'] != 0)
    df['mold_raw'] = mold
    df['mold_c'] = np.where(df['line'] == 'L3', (mold - 32) * 5 / 9, mold)
    df['mold_c'] = df['mold_c'].astype(float)
    df['defect_rate'] = df['defective_units'] / df['units_produced']
    sup = pd.read_csv(f'{SRC}/suppliers.csv', dtype=str)
    sup['supplier_code'] = sup['supplier_code'].str.strip().str.upper()
    sup['recipe_cycle_time_s'] = sup['recipe_cycle_time_s'].astype(float)
    df = df.merge(sup, on='supplier_code', how='left')
    return raw, n_raw, n_dedup, df

if __name__ == '__main__':
    raw, n_raw, n_dedup, df = load()
    print('raw rows', n_raw, 'after exact dedup', n_dedup, 'unique batch_id', df.batch_id.nunique())
    print(df['shift'].value_counts(dropna=False).to_dict())
    print(df['supplier_code'].value_counts(dropna=False).to_dict())
    print('unmatched supplier', df.supplier_name.isna().sum())
    print(df.shape)
EOF
cd $SP && python3 clean.py && echo "$SP"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
print('A1',df.batch_id.nunique())
print('A2 humidity missing/invalid', df.humidity_pct.isna().sum())
print('A3', df.defective_units.sum()/df.units_produced.sum(), df.defective_units.sum(), df.units_produced.sum())
print('A4 median mold C', df.mold_c.median(), df.mold_c.notna().sum())
# B2 leakage check
print(df[['defective_units','defect_rate','qc_inspection_min','rework_cost_eur','units_produced','cycle_time_s','machine_age_years','mold_c','humidity_pct','ambient_temp_c']].corr()[['defective_units','defect_rate']].round(3))
import numpy as np
print('rework/defective', (df.rework_cost_eur/df.defective_units).describe().round(3).to_dict())
print('qc/defective ratio', (df.qc_inspection_min/df.defective_units).describe().round(3).to_dict())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
import numpy.linalg as la
raw,n_raw,n_dedup,df=load()
def r2(y,X):
    X=np.column_stack([np.ones(len(X)),X]); b=la.lstsq(X,y,rcond=None)[0]; p=X@b
    return 1-((y-p)**2).sum()/((y-y.mean())**2).sum(), b
d=df.dropna(subset=['defective_units'])
print('qc ~ defects+units R2', r2(d.qc_inspection_min.values, d[['defective_units','units_produced']].values)[0].round(3))
print('qc ~ units only R2', r2(d.qc_inspection_min.values, d[['units_produced']].values)[0].round(3))
print('qc ~ defects only R2', r2(d.qc_inspection_min.values, d[['defective_units']].values)[0].round(3))
print('rework ~ defects R2', r2(d.rework_cost_eur.values, d[['defective_units']].values)[0].round(3), r2(d.rework_cost_eur.values, d[['defective_units']].values)[1].round(3))
# B3 defect rate by line by month
df['m']=df.date.dt.to_period('M')
t=df.groupby(['line','m']).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack(0).round(4)
print(t)
"

python3 -c "import statsmodels, scipy, sklearn; print(statsmodels.__version__, scipy.__version__, sklearn.__version__)" 2>&1; python3 -c "import pandas; print(pandas.__version__)"

python3 -c "import statsmodels, scipy; print(statsmodels.__version__, scipy.__version__)" 2>&1

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
v=df.dropna(subset=['mold_c'])
v=v.assign(w=v.date.dt.to_period('W'))
t=v.groupby(['w','line']).mold_c.mean().unstack()
t['L1-mean(L2,L4)']=t.L1-(t.L2+t.L4)/2
print(t.round(1).to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > glm1.py <<'EOF'
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
import statsmodels.api as sm
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy()
d['y']=d.defective_units; d['n']=d.units_produced
d['ok']=d.n-d.y
d['pre_dried']=d.pre_dried.str.lower()
print('rows', len(d))
f='defect_rate ~ mold_c + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
m=smf.glm('y + ok ~ mold_c + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)', data=d, family=sm.families.Binomial()).fit()
# explicit proportions form
import statsmodels.genmod.families as F
mod=smf.glm('defect_rate ~ mold_c + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)', data=d, family=sm.families.Binomial(), var_weights=d.n)
r=mod.fit()
print(r.summary().tables[1])
print('deviance', r.deviance, 'df', r.df_resid)
EOF
python3 glm1.py 2>&1 | grep -v Warning | head -80

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > scan.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
base='defect_rate ~ mold_c + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
def fit(form, dd):
    return smf.glm(form, data=dd, family=sm.families.Binomial(), var_weights=dd.units_produced).fit()
b=fit(base,d)
print('base dev', round(b.deviance,2))
res=[]
for L in ['L1','L2','L3','L4']:
    dates=sorted(d.loc[d.line==L,'date'].unique())
    best=None
    for dt in dates[10:-10]:
        dd=d.copy(); dd['post']=((dd.line==L)&(dd.date>=dt)).astype(int)
        f=fit(base+' + post',dd)
        drop=b.deviance-f.deviance
        if best is None or drop>best[1]: best=(pd.Timestamp(dt).date(),drop,f.params['post'],f.bse['post'])
    res.append((L,)+best)
    print(L, 'best date', best[0], 'deviance drop', round(best[1],2), 'coef', round(best[2],4), 'se', round(best[3],4))
EOF
python3 scan.py

sleep 100; cat /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b5wx3xb63.output

cat /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b5wx3xb63.output 2>/dev/null; echo "---"; ls /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/ 2>/dev/null

until grep -q "L4 best" /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b5wx3xb63.output 2>/dev/null || ! pgrep -f scan.py >/dev/null; do sleep 5; done; grep -E "best date|base dev" /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b5wx3xb63.output

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
df['m']=df.date.dt.to_period('M')
df['cyc_dev']=df.cycle_time_s-df.recipe_cycle_time_s
g=df.groupby(['line','m'])
out=pd.DataFrame({'age':g.machine_age_years.mean(),'amb':g.ambient_temp_c.mean(),'hum':g.humidity_pct.mean(),'cyc':g.cycle_time_s.mean(),'cycdev':g.cyc_dev.mean(),'night':g['shift'].apply(lambda s:(s=='Night').mean()),'alpha':g.supplier_name.apply(lambda s:(s=='Alpha').mean()),'beta':g.supplier_name.apply(lambda s:(s=='Beta').mean()),'gamma':g.supplier_name.apply(lambda s:(s=='Gamma').mean()),'units':g.units_produced.mean()})
print(out.round(2).to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > offset.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['post_s']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
base='defect_rate ~ mold_c + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
def fit(form, dd):
    return smf.glm(form, data=dd, family=sm.families.Binomial(), var_weights=dd.units_produced).fit()
# 1) estimate sensor offset for L1 after replacement
out=[]
for delta in np.arange(0,16.1,1.0):
    dd=d.copy(); dd['mold_c']=dd.mold_c-delta*dd.post_s
    f=fit(base,dd); out.append((delta,round(f.deviance,2)))
print('L1 post-replacement offset grid (delta, deviance):', out)
EOF
python3 offset.py

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > check_rank.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
import patsy
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
X=patsy.dmatrix('mold_c + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + C(line)', d, return_type='dataframe')
print('cols', X.shape[1], 'rank', np.linalg.matrix_rank(X.values))
print('defect_rate has inf/nan', np.isinf(d.defect_rate).sum(), d.defect_rate.isna().sum())
print('units zero', (d.units_produced==0).sum())
print(d.supplier_name.value_counts().to_dict(), d.operator_id.nunique())
u,s,vt=np.linalg.svd(X.values,full_matrices=False)
print('small singular values', s[-5:])
bad=np.where(s<1e-8)[0]
print([X.columns[i] for i in np.where(abs(vt[bad[-1]])>1e-6)[0]] if len(bad) else 'none')
EOF
python3 check_rank.py

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd
raw,n_raw,n_dedup,df=load()
ct=pd.crosstab(df.operator_id, df.line)
print(ct.to_string())
print(pd.crosstab(df.operator_id, df.shift).T.to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > model2.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
import patsy
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['post_s']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
def fit(form, dd):
    return smf.glm(form, data=dd, family=sm.families.Binomial(), var_weights=dd.units_produced).fit()
# rank check
X=patsy.dmatrix('mold_c + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name)', d, return_type='dataframe')
print('cols', X.shape[1], 'rank', np.linalg.matrix_rank(X.values))
# fine offset grid
best=None
for delta in np.arange(9,13.01,0.5):
    dd=d.copy(); dd['mold_c']=dd.mold_c-delta*dd.post_s
    f=fit('defect_rate ~ mold_c + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name)', dd)
    print('delta',delta,'dev',round(f.deviance,2))
EOF
python3 model2.py

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c']).copy()
d['post_s']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['dstr']=d.date.astype(str)
m=smf.ols('mold_c ~ C(dstr) + C(line) + post_s + ambient_temp_c + cycle_time_s + C(shift)', data=d).fit()
print('post_s offset estimate (date FE)', round(m.params['post_s'],2), '+/-', round(m.bse['post_s'],2))
m2=smf.ols('mold_c ~ C(dstr) + C(line) + post_s', data=d).fit()
print('without covariates', round(m2.params['post_s'],2))
w=d[(d.line=='L1')]
print('L1 pre mean', w[w.post_s==0].mold_c.mean().round(2), 'post', w[w.post_s==1].mold_c.mean().round(2))
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > offset2.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['post_s']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
def fit(form, dd):
    return smf.glm(form, data=dd, family=sm.families.Binomial(), var_weights=dd.units_produced).fit()
for form_name, extra in [('linear',''),('quadratic',' + I((mold_c-212)**2)')]:
    res=[]
    for delta in np.arange(9.0,13.01,0.5):
        dd=d.copy(); dd['mold_c']=dd.mold_c-delta*dd.post_s
        f=fit('defect_rate ~ mold_c + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name)'+extra, dd)
        res.append((round(delta,1),round(f.deviance,2)))
    print(form_name, res)
EOF
python3 offset2.py

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
df['w']=df.date.dt.to_period('W')
g=df.groupby(['w','line'])
t=pd.DataFrame({'rate':g.apply(lambda x:x.defective_units.sum()/x.units_produced.sum()),'mold':g.mold_c.mean(),'hum':g.humidity_pct.mean(),'cyc':g.cycle_time_s.mean(),'amb':g.ambient_temp_c.mean()}).unstack('line')
pd.set_option('display.width',250)
print(t.loc[:, pd.IndexSlice[['rate','mold'],['L2','L3']]].round(3).to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > scan2.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings, sys
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
OFF=11.2
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['cyc_dev']=d.cycle_time_s-d.recipe_cycle_time_s
def fit(form, dd):
    return smf.glm(form, data=dd, family=sm.families.Binomial(), var_weights=dd.units_produced).fit()
bases={
 'plain': 'defect_rate ~ mold_c + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name)',
 'rich': 'defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name)',
}
for name, base in bases.items():
    b=fit(base,d)
    print(name,'dev',round(b.deviance,2))
    for L in ['L2','L3']:
        dates=sorted(d.loc[d.line==L,'date'].unique())[10:-10]
        out=[]
        for dt in dates[::3]:
            dd=d.copy(); dd['post']=((dd.line==L)&(dd.date>=dt)).astype(int)
            f=fit(base+' + post',dd)
            out.append((pd.Timestamp(dt).date(), round(b.deviance-f.deviance,1), round(f.params['post'],3)))
        top=sorted(out,key=lambda x:-x[1])[:3]
        print(' ',L, 'top dates (date, dev drop, coef):', top)
EOF
timeout 110 python3 scan2.py 2>&1 | tail -20

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > lrt.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
from scipy import stats
OFF=11.2
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['L2post']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['L3post']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
def fit(form):
    return smf.glm(form, data=d, family=sm.families.Binomial(), var_weights=d.units_produced).fit()
full='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + L2post + L3post'
F=fit(full)
disp=F.pearson_chi2/F.df_resid
print('dispersion', round(disp,2))
terms={
 'mold_c (lin+quad)': ['mold_c','I(mold_c**2)'],
 'humidity x supplier': ['humidity_pct','humidity_pct:C(supplier_name)[T.Beta]','humidity_pct:C(supplier_name)[T.Gamma]'],
 'cycle x supplier': ['cycle_time_s','cycle_time_s:C(supplier_name)[T.Beta]','cycle_time_s:C(supplier_name)[T.Gamma]'],
 'ambient': ['ambient_temp_c'],
 'machine_age': ['machine_age_years'],
 'operator': [c for c in F.params.index if 'operator' in c],
 'shift': [c for c in F.params.index if 'shift' in c],
 'supplier main': [c for c in F.params.index if 'supplier_name' in c and ':' not in c],
 'L2post': ['L2post'], 'L3post': ['L3post'],
}
for name, cols in terms.items():
    keep=[c for c in F.params.index if c not in cols]
    # refit without these columns via design matrix
    X=F.model.exog; idx=[i for i,c in enumerate(F.model.exog_names) if c not in cols]
    m=sm.GLM(F.model.endog, X[:,idx], family=sm.families.Binomial(), var_weights=d.units_produced.values).fit()
    lr=(m.deviance-F.deviance)/disp
    p=stats.chi2.sf(lr, len(cols))
    print(f'{name:22s} df={len(cols)} LR(scaled)={lr:9.1f} p={p:.2e}')
print(F.params.round(4).to_string())
EOF
timeout 110 python3 lrt.py 2>&1 | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > lrt2.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
from scipy import stats
OFF=11.2
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['L2post']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['L3post']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
full='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct + I(humidity_pct**2)*C(supplier_name) + humidity_pct*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + L2post + L3post'
F=smf.glm(full, data=d, family=sm.families.Binomial(), var_weights=d.units_produced).fit()
disp=F.pearson_chi2/F.df_resid
print('dispersion', round(disp,2), 'dev', round(F.deviance,1))
names=F.model.exog_names
def lr(cols):
    idx=[i for i,c in enumerate(names) if c not in cols]
    assert len(idx)==len(names)-len(cols), cols
    m=sm.GLM(F.model.endog, F.model.exog[:,idx], family=sm.families.Binomial(), var_weights=d.units_produced.values).fit()
    s=(m.deviance-F.deviance)/disp
    return s, stats.chi2.sf(s,len(cols))
tests={
 'mold lin+quad':['mold_c','I(mold_c ** 2)'],
 'humidity quad x supplier(alpha only)':['I(humidity_pct ** 2)'],
 'ambient':['ambient_temp_c'],
 'machine_age':['machine_age_years'],
 'L2post':['L2post'],'L3post':['L3post'],
}
for k,v in tests.items():
    s,p=lr(v); print(f'{k:40s} LRscaled={s:8.1f} p={p:.2e}')
print(F.params[[c for c in names if 'humidity' in c or 'mold' in c or 'ambient' in c or 'machine' in c or 'cycle' in c]].round(5).to_string())
EOF
timeout 110 python3 lrt2.py 2>&1 | tail -40

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
OFF=11.2
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c']).copy()
d['mold_adj']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['dstr']=d.date.astype(str)
for f in ['mold_adj ~ ambient_temp_c + C(line)','mold_adj ~ ambient_temp_c + cycle_time_s + humidity_pct + C(supplier_name) + C(line) + C(operator_id) + C(shift)']:
    m=smf.ols(f,data=d).fit(); print(f); print(' ambient coef',round(m.params['ambient_temp_c'],3),'R2',round(m.rsquared,3),'resid sd',round(np.sqrt(m.mse_resid),2))
print('corr ambient vs mold_adj by line', d.groupby('line').apply(lambda g: round(g.ambient_temp_c.corr(g.mold_adj),3)).to_dict())
print('machine_age within line sd', d.groupby('line').machine_age_years.std().round(2).to_dict(), 'corr with mold within line', d.groupby('line').apply(lambda g: round(g.machine_age_years.corr(g.mold_adj),3)).to_dict())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > ambient_check.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
OFF=11.2
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['L2post']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['L3post']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
form='defect_rate ~ mold_c + humidity_pct*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + L2post + L3post'
def run(sub,label):
    m=smf.glm(form, data=sub, family=sm.families.Binomial(), var_weights=sub.units_produced).fit()
    disp=m.pearson_chi2/m.df_resid
    print(f'{label:28s} n={len(sub)} mold={m.params["mold_c"]:.4f} amb={m.params["ambient_temp_c"]:.4f} z_amb={m.tvalues["ambient_temp_c"]/np.sqrt(disp):.2f}')
run(d,'all')
run(d[d.date<pd.Timestamp('2025-05-15')],'pre-May15 (no regime)')
run(d[d.line=='L4'],'L4 only')
run(d[d.line=='L1'],'L1 only')
EOF
timeout 110 python3 ambient_check.py 2>&1 | tail -10

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
def rate(g): return g.defective_units.sum()/g.units_produced.sum()
cuts={'L2':'2025-06-15','L3':'2025-07-21'}
for L,dt in cuts.items():
    x=df[df.line==L].copy(); x['post']=x.date>=pd.Timestamp(dt)
    print('== ',L,'split at',dt)
    for col in ['supplier_name','shift','operator_id']:
        t=x.groupby([col,'post']).apply(lambda g: pd.Series({'rate':round(rate(g),4),'n':len(g)})).unstack('post')
        print(t.to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec && python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['fmt']=df.production_date.map(lambda s: 'iso' if '-' in s else 'slash')
df['per']=df.production_date.map(lambda s: None)
print(pd.crosstab([df.line,df.fmt], df['shift']).to_string())
print(pd.crosstab(df.line, df.supplier_code).to_string())
print(pd.crosstab(df.line, df.humidity_pct.eq('-1.0')))
"

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['fmt']=df.production_date.map(lambda s: 'iso' if '-' in s else 'slash')
print(pd.crosstab([df.line,df.fmt], df['shift']).to_string())
print(pd.crosstab(df.line, df.supplier_code).to_string())
print(pd.crosstab(df.line, df.humidity_pct.eq('-1.0')))
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > flex.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
from scipy import stats
OFF=11.2
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['L2post']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['L3post']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
d['cyc_dev']=d.cycle_time_s-d.recipe_cycle_time_s
specs={
 'rich': 'defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + L2post + L3post',
 'flex': 'defect_rate ~ mold_c*C(line) + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + I(cycle_time_s**2) + cyc_dev + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + L2post + L3post',
}
for k,f in specs.items():
    m=smf.glm(f, data=d, family=sm.families.Binomial(), var_weights=d.units_produced).fit()
    disp=m.pearson_chi2/m.df_resid
    out={}
    for c in ['L2post','L3post']:
        idx=[i for i,n in enumerate(m.model.exog_names) if n!=c]
        r=sm.GLM(m.model.endog,m.model.exog[:,idx],family=sm.families.Binomial(),var_weights=d.units_produced.values).fit()
        s=(r.deviance-m.deviance)/disp
        out[c]=(round(m.params[c],3), round(s,1), f'{stats.chi2.sf(s,1):.1e}')
    print(k, 'dev',round(m.deviance,1),'disp',round(disp,2), out)
EOF
timeout 115 python3 flex.py 2>&1 | tail -5

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > shape.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
OFF=11.2
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
base='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name)'
b=smf.glm(base,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
disp=b.pearson_chi2/b.df_resid
for L in ['L2','L3']:
    x=d[d.line==L]
    t=(x.date-pd.Timestamp('2025-01-06')).dt.days
    # step at best date
    best=None
    for dt in sorted(x.date.unique())[15:-15:2]:
        dd=d.copy(); dd['s']=((dd.line==L)&(dd.date>=dt)).astype(int)
        f=smf.glm(base+' + s',data=dd,family=sm.families.Binomial(),var_weights=dd.units_produced).fit()
        if best is None or f.deviance<best[1]: best=(pd.Timestamp(dt).date(),f.deviance)
    # ramp: linear trend on line from 2025-05-01 (ramp shape) vs step
    dd=d.copy(); dd['r']=np.where(dd.line==L,(dd.date-pd.Timestamp('2025-01-06')).dt.days/100.0,0.0)
    fr=smf.glm(base+' + r',data=dd,family=sm.families.Binomial(),var_weights=dd.units_produced).fit()
    print(L,'best step date',best[0],'dev step',round(best[1],1),'| linear trend dev',round(fr.deviance,1),'| null base dev',round(b.deviance,1))
EOF
timeout 115 python3 shape.py 2>&1 | grep -v Warn | tail -4

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > clean_lag.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
from scipy import stats
OFF=11.2
raw,n_raw,n_dedup,df=load()
m=pd.read_csv('/tmp/edabench_claude_cv1rg2ec/maintenance.csv',parse_dates=['date'])
mc=m[m.event=='mold_cleaning']
def days_since(row):
    c=mc[(mc.line==row.line)&(mc.date<=row.date)].date
    return (row.date-c.max()).days if len(c) else np.nan
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['dsc']=d.apply(days_since,axis=1)
print('days since cleaning distribution', d.dsc.describe().round(1).to_dict())
print('defect rate by days since cleaning bucket:')
d['bk']=pd.cut(d.dsc,[-1,2,5,8,11,14,17,21,30,60])
print(d.groupby('bk',observed=True).apply(lambda g: pd.Series({'rate':round(g.defective_units.sum()/g.units_produced.sum(),4),'n':len(g)})).to_string())
d['L2post']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['L3post']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
base='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name)'
full=base+' + L2post + L3post + dsc'
F=smf.glm(full,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
disp=F.pearson_chi2/F.df_resid
print('dsc coef', round(F.params['dsc'],4), 'z', round(F.tvalues['dsc'],2))
for c in ['L2post','L3post','dsc']:
    idx=[i for i,n in enumerate(F.model.exog_names) if n!=c]
    r=sm.GLM(F.model.endog,F.model.exog[:,idx],family=sm.families.Binomial(),var_weights=d.units_produced.values).fit()
    s=(r.deviance-F.deviance)/disp
    print(c,'LR', round(s,1), 'coef', round(F.params[c],3))
EOF
timeout 115 python3 clean_lag.py 2>&1 | grep -v -i warn | grep -v wls | tail -30

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
pd.set_option('display.width',250)
for L,dt in [('L3','2025-07-21'),('L2','2025-06-15')]:
    x=df[(df.line==L)&(df.date>=pd.Timestamp(dt)-pd.Timedelta(days=12))&(df.date<=pd.Timestamp(dt)+pd.Timedelta(days=12))]
    t=x.groupby('date').apply(lambda g: pd.Series({'n':len(g),'rate':round(g.defective_units.sum()/g.units_produced.sum(),3),'mold':round(g.mold_c.mean(),1),'hum':round(g.humidity_pct.mean(),1),'cyc':round(g.cycle_time_s.mean(),1),'amb':round(g.ambient_temp_c.mean(),1),'units':round(g.units_produced.mean()),'night':round((g['shift']=='Night').mean(),2),'age':round(g.machine_age_years.mean(),2),'qc':round(g.qc_inspection_min.mean(),1)}))
    print('==',L,dt); print(t.to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
df['m']=df.date.dt.to_period('M')
print(df.pivot_table(index='m',columns='line',values='qc_inspection_min',aggfunc='mean').round(1).to_string())
df['qc_per_def']=df.qc_inspection_min/df.defective_units
print(df.pivot_table(index='m',columns='line',values='qc_inspection_min',aggfunc='median').round(1).to_string())
x=df[df.line=='L3'].copy(); x['post']=x.date>=pd.Timestamp('2025-07-21')
print(x.groupby('post').qc_inspection_min.describe().round(1))
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
raw,n_raw,n_dedup,df=load()
df['units_k']=df.units_produced/100
def fitq(x,label):
    m=smf.ols('qc_inspection_min ~ defective_units + units_k', data=x).fit()
    print(f'{label:22s} n={len(x):4d} int={m.params[\"Intercept\"]:.2f} slope_def={m.params[\"defective_units\"]:.3f} slope_units={m.params[\"units_k\"]:.3f} R2={m.rsquared:.2f} mean_def={x.defective_units.mean():.1f}')
x3=df[df.line=='L3']
fitq(x3[x3.date<pd.Timestamp('2025-07-21')],'L3 pre 07-21')
fitq(x3[x3.date>=pd.Timestamp('2025-07-21')],'L3 post 07-21')
x2=df[df.line=='L2']
fitq(x2[x2.date<pd.Timestamp('2025-06-15')],'L2 pre 06-15')
fitq(x2[x2.date>=pd.Timestamp('2025-06-15')],'L2 post 06-15')
fitq(df[(df.line=='L1')],'L1 all')
fitq(df[(df.line=='L4')],'L4 all')
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > final_fit.py <<'EOF'
from clean import load
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
from scipy import stats
OFF=11.2
raw,n_raw,n_dedup,df=load()
mt=pd.read_csv('/tmp/edabench_claude_cv1rg2ec/maintenance.csv',parse_dates=['date'])
mc=mt[mt.event=='mold_cleaning']
def dsc(row):
    c=mc[(mc.line==row.line)&(mc.date<=row.date)].date
    return (row.date-c.max()).days
df['dsc']=df.apply(dsc,axis=1)
d=df.dropna(subset=['mold_c','humidity_pct']).copy().reset_index(drop=True)
d['mold_c']=d.mold_c-OFF*((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14')))
d['L3post']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
d['L2post']=0
BASE='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + dsc + L3post + L2post'
def fit(dd, form=BASE):
    return smf.glm(form, data=dd, family=sm.families.Binomial(), var_weights=dd.units_produced).fit()
# L2 start-date scan, daily from 06-01 to 06-25
res=[]
for dt in pd.date_range('2025-06-01','2025-06-25'):
    dd=d.copy(); dd['L2post']=((dd.line=='L2')&(dd.date>=dt)).astype(int)
    res.append((dt.date(), round(fit(dd).deviance,2)))
print('L2 start scan (date, deviance):'); print(sorted(res,key=lambda r:r[1])[:6])
d['L2post']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
F=fit(d); disp=F.pearson_chi2/F.df_resid
print('dev',round(F.deviance,1),'disp',round(disp,2))
def lrt(c):
    idx=[i for i,n in enumerate(F.model.exog_names) if not n.startswith(c)]
    r=sm.GLM(F.model.endog,F.model.exog[:,idx],family=sm.families.Binomial(),var_weights=d.units_produced.values).fit()
    s=(r.deviance-F.deviance)/disp
    return round(s,1), f'{stats.chi2.sf(s,1 if c in ["ambient_temp_c","dsc","L2post","L3post","machine_age_years"] else 2):.1e}'
for c in ['ambient_temp_c','dsc','L2post','L3post','C(operator_id)','C(shift)','mold_c','humidity_pct','cycle_time_s']:
    print(c, lrt(c))
d.to_pickle('final_d.pkl')
# ambient check on L1 pre-period only
x=d[(d.line=='L1')&(d.date<pd.Timestamp('2025-04-14'))]
m=smf.glm('defect_rate ~ mold_c + humidity_pct + cycle_time_s + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name)',data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit()
print('L1 pre-sensor ambient coef', round(m.params['ambient_temp_c'],4), 'z', round(m.tvalues['ambient_temp_c'],2))
EOF
timeout 115 python3 final_fit.py 2>&1 | grep -v -i warn | grep -v wls | tail -30

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > answers.py <<'EOF'
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
from scipy import stats
from clean import load
d=pd.read_pickle('final_d.pkl')
BASE='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + dsc + L3post + L2post'
F=smf.glm(BASE,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
disp=F.pearson_chi2/F.df_resid
names=F.model.exog_names
def lr(cols):
    idx=[i for i,n in enumerate(names) if n not in cols]
    r=sm.GLM(F.model.endog,F.model.exog[:,idx],family=sm.families.Binomial(),var_weights=d.units_produced.values).fit()
    s=(r.deviance-F.deviance)/disp
    return round(s,1), f'{stats.chi2.sf(s,len(cols)):.1e}'
print('B1 LR mold', lr(['mold_c','I(mold_c ** 2)']))
print('B1 LR humidity', lr([n for n in names if 'humidity' in n]))
print('B1 LR cycle', lr([n for n in names if 'cycle' in n]))
print('B1 LR operator', lr([n for n in names if 'operator' in n]))
print('B1 LR shift', lr([n for n in names if 'shift' in n]))
print('B1 LR ambient', lr(['ambient_temp_c']))
print('B1 LR machine_age (not in model; see earlier LR 0.9, p=0.33)')
# C2: Alpha humidity curve, averaged over Alpha batches
alpha=d[d.supplier_name=='Alpha'].copy()
grid=np.arange(16,72.01,0.1)
pred=[]
for h in grid:
    a=alpha.copy(); a['humidity_pct']=h
    pred.append(F.predict(a).mean())
pred=np.array(pred)
i=pred.argmin()
print('C2 min avg Alpha humidity', round(grid[i],1), 'rate', round(pred[i],5), 'observed humidity range Alpha', alpha.humidity_pct.min(), alpha.humidity_pct.max())
# quadratic analytic check on logit
b=F.params
print('C2 analytic (Alpha, linear+quad):', round(-b['humidity_pct']/(2*b['I(humidity_pct ** 2)']),2))
EOF
timeout 115 python3 answers.py 2>&1 | grep -v -i warn | tail -12

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > c1c3.py <<'EOF'
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
import statsmodels.api as sm
from clean import load
d=pd.read_pickle('final_d.pkl')
BASE='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + dsc + L3post + L2post'
F=smf.glm(BASE,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
# observed and model baseline
obs=d.defective_units.sum()/d.units_produced.sum()
p_old=F.predict(d)
print('complete rows', len(d), 'observed rate (complete rows)', round(obs,5), 'model rate', round((p_old*d.units_produced).sum()/d.units_produced.sum(),5))
# C1: all batches set to one supplier with its grade's standard recipe
from clean import load
raw,n_raw,n_dedup,full=load()
sup=pd.read_csv('/tmp/edabench_claude_cv1rg2ec/suppliers.csv')
sup['supplier_code']=sup.supplier_code.str.upper()
res={}
for _,s in sup.iterrows():
    x=d.copy()
    x['supplier_name']=s.supplier_name
    x['cycle_time_s']=float(s.recipe_cycle_time_s)
    p=F.predict(x)
    res[s.supplier_name]=(p*x.units_produced).sum()/x.units_produced.sum()
print('C1 single-supplier counterfactual rates:', {k:round(v,5) for k,v in res.items()})
# C3: 14-day mold cleaning rule
mt=pd.read_csv('/tmp/edabench_claude_cv1rg2ec/maintenance.csv',parse_dates=['date'])
mc=mt[mt.event=='mold_cleaning']
def dsc14(row):
    last=mc[(mc.line==row.line)&(mc.date<=row.date)].date.max()
    return (row.date-last).days % 14
x=d.copy()
x['dsc']=x.apply(dsc14,axis=1)
p_new=F.predict(x)
tot_units=full.units_produced.sum()
obs_all=full.defective_units.sum()/tot_units
adj=((p_new-p_old)*d.units_produced).sum()
c3=(full.defective_units.sum()+adj)/tot_units
print('C3 obs all rows', round(obs_all,5), 'adjustment (defects)', round(adj,1), 'C3 counterfactual', round(c3,5))
c3_model=(p_new*d.units_produced).sum()/d.units_produced.sum()
print('C3 model-only on complete rows', round(c3_model,5), ' vs model-old', round((p_old*d.units_produced).sum()/d.units_produced.sum(),5))
print('dsc14 distribution', x.dsc.describe().round(2).to_dict())
EOF
timeout 115 python3 c1c3.py 2>&1 | grep -v -i warn | tail -12

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
raw,n_raw,n_dedup,df=load()
m=df.mold_c.dropna()
post=(df.line=='L1')&(df.date>=pd.Timestamp('2025-04-14'))
for off in [0,6,11.2]:
    v=df.mold_c - off*post
    v=v.dropna()
    print('offset',off,'n',len(v),'median',round(v.median(),3),'mean',round(v.mean(),3))
print('L3 raw median check: F-as-C would give', round(df.mold_temp.replace(0,np.nan).dropna().median(),2))
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c']).copy()
d['post_s']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['dstr']=d.date.astype(str)
for lines in [['L1','L2','L4'],['L1','L2','L3','L4']]:
    x=d[d.line.isin(lines)]
    m=smf.ols('mold_c ~ C(dstr) + C(line) + post_s + ambient_temp_c', data=x).fit()
    print(lines, 'post offset', round(m.params['post_s'],2), '+/-', round(m.bse['post_s'],2))
# L1 vs L2+L4 average on pre-replacement period, to confirm no pre-period bias
pre=d[(d.line.isin(['L1','L2','L4']))&(d.date<pd.Timestamp('2025-04-14'))]
m=smf.ols('mold_c ~ C(dstr) + C(line)', data=pre).fit(); print('pre-period L1 vs L2/L4 diff', round(m.params['C(line)[T.L1]'],2))
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
raw,n_raw,n_dedup,df=load()
d=df.dropna(subset=['mold_c']).copy()
d['dstr']=d.date.astype(str)
pre=d[(d.line.isin(['L1','L2','L4']))&(d.date<pd.Timestamp('2025-04-14'))].copy()
pre['isL1']=(pre.line=='L1').astype(int)
m=smf.ols('mold_c ~ C(dstr) + isL1', data=pre).fit()
print('pre-replacement L1 minus (L2,L4) same-day diff', round(m.params['isL1'],2), '+/-', round(m.bse['isL1'],2))
post=d[(d.line.isin(['L1','L2','L4']))&(d.date>=pd.Timestamp('2025-04-14'))].copy()
post['isL1']=(post.line=='L1').astype(int)
m2=smf.ols('mold_c ~ C(dstr) + isL1', data=post).fit()
print('post-replacement L1 minus (L2,L4) same-day diff', round(m2.params['isL1'],2), '+/-', round(m2.bse['isL1'],2))
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && sed -i 's/^OFF=11.2/OFF=7.5/' final_fit.py && timeout 115 python3 final_fit.py 2>&1 | grep -v -i warn | grep -v wls | head -4 && timeout 100 python3 answers.py 2>&1 | grep -E "C2|LR" | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 110 python3 c1c3.py 2>&1 | grep -E "C1|C3" ; python3 -c "
from clean import load
import pandas as pd
raw,n_raw,n_dedup,df=load()
post=(df.line=='L1')&(df.date>=pd.Timestamp('2025-04-14'))
v=(df.mold_c-7.5*post).dropna()
print('A4 median with 7.5 offset', round(v.median(),3), 'n', len(v))
"

cd /tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
d=pd.read_pickle('final_d.pkl')
BASE='defect_rate ~ mold_c + I(mold_c**2) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name) + cycle_time_s*C(supplier_name) + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + dsc + L3post + L2post'
F=smf.glm(BASE+' + machine_age_years',data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
disp=F.pearson_chi2/F.df_resid
idx=[i for i,n in enumerate(F.model.exog_names) if n!='machine_age_years']
r=sm.GLM(F.model.endog,F.model.exog[:,idx],family=sm.families.Binomial(),var_weights=d.units_produced.values).fit()
s=(r.deviance-F.deviance)/disp
print('machine_age coef', round(F.params['machine_age_years'],4), 'LR', round(s,2), 'p', round(stats.chi2.sf(s,1),3))
print('within-line machine age vs defect (raw corr after line demeaning):', round(np.corrcoef(d.machine_age_years-d.groupby('line').machine_age_years.transform('mean'), d.defect_rate-d.groupby('line').defect_rate.transform('mean'))[0,1],3))
"
