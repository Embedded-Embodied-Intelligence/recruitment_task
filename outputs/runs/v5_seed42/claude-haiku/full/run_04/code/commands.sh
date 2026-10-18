ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && cat maintenance.csv && echo && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('==',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    if df[c].nunique()<60: print(vc.to_string())
    else: print(df[c].head(8).tolist())
"

mkdir -p $TMPDIR/an && python3 -c "
import pandas as pd
pd.set_option('display.width',250); pd.set_option('display.max_columns',30)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d),'dup ids',d.batch_id.nunique())
print(d.head(20).to_string())
# exact duplicate rows?
print('exact dup rows', df.duplicated().sum())
# date formats
import re
iso=df.production_date.str.match(r'^\d{4}-\d{2}-\d{2}$')
us=df.production_date.str.match(r'^\d{2}/\d{2}/\d{4}$')
print('iso',iso.sum(),'us',us.sum(),'other',(~iso&~us).sum())
print(df.loc[~iso&~us,'production_date'].unique()[:20])
"

python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
df['row']=range(len(df))
slash=df.production_date.str.contains('/')
a=df.production_date.str.extract(r'^(\d{2})/(\d{2})/(\d{4})$').astype(float)
unamb_mdy=(a[0]<=12)&(a[1]>12)
unamb_dmy=(a[0]>12)&(a[1]<=12)
amb=slash&(a[0]<=12)&(a[1]<=12)
print('slash rows',slash.sum(),'MDY-only',unamb_mdy.sum(),'DMY-only',unamb_dmy.sum(),'ambiguous',amb.sum())
print('ambiguous where day==month',(a[0]==a[1])[amb].sum())
# row order: are ISO rows ordered by date?
iso=df.production_date.str.match(r'^\d{4}-')
s=df.loc[iso,'production_date'].tolist()
print('ISO monotonic in file order?', all(x<=y for x,y in zip(s,s[1:])), 'inversions',sum(x>y for x,y in zip(s,s[1:])))
print(df.production_date.iloc[:40].tolist())
"

python3 -c "
import pandas as pd
pd.set_option('display.width',250); pd.set_option('display.max_columns',30)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
df['row']=range(len(df))
iso=df.production_date.str.match(r'^\d{4}-')
s=df[iso][['row','production_date','line','batch_id']]
s=s.reset_index(drop=True)
inv=s.index[s.production_date.shift(1)>s.production_date]
for i in inv[:8]:
    print(s.iloc[max(0,i-2):i+2].to_string(header=False)); print('--')
print(df.production_date[df.production_date.str.match(r'^\d{4}-')].str[:7].value_counts().sort_index())
"

python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x=pd.to_numeric(df[c],errors='coerce')
    bad=df.loc[x.isna(),c].unique()
    print(c,'nonnumeric:',bad[:10], 'n=',(x.isna()).sum())
    print(x.describe(percentiles=[.001,.01,.05,.5,.95,.99,.999]).round(2).to_dict())
    print('  sorted low',np.sort(x.dropna().unique())[:6],' high',np.sort(x.dropna().unique())[-6:])
"

python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
for c in ['humidity_pct','mold_temp','defective_units','units_produced']: df[c]=pd.to_numeric(df[c],errors='coerce')
df['row']=range(len(df))
print('humidity -1:',(df.humidity_pct==-1).sum(),' empty',df.humidity_pct.isna().sum())
print('mold 0:',(df.mold_temp==0).sum())
print('defective>units',(df.defective_units>df.units_produced).sum())
df['F']=df.mold_temp>300
print(pd.crosstab(df.line,df.F))
df['iso']=df.production_date.str.match(r'^\d{4}-')
print(df[df.F].groupby(['line']).mold_temp.describe().round(1))
print(df[(df.mold_temp>0)&(~df.F)].groupby(['line']).mold_temp.describe().round(1))
print(df[df.mold_temp==0][['batch_id','production_date','line','mold_temp']].head(12).to_string())
"

python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
for c in ['humidity_pct','mold_temp','defective_units','units_produced']: df[c]=pd.to_numeric(df[c],errors='coerce')
print(df[(df.line=='L3')&(df.mold_temp<300)][['batch_id','production_date','line','mold_temp']].to_string())
df['row']=range(len(df))
def pdate(s):
    import re
    if re.match(r'^\d{4}-',s): return pd.Timestamp(s)
    a,b,y=s.split('/')
    return None
df['mC']=np.where(df.mold_temp>300,(df.mold_temp-32)*5/9,df.mold_temp)
df.loc[df.mold_temp==0,'mC']=np.nan
df['iso']=df.production_date.str.match(r'^\d{4}-')
d=df[df.iso].copy(); d['d']=pd.to_datetime(d.production_date)
d=d[d.mC.notna()]
print(d.assign(m=d.d.dt.month).pivot_table(index='m',columns='line',values='mC',aggfunc='mean').round(1))
l1=d[d.line=='L1'].sort_values('d')
l1['post']=l1.d>='2025-04-14'
print(l1.groupby('post').mC.describe().round(2))
print(l1[(l1.d>='2025-04-01')&(l1.d<='2025-04-30')].groupby(l1.d.dt.date).mC.mean().round(1).to_string())
"

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
df['fmt']=df.production_date.map(lambda s:'ISO' if '-' in s else ('MDY/DMY'))
print(pd.crosstab(df.line,df.fmt))
print(pd.crosstab(df.line,df.shift.str.strip().str.lower()))
print(pd.crosstab(df.line,df.supplier_code.str.strip().str.upper()))
"

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
s=df[df.production_date.str.contains('/')].copy()
a=s.production_date.str.extract(r'^(\d{2})/(\d{2})/(\d{4})$').astype(int)
s['a']=a[0]; s['b']=a[1]
s['kind']=['MDY-only' if (x<=12 and y>12) else ('DMY-only' if (x>12 and y<=12) else ('ambig' if x<=12 and y<=12 else 'none')) for x,y in zip(s.a,s.b)]
print(pd.crosstab(s.line,s.kind))
print(s.production_date.str[-4:].value_counts())
"

mkdir -p $TMPDIR/an && cat > $TMPDIR/an/clean.py <<'EOF'
import pandas as pd, numpy as np

SRC = '/tmp/edabench_claude_6osld_dy/'

def load_raw():
    return pd.read_csv(SRC + 'batches.csv', dtype=str, keep_default_na=False)

def parse_date(s, line):
    if '-' in s:
        return pd.to_datetime(s, format='%Y-%m-%d')
    fmt = '%m/%d/%Y' if line == 'L1' else '%d/%m/%Y'
    return pd.to_datetime(s, format=fmt)

def clean(raw=None):
    df = (load_raw() if raw is None else raw).copy()
    df['row'] = np.arange(len(df))
    df['date'] = [parse_date(s, l) for s, l in zip(df.production_date, df.line)]
    df['shift'] = df['shift'].str.strip().str.lower().map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
    df['supplier_code'] = df.supplier_code.str.strip().str.upper()
    for c in ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'cycle_time_s', 'units_produced',
              'defective_units', 'qc_inspection_min', 'rework_cost_eur']:
        df[c] = pd.to_numeric(df[c], errors='coerce')
    df['humidity_pct'] = pd.to_numeric(df.humidity_pct.replace('', np.nan), errors='coerce')
    df.loc[df.humidity_pct < 0, 'humidity_pct'] = np.nan
    # L3 logs mold temperature in Fahrenheit; 0.0 is a missing-value code
    df.loc[df.mold_temp == 0, 'mold_temp'] = np.nan
    f = df.line.eq('L3') & df.mold_temp.notna()
    df.loc[f, 'mold_temp'] = (df.loc[f, 'mold_temp'] - 32) * 5 / 9
    return df
EOF
cd $TMPDIR/an && python3 -c "
import pandas as pd
from clean import clean
pd.set_option('display.width',250); pd.set_option('display.max_columns',30)
df=clean()
print('shift nulls',df['shift'].isna().sum(),'supplier codes',df.supplier_code.unique())
cols=[c for c in df.columns if c not in ('row','production_date')]
print('exact dup rows (ignoring row, raw date):',df.drop(columns=['row','production_date']).duplicated().sum())
print('exact dup rows (all normalised cols):',df[cols].duplicated().sum())
u=df.drop_duplicates(subset=cols)
print('after dedupe rows',len(u),'unique batch_id',u.batch_id.nunique(),'unique (batch,line)',u[['batch_id','line']].drop_duplicates().shape[0])
d=u[u.batch_id.duplicated(keep=False)].sort_values(['batch_id','date'])
print('still dup ids',d.batch_id.nunique())
print(d[['batch_id','date','line','shift','operator_id','supplier_code','units_produced','defective_units','mold_temp']].head(16).to_string())
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
from clean import clean
pd.set_option('display.width',250); pd.set_option('display.max_columns',30)
df=clean()
cols=[c for c in df.columns if c not in ('row','production_date')]
u=df.drop_duplicates(subset=cols).copy()
u.to_pickle('u.pkl')
print('unique batches',len(u))
print('humidity NaN',u.humidity_pct.isna().sum())
print('mold NaN',u.mold_temp.isna().sum())
print(u.assign(m=u.date.dt.month).pivot_table(index='m',columns='line',values='mold_temp',aggfunc='mean').round(1))
l1=u[u.line=='L1'].sort_values('date')
print(l1.set_index('date').mold_temp.resample('MS').agg(['mean','std','count']).round(1))
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
print(u.assign(m=u.date.dt.month).pivot_table(index='m',columns='line',values='ambient_temp_c',aggfunc='mean').round(1))
print(u.assign(m=u.date.dt.month).pivot_table(index='m',columns='line',values='cycle_time_s',aggfunc='mean').round(2))
print(u.assign(m=u.date.dt.month).pivot_table(index='m',columns='line',values='humidity_pct',aggfunc='mean').round(1))
l1=u[(u.line=='L1')&u.mold_temp.notna()].copy()
w=l1[(l1.date>='2025-04-01')&(l1.date<='2025-04-30')]
print(w.groupby('date').agg(mold=('mold_temp','mean'),amb=('ambient_temp_c','mean'),cyc=('cycle_time_s','mean'),n=('mold_temp','size')).round(1).to_string())
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
m=u[u.mold_temp.notna()].copy()
m['t']=(m.date-pd.Timestamp('2025-01-01')).dt.days
r=smf.ols('mold_temp ~ C(line) + ambient_temp_c + cycle_time_s + machine_age_years + t + C(shift)+C(supplier_code)',data=m).fit()
print(r.summary().tables[1])
m['res']=r.resid
print(m.groupby('line').res.describe().round(2))
l1=m[m.line=='L1'].sort_values('date')
print(l1.set_index('date').res.resample('MS').mean().round(2))
w=m[(m.line=='L1')&(m.date>='2025-03-25')&(m.date<='2025-04-30')].groupby('date').res.mean().round(1)
print(w.to_string())
" 2>&1 | tail -120

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
u['rate']=u.defective_units/u.units_produced
print('overall',u.defective_units.sum()/u.units_produced.sum(), 'mean rate',u.rate.mean())
print(u.rate.describe().round(4))
print(u.groupby('line').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(u.groupby('supplier_code').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(u.groupby('shift').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(u.groupby('operator_id').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).sort_values().to_string())
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','qc_inspection_min','rework_cost_eur']
print(u[num+['rate','defective_units']].corr(method='spearman')[['rate','defective_units']].round(3))
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
import statsmodels.api as sm, statsmodels.formula.api as smf
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
u['good']=u.units_produced-u.defective_units
c=u.dropna(subset=['mold_temp','humidity_pct']).copy()
print('complete n',len(c))
f='defective_units + good ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)'
X=smf.glm('defective_units + good ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + C(supplier_code)',data=c,family=sm.families.Binomial()).fit()
print(X.summary().tables[1]); print('dev/df',X.deviance/X.df_resid)
Y=smf.glm(f,data=c,family=sm.families.Binomial()).fit()
print('with operators dev/df',Y.deviance/Y.df_resid)
print(Y.summary().tables[1])
" 2>&1 | head -150

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250); pd.set_option('display.max_columns',40)
u=pd.read_pickle('u.pkl')
u['rate']=u.defective_units/u.units_produced
g=u.groupby('operator_id').agg(n=('rate','size'),rate=('rate','mean'),cyc=('cycle_time_s','mean'),age=('machine_age_years','mean'),hum_na=('humidity_pct',lambda s:s.isna().mean()),
 first=('date','min'),last=('date','max'),L1=('line',lambda s:(s=='L1').mean()),L2=('line',lambda s:(s=='L2').mean()),L3=('line',lambda s:(s=='L3').mean()),L4=('line',lambda s:(s=='L4').mean()),night=('shift',lambda s:(s=='Night').mean()))
print(g.round(2).to_string())
"

cd $TMPDIR/an && cat > fit.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm, statsmodels.formula.api as smf
def prep(u):
    c=u.dropna(subset=['mold_temp','humidity_pct']).copy()
    c['good']=c.units_produced-c.defective_units
    return c
def ll(formula,data):
    r=smf.glm(formula,data=data,family=sm.families.Binomial()).fit()
    return r.llf, r
EOF
python3 -c "
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from fit import *
u=pd.read_pickle('u.pkl')
c=prep(u)
f='defective_units + good ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift) + C(line) + C(supplier_code)'
post=(c.line=='L1')&(c.date>='2025-04-14')
pre=(c.line=='L1')&(c.date<'2025-04-14')
for name,mask in [('L1post',post),('L1pre',pre)]:
  res=[]
  for d in np.arange(-10,10.1,1):
    cc=c.copy(); cc.loc[mask,'mold_temp']=cc.loc[mask,'mold_temp']+d
    l,_=ll(f,cc); res.append((d,round(l,1)))
  print(name,res)
" 

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
m=u[u.mold_temp.notna()].copy()
m['post']=((m.line=='L1')&(m.date>='2025-04-14')).astype(int)
m['mon']=m.date.dt.month
r=smf.ols('mold_temp ~ ambient_temp_c + C(mon) + C(line) + post',data=m).fit()
print(r.params.round(2)); print(r.bse.round(2)[['post']], r.rsquared.round(3))
r2=smf.ols('mold_temp ~ ambient_temp_c + C(mon) + C(line) + cycle_time_s + machine_age_years + post',data=m).fit()
print(r2.params[['post','ambient_temp_c','cycle_time_s','machine_age_years']].round(3), r2.bse['post'].round(3))
# step test by day for L1 with ambient
l1=m[m.line=='L1'].copy()
r3=smf.ols('mold_temp ~ ambient_temp_c + C(mon) + C(line) + post',data=m[m.line.isin(['L1','L2','L4'])]).fit()
print('L1,L2,L4 only post',r3.params['post'].round(2), r3.bse['post'].round(2))
# check L3 conversion vs L2 using same model
r4=smf.ols('mold_temp ~ ambient_temp_c + C(mon) + C(line)',data=m[m.line.isin(['L2','L3','L4'])]).fit()
print(r4.params.round(2))
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
m=u[u.mold_temp.notna()].copy()
base=smf.ols('mold_temp ~ ambient_temp_c + C(date.dt.month)',data=m[m.line.isin(['L2','L4'])]).fit()
print('slope by line:')
for l,g in m.groupby('line'):
    rr=smf.ols('mold_temp ~ ambient_temp_c',data=g).fit()
    print(l, rr.params.round(3).to_dict(), 'n',len(g))
m['res']=m.mold_temp-base.predict(m.assign(**{}).rename(columns={}).assign(**{}) if False else 0)
" 2>&1 | tail -12
cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
m=u[u.mold_temp.notna()].copy()
m['mon']=m.date.dt.month
b=smf.ols('mold_temp ~ ambient_temp_c + C(mon)',data=m[m.line.isin(['L2','L4'])]).fit()
m['res']=m.mold_temp-b.predict(m)
print(m.pivot_table(index='mon',columns='line',values='res',aggfunc='mean').round(2))
print(m.pivot_table(index='mon',columns='line',values='ambient_temp_c',aggfunc='mean').round(1))
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
m=u[u.mold_temp.notna()].copy()
m['mon']=m.date.dt.month
m['post']=((m.line=='L1')&(m.date>='2025-04-14')).astype(int)
ref=m[m.line.isin(['L2','L4'])]
b=smf.ols('mold_temp ~ ambient_temp_c + C(mon) + C(line)',data=ref).fit()
print('L2/L4 model slope',b.params['ambient_temp_c'].round(3))
m['res']=m.mold_temp-b.predict(m)
l1=m[m.line=='L1']
print('L1 residual pre',l1[l1.post==0].res.mean().round(2),'post',l1[l1.post==1].res.mean().round(2), 'post>=Apr15', l1[l1.date>='2025-04-15'].res.mean().round(2))
print('L1 post median',l1[l1.post==1].res.median().round(2))
l3=m[m.line=='L3'].set_index('date').res
print(l3.resample('2W').mean().round(1).to_string())
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
m=u[u.mold_temp.notna()].copy()
m['mon']=m.date.dt.month
m['post']=((m.line=='L1')&(m.date>='2025-04-14')).astype(int)
ref=m[m.line.isin(['L2','L4'])]
b=smf.ols('mold_temp ~ ambient_temp_c + C(mon)',data=ref).fit()
m['res']=m.mold_temp-b.predict(m)
l1=m[m.line=='L1']
print('L1 residual pre',l1[l1.post==0].res.mean().round(2),'post',l1[l1.post==1].res.mean().round(2),'post median',l1[l1.post==1].res.median().round(2))
print('post from Apr15', l1[l1.date>='2025-04-15'].res.mean().round(2), 'n',(l1.date>='2025-04-15').sum())
print('L2 mean res',m[m.line=='L2'].res.mean().round(2),'L4',m[m.line=='L4'].res.mean().round(2),'L3',m[m.line=='L3'].res.mean().round(2))
l3=m[m.line=='L3'].set_index('date').res
print(l3.resample('MS').mean().round(1).to_string())
print(l3['2025-05-15':'2025-06-30'].resample('W').mean().round(1).to_string())
print(m[m.line=='L1'].set_index('date').res['2025-04-08':'2025-04-22'].round(1).to_string())
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
m=u[u.mold_temp.notna()].copy()
m['mon']=m.date.dt.month
ref=m[m.line.isin(['L2','L4'])]
b=smf.ols('mold_temp ~ ambient_temp_c + C(mon)',data=ref).fit()
m['res']=m.mold_temp-b.predict(m)
l3=m[m.line=='L3'].sort_values('date')
w=l3[(l3.date>='2025-05-10')&(l3.date<='2025-06-20')].groupby('date').agg(res=('res','mean'),n=('res','size'),raw=('mold_temp','mean'))
print(w.round(1).to_string())
print('L3 raw F-check: row order around june')
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
u['rate']=u.defective_units/u.units_produced
def binned(col,q=10,df=u):
    d=df.dropna(subset=[col]).copy()
    d['b']=pd.qcut(d[col],q,duplicates='drop')
    g=d.groupby('b',observed=True).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum(),'mean_x':x[col].mean()}))
    print(col); print(g.round(4).to_string())
binned('humidity_pct',10)
binned('cycle_time_s',10)
binned('mold_temp',10)
binned('ambient_temp_c',8)
binned('machine_age_years',8)
binned('units_produced',8)
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
u['post']=((u.line=='L1')&(u.date>='2025-04-14')).astype(int)
u['mold_act']=u.mold_temp-7.7*u.post
u['good']=u.units_produced-u.defective_units
c=u.dropna(subset=['mold_temp','humidity_pct']).copy()
c['hum2']=(c.humidity_pct-35)**2
base='defective_units + good ~ '
spec={
 'A_lin':'mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code)',
 'B_op':'mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code) + C(operator_id)',
 'C_rec':'mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + C(supplier_code)',
}
for k,v in spec.items():
    r=smf.glm(base+v,data=c,family=sm.families.Binomial()).fit(scale='X2')
    print(k,'pearson disp',round(r.pearson_chi2/r.df_resid,2), 'llf',round(r.llf,1))
    print(r.params.round(4).to_string()); print(r.pvalues.round(4)[r.pvalues<0.05].to_string()); print()
" 2>&1 | head -150

cd $TMPDIR/an && cat > feat.py <<'EOF'
import pandas as pd, numpy as np
SRC='/tmp/edabench_claude_6osld_dy/'
def days_since_clean(u, events=None):
    ev = pd.read_csv(SRC+'maintenance.csv', parse_dates=['date'])
    ev = ev[ev.event=='mold_cleaning']
    out = np.full(len(u), np.nan)
    for line, g in u.groupby('line'):
        cl = np.sort(ev[ev.line==line].date.values) if events is None else np.sort(events[line])
        idx = g.index
        d = g.date.values
        pos = np.searchsorted(cl, d, side='right')-1   # last cleaning on or before batch date
        last = np.where(pos>=0, cl[np.clip(pos,0,None)], np.datetime64('NaT'))
        out[u.index.get_indexer(idx)] = (d-last).astype('timedelta64[D]').astype(float)
    return out
EOF
python3 -c "
import pandas as pd, numpy as np
from feat import days_since_clean
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
print(u.groupby('line').machine_age_years.describe().round(1))
u['dsc']=days_since_clean(u)
print(u.dsc.describe().round(1))
print(u.dsc.isna().sum())
u['rate']=u.defective_units/u.units_produced
u['b']=pd.cut(u.dsc,[-1,0,3,7,10,14,20,30,60,200])
print(u.groupby('b',observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4))
print(u.groupby(['line','b'],observed=True).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack().round(4))
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from feat import days_since_clean
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
u['post']=((u.line=='L1')&(u.date>='2025-04-14')).astype(int)
u['mold_act']=u.mold_temp-7.7*u.post
u['good']=u.units_produced-u.defective_units
u['dsc']=days_since_clean(u)
c=u.dropna(subset=['mold_temp','humidity_pct']).copy()
c['hum2']=(c.humidity_pct-35)**2
base='defective_units + good ~ '
spec={
 'lin_dsc':'dsc + mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code)',
 'lin_dsc_op':'dsc + mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code) + C(operator_id)',
}
for k,v in spec.items():
    r=smf.glm(base+v,data=c,family=sm.families.Binomial()).fit(scale='X2')
    print(k,'pearson disp',round(r.pearson_chi2/r.df_resid,2), 'llf',round(r.llf,1))
    print(pd.DataFrame({'coef':r.params,'p':r.pvalues}).round(4).head(16).to_string()); print()
" 2>&1 | head -80

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from feat import days_since_clean
pd.set_option('display.width',250)
warnings.filterwarnings('ignore')
u=pd.read_pickle('u.pkl')
u['post']=((u.line=='L1')&(u.date>='2025-04-14')).astype(int)
u['mold_act']=u.mold_temp-7.7*u.post
u['good']=u.units_produced-u.defective_units
u['dsc']=days_since_clean(u)
c=u.dropna(subset=['mold_temp','humidity_pct']).copy()
c['hum2']=(c.humidity_pct-35)**2
r=smf.glm('defective_units + good ~ dsc + mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code) + C(operator_id)',data=c,family=sm.families.Binomial()).fit(scale='X2')
c['mu']=r.predict(c)*c.units_produced
c['pr']=(c.defective_units-c.mu)/np.sqrt(c.mu*(1-r.predict(c)))
c.to_pickle('c_res.pkl')
for l,g in c.groupby('line'):
    g=g.sort_values('date')
    m=g.set_index('date').pr.resample('MS').mean()
    print(l, m.round(2).to_dict().values())
    cs=np.cumsum(g.pr.values-g.pr.mean())
    print(' cusum range', round(cs.min(),1), round(cs.max(),1), ' argmax date', g.date.values[np.argmax(np.abs(cs))])
" 2>&1 | tail -30

cd $TMPDIR/an && cat > scan.py <<'EOF'
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
warnings.filterwarnings('ignore')
c=pd.read_pickle('c_res.pkl')
f='defective_units + good ~ dsc + mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code) + C(operator_id)'
base=smf.glm(f,data=c,family=sm.families.Binomial()).fit()
print('base llf',round(base.llf,1))
out=[]
for line in ['L1','L2','L3','L4']:
    best=None
    dates=sorted(c[c.line==line].date.unique())
    for t in dates[10:-10]:
        d=c.assign(step=((c.line==line)&(c.date>=t)).astype(int))
        r=smf.glm(f+' + step',data=d,family=sm.families.Binomial()).fit()
        if best is None or r.llf>best[1]: best=(pd.Timestamp(t).date(),r.llf,r.params['step'],r.bse['step'])
    out.append((line,best[0],round(best[1]-base.llf,1),round(best[2],3),round(best[3],3)))
for o in out: print(o)
EOF
python3 scan.py

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
u['rate']=u.defective_units/u.units_produced
cut={'L2':'2025-06-16','L3':'2025-07-21'}
for l,t in cut.items():
    g=u[u.line==l]
    pre=g[g.date<t]; post=g[g.date>=t]
    for name,x in [('pre',pre),('post',post)]:
        print(l,name,'n',len(x),'units mean',round(x.units_produced.mean(),1),'defect mean',round(x.defective_units.mean(),1),'rate',round(x.defective_units.sum()/x.units_produced.sum(),4),
              'cyc',round(x.cycle_time_s.mean(),2),'mold',round(x.mold_temp.mean(),1),'hum',round(x.humidity_pct.mean(),1),'qc',round(x.qc_inspection_min.mean(),2),'rework',round(x.rework_cost_eur.mean(),1),'dsc',round(x.dsc.mean(),1) if 'dsc' in x else '')
    print(' shifts/ops', g.groupby(g.date>=t)['operator_id'].nunique().to_dict(), 'supplier mix', g.groupby(g.date>=t)['supplier_code'].value_counts(normalize=True).round(2).to_dict())
"

cd $TMPDIR/an && cat > scan2.py <<'EOF'
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
warnings.filterwarnings('ignore')
c=pd.read_pickle('c_res.pkl')
c['dsc']=c.dsc.astype(float)
c['dsc_c']=c.dsc
rich='dsc + mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code) + C(operator_id) + C(line):(mold_act + ambient_temp_c + dsc + humidity_pct + cycle_time_s)'
base=smf.glm('defective_units + good ~ '+rich,data=c,family=sm.families.Binomial()).fit()
print('rich base llf',round(base.llf,1), 'disp', round(base.pearson_chi2/base.df_resid,2))
for line in ['L2','L3','L1','L4']:
    best=None
    for t in sorted(c[c.line==line].date.unique())[10:-10]:
        d=c.assign(step=((c.line==line)&(c.date>=t)).astype(int))
        r=smf.glm('defective_units + good ~ '+rich+' + step',data=d,family=sm.families.Binomial()).fit()
        if best is None or r.llf>best[1]: best=(pd.Timestamp(t).date(),r.llf,r.params['step'],r.bse['step'])
    print(line,best[0],'dLL',round(best[1]-base.llf,1),'coef',round(best[2],3),'se',round(best[3],3))
EOF
python3 scan2.py

sleep 100; cat /tmp/claude-0/-tmp-edabench-claude-6osld-dy/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bsdtyplx0.output 2>/dev/null | tail -20

cat /tmp/claude-0/-tmp-edabench-claude-6osld-dy/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bsdtyplx0.output | tail -20

cd $TMPDIR/an && timeout 110000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
warnings.filterwarnings('ignore')
c=pd.read_pickle('c_res.pkl')
f='defective_units + good ~ dsc + mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code) + C(operator_id)'
base=smf.glm(f,data=c,family=smf.families.Binomial if False else __import__('statsmodels.api',fromlist=['x']).families.Binomial()).fit()
import statsmodels.api as sm
base=smf.glm(f,data=c,family=sm.families.Binomial()).fit()
res={}
for t in pd.date_range('2025-06-08','2025-06-22'):
    d=c.assign(step=((c.line=='L2')&(c.date>=t)).astype(int))
    r=smf.glm(f+' + step',data=d,family=sm.families.Binomial()).fit()
    res[str(t.date())]=round(r.llf,1)
print('L2 step scan', sorted(res.items(), key=lambda x:-x[1])[:5])
# ramp vs step for L3 and L2
d=c.copy(); d['t']=(d.date-pd.Timestamp('2025-01-01')).dt.days
for line in ['L2','L3']:
    s=d.assign(step=((d.line==line)&(d.date>='2025-06-16')).astype(int) if line=='L2' else ((d.line==line)&(d.date>='2025-07-21')).astype(int))
    rs=smf.glm(f+' + step',data=s,family=sm.families.Binomial()).fit()
    rr=smf.glm(f+' + ramp',data=d.assign(ramp=((d.line==line)*(d.t-d.t.min())/100.0)),family=sm.families.Binomial()).fit()
    print(line,'step llf',round(rs.llf,1),'ramp llf',round(rr.llf,1))
" 

cd $TMPDIR/an && timeout 115000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
warnings.filterwarnings('ignore')
c=pd.read_pickle('c_res.pkl')
c['dscb']=pd.cut(c.dsc,[-1,3,7,10,14,20,30,70],labels=False).astype(str)
f='defective_units + good ~ C(dscb) + mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + C(supplier_code) + C(operator_id)'
base=smf.glm(f,data=c,family=sm.families.Binomial()).fit()
print('base llf',round(base.llf,1),'disp',round(base.pearson_chi2/base.df_resid,2))
print(base.params.filter(like='dscb').round(3).to_string())
for line,t in [('L2','2025-06-16'),('L3','2025-07-21')]:
    d=c.assign(step=((c.line==line)&(c.date>=t)).astype(int))
    r=smf.glm(f+' + step',data=d,family=sm.families.Binomial()).fit()
    print(line,t,'dLL',round(r.llf-base.llf,1),'coef',round(r.params['step'],3),'se',round(r.bse['step'],3))
" 

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
u['rw_per_def']=u.rework_cost_eur/u.defective_units
u['qc_per_def']=u.qc_inspection_min
u['m']=u.date.dt.month
print(u.pivot_table(index='m',columns='line',values='rw_per_def',aggfunc='median').round(2))
print(u.pivot_table(index='m',columns='line',values='rework_cost_eur',aggfunc='sum').div(u.pivot_table(index='m',columns='line',values='defective_units',aggfunc='sum')).round(2))
import statsmodels.formula.api as smf
for l in ['L1','L2','L3','L4']:
    g=u[u.line==l].copy(); g['post']=(g.date>=('2025-06-16' if l=='L2' else '2025-07-21')).astype(int)
    r=smf.ols('rework_cost_eur ~ defective_units + units_produced + post:defective_units',data=g).fit()
    print(l, r.params.round(3).to_dict(), 'R2', round(r.rsquared,3))
"

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
u=pd.read_pickle('u.pkl')
g=u[u.line=='L3'].sort_values('date').copy()
g['ratio']=g.rework_cost_eur/g.defective_units
w=g[(g.date>='2025-07-10')&(g.date<='2025-08-05')]
print(w[['date','batch_id','shift','units_produced','defective_units','rework_cost_eur','ratio','qc_inspection_min']].round(2).to_string())
"

cd $TMPDIR/an && cat > model.py <<'EOF'
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from feat import days_since_clean
warnings.filterwarnings('ignore')
L1_OFFSET = 7.7        # recorded L1 mold temp runs this many C above L2/L4 after the 2025-04-14 sensor change
L3_UNDERCOUNT = 2.2    # L3 recorded defects after 2025-07-21 are about half the rework-implied count
def build():
    u = pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-6osld-dy/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/u.pkl') if False else pd.read_pickle('u.pkl')
    u = u.copy()
    u['post_s'] = ((u.line == 'L1') & (u.date >= '2025-04-15')).astype(int)
    u['mold_act'] = u.mold_temp - L1_OFFSET * u.post_s
    u['dsc'] = days_since_clean(u)
    u['hum2'] = (u.humidity_pct - 35) ** 2
    u['step_L2'] = ((u.line == 'L2') & (u.date >= '2025-06-16')).astype(int)
    u['def_true'] = u.defective_units.astype(float)
    m = (u.line == 'L3') & (u.date >= '2025-07-21')
    u.loc[m, 'def_true'] = u.loc[m, 'defective_units'] * L3_UNDERCOUNT
    u['good'] = u.units_produced - u.def_true
    return u
EOF
python3 -c "
import pandas as pd, numpy as np
from model import build
u=build()
print(u[['mold_act','dsc','def_true','good']].describe().round(2).to_string())
print('L3 post def_true > units:', (u.def_true>u.units_produced).sum())
q=u.qc_inspection_min
import statsmodels.formula.api as smf
r=smf.ols('qc_inspection_min ~ defective_units + C(line)',data=u[(u.date<'2025-07-21')|(u.line!='L3')]).fit()
print('qc~defect R2',round(r.rsquared,3), r.params['defective_units'].round(4))
" 2>&1 | tail -20

cd $TMPDIR/an && cat > lrt.py <<'EOF'
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
from model import build
warnings.filterwarnings('ignore')
u=build()
c=u.dropna(subset=['mold_act','humidity_pct','dsc']).copy()
c['good']=c.units_produced-c.def_true
base_terms='mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + machine_age_years + dsc + step_L2 + C(shift) + C(line) + C(supplier_code) + C(operator_id)'
def fit(terms):
    return smf.glm('def_true + good ~ '+terms,data=c,family=sm.families.Binomial()).fit()
full=fit(base_terms)
phi=full.pearson_chi2/full.df_resid
print('n',len(c),'dispersion',round(phi,2))
tests={
 'mold_act':['mold_act'],
 'humidity (lin+quad)':['humidity_pct','hum2'],
 'cycle_time_s':['cycle_time_s'],
 'ambient_temp_c':['ambient_temp_c'],
 'machine_age_years':['machine_age_years'],
 'operator_id':['C(operator_id)'],
 'shift':['C(shift)'],
 'dsc':['dsc'],
 'supplier_code':['C(supplier_code)'],
 'line':['C(line)'],
}
terms_list=base_terms.split(' + ')
for name,drop in tests.items():
    rest=[t for t in terms_list if t not in drop]
    r=fit(' + '.join(rest))
    dd=(r.deviance-full.deviance)
    df=full.df_model-r.df_model if False else (len(r.params)-len(full.params))
    F=dd/phi/abs(df)
    p=1-stats.f.cdf(F,abs(df),full.df_resid)
    print(f'{name:22s} df={abs(df):3d} scaledDev={dd/phi:8.1f} p={p:.2e}')
EOF
timeout 115000 python3 lrt.py

cd $TMPDIR/an && timeout 115000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
import model
warnings.filterwarnings('ignore')
base='mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + dsc + step_L2 + C(shift) + C(line) + C(supplier_code)'
for off in [0,5,7.7,10]:
    model.L1_OFFSET=off
    u=model.build()
    c=u.dropna(subset=['mold_act','humidity_pct','dsc']).copy()
    f=lambda t: smf.glm('def_true + good ~ '+t,data=c.assign(good=c.units_produced-c.def_true),family=sm.families.Binomial()).fit()
    full=f(base); phi=full.pearson_chi2/full.df_resid
    red=f(base.replace(' + ambient_temp_c',''))
    dd=(red.deviance-full.deviance)/phi
    print('offset',off,'ambient coef',round(full.params['ambient_temp_c'],4),'scaled dLR',round(dd,1),'p',round(stats.chi2.sf(dd,1),5))
"

cd $TMPDIR/an && timeout 115000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
import model
warnings.filterwarnings('ignore')
model.L1_OFFSET=0
u=model.build()
u['L1post']=u.post_s
c=u.dropna(subset=['mold_temp','humidity_pct','dsc']).copy()
c['good']=c.units_produced-c.def_true
base='mold_temp + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + dsc + step_L2 + C(shift) + C(line) + C(supplier_code) + L1post'
f=lambda t: smf.glm('def_true + good ~ '+t,data=c,family=sm.families.Binomial()).fit()
full=f(base); phi=full.pearson_chi2/full.df_resid
print('mold coef',round(full.params['mold_temp'],4),'L1post coef',round(full.params['L1post'],3),'ambient',round(full.params['ambient_temp_c'],4), 'se amb', round(full.bse['ambient_temp_c'],4))
for name in ['ambient_temp_c','L1post']:
    red=f(base.replace(' + '+name,''))
    dd=(red.deviance-full.deviance)/phi
    print(name,'scaled dLR',round(dd,1),'p',round(stats.chi2.sf(dd,1),5))
" 

cd $TMPDIR/an && timeout 115000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
import model
warnings.filterwarnings('ignore')
model.L1_OFFSET=7.7
u=model.build()
for lines in [['L2','L4'],['L1'],['L3'],['L1','L2','L3','L4']]:
    c=u[u.line.isin(lines)].dropna(subset=['mold_act','humidity_pct','dsc']).copy()
    c['good']=c.units_produced-c.def_true
    terms='mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + dsc + step_L2 + C(shift) + C(supplier_code)'+('' if len(lines)==1 else ' + C(line)')
    f=lambda t: smf.glm('def_true + good ~ '+t,data=c,family=sm.families.Binomial()).fit()
    full=f(terms); phi=full.pearson_chi2/full.df_resid
    out=[]
    for name in ['ambient_temp_c','mold_act','shift']:
        if name=='shift': red=f(terms.replace(' + C(shift)',''))
        else: red=f(terms.replace(' + '+name,''))
        dd=(red.deviance-full.deviance)/phi
        out.append((name,round(dd,1),round(stats.chi2.sf(dd,1),4)))
    print(lines,'n',len(c),'disp',round(phi,2),out)
" 

cd $TMPDIR/an && timeout 115000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.formula.api as smf
import statsmodels.api as sm
from scipy import stats
import model
warnings.filterwarnings('ignore')
model.L1_OFFSET=7.7
u=model.build()
def test(name,c,terms):
    c=c.dropna(subset=['mold_act','humidity_pct','dsc']).copy(); c['good']=c.units_produced-c.def_true
    f=lambda t: smf.glm('def_true + good ~ '+t,data=c,family=sm.families.Binomial()).fit()
    full=f(terms); phi=full.pearson_chi2/full.df_resid
    res=[]
    for drop in ['ambient_temp_c','mold_act','shift']:
        parts=[p.strip() for p in terms.split('+')]
        rest=' + '.join([p for p in parts if p!=drop]) if drop!='shift' else ' + '.join([p for p in parts if p!='C(shift)'])
        red=f(rest)
        dd=(red.deviance-full.deviance)/phi
        res.append((drop, round(full.params.get(drop,np.nan),4) if drop in full.params else '', round(dd,1), round(stats.chi2.sf(dd,1),4)))
    print(name,'n',len(c),'disp',round(phi,2),res)
T='mold_act + humidity_pct + hum2 + cycle_time_s + ambient_temp_c + dsc + C(shift) + C(supplier_code)'
test('L4 only', u[u.line=='L4'], T)
test('L2 pre-step', u[(u.line=='L2')&(u.date<'2025-06-16')], T)
test('L2 all w/ step', u[u.line=='L2'], T+' + step_L2')
" 

cd $TMPDIR/an && timeout 115000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
import model
warnings.filterwarnings('ignore')
model.L1_OFFSET=7.7
u=model.build()
c=u.dropna(subset=['mold_act','humidity_pct','dsc']).copy(); c['good']=c.units_produced-c.def_true
c['dscb']=pd.cut(c.dsc,[-1,3,7,10,14,20,30,70],labels=False).astype(str)
F='def_true + good ~ '
core='mold_act + humidity_pct + hum2 + cycle_time_s + dsc + step_L2 + C(shift) + C(line) + C(supplier_code)'
def fit(t): return smf.glm(F+t,data=c,family=sm.families.Binomial()).fit()
full=fit(core); phi=full.pearson_chi2/full.df_resid
print('core disp',round(phi,2), 'llf',round(full.llf,1))
for name,extra in [('sup x humidity (lin)', 'C(supplier_code):humidity_pct'),('sup x hum2','C(supplier_code):hum2'),('sup x cycle','C(supplier_code):cycle_time_s'),('sup x mold','C(supplier_code):mold_act'),('sup x dsc','C(supplier_code):dsc'), ('dsc binned instead', None)]:
    if extra is None:
        r=fit(core.replace('dsc','C(dscb)'))
    else: r=fit(core+' + '+extra)
    dd=(r.deviance-full.deviance)/phi if extra else (r.deviance-full.deviance)/phi
    df=len(r.params)-len(full.params)
    print(name,'df',df,'scaled dLR',round(dd,1),'p',round(stats.chi2.sf(dd,abs(df)),5) if extra else '')
print(pd.DataFrame({'coef':full.params,'p':full.pvalues}).round(4).to_string())
" 

cd $TMPDIR/an && timeout 115000 python3 -c "
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
import model
warnings.filterwarnings('ignore')
model.L1_OFFSET=7.7
u=model.build()
c=u.dropna(subset=['mold_act','humidity_pct','dsc']).copy(); c['good']=c.units_produced-c.def_true
c['hb']=pd.cut(c.humidity_pct,[10,20,25,30,35,40,45,50,55,60,75])
c['rate_adj']=c.def_true/c.units_produced
print(c.groupby(['supplier_code','hb'],observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.def_true.sum()/g.units_produced.sum()})).unstack(0).round(4).to_string())
" 

cd $TMPDIR/an && cat > final_model.py <<'EOF'
import pandas as pd, numpy as np, warnings
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
import model
warnings.filterwarnings('ignore')
model.L1_OFFSET=7.7
u=model.build()
c=u.dropna(subset=['mold_act','humidity_pct','dsc']).copy()
c['good']=c.units_produced-c.def_true
DSC_BINS=[-1,3,7,10,14,20,30,70]
c['dscb']=pd.cut(c.dsc,DSC_BINS,labels=False).astype(str)
def fit(terms,data=c):
    return smf.glm('def_true + good ~ '+terms,data=data,family=sm.families.Binomial()).fit()
EOF
timeout 115000 python3 -c "
from final_model import *
terms='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):(humidity_pct + hum2)'
r=fit(terms)
print('disp',round(r.pearson_chi2/r.df_resid,2))
print(r.params.round(4).to_string())
for s in ['SP-01','SP-02','SP-03']:
    b=r.params['humidity_pct'] if s=='SP-01' else r.params['humidity_pct']+r.params[f'C(supplier_code)[{s}]:humidity_pct']
    a=r.params['hum2'] if s=='SP-01' else r.params['hum2']+r.params[f'C(supplier_code)[{s}]:hum2']
    print(s,'a',round(a,5),'b',round(b,5),'argmin',round(-b/(2*a),2) if a>0 else 'no min')
"


cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
import patsy
terms_q='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):(humidity_pct + hum2)'
rq=fit(terms_q)
grid=np.arange(12,72.5,0.5)
def curve(r, sup, hfun):
    d=pd.DataFrame({'humidity_pct':grid,'hum2':(grid-35)**2})
    d['supplier_code']=sup; d['mold_act']=211.6; d['cycle_time_s']=31.5; d['dscb']='0'; d['step_L2']=0; d['shift']='Day'; d['line']='L1'
    return r.predict(d)
for s in ['SP-01','SP-02','SP-03']:
    p=curve(rq,s,None)
    print('quad',s,'argmin h=',grid[np.argmin(p.values)],'min rate',round(p.min(),4))
# spline check (natural cubic via patsy cr) with supplier interaction
terms_s='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):cr(humidity_pct, df=5)'
rs=smf.glm('def_true + good ~ '+terms_s,data=c,family=sm.families.Binomial()).fit()
print('spline disp',round(rs.pearson_chi2/rs.df_resid,2),'llf quad',round(rq.llf,1),'llf spline',round(rs.llf,1))
for s in ['SP-01','SP-02','SP-03']:
    d=pd.DataFrame({'humidity_pct':grid})
    d['supplier_code']=s; d['mold_act']=211.6; d['cycle_time_s']=31.5; d['dscb']='0'; d['step_L2']=0; d['shift']='Day'; d['line']='L1'
    p=rs.predict(d)
    print('spline',s,'argmin h=',grid[np.argmin(p.values)],'min rate',round(p.min(),4))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
grid=np.arange(12,72.01,0.1)
for df in [3,4,5,6,7]:
    t='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):cr(humidity_pct, df=%d)'%df
    r=smf.glm('def_true + good ~ '+t,data=c,family=sm.families.Binomial()).fit()
    d=pd.DataFrame({'humidity_pct':grid,'supplier_code':'SP-01','mold_act':211.6,'cycle_time_s':31.5,'dscb':'0','step_L2':0,'shift':'Day','line':'L1'})
    p=r.predict(d).values
    print('df',df,'SP-01 argmin',round(grid[np.argmin(p)],1),'llf',round(r.llf,1))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
t0='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code)'
r0=smf.glm('def_true + good ~ '+t0,data=c,family=sm.families.Binomial()).fit()
c['lp0']=r0.predict(c,linear=True)
a=c[c.supplier_code=='SP-01'].copy()
a['hb']=pd.cut(a.humidity_pct,[10,15,20,25,30,35,40,45,50,55,60,75])
f=smf.glm('def_true + good ~ C(hb) + 0',data=a.assign(hb=a.hb.astype(str)),offset=a.lp0,family=sm.families.Binomial()).fit()
out=pd.DataFrame({'coef':f.params,'se':f.bse}).round(3)
out['rate_at_mean']=(1/(1+np.exp(-out.coef)))
print(out.to_string())
" 2>&1 | grep -v Warn

cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
t0='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code)'
r0=smf.glm('def_true + good ~ '+t0,data=c,family=sm.families.Binomial()).fit()
c['lp0']=r0.predict(c,which='linear') if False else np.log(r0.predict(c)/(1-r0.predict(c)))
a=c[c.supplier_code=='SP-01'].copy()
a['hb']=pd.cut(a.humidity_pct,[10,15,20,25,30,35,40,45,50,55,60,75]).astype(str)
f=smf.glm('def_true + good ~ C(hb) - 1',data=a,offset=a.lp0,family=sm.families.Binomial()).fit()
out=pd.DataFrame({'coef':f.params,'se':f.bse,'n':a.groupby('hb').size()}).round(3)
out['rate_at_offset0']=(1/(1+np.exp(-out.coef)))
print(out.to_string())
" 2>&1 | grep -v Warn

cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
t0='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code)'
r0=smf.glm('def_true + good ~ '+t0,data=c,family=sm.families.Binomial()).fit()
p0=r0.predict(c); c['lp0']=np.log(p0/(1-p0))
a=c[c.supplier_code=='SP-01'].copy()
for edges in [np.arange(10,45.1,2.5), np.arange(12,46,4), np.arange(10,40.1,5)]:
    hb=pd.cut(a.humidity_pct,edges)
    f=smf.glm('def_true + good ~ C(hb) - 1',data=a.assign(hb=hb.astype(str)),offset=a.lp0,family=sm.families.Binomial()).fit()
    co=f.params; mids=[(iv.left+iv.right)/2 for iv in hb.cat.categories]
    ser=pd.Series(co.values,index=[str(x) for x in f.params.index])
    k=np.array([ (lambda s: float(s.split(',')[0][1:]) if False else 0)(x) for x in co.index])
    idx=np.argmin(co.values)
    # vertex of quadratic fit over bins with coefficient
    x=np.array(mids); y=co.values
    ok=np.isfinite(y)
    cf=np.polyfit(x[ok],y[ok],2); vert=-cf[1]/(2*cf[0]) if cf[0]>0 else np.nan
    print('bins',len(edges)-1,'min bin',hb.cat.categories[idx] if False else co.index[idx],'quadratic vertex',round(vert,2))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
import patsy
recipe={'SP-01':30,'SP-02':30,'SP-03':36}
specs={
 'quad': 'mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):(humidity_pct + hum2)',
 'spline5': 'mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):cr(humidity_pct, df=5)',
 'spline4': 'mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):cr(humidity_pct, df=4)',
}
for name,t in specs.items():
    r=smf.glm('def_true + good ~ '+t,data=c,family=sm.families.Binomial()).fit()
    p_act=r.predict(c).values
    rows=[]
    for s in ['SP-01','SP-02','SP-03']:
        d=c.copy(); d['supplier_code']=s; d['cycle_time_s']=recipe[s]
        p_s=r.predict(d).values
        ratio_rate=(c.defective_units.values*p_s/p_act).sum()/c.units_produced.sum()
        model_rate=(c.units_produced.values*p_s).sum()/c.units_produced.sum()
        rows.append((s,round(ratio_rate,5),round(model_rate,5)))
    print(name, rows)
    # actual baseline for reference
    print('  actual recorded rate', round(c.defective_units.sum()/c.units_produced.sum(),5), ' model-actual', round((c.units_produced*p_act).sum()/c.units_produced.sum(),5))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > cf_clean.py <<'EOF'
import pandas as pd, numpy as np
SRC='/tmp/edabench_claude_6osld_dy/'
def cf_schedule(max_gap=14, end=pd.Timestamp('2025-09-30')):
    ev=pd.read_csv(SRC+'maintenance.csv',parse_dates=['date'])
    ev=ev[ev.event=='mold_cleaning']
    sched={}
    for line,g in ev.groupby('line'):
        acts=sorted(g.date)
        cl=[acts[0]]
        for nxt in acts[1:]:
            while (nxt-cl[-1]).days>max_gap:
                cl.append(cl[-1]+pd.Timedelta(days=max_gap))
            cl.append(nxt)
        while (end-cl[-1]).days>=max_gap:
            cl.append(cl[-1]+pd.Timedelta(days=max_gap))
        sched[line]=cl
    return sched
def dsc_from(sched, df):
    out=np.full(len(df),np.nan)
    for line in sched:
        m=(df.line==line).values
        cl=np.array(sched[line],dtype='datetime64[ns]')
        d=df.date.values[m].astype('datetime64[ns]')
        pos=np.searchsorted(cl,d,side='right')-1
        last=cl[np.clip(pos,0,None)]
        out[m]=((d-last)/np.timedelta64(1,'D')).astype(float)
    return out
EOF
python3 -c "
from cf_clean import *
import pandas as pd
s=cf_schedule()
for k,v in s.items(): print(k, len(v), [x.strftime('%m-%d') for x in v][:12])
"

cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
from cf_clean import cf_schedule, dsc_from, SRC
import pandas as pd
act_sched={}
ev=pd.read_csv(SRC+'maintenance.csv',parse_dates=['date']); ev=ev[ev.event=='mold_cleaning']
for l,g in ev.groupby('line'): act_sched[l]=sorted(g.date)
chk=dsc_from(act_sched,c)
print('actual dsc reproduced:', np.allclose(chk,c.dsc.values))
cf=cf_schedule()
c['dsc_cf']=dsc_from(cf,c)
c['dscb_cf']=pd.cut(c.dsc_cf,DSC_BINS,labels=False).astype(str)
print('max cf dsc',c.dsc_cf.max(), 'mean actual dsc',round(c.dsc.mean(),2),'mean cf dsc',round(c.dsc_cf.mean(),2))
specs={
 'quad': 'mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):(humidity_pct + hum2)',
 'spline5': 'mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):cr(humidity_pct, df=5)',
 'spline4': 'mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):cr(humidity_pct, df=4)',
}
for name,t in specs.items():
    r=smf.glm('def_true + good ~ '+t,data=c,family=sm.families.Binomial()).fit()
    p_act=r.predict(c).values
    d=c.copy(); d['dscb']=d.dscb_cf
    p_cf=r.predict(d).values
    ratio=(c.defective_units.values*p_cf/p_act).sum()/c.units_produced.sum()
    model=(c.units_produced.values*p_cf).sum()/c.units_produced.sum()
    base=(c.defective_units.values).sum()/c.units_produced.sum()
    print(name,'recorded-baseline cf rate',round(ratio,5),'model-only cf rate',round(model,5),'recorded actual rate',round(base,5))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && timeout 115000 python3 -c "
from final_model import *
from cf_clean import cf_schedule, dsc_from
import model
u=model.build()
u=u.dropna(subset=['mold_act','dsc']).copy()
print('batches with mold & dsc',len(u),' missing humidity',u.humidity_pct.isna().sum())
# training set = complete cases
tr=u.dropna(subset=['humidity_pct']).copy()
tr['good']=tr.units_produced-tr.def_true; tr['dscb']=pd.cut(tr.dsc,DSC_BINS,labels=False).astype(str)
t='mold_act + cycle_time_s + C(dscb) + step_L2 + C(shift) + C(line) + C(supplier_code) + C(supplier_code):cr(humidity_pct, df=5)'
r=smf.glm('def_true + good ~ '+t,data=tr,family=sm.families.Binomial()).fit()
# impute missing humidity with the line-supplier median (only used to score the counterfactual)
u['hum_imp']=u.humidity_pct.fillna(u.groupby(['line','supplier_code']).humidity_pct.transform('median'))
u['humidity_pct']=u.hum_imp; u['hum2']=(u.hum_imp-35)**2
u['good']=u.units_produced-u.def_true; u['dscb']=pd.cut(u.dsc,DSC_BINS,labels=False).astype(str)
p_act=r.predict(u).values
recipe={'SP-01':30,'SP-02':30,'SP-03':36}
for s in ['SP-01','SP-02','SP-03']:
    d=u.copy(); d['supplier_code']=s; d['cycle_time_s']=recipe[s]
    p=r.predict(d).values
    print('supplier cf',s, round((u.defective_units.values*p/p_act).sum()/u.units_produced.sum(),5))
cf=cf_schedule(); u['dsc_cf']=dsc_from(cf,u); u['dscb_cf']=pd.cut(u.dsc_cf,DSC_BINS,labels=False).astype(str)
d=u.copy(); d['dscb']=d.dscb_cf
p_cf=r.predict(d).values
print('C3 all-batch ratio approach', round((u.defective_units.values*p_cf/p_act).sum()/u.units_produced.sum(),5))
print('actual recorded all batches', round(u.defective_units.sum()/u.units_produced.sum(),5))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && python3 -c "
import pandas as pd, numpy as np
import model
u=model.build()
mv=u.mold_temp.notna()
print('valid mold batches',mv.sum(),' A2 humidity invalid/missing',u.humidity_pct.isna().sum(), ' A1 unique',len(u))
raw=u.loc[mv,'mold_temp']
print('median recorded, L3 F->C and zeros removed, no L1 fix:',round(raw.median(),3))
print('median actual (L1 post corrected by 7.7):',round(u.loc[mv,'mold_act'].median(),3))
for off in [7.6,8.0]:
    print(' with offset',off, round((u.loc[mv,'mold_temp']-off*u.loc[mv,'post_s']).median(),3))
print('A3 overall', round(u.defective_units.sum()/u.units_produced.sum(),6))
print('batches total units', u.units_produced.sum(), 'defective', u.defective_units.sum())
"

cd $TMPDIR/an && python3 -c "
import pandas as pd
import model
u=model.build()
g=u[(u.line=='L2')&(u.date>='2025-06-08')&(u.date<='2025-06-22')].sort_values('date')
g=g.assign(rate=g.def_true/g.units_produced)
print(g[['date','batch_id','shift','units_produced','defective_units','rate']].round(3).to_string(index=False))
"
