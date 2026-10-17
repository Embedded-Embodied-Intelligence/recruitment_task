ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('---',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    print(vc.head(12).to_dict() if df[c].nunique()<60 else df[c].sample(15,random_state=1).tolist())
print('dup batch_id', df.batch_id.duplicated().sum(), 'full dup', df.duplicated().sum())
"
echo; cat suppliers.csv; echo; cat maintenance.csv | awk -F, '{print $3, $4}' | sort | uniq -c

python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=df.production_date
pat=d.map(lambda s: 'iso' if re.fullmatch(r'\d{4}-\d{2}-\d{2}',s) else ('slash' if re.fullmatch(r'\d{2}/\d{2}/\d{4}',s) else 'other:'+s))
print(pat.value_counts().head())
sl=d[pat=='slash']
a=sl.str[:2].astype(int); b=sl.str[3:5].astype(int)
print('first>12',(a>12).sum(),'second>12',(b>12).sum(),'both<=12',((a<=12)&(b<=12)).sum())
print(d[pat.str.startswith('other')].unique()[:20])
# duplicates
dup=df[df.duplicated(keep=False)]
print('dup rows sample'); print(dup.head(4).to_string())
# batch-id dup with differing content
g=df.groupby('batch_id').size(); ids=g[g>1].index
nd=df[df.batch_id.isin(ids)].drop_duplicates()
print('batch ids with conflicting content', nd.batch_id.duplicated().sum())
print(nd[nd.batch_id.duplicated(keep=False)].sort_values('batch_id').head(6).to_string())
"


python3 -c "
import pandas as pd, re, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
print(len(df))
iso=df[df.production_date.str.contains('-')]
print('iso sorted in file order?', iso.production_date.is_monotonic_increasing)
print(df.production_date.iloc[:40].tolist())
print(iso.production_date.min(), iso.production_date.max())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(df[c],errors='coerce')
    bad=df[c][x.isna()].unique()
    print(c,'nonnum',bad[:10], 'min',x.min(),'max',x.max(),'median',x.median())
"


grep -n "sensor" maintenance.csv; python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp); df['hum']=pd.to_numeric(df.humidity_pct,errors='coerce')
print('hum<0',(df.hum<0).sum(),'hum==-1',(df.hum==-1).sum(),'hum blank',(df.humidity_pct=='').sum(),'hum>100',(df.hum>100).sum())
print(np.histogram(df.mt,bins=[0,1,50,100,150,180,200,230,260,300,350,380,400,420,450,470])) 
print('mt==0',(df.mt==0).sum(), 'mt<100',(df.mt<100).sum())
df['hi']=df.mt>300
print(pd.crosstab(df.line,df.hi))
print(df[df.hi].production_date.head(3).tolist())
print(df.groupby('line').mt.describe())
"


python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp); df['hum']=pd.to_numeric(df.humidity_pct,errors='coerce')
print(df[(df.line=='L3')&(df.mt<300)][['batch_id','production_date','mold_temp']].to_string())
print(df[df.mt==0].line.value_counts())
print('hum values between 0 and 5:', sorted(df.hum[(df.hum>=0)&(df.hum<5)].unique())[:20])
print('hum low values:', np.sort(df.hum.dropna().unique())[:8])
"


mkdir -p $TMPDIR/an && cd /tmp/edabench_claude_7_5y_myr && cat > $TMPDIR/an/parse.py <<'EOF'
import pandas as pd, numpy as np, re
from datetime import date

def load_raw():
    return pd.read_csv('/tmp/edabench_claude_7_5y_myr/batches.csv', dtype=str, keep_default_na=False)

def candidates(s):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', s):
        return [pd.Timestamp(s)]
    a, b, y = s.split('/')
    a, b, y = int(a), int(b), int(y)
    out = []
    for m, d in [(b, a), (a, b)]:  # (month, day) for DD/MM then MM/DD
        try:
            t = pd.Timestamp(year=y, month=m, day=d)
            if t not in out:
                out.append(t)
        except ValueError:
            pass
    return out
EOF
cd $TMPDIR/an && python3 -c "
from parse import *
df=load_raw().drop_duplicates().reset_index(drop=True)
c=df.production_date.map(candidates)
amb=c.map(len)>1
print('ambiguous',amb.sum(),'unambiguous',(~amb).sum(), 'zero cands', (c.map(len)==0).sum())
u=c[~amb].map(lambda x:x[0])
diff=u.diff().dt.days
print('backward jumps among unambiguous:', (diff<0).sum(), 'min diff', diff.min())
print(u[diff<0].head(10).tolist())
print('range', u.min(), u.max())
"


cd $TMPDIR/an && python3 -c "
from parse import *
df=load_raw().drop_duplicates().reset_index(drop=True)
c=df.production_date.map(candidates)
amb=c.map(len)>1
df['cand']=c.map(lambda x:[str(t.date()) for t in x])
u=c.map(lambda x:x[0] if len(x)==1 else pd.NaT)
d=u.diff().dt.days
idx=d[d<0].index
for i in idx[:12]:
    print(df.loc[i-2:i+1,['production_date','line','cand']].to_string(header=False)); print()
" | head -120


cd $TMPDIR/an && cat >> parse.py <<'EOF'

def resolve_dates(df):
    """Return a Series of Timestamps. Ambiguous DD/MM vs MM/DD slash dates are
    resolved against unambiguous dates from the same line, nearest in file order."""
    cands = df.production_date.map(candidates)
    unamb = cands.map(lambda x: x[0] if len(x) == 1 else pd.NaT)
    out = unamb.copy()
    margins = {}
    for i in df.index[cands.map(len) > 1]:
        line = df.at[i, 'line']
        same = df.index[(df.line == line) & unamb.notna()]
        left = same[same < i][-8:]
        right = same[same > i][:8]
        ref = pd.Series(list(unamb[left]) + list(unamb[right]))
        med = ref.sort_values().iloc[len(ref) // 2]
        dists = sorted(((abs((t - med).days), t) for t in cands[i]))
        out[i] = dists[0][1]
        margins[i] = dists[1][0] - dists[0][0]
    return out, pd.Series(margins)
EOF
python3 -c "
from parse import *
df=load_raw().drop_duplicates().reset_index(drop=True)
d,m=resolve_dates(df)
print('unresolved', d.isna().sum())
print('margin stats', m.describe())
print('margin<30 days:', (m<30).sum(), 'of', len(m))
print(d.min(), d.max())
print(d.dt.to_period('M').value_counts().sort_index())
"


cd $TMPDIR/an && python3 -c "
from parse import *
df=load_raw().drop_duplicates().reset_index(drop=True)
d,m=resolve_dates(df)
df['d']=d
for line,g in df.groupby('line'):
    diff=g.d.diff().dt.days
    print(line, 'rows',len(g),'backward jumps', (diff<0).sum(), 'min', diff.min(), 'max', diff.max())
    bad=g[diff<0]
    print(bad[['production_date','d']].head(5).to_string())
"


cd $TMPDIR/an && cat >> parse.py <<'EOF'

def resolve_dates_global(df, k=6):
    cands = df.production_date.map(candidates)
    unamb = cands.map(lambda x: x[0] if len(x) == 1 else pd.NaT)
    out = unamb.copy()
    margins = {}
    known = unamb.dropna()
    for i in df.index[cands.map(len) > 1]:
        left = known[known.index < i][-k:]
        right = known[known.index > i][:k]
        ref = sorted(list(left) + list(right))
        med = ref[len(ref) // 2]
        dists = sorted(((abs((t - med).days), t) for t in cands[i]))
        out[i] = dists[0][1]
        margins[i] = dists[1][0] - dists[0][0]
    return out, pd.Series(margins)
EOF
python3 -c "
from parse import *
df=load_raw().drop_duplicates().reset_index(drop=True)
for k in [3,6,12]:
    d,m=resolve_dates_global(df,k)
    diff=d.diff().dt.days
    print('k',k,'backward jumps',(diff<0).sum(),'min',diff.min(),'margin<30',(m<30).sum())
d,m=resolve_dates_global(df,6)
df['d']=d
x=pd.DataFrame({'pd':df.production_date,'d':d,'line':df.line})
x['diff']=d.diff().dt.days
print(x[x['diff']<-3].head(15).to_string())
"


cd $TMPDIR/an && python3 -c "
from parse import *
df=load_raw().drop_duplicates().reset_index(drop=True)
c=df.production_date.map(candidates)
u=c.map(lambda x:x[0] if len(x)==1 else pd.NaT)
s=pd.Series(u.values)
for start in range(0,len(df),150):
    chunk=s[start:start+150].dropna()
    print(start, chunk.min().date(), chunk.max().date(), round(chunk.map(lambda t:t.dayofyear).corr(pd.Series(range(len(chunk)))),2))
"


cd $TMPDIR/an && cat > clean.py <<'EOF'
import pandas as pd, numpy as np, re
from parse import candidates, load_raw

def resolve_dates_window(df, k=20):
    cands = df.production_date.map(candidates)
    unamb = cands.map(lambda x: x[0] if len(x) == 1 else pd.NaT)
    out = unamb.copy()
    known = unamb.dropna()
    for i in df.index[cands.map(len) > 1]:
        left = known[known.index < i][-k:]
        right = known[known.index > i][:k]
        ref = sorted(list(left) + list(right))
        med = ref[len(ref) // 2]
        out[i] = min(cands[i], key=lambda t: abs((t - med).days))
    return out

def load_clean():
    raw = load_raw()
    df = raw.drop_duplicates().reset_index(drop=True)
    df['date'] = resolve_dates_window(df)
    df['shift'] = df['shift'].str.strip().str.lower().map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
    df['supplier_code'] = df['supplier_code'].str.strip().str.upper()
    for c in ['machine_age_years', 'ambient_temp_c', 'cycle_time_s', 'units_produced', 'defective_units', 'qc_inspection_min', 'rework_cost_eur']:
        df[c] = pd.to_numeric(df[c])
    df['humidity'] = pd.to_numeric(df['humidity_pct'], errors='coerce')
    df.loc[df.humidity < 0, 'humidity'] = np.nan
    mt = pd.to_numeric(df['mold_temp'])
    mt = mt.where(mt != 0)  # 0.0 = missing reading
    df['mold_raw'] = mt
    # line L3 reports Fahrenheit
    df['mold_c'] = np.where(df.line == 'L3', (mt - 32) * 5 / 9, mt)
    df['defect_rate'] = df.defective_units / df.units_produced
    sup = pd.read_csv('/tmp/edabench_claude_7_5y_myr/suppliers.csv', dtype=str)
    sup['recipe_cycle_time_s'] = sup.recipe_cycle_time_s.astype(float)
    df = df.merge(sup, on='supplier_code', how='left', validate='many_to_one')
    return df, sup
EOF
python3 -c "
from clean import *
df,sup=load_clean()
print(df.shape, df.batch_id.nunique())
print(df['shift'].value_counts(dropna=False))
print(df.supplier_code.value_counts(dropna=False))
print('humidity missing', df.humidity.isna().sum(), 'mold missing', df.mold_c.isna().sum())
print('A3', df.defective_units.sum()/df.units_produced.sum())
print('A4 median mold C', df.mold_c.median(), df.mold_c.notna().sum())
print(df.groupby('line').mold_c.describe())
print(df.date.min(), df.date.max(), df.date.isna().sum())
"


cd $TMPDIR/an && python3 -c "
from clean import *
df,sup=load_clean()
l1=df[df.line=='L1'].copy()
l1['post']=l1.date>=pd.Timestamp('2025-04-14')
print(l1.groupby('post').mold_c.describe())
# weekly view around change
l1['wk']=l1.date.dt.to_period('W')
print(l1.groupby('wk').agg(mt=('mold_c','mean'),n=('mold_c','size'),dr=('defect_rate','mean')).round(3).to_string())
" | head -80


cd $TMPDIR/an && python3 -c "
from clean import *
df,sup=load_clean()
df['post']=(df.line=='L1')&(df.date>=pd.Timestamp('2025-04-14'))
df['seg']=np.where(df.post,'L1post',np.where(df.line=='L1','L1pre',df.line))
bins=[185,195,200,205,210,215,220,225,230,245]
df['bin']=pd.cut(df.mold_c,bins)
print(df.pivot_table(index='bin',columns='seg',values='defect_rate',aggfunc='mean',observed=False).round(4).to_string())
print(df.pivot_table(index='bin',columns='seg',values='defect_rate',aggfunc='size',observed=False).to_string())
"


python3 -c "import statsmodels, sklearn, scipy; print(statsmodels.__version__, sklearn.__version__, scipy.__version__)" 2>&1; python3 -c "import pandas; print(pandas.__version__)"

python3 -c "import statsmodels; print(statsmodels.__version__)"; python3 -c "import scipy; print(scipy.__version__)"; python3 -c "import numpy; print(numpy.__version__)"

cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
import statsmodels.formula.api as smf
import statsmodels.api as sm
df,sup=load_clean()
df['post']=((df.line=='L1')&(df.date>=pd.Timestamp('2025-04-14'))).astype(int)
df['y']=df.defective_units; df['n']=df.units_produced
d=df.dropna(subset=['humidity','mold_c']).copy()
print('n',len(d))
f='defect_rate ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)'
m=smf.glm('y + (n-y) ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)', data=d, family=sm.families.Binomial()).fit(scale='X2')
print(m.summary2().tables[1].round(4).to_string())
" 2>&1 | head -80


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
import patsy
df,sup=load_clean()
d=df.dropna(subset=['humidity','mold_c']).copy()
X=patsy.dmatrix('mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)', d, return_type='dataframe')
print(X.shape, np.linalg.matrix_rank(X.values))
import numpy as np
u,s,vt=np.linalg.svd(X.values, full_matrices=False)
small=[i for i,v in enumerate(s) if v<1e-8*s[0]]
print('null dims',len(small))
if small:
    print([X.columns[j] for j in np.where(abs(vt[small[0]])>1e-6)[0]])
print(pd.crosstab(d.supplier_code,d.line))
print(pd.crosstab(d.operator_id,d.shift).head(30))
"


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
df,sup=load_clean()
d=df.dropna(subset=['humidity','mold_c']).copy()
print(pd.crosstab(d['operator_id'],d['line']).to_string())
print(d.groupby('operator_id').size().describe())
print(d.operator_id.unique())
"


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
import statsmodels.formula.api as smf
import statsmodels.api as sm
df,sup=load_clean()
df['post']=((df.line=='L1')&(df.date>=pd.Timestamp('2025-04-14'))).astype(int)
d=df.dropna(subset=['humidity','mold_c']).copy()
d['y']=d.defective_units; d['n']=d.units_produced
m=smf.glm('y + (n-y) ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)', data=d, family=sm.families.Binomial()).fit()
print('rank',np.linalg.matrix_rank(m.model.exog), m.model.exog.shape)
print('pearson chi2/df', m.pearson_chi2/m.df_resid)
t=m.summary2().tables[1]
print(t.loc[[i for i in t.index if not i.startswith('C(operator')]].round(5).to_string())
" 2>&1 | tail -30


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
import statsmodels.formula.api as smf
import statsmodels.api as sm
df,sup=load_clean()
d0=df.dropna(subset=['humidity','mold_c']).copy()
d0['y']=d0.defective_units; d0['n']=d0.units_produced
pre=(d0.line=='L1')&(d0.date<pd.Timestamp('2025-04-14'))
res=[]
for delta in [-14,-10,-6,-3,0,3,6,10,13.7,16]:
    d=d0.copy(); d['mold_adj']=d.mold_c+np.where(pre,delta,0)
    m=smf.glm('y + (n-y) ~ mold_adj + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)', data=d, family=sm.families.Binomial()).fit()
    res.append((delta, round(m.deviance,2), round(m.llf,2), round(m.params['mold_adj'],5)))
for r in res: print(r)
" 2>&1 | tail -15


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
import statsmodels.formula.api as smf
df,sup=load_clean()
df['post']=((df.line=='L1')&(df.date>=pd.Timestamp('2025-04-14'))).astype(int)
df['t']=(df.date-pd.Timestamp('2025-01-01')).dt.days
d=df.dropna(subset=['mold_c'])
for name,sub in [('L1 only',d[d.line=='L1']),('all lines',d)]:
    m=smf.ols('mold_c ~ post + t + ambient_temp_c + cycle_time_s + C(line) + C(shift)' if name=='all lines' else 'mold_c ~ post + t + ambient_temp_c + cycle_time_s + C(shift)', data=sub).fit()
    print(name, m.params[['post','t','ambient_temp_c','cycle_time_s']].round(4).to_dict(), 'se post', round(m.bse['post'],3))
m=smf.ols('mold_c ~ post + t + ambient_temp_c + cycle_time_s + C(shift)', data=d[d.line=='L1']).fit()
print(m.summary().tables[1])
g=d[d.line!='L3'].groupby('line').mold_c.agg(['mean','std'])
print(g)
print(d[d.line=='L1'].groupby('post').apply(lambda x: pd.Series({'ambient':x.ambient_temp_c.mean(),'cyc':x.cycle_time_s.mean()})))
" 2>&1 | tail -60


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
df,sup=load_clean()
pre=(df.line=='L1')&(df.date<pd.Timestamp('2025-04-14'))
for delta in [0,6.2,6.9,10,13.7]:
    v=df.mold_c+np.where(pre,delta,0)
    v=v.dropna()
    print(delta, round(v.median(),3), len(v))
"


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
df,sup=load_clean()
pre=(df.line=='L1')&(df.date<pd.Timestamp('2025-04-14'))
df['mold_adj']=df.mold_c+np.where(pre,6.9,0)
df['hum_bin']=pd.cut(df.humidity,[10,15,20,25,30,35,40,45,50,55,60,65,75])
print(df.pivot_table(index='hum_bin',columns='supplier_code',values='defect_rate',aggfunc='mean',observed=False).round(4).to_string())
print(df.pivot_table(index='hum_bin',columns='supplier_code',values='defect_rate',aggfunc='size',observed=False).to_string())
print(df.groupby('supplier_code').humidity.describe())
print(df.groupby('supplier_code').pre_dried.first())
"


cd $TMPDIR/an && cat > fit.py <<'EOF'
from clean import *
import statsmodels.formula.api as smf
import statsmodels.api as sm

def prep():
    df, sup = load_clean()
    pre = (df.line == 'L1') & (df.date < pd.Timestamp('2025-04-14'))
    df['mold_adj'] = df.mold_c + np.where(pre, 6.9, 0)
    d = df.dropna(subset=['humidity', 'mold_adj']).copy()
    d['y'] = d.defective_units
    d['n'] = d.units_produced
    return d, sup

def fit(formula, d):
    return smf.glm('y + (n-y) ~ ' + formula, data=d, family=sm.families.Binomial()).fit()
EOF
python3 -W ignore -c "
from fit import *
d,sup=prep()
base='mold_adj + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)'
models={
 'lin': base,
 'quadH': base+' + I(humidity**2)',
 'quadH_supp': base+' + I(humidity**2) + humidity:C(supplier_code) + I(humidity**2):C(supplier_code)',
 'lin_supp': base+' + humidity:C(supplier_code)',
}
for k,f in models.items():
    m=fit(f,d)
    print(k, 'dev',round(m.deviance,2),'aic',round(m.aic,1),'df',m.df_model, 'disp',round(m.pearson_chi2/m.df_resid,3))
m=fit(models['quadH_supp'],d)
t=m.summary2().tables[1]
print(t.loc[[i for i in t.index if 'humid' in i or 'supplier' in i or 'mold' in i or 'cycle' in i or 'ambient' in i]].round(6).to_string())
" 2>&1 | tail -40


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
d,sup=prep()
base='mold_adj + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)'
m=fit(base+' + bs(humidity, df=6) * C(supplier_code)', d)
print('dev',round(m.deviance,2),'df',m.df_model,'disp',round(m.pearson_chi2/m.df_resid,3))
grid=pd.DataFrame({'humidity':np.arange(12.1,72.31,0.1)})
rows=[]
ref=d.iloc[[0]].copy()
for s in ['SP-01','SP-02','SP-03']:
    g=grid.copy(); g['supplier_code']=s
    # average the other covariates over the data so only humidity and supplier change
    preds=[]
    for _,r in d.sample(400,random_state=0).iterrows():
        g2=g.copy()
        for c in ['mold_adj','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']:
            g2[c]=r[c]
        g2['supplier_code']=s
        preds.append(m.predict(g2,linear=True).values)
    eta=np.mean(preds,axis=0)
    rows.append(pd.Series(eta,index=grid.humidity.round(1),name=s))
E=pd.concat(rows,axis=1)
p=1/(1+np.exp(-E))
print(p.iloc[::20].round(4).to_string())
for s in ['SP-01','SP-02','SP-03']:
    print(s,'argmin humidity', p[s].idxmin(), round(p[s].min(),5))
" 2>&1 | tail -60


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
d,sup=prep()
base='mold_adj + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)'
m=fit(base+' + bs(humidity, df=6) * C(supplier_code)', d)
samp=d.sample(300,random_state=0)
hg=np.round(np.arange(12.1,72.3,0.1),1)
out={}
for s in ['SP-01','SP-02','SP-03']:
    acc=np.zeros(len(hg))
    for _,r in samp.iterrows():
        g=pd.DataFrame({'humidity':hg})
        for c in ['mold_adj','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']:
            g[c]=r[c]
        g['supplier_code']=s
        acc+=m.predict(g).values
    out[s]=acc/len(samp)
P=pd.DataFrame(out,index=hg)
print(P.iloc[::50].round(4).to_string())
for s in P: print(s,'argmin',P[s].idxmin(),round(P[s].min(),5))
P.to_csv('$TMPDIR/an/hum_curves.csv')
" 2>&1 | tail -40


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
d,sup=prep()
mt=pd.read_csv('/tmp/edabench_claude_7_5y_myr/maintenance.csv')
mt['date']=pd.to_datetime(mt.date)
cl=mt[mt.event=='mold_cleaning']
print(cl.groupby('line').date.agg(['min','max','count']))
for line,g in cl.groupby('line'):
    gaps=g.sort_values('date').date.diff().dt.days
    print(line,'gaps>14:', (gaps>14).sum(), 'max gap', gaps.max(), 'sorted list', sorted(g.date.dt.strftime('%m-%d'))[:8])
print(mt[mt.event!='mold_cleaning'])
"


cd $TMPDIR/an && cat >> fit.py <<'EOF'

def add_days_since_clean(d):
    mt = pd.read_csv('/tmp/edabench_claude_7_5y_myr/maintenance.csv')
    mt['date'] = pd.to_datetime(mt.date)
    cl = mt[mt.event == 'mold_cleaning']
    def last(row):
        g = cl[(cl.line == row.line) & (cl.date <= row.date)].date
        return (row.date - g.max()).days
    d['days_since_clean'] = d.apply(last, axis=1)
    return d
EOF
python3 -W ignore -c "
from fit import *
d,sup=prep()
d=add_days_since_clean(d)
print(d.days_since_clean.describe())
d['dsbin']=pd.cut(d.days_since_clean,[-1,3,6,9,12,14,17,20,25,40])
print(d.groupby('dsbin',observed=True).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()})).round(4).to_string())
base='mold_adj + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)'
m=fit(base+' + days_since_clean', d)
print('ds coef', m.params['days_since_clean'], m.bse['days_since_clean'], 'z', m.tvalues['days_since_clean'])
m2=fit(base, d)
print('dev diff', m2.deviance-m.deviance)
" 2>&1 | tail -40


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
d,sup=prep()
d=add_days_since_clean(d)
f='mold_adj + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + days_since_clean + bs(humidity, df=6)*C(supplier_code)'
m=fit(f,d)
print('disp', round(m.pearson_chi2/m.df_resid,3), 'dev', round(m.deviance,1))
d['mu']=m.predict(d)
d['pr']=(d.y-d.n*d.mu)/np.sqrt(d.n*d.mu*(1-d.mu))
d.to_pickle('$TMPDIR/an/d_model.pkl')
# CUSUM-like scan of Pearson residual mean before vs after date, per line
res=[]
for line,g in d.groupby('line'):
    g=g.sort_values('date')
    dates=sorted(g.date.unique())
    for t in dates[10:-10]:
        a=g[g.date<t].pr; b=g[g.date>=t].pr
        if len(a)<40 or len(b)<40: continue
        tstat=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        res.append((line,pd.Timestamp(t).date(),round(tstat,2),round(b.mean()-a.mean(),3)))
r=pd.DataFrame(res,columns=['line','date','t','diff'])
print(r.sort_values('t',key=abs,ascending=False).head(12).to_string())
print(d.groupby('line').pr.agg(['mean','std']).round(3))
" 2>&1 | tail -40


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
df,sup=load_clean()
l3=df[df.line=='L3'].sort_values('date')
l3['wk']=l3.date.dt.to_period('W')
print(l3.groupby('wk').agg(raw=('mold_raw','median'),mc=('mold_c','median'),n=('mold_c','size'),dr=('defect_rate','mean')).round(2).to_string())
print(l3[(l3.date>='2025-07-10')&(l3.date<='2025-07-31')][['date','mold_raw','mold_c','defect_rate','ambient_temp_c']].sort_values('date').head(30).to_string())
"


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
from fit import *
d=pd.read_pickle('$TMPDIR/an/d_model.pkl')
mt=pd.read_csv('/tmp/edabench_claude_7_5y_myr/maintenance.csv'); mt['date']=pd.to_datetime(mt.date)
print(mt[(mt.line=='L3')&(mt.date>='2025-05-01')&(mt.date<='2025-08-31')].to_string())
for line,g in d.groupby('line'):
    g=g.sort_values('date')
    best=None
    for t in sorted(g.date.unique())[10:-10]:
        a=g[g.date<t].pr; b=g[g.date>=t].pr
        if len(a)<40 or len(b)<40: continue
        ts=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best is None or abs(ts)>abs(best[1]): best=(pd.Timestamp(t).date(),ts,b.mean()-a.mean())
    print(line,best)
"


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
d=pd.read_pickle('$TMPDIR/an/d_model.pkl')
for line in ['L2','L3']:
    g=d[d.line==line].copy()
    g['wk']=g.date.dt.to_period('W')
    agg=g.groupby('wk').apply(lambda x: pd.Series({'obs':x.defective_units.sum()/x.units_produced.sum(),'pred':(x.n*x.mu).sum()/x.n.sum(),'pr':x.pr.mean(),'mold':x.mold_adj.mean(),'hum':x.humidity.mean(),'amb':x.ambient_temp_c.mean(),'cyc':x.cycle_time_s.mean(),'dsc':x.days_since_clean.mean(),'n':len(x)}))
    print(line); print(agg.round(3).to_string())
" 2>&1 | head -120


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
from fit import *
d=pd.read_pickle('$TMPDIR/an/d_model.pkl')
f='bs(mold_adj,df=4) + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + bs(days_since_clean,df=5) + bs(humidity, df=6)*C(supplier_code)'
m=fit(f,d)
print('disp', round(m.pearson_chi2/m.df_resid,3), 'dev', round(m.deviance,1))
d['mu']=m.predict(d)
d['pr']=(d.y-d.n*d.mu)/np.sqrt(d.n*d.mu*(1-d.mu))
d.to_pickle('$TMPDIR/an/d_model2.pkl')
for line,g in d.groupby('line'):
    g=g.sort_values('date'); best=None
    for t in sorted(g.date.unique())[10:-10]:
        a=g[g.date<t].pr; b=g[g.date>=t].pr
        if len(a)<40 or len(b)<40: continue
        ts=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best is None or abs(ts)>abs(best[1]): best=(pd.Timestamp(t).date(),round(ts,2),round(b.mean()-a.mean(),3))
    print(line,best)
"


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
d=pd.read_pickle('$TMPDIR/an/d_model2.pkl')
for line,t0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=d[d.line==line].copy()
    g['post']=g.date>=pd.Timestamp(t0)
    print(line, 'operator counts pre/post:')
    print(pd.crosstab(g.operator_id,g.post).T.to_string())
    print(pd.crosstab(g['shift'],g.post))
    print(pd.crosstab(g.supplier_code,g.post))
    print(g.groupby('post')[['mold_adj','humidity','cycle_time_s','ambient_temp_c','days_since_clean','machine_age_years']].mean().round(2))
"


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
from clean import load_clean
df,sup=load_clean()
for line in ['L2','L3']:
    g=df[df.line==line].copy()
    g['wk']=g.date.dt.to_period('W')
    g['rw_per_def']=g.rework_cost_eur/g.defective_units
    a=g.groupby('wk').agg(units=('units_produced','mean'),defs=('defective_units','mean'),qc=('qc_inspection_min','mean'),rw=('rw_per_def','mean'),cyc=('cycle_time_s','mean'),n=('batch_id','size'))
    print(line); print(a.round(2).iloc[10:].to_string())
" | head -90


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
from clean import load_clean
df,sup=load_clean()
df['post']=(df.line=='L3')&(df.date>=pd.Timestamp('2025-07-21'))
df['rw_def']=df.rework_cost_eur/df.defective_units
df['rw_units']=df.rework_cost_eur/df.units_produced
for key,g in df.groupby(['line','post']):
    if key[0] not in ['L3','L2']: continue
    x=g
    c=np.polyfit(x.defective_units,x.rework_cost_eur,1)
    print(key, 'n',len(x),'rw/def median',round(x.rw_def.median(),3),'rw/units median',round(x.rw_units.median(),4),'fit slope',round(c[0],3),'intercept',round(c[1],2), 'corr qc~def', round(np.corrcoef(x.defective_units,x.qc_inspection_min)[0,1],3), 'qc mean', round(x.qc_inspection_min.mean(),2))
print(df.groupby('line').apply(lambda x: np.corrcoef(x.defective_units,x.rework_cost_eur)[0,1]).round(3))
"


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
d=pd.read_pickle('$TMPDIR/an/d_model2.pkl')
from clean import load_clean
df,sup=load_clean()
d=d.merge(df[['batch_id','rework_cost_eur','qc_inspection_min']],on='batch_id',how='left',suffixes=('','_r'))
d['pred_def']=d.mu*d.n
d['post']=(d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))
for (line,post),g in d.groupby(['line','post']):
    if line!='L3': continue
    r_pred=(g.rework_cost_eur/g.pred_def).median()
    r_rec=(g.rework_cost_eur/g.y).median()
    print(line,'post' if post else 'pre','n',len(g),'rework/predicted defects',round(r_pred,3),'rework/recorded defects',round(r_rec,3),'recorded share',round(g.y.sum()/g.n.sum(),4),'predicted share',round(g.pred_def.sum()/g.n.sum(),4))
# same ratio test for other lines pre period
for line in ['L1','L2','L4']:
    g=d[d.line==line]
    print(line,'rework/predicted',round((g.rework_cost_eur/g.pred_def).median(),3))
"


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
d=pd.read_pickle('$TMPDIR/an/d_model2.pkl')
from clean import load_clean
df,sup=load_clean()
d=d.merge(df[['batch_id','rework_cost_eur']],on='batch_id',how='left')
d['pred_def']=d.mu*d.n
for line,t0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=d[d.line==line]
    for lab,x in [('pre',g[g.date<pd.Timestamp(t0)]),('post',g[g.date>=pd.Timestamp(t0)])]:
        print(line,lab,'n',len(x),'rec share',round(x.y.sum()/x.n.sum(),4),'pred share',round(x.pred_def.sum()/x.n.sum(),4),
              'rw/recorded',round((x.rework_cost_eur/x.y).median(),3),'rw/pred',round((x.rework_cost_eur/x.pred_def).median(),3),
              'rw total/recorded', round(x.rework_cost_eur.sum()/x.y.sum(),3), 'rw total/pred', round(x.rework_cost_eur.sum()/x.pred_def.sum(),3))
"


cd $TMPDIR/an && python3 -W ignore -c "
import pandas as pd, numpy as np
d=pd.read_pickle('$TMPDIR/an/d_model2.pkl')
d=d.drop(columns=[c for c in d.columns if c.startswith('rework')], errors='ignore')
from clean import load_clean
df,sup=load_clean()
d=d.merge(df[['batch_id','rework_cost_eur']],on='batch_id',how='left')
d['pred_def']=d.mu*d.n
for line,t0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=d[d.line==line]
    for lab,x in [('pre',g[g.date<pd.Timestamp(t0)]),('post',g[g.date>=pd.Timestamp(t0)])]:
        print(line,lab,'n',len(x),'rec share',round(x.y.sum()/x.n.sum(),4),'pred share',round(x.pred_def.sum()/x.n.sum(),4),
              'rw/recorded',round((x.rework_cost_eur/x.y).median(),3),'rw/pred',round((x.rework_cost_eur/x.pred_def).median(),3))
"


cd $TMPDIR/an && cat >> fit.py <<'EOF'

BASE = ('bs(mold_adj, df=4) + cycle_time_s + machine_age_years + ambient_temp_c'
        ' + C(operator_id) + C(shift) + C(supplier_code) + bs(days_since_clean, df=5)'
        ' + bs(humidity, df=6) * C(supplier_code) + l2_step + l3_rec')

def prep_final():
    d = add_days_since_clean(prep()[0])
    d['l2_step'] = ((d.line == 'L2') & (d.date >= pd.Timestamp('2025-06-16'))).astype(int)
    d['l3_rec'] = ((d.line == 'L3') & (d.date >= pd.Timestamp('2025-07-21'))).astype(int)
    return d

def f_test(full, reduced, disp):
    dfn = reduced.df_resid - full.df_resid
    F = (reduced.deviance - full.deviance) / dfn / disp
    from scipy import stats
    return dfn, F, stats.f.sf(F, dfn, full.df_resid)
EOF
python3 -W ignore -c "
from fit import *
d=prep_final()
full=fit(BASE,d)
disp=full.pearson_chi2/full.df_resid
print('disp',round(disp,3),'dev',round(full.deviance,1))
print(full.summary2().tables[1].loc[['l2_step','l3_rec','cycle_time_s','ambient_temp_c','machine_age_years']].round(5).to_string())
tests={
 'mold_temp': BASE.replace('bs(mold_adj, df=4) + ',''),
 'humidity': BASE.replace('+ bs(humidity, df=6) * C(supplier_code)',''),
 'cycle_time': BASE.replace('cycle_time_s + ',''),
 'machine_age': BASE.replace('machine_age_years + ',''),
 'ambient': BASE.replace('ambient_temp_c + ',''),
 'shift': BASE.replace('C(shift) + ',''),
 'operator (within-line)': BASE.replace('C(operator_id)','C(line)').replace('+ C(line)',''),
}
for k,f in tests.items():
    if k.startswith('operator'):
        f=BASE.replace('C(operator_id)','C(line)')
    if k=='humidity':
        f=BASE.replace('+ bs(humidity, df=6) * C(supplier_code)','')
    r=fit(f,d)
    dfn,F,p=f_test(full,r,disp)
    print(f'{k:24s} dfdiff {dfn:4.0f} F {F:8.2f} p {p:.3g}')
" 2>&1 | tail -30


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
d=prep_final()
full=fit(BASE,d)
disp=full.pearson_chi2/full.df_resid
t=full.summary2().tables[1]
ops=t.loc[[i for i in t.index if 'operator' in i]].copy()
ops['z_scaled']=ops['Coef.']/(ops['Std.Err.']*np.sqrt(disp))
print(ops[['Coef.','z_scaled']].round(3).to_string())
# robustness with linear specs
lin=('mold_adj + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + days_since_clean + humidity:C(supplier_code) + I(humidity**2) + I(humidity**2):C(supplier_code) + l2_step + l3_rec')
fl=fit(lin,d); dl=fl.pearson_chi2/fl.df_resid
rl=fit(lin.replace('C(operator_id)','C(line)'),d)
dfn,F,p=f_test(fl,rl,dl)
print('linear spec operator F',round(F,2),'p',round(p,4),'disp',round(dl,3))
" 2>&1 | tail -40


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
d=prep_final()
full=fit(BASE,d)
disp=full.pearson_chi2/full.df_resid
# within-line operator test: replace operator dummies by a line-level dummy for each line
for line in ['L1','L2','L3','L4']:
    d2=d.copy()
    ops=d2[d2.line==line].operator_id.unique()
    # test whether operator within this line matters: operator dummies only for this line, others as line-level
    d2['op_in']=np.where(d2.line==line,d2.operator_id,'other')
    r=fit(BASE.replace('C(operator_id)','C(line)'),d2)
    f=fit(BASE.replace('C(operator_id)','C(line)') .replace('C(line)','C(line)'),d2)
    d2['opL']=np.where(d2.line==line,d2.operator_id,'x')
    fo=fit(BASE.replace('C(operator_id)','C(line) + C(opL)'),d2)
    dfn,F,p=f_test(fo,r,disp)
    print(line,'within-line operator dfdiff',dfn,'F',round(F,2),'p',round(p,4))
" 2>&1 | tail -10


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
import statsmodels.formula.api as smf
d=prep_final()
d['rate']=d.defect_rate
f_full='rate ~ bs(mold_adj, df=4) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + bs(days_since_clean, df=5) + bs(humidity, df=6)*C(supplier_code) + l2_step + l3_rec'
for lab,f in [('with operator',f_full+' + C(operator_id)'),('line only',f_full+' + C(line)')]:
    m=smf.wls(f,data=d,weights=d.units_produced).fit(cov_type='HC1')
    print(lab,'R2',round(m.rsquared,4))
    if lab=='with operator':
        names=[n for n in m.params.index if 'operator' in n]
        R=np.zeros((len(names),len(m.params)))
        for i,n in enumerate(names): R[i,list(m.params.index).index(n)]=1
        w=m.wald_test(R,use_f=True,scalar=True)
        print('joint operator F',round(float(w.statistic),3),'p',round(float(w.pvalue),4))
    else:
        pass
" 2>&1 | tail -8


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
import statsmodels.formula.api as smf
d=prep_final()
d['rate']=d.defect_rate
f_full='rate ~ bs(mold_adj, df=4) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + bs(days_since_clean, df=5) + bs(humidity, df=6)*C(supplier_code) + l2_step + l3_rec + C(line)'
m=smf.wls(f_full+' + C(operator_id)',data=d,weights=d.units_produced).fit()
names=[n for n in m.params.index if 'operator' in n]
R=np.zeros((len(names),len(m.params)))
for i,n in enumerate(names): R[i,list(m.params.index).index(n)]=1
w=m.wald_test(R,use_f=True,scalar=True)
print('within-line operator F (classic)',round(float(w.statistic),3),'p',round(float(w.pvalue),4))
m2=smf.wls(f_full+' + C(operator_id)',data=d,weights=d.units_produced).fit(cov_type='HC1')
w2=m2.wald_test(R,use_f=True,scalar=True)
print('within-line operator F (HC1)',round(float(w2.statistic),3),'p',round(float(w2.pvalue),4))
# shift and other candidate tests with HC1
for v in ['ambient_temp_c','machine_age_years','cycle_time_s']:
    print(v,'coef HC1 p', round(m2.pvalues[v],4))
print('shift', m2.pvalues[[n for n in m2.params.index if 'shift' in n][0]])
" 2>&1 | tail -10


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
import statsmodels.formula.api as smf
from scipy import stats
d=prep_final()
d['rate']=d.defect_rate
core='rate ~ bs(mold_adj, df=4) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + bs(days_since_clean, df=5) + bs(humidity, df=6)*C(supplier_code) + l2_step + l3_rec'
red=smf.wls(core+' + C(line)',data=d,weights=d.units_produced).fit()
full=smf.wls(core+' + C(operator_id)',data=d,weights=d.units_produced).fit()
dfn=red.df_resid-full.df_resid
F=((red.ssr-full.ssr)/dfn)/(full.ssr/full.df_resid)
print('WLS within-line operator F',round(F,3),'df',dfn,'p',round(stats.f.sf(F,dfn,full.df_resid),4))
" 2>&1 | tail -3


cd $TMPDIR/an && timeout 900 python3 -W ignore -c "
from fit import *
import statsmodels.formula.api as smf
from scipy import stats
d=prep_final()
d['rate']=d.defect_rate
core='rate ~ bs(mold_adj, df=4) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + bs(days_since_clean, df=5) + bs(humidity, df=6)*C(supplier_code) + l2_step + l3_rec'
def Fstat(dd):
    red=smf.wls(core+' + C(line)',data=dd,weights=dd.units_produced).fit()
    full=smf.wls(core+' + C(operator_id)',data=dd,weights=dd.units_produced).fit()
    dfn=red.df_resid-full.df_resid
    return ((red.ssr-full.ssr)/dfn)/(full.ssr/full.df_resid)
F0=Fstat(d)
rng=np.random.default_rng(1)
cnt=0; N=300; Fs=[]
for k in range(N):
    dd=d.copy()
    for line,idx in dd.groupby('line').groups.items():
        ops=dd.loc[idx,'operator_id'].values.copy()
        rng.shuffle(ops)
        dd.loc[idx,'operator_id']=ops
    Fk=Fstat(dd); Fs.append(Fk)
    cnt+= Fk>=F0
print('observed F',round(F0,3),'perm p',(cnt+1)/(N+1), 'perm 95pct', round(np.quantile(Fs,0.95),3))
" 2>&1 | tail -3


cd $TMPDIR/an && python3 -W ignore -c "
from clean import *
import statsmodels.formula.api as smf
df,sup=load_clean()
df['t']=(df.date-pd.Timestamp('2025-01-01')).dt.days
d=df.dropna(subset=['humidity'])
for f in ['humidity ~ C(line)','humidity ~ C(line)+t','humidity ~ C(line)+t+ambient_temp_c+C(shift)+C(supplier_code)']:
    m=smf.ols(f,data=d).fit(); print(f,'R2',round(m.rsquared,4))
print(df.humidity.isna().groupby(df.line).mean().round(3))
print(df.humidity.isna().groupby(df.supplier_code).mean().round(3))
print(df.humidity.isna().groupby(df.shift).mean().round(3))
"


cd $TMPDIR/an && cat > final.py <<'EOF'
from fit import *

rng = np.random.default_rng(7)
d = prep_final()
train = d.dropna(subset=['humidity']).copy()
m = fit(BASE, train)
disp = m.pearson_chi2 / m.df_resid
hum_pool = train.humidity.values

def predict_rate(frame, ndraw=60):
    """Predicted defect rate per row. Rows lacking humidity are averaged over
    draws from the observed humidity distribution."""
    out = np.zeros(len(frame))
    have = frame.humidity.notna().values
    if have.any():
        out[have] = m.predict(frame[have]).values
    miss = frame[~have]
    if len(miss):
        acc = np.zeros(len(miss))
        for _ in range(ndraw):
            g = miss.copy()
            g['humidity'] = rng.choice(hum_pool, size=len(g))
            acc += m.predict(g).values
        out[~have] = acc / ndraw
    return out

def overall(frame, rate):
    return (frame.n * rate).sum() / frame.n.sum()

if __name__ == '__main__':
    p_base = predict_rate(d)
    print('observed rate (all)', round(d.y.sum() / d.n.sum(), 5))
    print('model rate (all)', round(overall(d, p_base), 5))
    print('model vs observed defects on rows with humidity:',
          round((train.n * m.predict(train)).sum(), 1), round(train.y.sum(), 1))
    print('disp', round(disp, 3))
EOF
python3 -W ignore final.py


cd $TMPDIR/an && python3 -W ignore -c "
from final import *
print('converged',m.converged, 'iters', m.fit_history['iteration'] if 'iteration' in m.fit_history else '')
print('rank', np.linalg.matrix_rank(m.model.exog), m.model.exog.shape)
print('sum y', train.y.sum(), 'sum n', train.n.sum())
print('sum fitted*n (fittedvalues)', (m.fittedvalues*train.n.values).sum())
print('endog head', m.model.endog[:3])
print(train[['y','n']].head(3))
" 2>&1 | tail -12


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
import patsy
d=prep_final()
f=BASE
yX=patsy.dmatrices('~ '+f, d, return_type='dataframe')[1]
Y=np.column_stack([d.y.values, (d.n-d.y).values])
m=sm.GLM(Y,yX,family=sm.families.Binomial()).fit()
print('converged',m.converged,'sum fitted*n',round((m.fittedvalues*d.n.values).sum(),1),'sum y',d.y.sum())
m2=sm.GLM(d.y.values/d.n.values,yX,family=sm.families.Binomial(),var_weights=d.n.values).fit()
print('var_weights version sum fitted*n',round((m2.fittedvalues*d.n.values).sum(),1), 'coef diff', np.max(np.abs(m.params-m2.params)))
print(m2.params.loc[['mold_adj','cycle_time_s','ambient_temp_c','machine_age_years','l2_step','l3_rec']].round(5) if 'mold_adj' in m2.params else m2.params.head())
"


cd $TMPDIR/an && python3 -W ignore -c "
from fit import *
import patsy
d=prep_final()
X=patsy.dmatrix(BASE, d, return_type='dataframe')
Y=np.column_stack([d.y.values, (d.n-d.y).values])
m=sm.GLM(Y,X,family=sm.families.Binomial()).fit()
print('converged',m.converged,'sum fitted*n',round((m.fittedvalues*d.n.values).sum(),1),'sum y',d.y.sum())
m2=sm.GLM(d.y.values/d.n.values,X,family=sm.families.Binomial(),var_weights=d.n.values).fit()
print('var_weights version sum fitted*n',round((m2.fittedvalues*d.n.values).sum(),1), 'coef diff', np.max(np.abs(m.params-m2.params)))
print(m.params.filter(regex='mold|cycle|ambient|machine|l2|l3|humidity').round(5).to_string())
"


cd $TMPDIR/an && cat > model.py <<'EOF'
from fit import *
import patsy
from scipy import stats

def fit_counts(formula, d):
    X = patsy.dmatrix(formula, d, return_type='dataframe')
    Y = np.column_stack([d.y.values, (d.n - d.y).values])
    return sm.GLM(Y, X, family=sm.families.Binomial()).fit()

def ftest(full, reduced, disp):
    dfn = reduced.df_resid - full.df_resid
    F = (reduced.deviance - full.deviance) / dfn / disp
    return dfn, F, stats.f.sf(F, dfn, full.df_resid)
EOF
python3 -W ignore -c "
from model import *
d=prep_final()
full=fit_counts(BASE,d)
disp=full.pearson_chi2/full.df_resid
print('converged',full.converged,'disp',round(disp,3),'dev',round(full.deviance,1))
tests={
 'mold_temp': BASE.replace('bs(mold_adj, df=4) + ',''),
 'humidity': BASE.replace(' + bs(humidity, df=6) * C(supplier_code)',''),
 'cycle_time': BASE.replace('cycle_time_s + ',''),
 'machine_age': BASE.replace('machine_age_years + ',''),
 'ambient': BASE.replace('ambient_temp_c + ',''),
 'shift': BASE.replace('C(shift) + ',''),
 'operator (within-line)': BASE.replace('C(operator_id)','C(line)'),
}
for k,f in tests.items():
    r=fit_counts(f,d)
    dfn,F,p=ftest(full,r,disp)
    print(f'{k:24s} dfdiff {dfn:4.0f} F {F:9.2f} p {p:.3g}')
print(full.params.filter(regex='shift|l2|l3|cycle|ambient|machine').round(5).to_string())
" 2>&1 | tail -30


cd $TMPDIR/an && timeout 900 python3 -W ignore -c "
from model import *
import time
d=prep_final()
full=fit_counts(BASE,d); disp=full.pearson_chi2/full.df_resid
def Fobs(dd):
    r=fit_counts(BASE.replace('C(operator_id)','C(line)'),dd)
    f=fit_counts(BASE,dd)
    return ftest(f,r,disp)[1]
t0=time.time()
F0=Fobs(d); print('observed F',round(F0,3),'time per pair',round(time.time()-t0,2))
rng=np.random.default_rng(3)
N=199; cnt=0; Fs=[]
for k in range(N):
    dd=d.copy()
    for line,idx in dd.groupby('line').groups.items():
        ops=dd.loc[idx,'operator_id'].values.copy(); rng.shuffle(ops); dd.loc[idx,'operator_id']=ops
    Fk=Fobs(dd); Fs.append(Fk); cnt+=Fk>=F0
print('perm p',round((cnt+1)/(N+1),4),'perm 95pct',round(np.quantile(Fs,0.95),3))
" 2>&1 | tail -4


cd $TMPDIR/an && python3 -W ignore -c "
from model import *
d=prep_final()
full=fit_counts(BASE,d)
d['mu']=full.fittedvalues
d['pr']=(d.y-d.n*d.mu)/np.sqrt(d.n*d.mu*(1-d.mu))
d.to_pickle('$TMPDIR/an/d_final.pkl')
best=[]
for line,g in d.groupby('line'):
    g=g.sort_values('date'); bb=None
    for t in sorted(g.date.unique())[10:-10]:
        a=g[g.date<t].pr; b=g[g.date>=t].pr
        if len(a)<40 or len(b)<40: continue
        ts=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if bb is None or abs(ts)>abs(bb[1]): bb=(pd.Timestamp(t).date(),round(ts,2),round(b.mean()-a.mean(),3))
    print(line,bb)
print(d.groupby('line').pr.mean().round(3).to_dict())
" 2>&1 | tail -8


cd $TMPDIR/an && python3 -W ignore -c "
from model import *
d=prep_final()
B0=BASE.replace(' + l2_step + l3_rec','')
full=fit_counts(B0,d)
d['mu']=full.fittedvalues
d['pr']=(d.y-d.n*d.mu)/np.sqrt(d.n*d.mu*(1-d.mu))
for line,g in d.groupby('line'):
    g=g.sort_values('date'); bb=None
    for t in sorted(g.date.unique())[10:-10]:
        a=g[g.date<t].pr; b=g[g.date>=t].pr
        if len(a)<40 or len(b)<40: continue
        ts=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if bb is None or abs(ts)>abs(bb[1]): bb=(pd.Timestamp(t).date(),round(ts,2),round(b.mean()-a.mean(),3))
    print(line,bb)
" 2>&1 | tail -6


cd $TMPDIR/an && python3 -W ignore -c "
from model import *
from clean import load_clean
d=prep_final()
df,_=load_clean()
d=d.drop(columns=[c for c in d.columns if c.startswith('rework')],errors='ignore').merge(df[['batch_id','rework_cost_eur']],on='batch_id')
B0=BASE.replace(' + l2_step + l3_rec','')
full=fit_counts(B0,d)
d['pred_def']=full.fittedvalues*d.n
for line,t0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=d[d.line==line]
    for lab,x in [('pre',g[g.date<pd.Timestamp(t0)]),('post',g[g.date>=pd.Timestamp(t0)])]:
        print(line,lab,'n',len(x),'recorded share',round(x.y.sum()/x.n.sum(),4),'process-predicted share',round(x.pred_def.sum()/x.n.sum(),4),
              '| rework/recorded',round(x.rework_cost_eur.sum()/x.y.sum(),3),'rework/predicted',round(x.rework_cost_eur.sum()/x.pred_def.sum(),3))
" 2>&1 | tail -6


cd $TMPDIR/an && python3 -W ignore -c "
from model import *
d0=prep_final()
pre=(d0.line=='L1')&(d0.date<pd.Timestamp('2025-04-14'))
base_mold=d0.mold_c  # raw corrected units
for delta in [0,4,6.9,8,10,12,13.7]:
    d=d0.copy()
    d['mold_adj']=d.mold_c+np.where(pre,delta,0)
    m=fit_counts(BASE,d)
    print(delta, round(m.deviance,2))
# first affected date check on L2 around the shift
d=d0.copy()
full=fit_counts(BASE.replace(' + l2_step',''),d)
d['mu']=full.fittedvalues
g=d[(d.line=='L2')&(d.date>='2025-06-05')&(d.date<='2025-06-24')]
print(g.groupby('date').apply(lambda x: pd.Series({'n':len(x),'rec':round(x.y.sum()/x.n.sum(),3),'pred':round((x.mu*x.n).sum()/x.n.sum(),3)})).to_string())
" 2>&1 | tail -40


cd $TMPDIR/an && cat > counterfactual.py <<'EOF'
from model import *
import patsy

rng = np.random.default_rng(11)
d = prep_final()                         # rows with valid humidity and mold (2727)
full = fit_counts(BASE, d)
disp = full.pearson_chi2 / full.df_resid
info = patsy.dmatrix(BASE, d).design_info

# all 3000 unique batches with same derived columns
from clean import load_clean
allb, sup = load_clean()
allb['post_l1'] = ((allb.line == 'L1') & (allb.date >= pd.Timestamp('2025-04-14'))).astype(int)
allb['mold_adj'] = allb.mold_c + np.where((allb.line == 'L1') & (allb.date < pd.Timestamp('2025-04-14')), 6.9, 0)
allb['t'] = (allb.date - pd.Timestamp('2025-01-01')).dt.days
allb = add_days_since_clean(allb)
allb['l2_step'] = ((allb.line == 'L2') & (allb.date >= pd.Timestamp('2025-06-16'))).astype(int)
allb['l3_rec'] = ((allb.line == 'L3') & (allb.date >= pd.Timestamp('2025-07-21'))).astype(int)
allb['y'] = allb.defective_units
allb['n'] = allb.units_produced

# impute missing mold temperature (49 zero readings) from line, ambient and time
import statsmodels.formula.api as smf
mo = smf.ols('mold_adj ~ C(line) + ambient_temp_c + cycle_time_s + t', data=allb.dropna(subset=['mold_adj'])).fit()
miss_m = allb.mold_adj.isna()
allb.loc[miss_m, 'mold_adj'] = mo.predict(allb[miss_m])

hum_pool = d.humidity.values

def predict_rate(frame, ndraw=60):
    """Expected defect rate per batch under the model. Rows without humidity are
    averaged over draws from the observed humidity distribution."""
    out = np.zeros(len(frame))
    have = frame.humidity.notna().values
    X = patsy.build_design_matrices([info], frame[have], return_type='dataframe')[0]
    out[have] = 1 / (1 + np.exp(-(X.values @ full.params.values)))
    miss = frame[~have]
    if len(miss):
        acc = np.zeros(len(miss))
        for _ in range(ndraw):
            g = miss.copy()
            g['humidity'] = rng.choice(hum_pool, size=len(g))
            Xg = patsy.build_design_matrices([info], g, return_type='dataframe')[0]
            acc += 1 / (1 + np.exp(-(Xg.values @ full.params.values)))
        out[~have] = acc / ndraw
    return out

def overall(frame, rate):
    return (frame.n * rate).sum() / frame.n.sum()
EOF
python3 -W ignore -c "
from counterfactual import *
print('batches', len(allb), 'missing humidity', allb.humidity.isna().sum(), 'mold imputed', miss_m.sum())
p0=predict_rate(allb)
print('observed overall (all 3000)', round(allb.y.sum()/allb.n.sum(),5))
print('model overall baseline', round(overall(allb,p0),5))
print('model defects vs observed defects', round((allb.n*p0).sum(),1), allb.y.sum())
" 2>&1 | tail -6

