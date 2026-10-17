ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape); print(df.columns.tolist())
for c in df.columns:
    vc=df[c].value_counts()
    print('\n##',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    print(vc.head(15).to_dict() if df[c].nunique()<60 else df[c].sample(12,random_state=1).tolist())
print('dup batch_id rows', df.batch_id.duplicated(keep=False).sum(), 'unique', df.batch_id.nunique())
print('full dup rows', df.duplicated().sum())
"
cat suppliers.csv; echo; cat maintenance.csv | head -80

python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print(d.head(8).to_string())
# non-identical duplicates
nd=df[df.duplicated(keep=False)==False]
g=d.groupby('batch_id').apply(lambda x: x.drop_duplicates().shape[0])
print('ids with conflicting dup versions', (g>1).sum())
print(d.drop_duplicates().groupby('batch_id').size().value_counts())
# date formats
pats=df.production_date.map(lambda s: 'iso' if re.fullmatch(r'\d{4}-\d{2}-\d{2}',s) else ('slash' if re.fullmatch(r'\d{2}/\d{2}/\d{4}',s) else 'other:'+s))
print(pats.str[:10].value_counts().head(20))
"


python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
s=df.production_date[df.production_date.str.contains('/')]
a=s.str.split('/',expand=True).astype(int)
print('slash rows',len(s))
print('first>12 (DD/MM):',(a[0]>12).sum(),' second>12 (MM/DD):',(a[1]>12).sum(),' ambiguous:',((a[0]<=12)&(a[1]<=12)).sum())
print('ambiguous and first==second', ((a[0]==a[1])&(a[0]<=12)).sum())
print('years', a[2].value_counts().to_dict())
iso=df.production_date[df.production_date.str.contains('-')]
print('iso range', iso.min(), iso.max())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(df[c],errors='coerce')
    print(c,'nonnum',((x.isna())&(df[c].str.strip()!='')).sum(),'blank',(df[c].str.strip()=='').sum(),'min',x.min(),'max',x.max())
    print('   quantiles', x.quantile([0,.01,.05,.25,.5,.75,.95,.99,1]).round(2).tolist())
print(df.humidity_pct[pd.to_numeric(df.humidity_pct,errors='coerce')<=0].value_counts().to_dict())
print(df.humidity_pct[pd.to_numeric(df.humidity_pct,errors='coerce')>100].value_counts().to_dict())
"


python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
iso=df[df.production_date.str.contains('-')].copy()
iso['d']=pd.to_datetime(iso.production_date)
print('weekday counts ISO:', iso.d.dt.day_name().value_counts().to_dict())
print('ISO distinct dates', iso.d.nunique(), 'span', (iso.d.max()-iso.d.min()).days+1)
print('batches per date-line median', iso.groupby(['d','line']).size().describe().to_dict())
# ambiguous slash rows: check whether both interpretations are weekdays
s=df[df.production_date.str.contains('/')].copy()
p=s.production_date.str.split('/',expand=True).astype(int)
amb=(p[0]<=12)&(p[1]<=12)&(p[0]!=p[1])
print('ambiguous non-equal',amb.sum())
mmdd=pd.to_datetime(dict(year=p[2],month=p[0],day=p[1]),errors='coerce')
ddmm=pd.to_datetime(dict(year=p[2],month=p[1],day=p[0]),errors='coerce')
x=s[amb.values].copy()
x['mm']=mmdd[amb.values].dt.day_name().values; x['dm']=ddmm[amb.values].dt.day_name().values
print('MM/DD weekday', x.mm.value_counts().to_dict())
print('DD/MM weekday', x.dm.value_counts().to_dict())
"


python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
for c in ['ambient_temp_c','machine_age_years']: df[c]=df[c].astype(float)
iso=df[df.production_date.str.contains('-')].copy()
iso['d']=pd.to_datetime(iso.production_date)
iso['doy']=iso.d.dt.dayofyear
# seasonal fit ambient ~ harmonics
X=np.column_stack([np.ones(len(iso)),np.sin(2*np.pi*iso.doy/365),np.cos(2*np.pi*iso.doy/365)])
b=np.linalg.lstsq(X,iso.ambient_temp_c,rcond=None)[0]
res=iso.ambient_temp_c-X@b
print('coef',b.round(2),'resid sd',res.std().round(2),'R2',round(1-res.var()/iso.ambient_temp_c.var(),3))
print(iso.groupby(iso.d.dt.month).ambient_temp_c.agg(['mean','std']).round(2))
# within-day sd
print('within-day sd', iso.groupby('d').ambient_temp_c.std().mean().round(2))
# per-line machine age by date
print(iso[iso.line=='L1'].sort_values('d')[['production_date','machine_age_years']].drop_duplicates('production_date').head(12).to_string())
"


python3 -c "
import pandas as pd, numpy as np
raw=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
print(raw.line.unique())
df=raw.copy()
df['ambient_temp_c']=df.ambient_temp_c.astype(float)
iso=df[df.production_date.str.contains('-')].copy()
iso['d']=pd.to_datetime(iso.production_date)
def seas(d):
    doy=d.dt.dayofyear
    return np.column_stack([np.ones(len(d)),np.sin(2*np.pi*doy/365),np.cos(2*np.pi*doy/365)])
b=np.linalg.lstsq(seas(iso.d),iso.ambient_temp_c,rcond=None)[0]
def pred(d): return seas(pd.DatetimeIndex(d).to_series().reset_index(drop=True)) @ b
s=df[df.production_date.str.contains('/')].copy()
p=s.production_date.str.split('/',expand=True).astype(int)
mmdd=pd.to_datetime(dict(year=p[2],month=p[0],day=p[1]),errors='coerce')
ddmm=pd.to_datetime(dict(year=p[2],month=p[1],day=p[0]),errors='coerce')
# validation on rows where exactly one reading is valid and the other is not a valid date
known_mm=(p[1]>12); known_dm=(p[0]>12)
amb=(~known_mm)&(~known_dm)
at=s.ambient_temp_c.astype(float).values
def err(dates):
    return np.abs(at-pred(dates.fillna(pd.Timestamp('2025-01-01'))))
e1=err(mmdd); e2=err(ddmm)
# truth on known rows
truth=pd.Series(np.where(known_mm,'mm',np.where(known_dm,'dm','amb')),index=s.index)
choose=np.where(e1<=e2,'mm','dm')
m=truth!='amb'
print('validation accuracy on known rows', (choose[m.values]==truth[m].values).mean().round(4), 'n',m.sum())
gap=np.abs(e1-e2)
print('median abs gap ambiguous', np.median(gap[amb.values]).round(2), 'frac gap>1.5', (gap[amb.values]>1.5).mean().round(3))
print('accuracy for known rows with gap>1.5', (choose[(m&(gap>1.5)).values]==truth[m&(gap>1.5)].values).mean().round(4), (m&(gap>1.5)).sum())
"


python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['machine_age_years']=df.machine_age_years.astype(float)
iso=df[df.production_date.str.contains('-')].copy()
iso['d']=pd.to_datetime(iso.production_date)
iso['t']=(iso.d-pd.Timestamp('2025-01-01')).dt.days
for ln,g in iso.groupby('line'):
    c=np.corrcoef(g.t,g.machine_age_years)[0,1]
    sl=np.polyfit(g.t,g.machine_age_years,1)
    r=g.machine_age_years-np.polyval(sl,g.t)
    print(ln,'n',len(g),'corr',round(c,3),'slope/yr',round(sl[0]*365,3),'resid sd',round(r.std(),3),'min',g.machine_age_years.min(),'max',g.machine_age_years.max())
print(iso.groupby(['line','d']).machine_age_years.agg(['min','max']).head(12))
print(iso.groupby(['line']).machine_age_years.describe())
"


python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['fmt']=df.production_date.map(lambda s:'iso' if '-' in s else 'slash')
p=df.production_date.str.split('/',expand=True)
df['a']=p[0].where(p[0].notna()); 
s=df[df.fmt=='slash'].copy()
s['a']=s.production_date.str.split('/').str[0].astype(int); s['b']=s.production_date.str.split('/').str[1].astype(int)
s['kind']=s.apply(lambda r:'DD/MM' if r.a>12 else ('MM/DD' if r.b>12 else 'amb'),axis=1)
print(pd.crosstab(df.line,df.fmt))
print(pd.crosstab(s.line,s.kind))
print(pd.crosstab(df.line,df.shift.str.strip().str.lower()))
"


mkdir -p $TMPDIR/x && cd /tmp/edabench_claude_anppsz_3 && python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=df.mold_temp.astype(float)
df['fmt']=df.production_date.map(lambda s:'iso' if '-' in s else ('mdy' if df.loc[df.production_date==s,'line'].iloc[0]=='L1' else 'dmy'))
print(pd.cut(df.mt,[-1,0.5,100,150,180,195,250,300,350,380,400,450,500]).value_counts().sort_index())
print(df.groupby('line').mt.describe().round(1))
print(pd.crosstab(df.line, pd.cut(df.mt,[-1,0.5,300,380,500])))
print(df[(df.mt>0.5)&(df.mt<300)].groupby('line').mt.describe().round(1))
print(df[(df.mt>300)].groupby('line').mt.describe().round(1))
print(df.groupby('supplier_code').mt.describe().round(1))
"


python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
def pdate(r):
    s=r.production_date
    if '-' in s: return pd.Timestamp(s)
    a,b,y=s.split('/')
    return pd.Timestamp(int(y),int(a),int(b)) if r.line=='L1' else pd.Timestamp(int(y),int(b),int(a))
df['d']=df.apply(pdate,axis=1)
print('date range',df.d.min(),df.d.max(), 'nunique', df.d.nunique())
df['mt']=df.mold_temp.astype(float)
df.loc[df.line=='L3','mt']=(df.loc[df.line=='L3','mt']-32)*5/9
v=df[df.mt>0.5]
l1=v[v.line=='L1'].copy()
l1['pre']=l1.d<pd.Timestamp('2025-04-14')
print(l1.groupby('pre').mt.describe().round(2))
print(l1.groupby(l1.d.dt.month).mt.agg(['mean','median','count']).round(2))
print('monthly all lines'); print(v.groupby(['line',v.d.dt.month]).mt.mean().unstack(0).round(1))
print(df[df.line=='L1'].loc[lambda x:(x.d>='2025-04-10')&(x.d<='2025-04-18'),['d','mold_temp','humidity_pct']].sort_values('d').to_string())
"


SP=/tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; mkdir -p $SP; cat > $SP/clean.py <<'EOF'
import pandas as pd, numpy as np

DIR = '/tmp/edabench_claude_anppsz_3/'

def load():
    raw = pd.read_csv(DIR + 'batches.csv', dtype=str, keep_default_na=False)
    n_raw = len(raw)
    df = raw.drop_duplicates().copy()
    # exact duplicate rows only; batch_ids never conflict
    assert df.batch_id.is_unique

    # dates: format depends on line (L1 MM/DD/YYYY, L4 DD/MM/YYYY, L2/L3 ISO)
    def pdate(r):
        s = r.production_date
        if '-' in s:
            return pd.Timestamp(s)
        a, b, y = (int(x) for x in s.split('/'))
        return pd.Timestamp(y, a, b) if r.line == 'L1' else pd.Timestamp(y, b, a)
    df['date'] = df.apply(pdate, axis=1)

    # shift: normalise free-text codes
    key = df['shift'].str.strip().str.lower().str[0]
    df['shift'] = key.map({'d': 'Day', 'n': 'Night'})
    assert df['shift'].notna().all()

    df['supplier_code'] = df.supplier_code.str.strip().str.upper()
    df['operator_id'] = df.operator_id.str.strip().str.upper()

    for c in ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'humidity_pct',
              'cycle_time_s', 'units_produced', 'defective_units', 'qc_inspection_min',
              'rework_cost_eur']:
        df[c] = pd.to_numeric(df[c].replace('', np.nan), errors='coerce')

    # humidity: blank or -1 sentinel is not a valid reading
    df.loc[df.humidity_pct <= 0, 'humidity_pct'] = np.nan
    # mold temperature: 0 = missing; line L3 logs in Fahrenheit
    df.loc[df.mold_temp <= 0, 'mold_temp'] = np.nan
    f = df.line == 'L3'
    df.loc[f, 'mold_temp'] = (df.loc[f, 'mold_temp'] - 32) * 5 / 9

    df['defect_rate'] = df.defective_units / df.units_produced
    df.attrs['n_raw'] = n_raw
    return df.reset_index(drop=True)

def load_ref():
    sup = pd.read_csv(DIR + 'suppliers.csv')
    sup['supplier_code'] = sup.supplier_code.str.strip().str.upper()
    mnt = pd.read_csv(DIR + 'maintenance.csv', parse_dates=['date'])
    return sup, mnt
EOF
cd $SP && python3 -c "
from clean import *
df=load(); sup,mnt=load_ref()
print(df.shape, df.attrs)
print('suppliers matched', df.supplier_code.isin(sup.supplier_code).mean())
print(df.operator_id.unique())
print('defective>units', (df.defective_units>df.units_produced).sum())
print('A2 missing humidity', df.humidity_pct.isna().sum())
print('valid mold temp n', df.mold_temp.notna().sum())
print('mold temp median raw-C (before sensor fix)', df.mold_temp.median())
print(df.date.min(), df.date.max(), df.groupby('line').date.agg(['min','max']))
print(mnt.event.value_counts())
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import numpy as np
df=load()
v=df[df.mold_temp.notna()].copy()
v['post']=((v.line=='L1')&(v.date>=pd.Timestamp('2025-04-14'))).astype(float)
X=pd.get_dummies(v[['date','line']].astype(str),drop_first=True).astype(float)
X['post']=v.post.values
X.insert(0,'const',1.0)
b,res,rk,sv=np.linalg.lstsq(X.values,v.mold_temp.values,rcond=None)
r=v.mold_temp.values-X.values@b
n,k=X.shape; s2=(r@r)/(n-k); cov=s2*np.linalg.inv(X.values.T@X.values)
i=list(X.columns).index('post')
print('post offset', round(b[i],3),'se',round(np.sqrt(cov[i,i]),3), 'n',n)
# alternative: lines pre-/post-only check using same-day differences
dd=v.groupby(['date','line']).mold_temp.mean().unstack()
diff=dd['L1']-dd[['L2','L4']].mean(axis=1)
pre=diff[diff.index<'2025-04-14']; post=diff[diff.index>='2025-04-15']
print('same-day L1-(L2,L4) pre median',round(pre.median(),2),'mean',round(pre.mean(),2),'post median',round(post.median(),2),'mean',round(post.mean(),2))
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import numpy as np
df=load()
v=df[df.mold_temp.notna()&df.line.isin(['L1','L2','L4'])].copy()
v['post']=((v.line=='L1')&(v.date>=pd.Timestamp('2025-04-14'))).astype(float)
X=pd.get_dummies(v[['date','line']].astype(str),drop_first=True).astype(float)
X['post']=v.post.values; X.insert(0,'const',1.0)
b=np.linalg.lstsq(X.values,v.mold_temp.values,rcond=None)[0]
r=v.mold_temp.values-X.values@b; n,k=X.shape
cov=(r@r/(n-k))*np.linalg.inv(X.values.T@X.values)
i=list(X.columns).index('post'); print('L1,L2,L4 post offset',round(b[i],3),'se',round(np.sqrt(cov[i,i]),3))
# within-day diff by date
dd=v.groupby(['date','line']).mold_temp.mean().unstack()
diff=(dd['L1']-dd[['L2','L4']].mean(axis=1)).dropna()
print('pre mean/ med', diff[diff.index<'2025-04-14'].mean().round(2), diff[diff.index<'2025-04-14'].median().round(2))
print('post mean/ med', diff[diff.index>='2025-04-15'].mean().round(2), diff[diff.index>='2025-04-15'].median().round(2))
print(diff.groupby(diff.index.month).mean().round(2))
# L3 check: L3 minus mean(L2,L4) same-day after conversion
d3=(dd['L1'].mean()) 
l3=v0=None
"


cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat >> clean.py <<'EOF'

SENSOR_STEP = 7.36  # L1 mold sensor replaced 2025-04-14; post readings read high

def build():
    df = load()
    sup, mnt = load_ref()
    post = (df.line == 'L1') & (df.date >= pd.Timestamp('2025-04-14'))
    df.loc[post, 'mold_temp'] = df.loc[post, 'mold_temp'] - SENSOR_STEP
    df = df.merge(sup, on='supplier_code', how='left')
    df['cycle_dev'] = df.cycle_time_s - df.recipe_cycle_time_s
    return df
EOF
python3 -c "
from clean import *
df=build()
print('A3 overall', df.defective_units.sum()/df.units_produced.sum())
print('A4 median mold C', df.mold_temp.median(), 'n valid', df.mold_temp.notna().sum())
print(df.groupby('supplier_name').apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4))
print(df.groupby('line').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(df.groupby('shift').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(df.groupby('pre_dried').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import statsmodels, sklearn; print('sm',statsmodels.__version__)" 2>&1; python3 -c "
from clean import *
df=build()
def rate(g): return g.defective_units.sum()/g.units_produced.sum()
for c,bins in [('mold_temp',[190,200,205,210,215,220,225,230,240]),('humidity_pct',[0,15,25,35,45,55,65,80]),('cycle_dev',[-20,-5,-2,0,2,5,10,20]),('cycle_time_s',[17,25,30,35,40,46]),('machine_age_years',[0,2,4,6,8,10,15,25]),('ambient_temp_c',[10,15,20,25,30,35])]:
    b=pd.cut(df[c],bins)
    print('\n##',c); print(df.groupby(b,observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':round(rate(g),4)})).to_string())
print(df.groupby('operator_id').apply(rate).round(4).sort_values().to_string())
"

python3 -c "import statsmodels; print('statsmodels', statsmodels.__version__)" 2>&1; python3 -c "import scipy; print('scipy', scipy.__version__)" 2>&1; python3 -c "import pandas, numpy; print(pandas.__version__, numpy.__version__)"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
df=build()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['y']=d.defective_units; d['n']=d.units_produced
f='defective_units + I(units_produced-defective_units) ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
m=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
phi=m.pearson_chi2/m.df_resid
print('n',len(d),'dispersion',round(phi,3))
out=pd.DataFrame({'coef':m.params,'p':m.pvalues})
print(out.round(4).to_string())
m2=smf.glm(f,data=d,family=sm.families.Binomial()).fit(scale='X2')
print(pd.DataFrame({'coef':m2.params,'se':m2.bse,'p':m2.pvalues}).round(4).loc[['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']].to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > fit.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
import numpy as np, pandas as pd
import statsmodels.api as sm
from clean import build

def design(d, num, cats):
    X = d[num].astype(float).copy()
    for c in cats:
        X = pd.concat([X, pd.get_dummies(d[c], prefix=c, drop_first=True, dtype=float)], axis=1)
    return sm.add_constant(X, has_constant='add')

def glm(d, num, cats=(), scale=None):
    X = design(d, list(num), list(cats))
    y = np.column_stack([d.defective_units, d.units_produced - d.defective_units])
    m = sm.GLM(y, X, family=sm.families.Binomial()).fit(scale=scale)
    return m
EOF
python3 -c "
from fit import *
df=build()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
num=['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']
m=glm(d,num,['operator_id','shift','supplier_name','line'])
print('n',len(d),'Pearson dispersion',round(m.pearson_chi2/m.df_resid,3))
m2=glm(d,num,['operator_id','shift','supplier_name','line'],scale='X2')
print(pd.DataFrame({'coef':m2.params,'se':m2.bse,'p':m2.pvalues}).round(4).to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from fit import *
df=build()
print(pd.crosstab(df.line,df.supplier_name))
print(pd.crosstab(df.line,df.operator_id).T.head(30))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
num=['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']
X=design(d,num,['operator_id','shift','supplier_name','line'])
print('shape',X.shape,'rank',np.linalg.matrix_rank(X.values))
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from fit import *
from scipy import stats
df=build()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
print(d.groupby('line').machine_age_years.describe().round(2))
print(d.groupby('line').ambient_temp_c.describe().round(2))
base_num=['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']
cats=['operator_id','shift','supplier_name']
full=glm(d,base_num,cats,scale='X2')
print('rank full',np.linalg.matrix_rank(design(d,base_num,cats).values), design(d,base_num,cats).shape)
ll_full=glm(d,base_num,cats).llf
for v in base_num:
    m=glm(d,[x for x in base_num if x!=v],cats)
    lr=2*(ll_full-m.llf)
    print(f'{v:20s} LR={lr:9.2f}  p={stats.chi2.sf(lr,1):.3g} (scaled-by-disp: {lr/8.58:.1f})')
for v in cats:
    c2=[x for x in cats if x!=v]
    m=glm(d,base_num,c2)
    lr=2*(ll_full-m.llf)
    dfree=(design(d,base_num,cats).shape[1]-design(d,base_num,c2).shape[1])
    print(f'{v:20s} LR={lr:9.2f} df={dfree} p={stats.chi2.sf(lr,dfree):.3g}')
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > tests.py <<'EOF'
from fit import *
from scipy import stats
import statsmodels.formula.api as smf
df=build()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['y']=d.defective_units; d['n']=d.units_produced
d['ok']=d.units_produced-d.defective_units
d['t']=(d.date-pd.Timestamp('2025-01-01')).dt.days
d['mt2']=(d.mold_temp-212)**2
d['hum_dry']=d.humidity_pct*(d.pre_dried=='no')
def fit(formula, data=d):
    return smf.glm('y + ok ~ '+formula, data=data, family=sm.families.Binomial()).fit(scale='X2' if False else None)
def ll(formula):
    return smf.glm('y + ok ~ '+formula, data=d, family=sm.families.Binomial()).fit().llf
def lr(f_big, f_small, dfree):
    s=2*(ll(f_big)-ll(f_small)); return round(s,2), stats.chi2.sf(s,dfree)
EOF
python3 -c "
from tests import *
base='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name)'
print('base ll', round(ll(base),1))
print('quad mold', lr(base+' + mt2', base, 1))
print('t trend', lr(base+' + t', base, 1))
print('hum x dried', lr(base+' + hum_dry', base, 1))
print('cycle_dev instead of cycle', lr(base.replace('cycle_time_s','cycle_dev')+'', base.replace('cycle_time_s','cycle_dev'), 1) if False else 'skip')
b2=base.replace('cycle_time_s','cycle_dev')
d['cycle_dev']=d.cycle_dev
print('ll cycle_dev model', round(ll(b2),1),' vs cycle_time', round(ll(base),1))
print('ll ambient removed', round(ll(base.replace(' + ambient_temp_c','')),1))
print('ambient removed LR', lr(base, base.replace(' + ambient_temp_c',''),1))
"


cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from tests import *
base='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name)'
for s,g in d.groupby('supplier_name'):
    m=smf.glm('y + ok ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)', data=g, family=sm.families.Binomial()).fit()
    print(s, 'n',len(g), 'hum coef',round(m.params['humidity_pct'],4), 'p',round(m.pvalues['humidity_pct'],4), 'mold',round(m.params['mold_temp'],4),'cyc',round(m.params['cycle_time_s'],4),'amb',round(m.params['ambient_temp_c'],4))
print(d.groupby('supplier_name').humidity_pct.describe().round(1))
" 2>&1 | grep -v Warning

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from tests import *
import numpy as np
a=d[d.supplier_name=='Alpha'].copy()
a['hb']=pd.cut(a.humidity_pct,[10,15,20,25,30,35,40,45,50,55,60,65,75])
print(a.groupby('hb',observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
for form in ['humidity_pct','humidity_pct + I(humidity_pct**2)']:
    m=smf.glm('y + ok ~ mold_temp + '+form+' + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)', data=a, family=sm.families.Binomial()).fit()
    print(form, m.params.filter(like='humid').round(5).to_dict(), m.pvalues.filter(like='humid').round(4).to_dict(), 'llf',round(m.llf,2))
m=smf.glm('y + ok ~ mold_temp + humidity_pct + I(humidity_pct**2) + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)', data=a, family=sm.families.Binomial()).fit()
b1,b2=m.params['humidity_pct'],m.params['I(humidity_pct ** 2)']
print('vertex', -b1/(2*b2), 'curv', b2)
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat >> clean.py <<'EOF'

def add_cleaning(df):
    _, mnt = load_ref()
    cl = mnt[mnt.event == 'mold_cleaning']
    out = []
    for ln, g in df.groupby('line'):
        c = np.sort(cl[cl.line == ln].date.values)
        dates = g.date.values
        idx = np.searchsorted(c, dates, side='right') - 1  # last cleaning on/before batch day
        last = pd.to_datetime(c[idx])
        out.append(pd.Series((g.date - last).dt.days.values, index=g.index))
    df['days_since_clean'] = pd.concat(out)
    return df
EOF
python3 -c "
from clean import *
df=add_cleaning(build())
print(df.days_since_clean.describe().round(2))
print('share over 14', (df.days_since_clean>14).mean().round(3), ' max', df.days_since_clean.max())
print(df.groupby(pd.cut(df.days_since_clean,[-1,0,3,7,10,14,17,21,30])).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4))
m=load_ref()[1]; cl=m[m.event=='mold_cleaning']
for ln,g in cl.groupby('line'):
    gaps=g.date.sort_values().diff().dt.days
    print(ln, 'gaps max', gaps.max(), 'n >14', (gaps>14).sum(), 'first', g.date.min().date(), 'last', g.date.max().date())
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
from fit import *
import statsmodels.formula.api as smf
from scipy import stats
df=add_cleaning(build())
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['y']=d.defective_units; d['ok']=d.units_produced-d.defective_units
d['t']=(d.date-pd.Timestamp('2025-01-01')).dt.days
d['dsc2']=d.days_since_clean**2
d['hum_a']=d.humidity_pct*(d.supplier_name=='Alpha')
d['hum2_a']=d.humidity_pct**2*(d.supplier_name=='Alpha')
d['hum_nd']=d.humidity_pct*(d.supplier_name!='Alpha')
d['hum2_nd']=d.humidity_pct**2*(d.supplier_name!='Alpha')
def ll(f): return smf.glm('y + ok ~ '+f, data=d, family=sm.families.Binomial()).fit()
base='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name)'
m0=ll(base); m1=ll(base+' + days_since_clean'); m2=ll(base+' + days_since_clean + dsc2'); m3=ll(base+' + days_since_clean + t')
for nm,m in [('base',m0),('+dsc',m1),('+dsc+dsc2',m2),('+dsc+t',m3)]:
    print(nm, 'llf',round(m.llf,1))
print('dsc coef', round(m1.params['days_since_clean'],5), 'p', m1.pvalues['days_since_clean'])
print('t coef in dsc+t', round(m3.params['t'],6), m3.pvalues['t'], 'dsc in +t', round(m3.params['days_since_clean'],5), m3.pvalues['days_since_clean'])
print('LR dsc',round(2*(m1.llf-m0.llf),1),'LR t|dsc',round(2*(m3.llf-m1.llf),2), stats.chi2.sf(2*(m3.llf-m1.llf),1))
print('ambient coef in dsc model', round(m1.params['ambient_temp_c'],4), m1.pvalues['ambient_temp_c'])
print('machine age in dsc model', round(m1.params['machine_age_years'],4), m1.pvalues['machine_age_years'])
print('mold',round(m1.params['mold_temp'],4),'hum',round(m1.params['humidity_pct'],4),'cyc',round(m1.params['cycle_time_s'],4))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > model.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
from fit import *
import statsmodels.formula.api as smf
from scipy import stats
df=add_cleaning(build())
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['y']=d.defective_units; d['ok']=d.units_produced-d.defective_units
d['t']=(d.date-pd.Timestamp('2025-01-01')).dt.days
BASE='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean + C(operator_id) + C(shift) + C(supplier_name)'
def fitm(f, data=None):
    data = d if data is None else data
    return smf.glm('y + ok ~ '+f, data=data, family=sm.families.Binomial()).fit()
EOF
python3 -c "
from model import *
m=fitm(BASE)
mu=m.fittedvalues
d['pred']=m.predict(d)*d.units_produced
d['pred_def']=d.pred
d['res']=(d.defective_units-d.pred)/np.sqrt(d.pred*(1-d.pred/d.units_produced))
print('pearson dispersion', round(m.pearson_chi2/m.df_resid,3))
d['wk']=d.date.dt.to_period('M')
g=d.groupby(['line','wk']).agg(obs=('defective_units','sum'),exp=('pred_def','sum'),u=('units_produced','sum'))
g['ratio']=(g.obs/g.exp).round(3)
print(g.ratio.unstack(0).to_string())
"

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
base=fitm(BASE)
res=[]
for ln in ['L1','L2','L3','L4']:
    best=None
    for dt in pd.date_range('2025-01-20','2025-09-15',freq='D'):
        dd=d.copy()
        dd['step']=((dd.line==ln)&(dd.date>=dt)).astype(float)
        m=fitm(BASE+' + step',data=dd)
        lr=2*(m.llf-base.llf)
        if best is None or lr>best[0]: best=(lr,dt.date(),m.params['step'],m.pvalues['step'])
    print(ln,'best step date',best[1],'LR',round(best[0],1),'coef',round(best[2],3),'p',best[3])
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
pd.set_option('display.width',200)
cuts={'L2':'2025-06-15','L3':'2025-07-21'}
for ln,cut in cuts.items():
    g=df[df.line==ln].copy()
    g['post']=g.date>=pd.Timestamp(cut)
    g['rate']=g.defective_units/g.units_produced
    cols=['units_produced','defective_units','rate','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','days_since_clean','qc_inspection_min','rework_cost_eur']
    print('\n==',ln,'cut',cut)
    print(g.groupby('post')[cols].mean().round(3).T.to_string())
    print(g.groupby('post').apply(lambda x: x.defective_units.sum()/x.units_produced.sum()).round(4).to_dict())
    print('n',g.groupby('post').size().to_dict())
    print(pd.crosstab(g.post,g.shift,normalize='index').round(2).to_string())
    print(pd.crosstab(g.post,g.supplier_name,normalize='index').round(2).to_string())
    print(g.groupby('post').operator_id.nunique().to_dict())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
g=df.copy()
g['rate']=g.defective_units/g.units_produced
print('corr qc vs rate', round(g[['qc_inspection_min','rate']].corr().iloc[0,1],3),' corr qc vs defective_units', round(g[['qc_inspection_min','defective_units']].corr().iloc[0,1],3))
print('rework per defective unit:', (g.rework_cost_eur/g.defective_units).describe().round(3).to_dict())
print('rework per unit produced:', (g.rework_cost_eur/g.units_produced).describe().round(4).to_dict())
import statsmodels.formula.api as smf
m=smf.ols('qc_inspection_min ~ rate + C(line) + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + machine_age_years + C(shift)', data=g.dropna(subset=['humidity_pct','mold_temp'])).fit()
print('qc ~ rate: coef',round(m.params['rate'],2),'p',round(m.pvalues['rate'],4), 'R2', round(m.rsquared,3))
g['post_L3']=((g.line=='L3')&(g.date>='2025-07-21')).astype(int)
g['post_L2']=((g.line=='L2')&(g.date>='2025-06-15')).astype(int)
m2=smf.ols('qc_inspection_min ~ post_L3 + post_L2 + C(line) + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + machine_age_years + C(shift)+ C(supplier_name)', data=g.dropna(subset=['humidity_pct','mold_temp'])).fit()
print(m2.params[['post_L3','post_L2']].round(3).to_dict(), m2.pvalues[['post_L3','post_L2']].round(4).to_dict())
print(g.groupby('line').qc_inspection_min.describe().round(2))
print(g.groupby(g.date.dt.to_period('M')).qc_inspection_min.mean().unstack(0).round(1) if False else '')
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
import statsmodels.formula.api as smf
g=df.copy()
for ln,cut in [('L2','2025-06-15'),('L3','2025-07-21')]:
    h=g[g.line==ln].copy(); h['post']=(h.date>=pd.Timestamp(cut)).astype(int)
    for p,hh in h.groupby('post'):
        m=smf.ols('qc_inspection_min ~ defective_units + units_produced', data=hh).fit()
        r=smf.ols('rework_cost_eur ~ defective_units', data=hh).fit()
        print(ln,'post',p,'qc~defect slope',round(m.params['defective_units'],4),'int',round(m.params['Intercept'],2),'R2',round(m.rsquared,3),' | rework slope per defect',round(r.params['defective_units'],3),'int',round(r.params['Intercept'],2),'R2',round(r.rsquared,3))
print('ALL lines: rework per defect by line-period')
g['post']=0
print(g.assign(rpd=g.rework_cost_eur/g.defective_units).groupby('line').rpd.describe().round(3))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > full.py <<'EOF'
from model import *
d['L2_step']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(float)
d['L3_step']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(float)
d['alpha']=(d.supplier_name=='Alpha').astype(float)
d['hum_alpha']=d.humidity_pct*d.alpha
d['hum_nonalpha']=d.humidity_pct*(1-d.alpha)
d['op_in_line']=d.operator_id
EOF
python3 -c "
from full import *
core='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean + L2_step + L3_step + C(shift) + C(supplier_name) + C(line)'
m=fitm(core)
print('core llf',round(m.llf,1),'disp',round(m.pearson_chi2/m.df_resid,2))
print(m.params.round(4).to_string()); print(m.pvalues.round(4).to_string())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
from scipy import stats
core='mold_temp + humidity_pct + hum_alpha + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean + L2_step + L3_step + C(shift) + C(supplier_name) + C(line)'
def fit_scaled(f,data=d):
    return smf.glm('y + ok ~ '+f, data=data, family=sm.families.Binomial()).fit(scale='X2')
m=fit_scaled(core)
print(pd.DataFrame({'coef':m.params,'se':m.bse,'p':m.pvalues}).round(4).loc[['mold_temp','humidity_pct','hum_alpha','cycle_time_s','machine_age_years','ambient_temp_c','days_since_clean','L2_step','L3_step','C(shift)[T.Night]']].to_string())
def llf(f): return smf.glm('y + ok ~ '+f, data=d, family=sm.families.Binomial()).fit().llf
disp=smf.glm('y + ok ~ '+core, data=d, family=sm.families.Binomial()).fit().pearson_chi2/ (len(d)-len(smf.glm('y + ok ~ '+core, data=d, family=sm.families.Binomial()).fit().params))
print('disp',round(disp,2))
L=llf(core)
tests={'shift':'C(shift)','machine_age':'machine_age_years','ambient':'ambient_temp_c','mold_temp':'mold_temp','humidity(alpha slope)':'humidity_pct + hum_alpha','cycle':'cycle_time_s','days_since':'days_since_clean'}
for k,v in tests.items():
    f2=core
    for term in v.split(' + '):
        f2=f2.replace(' + '+term,'').replace(term+' + ','')
    s=2*(L-llf(f2)); dfree=len(v.split(' + '))
    if k=='shift': dfree=1
    print(f'{k:24s} LR={s:9.2f} p(raw)={stats.chi2.sf(s,dfree):.3g}  p(disp-adj)={stats.chi2.sf(s/disp,dfree):.3g}')
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
from scipy import stats
base='mold_temp + humidity_pct + hum_alpha + cycle_time_s + days_since_clean + L2_step + L3_step + C(shift) + C(supplier_name) + C(line)'
def llf(f): return smf.glm('y + ok ~ '+f, data=d, family=sm.families.Binomial()).fit()
m0=llf(base); disp=m0.pearson_chi2/m0.df_resid
print('disp', round(disp,2))
# operator within line: operator dummies inside each line (nested) vs line only
opf=base+' + C(operator_id)'
m1=llf(opf)
dfree=m1.df_model-m0.df_model
lr=2*(m1.llf-m0.llf)
print('operator (nested) LR',round(lr,1),'df',dfree,'p',stats.chi2.sf(lr,dfree),'p disp-adj',stats.chi2.sf(lr/disp,dfree))
# shift controlled: operators by shift
print(pd.crosstab(d.operator_id,d.shift).head(6))
# shift effect within operator? (shift x operator interaction not needed)
# machine age: check nonlinearity and within-line
for ln in ['L1','L2','L3','L4']:
    g=d[d.line==ln]
    mm=smf.glm('y + ok ~ mold_temp + humidity_pct + hum_alpha + cycle_time_s + days_since_clean + L2_step + L3_step + C(shift) + C(supplier_name) + machine_age_years', data=g, family=sm.families.Binomial()).fit()
    print(ln,'machine_age coef',round(mm.params['machine_age_years'],4),'p',round(mm.pvalues['machine_age_years'],4))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
core='mold_temp + humidity_pct + hum_alpha + cycle_time_s + days_since_clean + L2_step + L3_step + C(shift) + C(supplier_name) + C(line)'
m=smf.glm('y + ok ~ '+core, data=d, family=sm.families.Binomial()).fit()
d['pe']=m.predict(d)*d.units_produced
d['rr']=d.defective_units/d.pe
g=d.groupby('line').apply(lambda x: x.defective_units.sum()/x.pe.sum()).round(3)
print('obs/exp by line', g.to_dict())
d['mab']=pd.cut(d.machine_age_years,[0,3,5,7,9,10,12,14,16,18,22])
print(d.groupby(['line','mab'],observed=True).apply(lambda x: pd.Series({'n':len(x),'oe':round(x.defective_units.sum()/x.pe.sum(),3)})).unstack(0).to_string())
op=d.groupby(['line','operator_id']).apply(lambda x: pd.Series({'n':len(x),'oe':round(x.defective_units.sum()/x.pe.sum(),3)}))
print(op.to_string())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
from scipy import stats
d['mt_c']=d.mold_temp-212; d['hu_c']=d.humidity_pct-33; d['cyc_c']=d.cycle_time_s-31; d['dsc_c']=d.days_since_clean-8
d['mt2']=d.mt_c**2; d['hu2']=d.hu_c**2; d['cy2']=d.cyc_c**2; d['dsc2']=d.dsc_c**2
d['hu2_alpha']=d.hu2*d.alpha; d['hu_alpha_c']=d.hu_c*d.alpha
flex='mt_c + mt2 + hu_c + hu2 + hu_alpha_c + hu2_alpha + cyc_c + cy2 + dsc_c + dsc2 + machine_age_years + ambient_temp_c + L2_step + L3_step + C(shift) + C(supplier_name) + C(line)'
def fit(f): return smf.glm('y + ok ~ '+f, data=d, family=sm.families.Binomial()).fit()
m0=fit(flex); disp=m0.pearson_chi2/m0.df_resid
print('flex disp',round(disp,3),'llf',round(m0.llf,1))
print(pd.DataFrame({'coef':m0.params,'p':m0.pvalues}).round(4).to_string())
m1=fit(flex+' + C(operator_id)')
lr=2*(m1.llf-m0.llf); print('operator LR',round(lr,1),'df',m1.df_model-m0.df_model,'p disp-adj',stats.chi2.sf(lr/disp,m1.df_model-m0.df_model))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
from scipy import stats
print(pd.crosstab(d.operator_id, d['shift']).T.to_string())
d['mt_c']=d.mold_temp-212; d['hu_c']=d.humidity_pct-33; d['cyc_c']=d.cycle_time_s-31; d['dsc_c']=d.days_since_clean-8
d['mt2']=d.mt_c**2; d['hu2']=d.hu_c**2; d['hu_alpha_c']=d.hu_c*d.alpha; d['cy2']=d.cyc_c**2
flex='mt_c + mt2 + hu_c + hu2 + hu_alpha_c + cyc_c + cy2 + dsc_c + machine_age_years + ambient_temp_c + L2_step + L3_step + C(supplier_name) + C(line)'
def fit(f): return smf.glm('y + ok ~ '+f, data=d, family=sm.families.Binomial()).fit()
m0=fit(flex+' + C(shift)'); disp=m0.pearson_chi2/m0.df_resid
m_noshift=fit(flex)
lr=2*(m0.llf-m_noshift.llf); print('shift LR',round(lr,1),'p disp',stats.chi2.sf(lr/disp,1))
m_op=fit(flex+' + C(shift) + C(operator_id)'); m_op0=fit(flex+' + C(shift)')
lr2=2*(m_op.llf-m_op0.llf); print('operator LR (with shift)',round(lr2,1),'p disp',stats.chi2.sf(lr2/disp,20))
print('shift coef', round(m0.params['C(shift)[T.Night]'],4), 'with operator', round(m_op.params['C(shift)[T.Night]'],4))
print('disp', round(disp,3))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > perm.py <<'EOF'
from full import *
import warnings; warnings.filterwarnings('ignore')
d['mt_c']=d.mold_temp-212; d['hu_c']=d.humidity_pct-33; d['cyc_c']=d.cycle_time_s-31; d['dsc_c']=d.days_since_clean-8
d['mt2']=d.mt_c**2; d['hu2']=d.hu_c**2; d['hu_alpha_c']=d.hu_c*d.alpha; d['cy2']=d.cyc_c**2
flex='mt_c + mt2 + hu_c + hu2 + hu_alpha_c + cyc_c + cy2 + dsc_c + machine_age_years + ambient_temp_c + L2_step + L3_step + C(supplier_name) + C(line) + C(shift)'
def llf(data, f):
    return smf.glm('y + ok ~ '+f, data=data, family=sm.families.Binomial()).fit().llf
EOF
python3 -c "
from perm import *
rng=np.random.default_rng(0)
base_ll=llf(d, flex)
obs_op=2*(llf(d, flex+' + C(operator_id)')-base_ll)
print('observed operator LR',round(obs_op,1))
perm=[]
for i in range(150):
    dd=d.copy()
    dd['operator_id']=dd.groupby('line').operator_id.transform(lambda s: rng.permutation(s.values))
    perm.append(2*(llf(dd, flex+' + C(operator_id)')-llf(dd, flex)))
perm=np.array(perm)
print('operator permutation p', round((np.sum(perm>=obs_op)+1)/(len(perm)+1),4), 'perm mean', round(perm.mean(),1), 'perm 95%', round(np.quantile(perm,0.95),1))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from perm import *
rng=np.random.default_rng(1)
f_wo=flex.replace(' + machine_age_years','')
f_wa=flex.replace(' + ambient_temp_c','')
for name,f_small,term,col in [('machine_age',f_wo,'machine_age_years','machine_age_years'),('ambient',f_wa,'ambient_temp_c','ambient_temp_c')]:
    obs=2*(llf(d,flex)-llf(d,f_small))
    perm=[]
    for i in range(150):
        dd=d.copy()
        dd[col]=dd.groupby('line')[col].transform(lambda s: rng.permutation(s.values))
        perm.append(2*(llf(dd,flex)-llf(dd,f_small)))
    perm=np.array(perm)
    print(name,'obs LR',round(obs,2),'perm p',round((np.sum(perm>=obs)+1)/(len(perm)+1),3),'perm mean',round(perm.mean(),2))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from perm import *
base_f=flex
base_ll=llf(d,flex)
d2=d.copy()
res={}
for ln,other in [('L2','L3_step'),('L3','L2_step')]:
    rows=[]
    for dt in pd.date_range('2025-05-15','2025-08-15',freq='D'):
        dd=d.copy()
        dd['stp']=((dd.line==ln)&(dd.date>=dt)).astype(float)
        if ln=='L2': dd['stp']=dd['stp']  # L2 step candidate replacing L2_step
        f=flex.replace('L2_step','stp') if ln=='L2' else flex.replace('L3_step','stp')
        rows.append((dt.date(), 2*(llf(dd,f)-base_ll) ))
    rows=sorted(rows,key=lambda x:-x[1])
    print(ln,'top 4 dates by LR (vs no step)', [(str(a),round(b,1)) for a,b in rows[:4]])
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from perm import *
g=d[(d.line=='L2')&(d.date>='2025-06-08')&(d.date<='2025-06-22')].copy()
g['rate']=(g.defective_units/g.units_produced).round(4)
print(g.groupby('date').apply(lambda x: pd.Series({'n':len(x),'rate':round(x.defective_units.sum()/x.units_produced.sum(),4),'units':x.units_produced.sum()})).to_string())
for dt in ['2025-06-14','2025-06-15','2025-06-16']:
    print(dt, 'L2 rows', (g.date==dt).sum())
print(g[['date','batch_id','defect_rate' if 'defect_rate' in g else 'rate','mold_temp','humidity_pct','days_since_clean']].sort_values('date').head(40).to_string())
" 2>&1 | grep -v Warn | head -80

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from perm import *
core='mold_temp + humidity_pct + hum_alpha + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean + L3_step + C(shift) + C(supplier_name) + C(line)'
def ll(data,f): return smf.glm('y + ok ~ '+f, data=data, family=sm.families.Binomial()).fit().llf
out=[]
for dt in pd.date_range('2025-06-11','2025-06-19',freq='D'):
    dd=d.copy(); dd['stp']=((dd.line=='L2')&(dd.date>=dt)).astype(float)
    out.append((dt.date(), round(ll(dd,core.replace('+ C(line)','+ C(line)')+' + stp'),2), round(ll(dd,flex.replace('L2_step','stp')),2)))
o=pd.DataFrame(out,columns=['date','core_llf','flex_llf'])
o['core_dLL']=(o.core_llf-o.core_llf.max()).round(2); o['flex_dLL']=(o.flex_llf-o.flex_llf.max()).round(2)
print(o.to_string())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > spl.py <<'EOF'
from full import *
import warnings; warnings.filterwarnings('ignore')
from scipy import stats
d['nonalpha']=1-d.alpha
SPL=('cr(mold_temp, df=4) + cr(cycle_time_s, df=4) + cr(days_since_clean, df=4) + '
     'cr(humidity_pct, df=5):alpha + cr(humidity_pct, df=5):nonalpha + '
     'machine_age_years + ambient_temp_c + L2_step + L3_step + C(shift) + C(supplier_name) + C(line)')
def fitd(f, data=None):
    data = d if data is None else data
    return smf.glm('y + ok ~ '+f, data=data, family=sm.families.Binomial()).fit()
EOF
python3 -c "
from spl import *
m=fitd(SPL)
print('llf',round(m.llf,1),'disp',round(m.pearson_chi2/m.df_resid,3))
print(m.pvalues.round(4).filter(like='L').to_string()); print(m.pvalues.round(4).filter(like='shift').to_string())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from spl import *
rows=[]
base=fitd(SPL).llf
for dt in pd.date_range('2025-06-01','2025-06-30',freq='D'):
    dd=d.copy(); dd['L2s']=((dd.line=='L2')&(dd.date>=dt)).astype(float)
    f=SPL.replace('L2_step','L2s')
    rows.append((str(dt.date()), round(fitd(f,dd).llf-base,2)))
print('L2 scan (dLL vs model with L2 step 06-15):')
for r in rows:
    print(r)
rows=[]
for dt in pd.date_range('2025-07-10','2025-08-01',freq='D'):
    dd=d.copy(); dd['L3s']=((dd.line=='L3')&(dd.date>=dt)).astype(float)
    rows.append((str(dt.date()), round(fitd(SPL.replace('L3_step','L3s'),dd).llf,2)))
best=max(rows,key=lambda x:x[1]); print('L3 best', best, 'vs 07-21', [r for r in rows if r[0]=='2025-07-21'])
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from spl import *
d['L2s']=((d.line=='L2')&(d.date>='2025-06-16')).astype(float)
S=SPL.replace('L2_step','L2s')
base=fitd(S).llf
print('base llf',round(base,2))
for ln in ['L1','L4']:
    best=None
    for dt in pd.date_range('2025-02-01','2025-08-31',freq='D'):
        dd=d.copy(); dd['x']=((dd.line==ln)&(dd.date>=dt)).astype(float)
        m=fitd(S+' + x',dd)
        lr=2*(m.llf-base)
        if best is None or lr>best[0]: best=(round(lr,2),str(dt.date()),round(m.params['x'],3))
    print(ln,'best step',best,'disp-adj LR',round(best[0]/2.688,2))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from spl import *
from scipy import stats
d['L2s']=((d.line=='L2')&(d.date>='2025-06-16')).astype(float)
S=SPL.replace('L2_step','L2s')
S2=S.replace('cr(humidity_pct, df=5):alpha + cr(humidity_pct, df=5):nonalpha','cr(humidity_pct, df=5):C(supplier_name)')
S2=S2.replace(' + C(supplier_name) + C(line)',' + C(line)')
m1=fitd(S); m2=fitd(S2)
lr=2*(m2.llf-m1.llf); dfree=m2.df_model-m1.df_model
print('supplier-specific humidity splines LR',round(lr,2),'df',dfree,'p disp',round(stats.chi2.sf(lr/2.688,dfree),4))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from spl import *
from scipy import stats
d['L2s']=((d.line=='L2')&(d.date>='2025-06-16')).astype(float)
S=SPL.replace('L2_step','L2s')
S2=S.replace('cr(humidity_pct, df=5):alpha + cr(humidity_pct, df=5):nonalpha','cr(humidity_pct, df=5):C(supplier_name)')
m1=fitd(S); m2=fitd(S2)
lr=2*(m2.llf-m1.llf); dfree=m2.df_model-m1.df_model
print('supplier-specific humidity LR',round(lr,2),'df',dfree,'p disp',round(stats.chi2.sf(lr/2.688,dfree),4))
print('S2 disp', round(m2.pearson_chi2/m2.df_resid,3))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > final.py <<'EOF'
from spl import *
d['L2s']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(float)
d['L3s']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(float)
FINAL=('cr(mold_temp, df=4) + cr(cycle_time_s, df=4) + cr(days_since_clean, df=4) + '
       'cr(humidity_pct, df=5):C(supplier_name) + machine_age_years + ambient_temp_c + '
       'L2s + L3s + C(shift) + C(supplier_name) + C(line)')
def fin(f=FINAL, data=None):
    return fitd(f, d if data is None else data)
EOF
python3 -c "
from final import *
from scipy import stats
m=fin(); disp=m.pearson_chi2/m.df_resid
print('final llf',round(m.llf,1),'disp',round(disp,3))
print('baseline predicted overall rate', round(m.fittedvalues.dot(d.units_produced)/d.units_produced.sum(),5) if False else round((m.predict(d)*d.units_produced).sum()/d.units_produced.sum(),5))
terms={'mold_temp':'cr(mold_temp, df=4)','cycle_time_s':'cr(cycle_time_s, df=4)','humidity_pct':'cr(humidity_pct, df=5):C(supplier_name)','machine_age_years':'machine_age_years','ambient_temp_c':'ambient_temp_c','operator_id':None,'shift':'C(shift)','days_since_clean':'cr(days_since_clean, df=4)'}
for k,t in terms.items():
    if t is None:
        f2=FINAL+' + C(operator_id)'
        m2=fin(f2); lr=2*(m2.llf-m.llf); df_=m2.df_model-m.df_model
        f0=FINAL
    else:
        f0=FINAL.replace(' + '+t,'') if (' + '+t) in FINAL else FINAL.replace(t+' + ','')
        m0=fin(f0); lr=2*(m.llf-m0.llf)
        df_=m.df_model-m0.df_model
    print(f'{k:20s} LR={lr:9.2f} df={df_:.0f} p(disp)={stats.chi2.sf(lr/disp,df_):.3g}')
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 900 python3 -c "
from final import *
import time
rng=np.random.default_rng(7)
def L(data,f): return smf.glm('y + ok ~ '+f, data=data, family=sm.families.Binomial()).fit().llf
base=L(d,FINAL)
obs=2*(L(d,FINAL+' + C(operator_id)')-base)
print('observed operator LR',round(obs,2))
t0=time.time(); perm=[]
for i in range(120):
    dd=d.copy()
    dd['operator_id']=dd.groupby('line').operator_id.transform(lambda s: rng.permutation(s.values))
    perm.append(2*(L(dd,FINAL+' + C(operator_id)')-L(dd,FINAL)))
perm=np.array(perm)
print('perm p', round((np.sum(perm>=obs)+1)/(len(perm)+1),4),'perm mean',round(perm.mean(),2),'95%',round(np.quantile(perm,.95),2),'secs',round(time.time()-t0))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > answers.py <<'EOF'
from final import *
from clean import load_ref
m = fin()
sup, mnt = load_ref()
def pred_rate(data, model=m):
    p = model.predict(data)
    return (p * data.units_produced).sum() / data.units_produced.sum(), (p * data.units_produced).sum()

if __name__ == '__main__':
    print('baseline model rate', round(pred_rate(d)[0], 5), 'observed', round(d.defective_units.sum()/d.units_produced.sum(), 5))
    # C1: every batch from one supplier, cycle time at that grade's recipe
    for _, r in sup.iterrows():
        dd = d.copy()
        dd['supplier_name'] = r.supplier_name
        dd['cycle_time_s'] = r.recipe_cycle_time_s
        dd['days_since_clean'] = d.days_since_clean
        a, _ = pred_rate(dd)
        dd2 = dd.copy(); dd2['L3s'] = 0.0
        b, _ = pred_rate(dd2)
        print('C1', r.supplier_name, r.resin_grade, 'recipe', r.recipe_cycle_time_s, 'rate(L3 as recorded)', round(a, 5), 'rate(L3 artifact removed)', round(b, 5))
    # C2: Alpha only, humidity sweep, other conditions as in each Alpha batch
    al = d[d.supplier_name == 'Alpha'].copy()
    grid = np.round(np.arange(12.5, 72.0, 0.1), 2)
    rates = []
    for h in grid:
        dd = al.copy(); dd['humidity_pct'] = h
        rates.append(pred_rate(dd)[0])
    rates = np.array(rates)
    i = rates.argmin()
    print('C2 Alpha argmin humidity', grid[i], 'rate', round(rates[i], 5), 'range', grid.min(), grid.max())
    for h in [20, 25, 28, 29, 30, 31, 35, 40, 45]:
        print('   h', h, round(rates[np.argmin(abs(grid-h))], 5))
EOF
python3 answers.py 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > c3.py <<'EOF'
from answers import *
import warnings; warnings.filterwarnings('ignore')
END = pd.Timestamp('2025-09-30')
cl = mnt[mnt.event == 'mold_cleaning']
def cf_days_since(df, every=14):
    out = pd.Series(index=df.index, dtype=float)
    for ln, g in df.groupby('line'):
        act = np.sort(cl[cl.line == ln].date.values)
        ev = list(act)
        for k in range(len(act)):
            nxt = act[k + 1] if k + 1 < len(act) else np.datetime64(END) + np.timedelta64(1, 'D')
            j = 1
            while act[k] + np.timedelta64(every * j, 'D') < nxt:
                ev.append(act[k] + np.timedelta64(every * j, 'D'))
                j += 1
        ev = np.sort(np.array(ev))
        idx = np.searchsorted(ev, g.date.values, side='right') - 1
        last = pd.to_datetime(ev[idx])
        out.loc[g.index] = (g.date - last).dt.days.values
    return out
dd = d.copy()
dd['days_since_clean'] = cf_days_since(d)
print('forced-cleaning days_since: max', dd.days_since_clean.max(), 'share>14', round((dd.days_since_clean>14).mean(),4))
print('observed days_since equal check (actual schedule reproduces):', (cf_days_since(d, every=10**6)-d.days_since_clean).abs().max())
a, _ = pred_rate(dd)
dd2 = dd.copy(); dd2['L3s'] = 0.0
b, _ = pred_rate(dd2)
print('C3 rate with cleaning every 14d (L3 as recorded):', round(a, 5))
print('C3 rate with cleaning every 14d (L3 artifact removed):', round(b, 5))
print('baseline model rate', round(pred_rate(d)[0],5))
EOF
python3 c3.py 2>&1 | grep -v Warn

sleep 60; cat /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b0ohxx3fp.output 2>/dev/null | grep -v Warn | tail -5

cat /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b0ohxx3fp.output 2>/dev/null | grep -v Warn | tail -5; echo "---"; ls -la /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/ 2>/dev/null

until [ -s /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b0ohxx3fp.output ]; do sleep 5; done; grep -v Warn /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b0ohxx3fp.output

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 110 python3 -c "
from answers import *
import warnings; warnings.filterwarnings('ignore')
base=m.llf
for dt in ['2025-06-14','2025-06-15','2025-06-16','2025-06-17']:
    dd=d.copy(); dd['L2s']=((dd.line=='L2')&(dd.date>=pd.Timestamp(dt))).astype(float)
    print(dt, round(fitd(FINAL, dd).llf - base, 2))
al=d[d.supplier_name=='Alpha'].copy()
grid=np.round(np.arange(27.0,32.0,0.05),2)
r=[pred_rate(al.assign(humidity_pct=h))[0] for h in grid]
print('fine argmin', grid[int(np.argmin(r))], round(min(r),6))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-anppsz-3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 110 python3 -c "
from answers import *
import warnings; warnings.filterwarnings('ignore')
dd=d.copy(); dd['L2s']=0.0
m0=fitd(FINAL, dd)
dd['exp']=m0.predict(dd)*dd.units_produced
g=dd[(dd.line=='L2')&(dd.date>='2025-06-10')&(dd.date<='2025-06-22')].groupby('date').agg(n=('batch_id','size'),obs=('defective_units','sum'),exp=('exp','sum'))
g['oe']=(g.obs/g.exp).round(2)
print(g.to_string())
pre=dd[(dd.line=='L2')&(dd.date<'2025-06-15')]; post=dd[(dd.line=='L2')&(dd.date>='2025-06-16')]
print('O/E pre-06-15', round(pre.defective_units.sum()/pre.exp.sum(),3),' O/E from 06-16', round(post.defective_units.sum()/post.exp.sum(),3))
print(dd[(dd.line=='L2')&(dd.date=='2025-06-15')][['batch_id','supplier_name','humidity_pct','days_since_clean','defective_units','units_produced']].to_string())
" 2>&1 | grep -v Warn
