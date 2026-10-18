ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && cat maintenance.csv && echo && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('---',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    print(vc.head(12).to_dict())
"

python3 -c "
import pandas as pd, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
# date formats
pat=df.production_date.str.replace(r'\d','9',regex=True)
print(pat.value_counts())
print(df[pat!='9999-99-99'].production_date.head(20).tolist())
print('shift all:',sorted(df['shift'].unique()))
print('supplier all:',sorted(df.supplier_code.unique()))
print('lines',sorted(df.line.unique()))
print('batch id pattern',df.batch_id.str.replace(r'\d','9',regex=True).value_counts().to_dict())
# duplicates
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d), 'dup ids',d.batch_id.nunique())
print(d.head(20).to_string())
print('exact dup rows:',df.duplicated().sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ex=df.drop_duplicates()
print('after exact dedup',len(ex), 'unique ids',ex.batch_id.nunique())
g=ex[ex.batch_id.duplicated(keep=False)].sort_values(['batch_id','line'])
print(g.groupby('batch_id').line.apply(list).head(40).to_string())
print('ids w/ >1 line:',(ex.groupby('batch_id').line.nunique()>1).sum())
print('ids w/ 3 rows', (df.batch_id.value_counts()>=3).sum())
print(df[df.batch_id=='B-30386'].to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ex=df.drop_duplicates()
print('unique (id,line):', ex[['batch_id','line']].drop_duplicates().shape[0], 'rows', len(ex))
s=ex.production_date
iso=s.str.match(r'^\d{4}-')
sl=s.str.match(r'^\d{2}/\d{2}/\d{4}$')
a=s.str.slice(0,2).astype(int); b=s.str.slice(3,5).astype(int)
ambig=sl&(a<=12)&(b<=12)
dmy=sl&(a>12)
mdy=sl&(b>12)
print('iso',iso.sum(),'dmy',dmy.sum(),'mdy',mdy.sum(),'ambig',ambig.sum())
# row order check
idx=np.arange(len(ex))
iso_d=pd.to_datetime(s[iso])
print('ISO dates within range?', iso_d.min(), iso_d.max())
print('iso rows index monotone?', np.corrcoef(idx[iso], iso_d.map(pd.Timestamp.toordinal))[0,1])
print(ex.production_date.head(30).tolist())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ex=df.drop_duplicates().reset_index(drop=True)
s=ex.production_date
iso=s.str.match(r'^\d{4}-\d{2}-\d{2}$')
sl=s.str.match(r'^\d{2}/\d{2}/\d{4}$')
print('iso',iso.sum(),'slash',sl.sum(),'other',(~iso&~sl).sum())
p=s[sl].str.split('/',expand=True).astype(int)
a=p[0]; b=p[1]
print('dmy (first>12)',(a>12).sum(),'mdy (second>12)',(b>12).sum(),'ambig',((a<=12)&(b<=12)).sum())
print('first-part==second... equal',(a==b).sum())
iso_d=pd.to_datetime(s[iso])
print('ISO range', iso_d.min(), iso_d.max())
print('ISO month counts', iso_d.dt.month.value_counts().sort_index().to_dict())
print('first 40 dates:', s.head(40).tolist())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ex=df.drop_duplicates().reset_index(drop=True)
s=ex.production_date
def cands(x):
    if '-' in x: return [pd.Timestamp(x)]
    a,b,y=map(int,x.split('/'))
    out=set()
    for m,d in [(a,b),(b,a)]:
        try: out.add(pd.Timestamp(y,m,d))
        except ValueError: pass
    return sorted(out)
c=[cands(x) for x in s]
known=[ (i,v[0]) for i,v in enumerate(c) if len(v)==1]
kidx=np.array([k[0] for k in known]); kd=pd.Series([k[1] for k in known])
print('monotone among known:', (kd.diff().dropna()>=pd.Timedelta(0)).all())
viol=np.where(np.diff(kd.values)<np.timedelta64(0))[0]
print('violations',len(viol))
for v in viol[:10]: print(kidx[v],kidx[v+1],kd.iloc[v],kd.iloc[v+1])
" 2>&1 | tail -20

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ex=df.drop_duplicates().reset_index(drop=True)
s=ex.production_date
def cands(x):
    if '-' in x: return [pd.Timestamp(x)]
    a,b,y=map(int,x.split('/'))
    out=set()
    for m,d in [(a,b),(b,a)]:
        try: out.add(pd.Timestamp(y,m,d))
        except ValueError: pass
    return sorted(out)
ex['cands']=[cands(x) for x in s]
ex['idx']=range(len(ex))
print(ex[['line','shift']].head(30).T.to_string())
print(ex.line.tolist()[:60])
# segments: runs of line
seg=(ex.line!=ex.line.shift()).cumsum()
print('line runs', seg.nunique())
"

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ex=df.drop_duplicates().reset_index(drop=True)
print(ex.loc[60:80,['batch_id','production_date','line','shift','operator_id']].to_string())
print(ex.loc[1165:1178,['batch_id','production_date','line','shift']].to_string())
"

python3 -c "
import pandas as pd
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
for b in ['B-93896','B-97329','B-23690','B-41881','B-42637','B-12109']:
    print(df[df.batch_id==b].to_string(header=False)); print()
"

mkdir -p $TMPDIR/s && cd /tmp/edabench_claude_d3fq9ip2 && python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x=pd.to_numeric(df[c],errors='coerce')
    print(c,'nonnum',x.isna().sum(), 'min',x.min(),'q01',round(x.quantile(.01),2),'med',x.median(),'q99',round(x.quantile(.99),2),'max',x.max())
    print('   value_counts top', x.value_counts().head(5).to_dict())
"

python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
df['h']=pd.to_numeric(df.humidity_pct,errors='coerce')
df['m']=pd.to_numeric(df.mold_temp,errors='coerce')
df['row']=range(len(df))
df['pos']=pd.cut(df.row,8,labels=False)
print(df[df.h==50.2].groupby(['line']).size())
print(df[df.h==50.2].row.describe())
print(df[df.h==50.2][['batch_id','production_date','line','shift','humidity_pct','ambient_temp_c']].head(12).to_string())
print('humidity -1 by line', df[df.h==-1].groupby('line').size().to_dict(), 'blank by line', df[df.humidity_pct==''].groupby('line').size().to_dict())
print('mold 0 by line', df[df.m==0].groupby('line').size().to_dict())
print('mold>300 by line', df[df.m>300].groupby('line').size().to_dict(), (df.m>300).sum())
print(np.histogram(df.m[df.m>0],bins=[0,150,180,200,230,260,300,350,380,400,420,440,470])[0])
"

python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
df['h']=pd.to_numeric(df.humidity_pct,errors='coerce')
df['m']=pd.to_numeric(df.mold_temp,errors='coerce')
df['row']=range(len(df))
# approximate date via neighbors later; first check 50.2 row range
r=df[df.h==50.2].row
print('50.2 rows range', r.min(), r.max(), 'count',len(r))
print(df.loc[r.min()-3:r.min()+3,['batch_id','production_date','line','humidity_pct']].to_string())
print(df.loc[r.max()-3:r.max()+3,['batch_id','production_date','line','humidity_pct']].to_string())
l2=df[df.line=='L2']
print('L2 humidity 50.2 share in L2 rows:', (l2.h==50.2).mean())
print(df[df.line=='L3'].m.describe())
print(df[(df.line=='L3')&(df.m<300)][['batch_id','production_date','mold_temp']].to_string())
print(df[(df.line!='L3')].m.describe())
"

python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250)
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
df['h']=pd.to_numeric(df.humidity_pct,errors='coerce')
df['row']=range(len(df))
iso=df.production_date.str.match(r'^\d{4}-')
d=df[iso].copy(); d['date']=pd.to_datetime(d.production_date)
l2=d[d.line=='L2']
print(l2[l2.h==50.2].date.agg(['min','max']), len(l2[l2.h==50.2]))
x=l2[(l2.date>='2025-03-01')&(l2.date<='2025-09-30')]
print(x.groupby(x.date.dt.to_period('M')).apply(lambda g:(g.h==50.2).mean()).round(2).to_dict())
print(d[d.h==50.2][['batch_id','production_date','line','shift']].to_string())
"

cat > $TMPDIR/s/clean.py <<'EOF'
import pandas as pd, numpy as np

RAW = '/tmp/edabench_claude_d3fq9ip2/'

def parse_date(x):
    if '-' in x:
        return pd.Timestamp(x)
    a, b, y = map(int, x.split('/'))
    if a > 12:
        return pd.Timestamp(y, b, a)
    if b > 12:
        return pd.Timestamp(y, a, b)
    return None  # ambiguous, resolved below

def load_raw():
    return pd.read_csv(RAW + 'batches.csv', dtype=str, keep_default_na=False)

def load():
    df = load_raw().drop_duplicates().reset_index(drop=True)
    df['date'] = [parse_date(x) for x in df.production_date]
    # resolve ambiguous dd/mm vs mm/dd using the nearest resolved dates of the same line in file order
    for i in np.where(df.date.isna())[0]:
        a, b, y = map(int, df.production_date[i].split('/'))
        cands = [pd.Timestamp(y, a, b), pd.Timestamp(y, b, a)]
        same = df[(df.line == df.line[i]) & df.date.notna()]
        before = same[same.index < i].date.tail(15)
        after = same[same.index > i].date.head(15)
        ref = pd.concat([before, after]).median()
        df.loc[i, 'date'] = min(cands, key=lambda c: abs((c - ref).days))
    shift_map = {'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'}
    df['shift'] = df['shift'].str.strip().str.lower().map(shift_map)
    df['supplier_code'] = df.supplier_code.str.strip().str.upper()
    df['humidity_raw'] = pd.to_numeric(df.humidity_pct, errors='coerce')
    df['mold_raw'] = pd.to_numeric(df.mold_temp, errors='coerce')
    for c in ['machine_age_years','ambient_temp_c','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
        df[c] = pd.to_numeric(df[c])
    return df

if __name__ == '__main__':
    df = load()
    print(df.shape, df.date.isna().sum(), df['shift'].value_counts(dropna=False).to_dict(), df.supplier_code.value_counts().to_dict())
EOF
python3 $TMPDIR/s/clean.py && python3 -c "
import sys; sys.path.insert(0,'$TMPDIR/s')
from clean import *
df=load()
print('date range',df.date.min(),df.date.max())
print('defect>units',(df.defective_units>df.units_produced).sum(), 'defect==0',(df.defective_units==0).sum())
df['rate']=df.defective_units/df.units_produced
print(df[['rate','qc_inspection_min','rework_cost_eur','defective_units','units_produced','cycle_time_s','humidity_raw','mold_raw','machine_age_years','ambient_temp_c']].corr().round(3).to_string())
df['rwc']=df.rework_cost_eur/df.defective_units
print(df.rwc.describe().round(3))
"

python3 -c "
import sys; sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.api as sm
df=load()
df['rate']=df.defective_units/df.units_produced
X=sm.add_constant(df[['defective_units','units_produced']])
for y in ['qc_inspection_min','rework_cost_eur']:
    m=sm.OLS(df[y],X).fit(); print(y,'R2 on defects+units',round(m.rsquared,4))
X2=sm.add_constant(np.column_stack([df.defective_units,df.units_produced,df.rate]))
m=sm.OLS(df.qc_inspection_min,sm.add_constant(df[['defective_units','units_produced','mold_raw','ambient_temp_c','machine_age_years','cycle_time_s']].fillna(0))).fit(); print('qc full R2',round(m.rsquared,3))
df['mold_c']=np.where(df.line=='L3',(df.mold_raw-32)*5/9,df.mold_raw)
df.loc[df.mold_raw==0,'mold_c']=np.nan
print(df.groupby('line').mold_c.describe().round(1).to_string())
" 2>&1 | grep -v Warning

cat >> $TMPDIR/s/clean.py <<'EOF'

def clean():
    df = load()
    df['mold_temp_c'] = np.where(df.line == 'L3', (df.mold_raw - 32) * 5 / 9, df.mold_raw)
    df.loc[df.mold_raw == 0, 'mold_temp_c'] = np.nan
    stuck = (df.line == 'L2') & (df.humidity_raw == 50.2) & (df.date >= '2025-03-03') & (df.date <= '2025-04-13')
    df['humidity_ok'] = df.humidity_raw.where((df.humidity_raw >= 0) & ~stuck)
    df['rate'] = df.defective_units / df.units_produced
    df['supplier_name'] = df.supplier_code.map({'SP-01': 'Alpha', 'SP-02': 'Beta', 'SP-03': 'Gamma'})
    return df
EOF
python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf
df=clean()
print('humidity missing/invalid rows', df.humidity_ok.isna().sum(), 'blank',(df.humidity_pct=='').sum(), '-1',(df.humidity_raw==-1).sum(), 'stuck', ((df.line=='L2')&(df.humidity_raw==50.2)&(df.date>='2025-03-03')&(df.date<='2025-04-13')).sum())
print('mold missing', df.mold_temp_c.isna().sum())
d=df.dropna(subset=['humidity_ok','mold_temp_c']).copy()
print('model rows', len(d))
d['ov']=d.defective_units; d['tot']=d.units_produced
d['cyc_dev']=d.cycle_time_s-d.supplier_code.map({'SP-01':30,'SP-02':30,'SP-03':36})
f='rate ~ mold_temp_c + humidity_ok + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)'
m=smf.glm('defective_units + I(units_produced-defective_units) ~ 1',data=d,family=sm.families.Binomial()) if False else None
import statsmodels.api as sm
y=np.column_stack([d.defective_units, d.units_produced-d.defective_units])
m=smf.glm(f,data=d,family=sm.families.Binomial(),freq_weights=None)
" 2>&1 | tail -5

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
df=clean()
d=df.dropna(subset=['humidity_ok','mold_temp_c']).copy()
d['cyc_dev']=d.cycle_time_s-d.supplier_code.map({'SP-01':30,'SP-02':30,'SP-03':36})
f='rate ~ mold_temp_c + humidity_ok + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)'
m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
print(m.summary2().tables[1].loc[['mold_temp_c','humidity_ok','cycle_time_s','machine_age_years','ambient_temp_c']].round(4).to_string())
print(m.summary2().tables[1].loc[lambda t: t.index.str.contains('shift|supplier|line')].round(4).to_string())
print('C(operator) p-values min/max', m.pvalues[m.pvalues.index.str.contains('operator')].agg(['min','max']).round(3).to_dict())
print('dispersion (pearson chi2/df)', round(m.pearson_chi2/m.df_resid,3))
" 2>&1 | tail -60

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
df=clean()
d=df.dropna(subset=['humidity_ok','mold_temp_c']).copy()
f='rate ~ mold_temp_c + humidity_ok + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)'
import patsy
y,X=patsy.dmatrices(f,d,return_type='dataframe')
print('X shape',X.shape,'rank',np.linalg.matrix_rank(X.values))
print(X.columns[np.linalg.svd(X.values,full_matrices=False)[2][-3:].argmax()] if False else '')
u,s,vt=np.linalg.svd(X.values); print('small sv',s[-3:])
print(pd.crosstab(d.line,d.supplier_code))
print(d.groupby('line').machine_age_years.agg(['min','max','mean']).round(2))
m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
op=m.summary2().tables[1]; print(op[op.index.str.contains('operator')].round(3).to_string())
" 2>&1 | tail -60

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import patsy
df=clean()
d=df.dropna(subset=['humidity_ok','mold_temp_c']).copy()
f='rate ~ mold_temp_c + humidity_ok + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)'
y,X=patsy.dmatrices(f,d,return_type='dataframe')
# find dependent columns greedily
import numpy as np
keep=[]
for c in X.columns:
    trial=keep+[c]
    if np.linalg.matrix_rank(X[trial].values)==len(trial): keep.append(c)
    else: print('dependent:',c)
print(d.operator_id.value_counts().sort_index().to_dict())
print(d.groupby('line').machine_age_years.nunique())
print(d.groupby('line')['ambient_temp_c'].nunique())
print(d.groupby('shift').size())
"

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
pd.set_option('display.width',250)
df=clean()
print(pd.crosstab(df.operator_id,df.line).to_string())
print(pd.crosstab(df.line,df.date.dt.to_period('M')).to_string())
"

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
df=clean()
d=df.dropna(subset=['humidity_ok','mold_temp_c']).copy()
base='rate ~ mold_temp_c + humidity_ok + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code)'
for name,f in [('op_nested',base+' + C(operator_id)'),('line_only',base+' + C(line)')]:
    m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
    t=m.summary2().tables[1]
    print(name,'AIC',round(m.aic,1),'scale',round(m.scale,2),'dev',round(m.deviance,1))
    print(t.loc[['mold_temp_c','humidity_ok','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)[T.Night]','C(supplier_code)[T.SP-02]','C(supplier_code)[T.SP-03]']].round(4).to_string())
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
df=clean()
d=df.dropna(subset=['humidity_ok','mold_temp_c']).copy()
f='rate ~ mold_temp_c + humidity_ok + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_code) + C(line)'
m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
d['mu']=m.predict(d)
d['pres']=(d.rate-d.mu)/np.sqrt(d.mu*(1-d.mu)/d.units_produced)
d['wk']=d.date.dt.to_period('M')
print(d.groupby(['line','wk']).pres.mean().unstack(0).round(2).to_string())
print('pearson scale per line', d.groupby('line').pres.apply(lambda x:(x**2).mean()).round(2).to_dict())
for v in ['mold_temp_c','humidity_ok','cycle_time_s','ambient_temp_c','machine_age_years']:
    print(v, d.groupby(pd.qcut(d[v],8,duplicates='drop')).pres.agg(['mean','size']).round(2).to_string())
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
df=clean()
d=df.dropna(subset=['humidity_ok','mold_temp_c']).copy()
d['t']=(d.date-pd.Timestamp('2025-01-01')).dt.days
f='rate ~ mold_temp_c + I(mold_temp_c**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line)'
m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
print(m.summary2().tables[1].round(5).to_string())
print('scale',round(m.scale,2),'deviance',round(m.deviance,1), 'AIC', round(m.aic,1))
d['mu']=m.predict(d)
d['pres']=(d.rate-d.mu)/np.sqrt(d.mu*(1-d.mu)/d.units_produced)
print('scale per line', d.groupby('line').pres.apply(lambda x:(x**2).mean()).round(2).to_dict())
d['wk']=d.date.dt.to_period('M')
print(d.groupby(['line','wk']).pres.mean().unstack(0).round(2).to_string())
d.to_pickle('$TMPDIR/s/d.pkl')
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d.pkl')
mt=pd.read_csv('maintenance.csv',parse_dates=['date'])
print(mt.event.value_counts().to_dict())
cl=mt[mt.event=='mold_cleaning']
def dsc(row):
    c=cl[(cl.line==row.line)&(cl.date<=row.date)]
    if c.empty: return np.nan
    return (row.date-c.date.max()).days
d['dsc']=d.apply(dsc,axis=1)
print(d.dsc.describe().round(1).to_dict())
print(d.groupby('line').dsc.describe().round(1).to_string())
print(d.groupby(pd.cut(d.dsc,[-1,2,4,7,10,14,20,30,60,200])).pres.agg(['mean','size']).round(2).to_string())
print(d.groupby(pd.cut(d.dsc,[-1,2,4,7,10,14,20,30,60,200])).rate.mean().round(4).to_string())
d.to_pickle('$TMPDIR/s/d.pkl')
"

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d.pkl')
base='rate ~ mold_temp_c + I(mold_temp_c**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line)'
for name,f in [('lin',base+' + dsc'),('quad',base+' + dsc + I(dsc**2)')]:
    m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
    print(name,'scale',round(m.scale,2),'dev',round(m.deviance,1))
    t=m.summary2().tables[1]; print(t.loc[[i for i in t.index if i in ['dsc','I(dsc ** 2)','mold_temp_c','humidity_ok','cycle_time_s','ambient_temp_c','C(shift)[T.Night]']]].round(5).to_string())
    d['mu']=m.predict(d); d['pres']=(d.rate-d.mu)/np.sqrt(d.mu*(1-d.mu)/d.units_produced)
    d['wk']=d.date.dt.to_period('M')
    print(d.groupby(['line','wk']).pres.mean().unstack(0).round(2).to_string())
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d.pkl')
f='rate ~ mold_temp_c + I(mold_temp_c**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
d['mu']=m.predict(d); d['pres']=(d.rate-d.mu)/np.sqrt(d.mu*(1-d.mu)/d.units_produced)
d.to_pickle('$TMPDIR/s/d2.pkl')
for ln,g in d.groupby('line'):
    g=g.sort_values('date')
    best=None
    r=g.pres.values; dates=g.date.values
    for k in range(40,len(r)-40):
        a,b=r[:k],r[k:]
        t=(b.mean()-a.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
        if best is None or abs(t)>abs(best[0]): best=(t,k,pd.Timestamp(dates[k]).date(),round(a.mean(),2),round(b.mean(),2))
    print(ln,'max |t| split',best)
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d2.pkl')
df=clean()
df['m']=df.mold_temp_c
print('raw rate by line/month (pooled):')
df['wk']=df.date.dt.to_period('M')
print((df.groupby(['line','wk']).defective_units.sum()/df.groupby(['line','wk']).units_produced.sum()).unstack(0).round(4).to_string())
print('L1 mold temp before/after 2025-04-14:', df[(df.line=='L1')].groupby(df.date>='2025-04-14').m.agg(['mean','median','size']).round(2).to_string())
print('other lines mold by month:', df[df.line!='L3'].groupby(['line','wk']).m.mean().unstack(0).round(1).to_string())
print('L1 mold by month:', df[df.line=='L1'].groupby('wk').m.mean().round(1).to_dict())
print('L2 pre/post 06-16: raw rate', df[df.line=='L2'].groupby(df.date>='2025-06-16').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print('L3 pre/post 07-21: raw rate', df[df.line=='L3'].groupby(df.date>='2025-07-21').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
"

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
pd.set_option('display.width',250)
df=clean()
df['wk']=df.date.dt.to_period('M')
df['rwc']=df.rework_cost_eur/df.defective_units
print('supplier share by line-month, L2:'); print(pd.crosstab(df[df.line=='L2'].wk, df[df.line=='L2'].supplier_code,normalize='index').round(2).to_string())
print('supplier share by line-month, L3:'); print(pd.crosstab(df[df.line=='L3'].wk, df[df.line=='L3'].supplier_code,normalize='index').round(2).to_string())
print(df.groupby(['line','wk']).rwc.median().unstack(0).round(2).to_string())
df['qc_per_def']=df.qc_inspection_min/df.defective_units
print(df.groupby(['line','wk']).qc_inspection_min.median().unstack(0).round(1).to_string())
print(df.groupby(['line','wk']).cycle_time_s.mean().unstack(0).round(1).to_string())
print(df.groupby(['line','wk']).machine_age_years.mean().unstack(0).round(1).to_string())
"

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.api as sm
pd.set_option('display.width',250)
df=clean()
df['post']=df.date>='2025-07-21'
for ln in ['L3','L2','L1','L4']:
  for post in [False,True]:
    g=df[(df.line==ln)&(df.post==post)] if ln=='L3' else df[(df.line==ln)&(df.date>='2025-06-16')==post]
    r=g.rework_cost_eur/g.defective_units
    b=np.polyfit(g.defective_units,g.rework_cost_eur,1)
    q=np.polyfit(g.defective_units,g.qc_inspection_min,1)
    print(ln,'post' if post else 'pre', len(g),'rwc quantiles',r.quantile([.1,.5,.9]).round(2).tolist(),'slope rwc~def',b.round(2),'qc~def',q.round(3),'def mean',round(g.defective_units.mean(),1),'rate',round(g.defective_units.sum()/g.units_produced.sum(),4))
"

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import pandas as pd
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d2.pkl')
g=d[d.line=='L2'].copy(); g['post']=g.date>='2025-06-16'
for c in ['humidity_ok','mold_temp_c','ambient_temp_c','cycle_time_s','machine_age_years','dsc','units_produced']:
    print(c, g.groupby('post')[c].agg(['mean','median']).round(2).to_dict())
print(pd.crosstab(g.post,g['shift'],normalize='index').round(2))
print(pd.crosstab(g.post,g.supplier_code,normalize='index').round(2))
print(pd.crosstab(g.post,g.operator_id,normalize='index').round(2).T)
print('mean pres pre/post', g.groupby('post').pres.mean().round(2).to_dict())
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
pd.set_option('display.width',250)
df=clean()
df['wk']=df.date.dt.to_period('M')
print(df.groupby(['line','wk']).ambient_temp_c.mean().unstack(0).round(1).to_string())
df['ratio']=(df.rework_cost_eur/4.22)/df.defective_units
l3=df[df.line=='L3'].sort_values('date')
print('L3 ratio by date near 07-21:')
print(l3[(l3.date>='2025-07-10')&(l3.date<='2025-08-05')][['date','defective_units','rework_cost_eur','ratio','qc_inspection_min']].round(2).to_string())
print('L3 ratio distribution post', l3[l3.date>='2025-07-21'].ratio.describe().round(2).to_dict())
print('L3 ratio distribution pre', l3[l3.date<'2025-07-21'].ratio.describe().round(2).to_dict())
"

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d2.pkl')
d['mu_units']=d.mu*d.units_produced
def seg(ln,cut):
    g=d[d.line==ln]
    a=g[g.date<cut]; b=g[g.date>=cut]
    return dict(pre_rec=round(a.defective_units.sum()/a.units_produced.sum(),4), pre_pred=round(a.mu_units.sum()/a.units_produced.sum(),4), post_rec=round(b.defective_units.sum()/b.units_produced.sum(),4), post_pred=round(b.mu_units.sum()/b.units_produced.sum(),4))
print('L2 @06-16', seg('L2','2025-06-16'))
print('L3 @07-21', seg('L3','2025-07-21'))
print('L1 @04-14', seg('L1','2025-04-14'))
print('L4 @06-16', seg('L4','2025-06-16'))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
d=pd.read_pickle('$TMPDIR/s/d2.pkl')
g=d.assign(pu=d.mu*d.units_produced).groupby('line')[['defective_units','pu','units_produced']].sum()
g['rec']=g.defective_units/g.units_produced; g['pred']=g.pu/g.units_produced
print(g.round(4))
print(d.groupby('line').apply(lambda x:(x.defective_units.sum(), (x.mu*x.units_produced).sum())).to_dict())
print(d[['mu','rate','units_produced']].describe().round(3))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d2.pkl')
bins=[-1,7,14,21,35,80]
for ln,cut in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=d[d.line==ln].copy(); g['post']=g.date>=cut
    g['db']=pd.cut(g.dsc,bins)
    print(ln); print(g.groupby(['post','db']).pres.agg(['mean','size']).round(2).unstack(0).to_string())
    print(g.groupby('post').dsc.describe().round(1).to_string())
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=pd.read_pickle('$TMPDIR/s/d2.pkl')
f='rate ~ bs(mold_temp_c,df=5) + bs(humidity_ok,df=5) + bs(cycle_time_s,df=4) + bs(ambient_temp_c,df=4) + bs(dsc,df=4) + C(shift) + C(supplier_code) + C(line)'
m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
d['mu2']=m.predict(d); d['pres2']=(d.rate-d.mu2)/np.sqrt(d.mu2*(1-d.mu2)/d.units_produced)
print('scale',round(m.scale,2),'dev',round(m.deviance,1))
for ln,cut in [('L2','2025-06-16'),('L3','2025-07-21'),('L1','2025-04-14')]:
    g=d[d.line==ln]; print(ln,'pre',round(g[g.date<cut].pres2.mean(),2),'post',round(g[g.date>=cut].pres2.mean(),2))
g=d.copy(); g['wk']=g.date.dt.to_period('M')
print(g.groupby(['line','wk']).pres2.mean().unstack(0).round(2).to_string())
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
df=clean()
df['dsc']=np.nan
d0=pd.read_pickle('$TMPDIR/s/d2.pkl')
d0=d0[['batch_id','line','date','dsc']]
base=df.dropna(subset=['humidity_ok','mold_temp_c']).copy().merge(d0[['batch_id','line','date','dsc']],on=['batch_id','line','date'],how='inner')
print(len(base))
post=(base.line=='L1')&(base.date>='2025-04-14')
for b in [0,4,6,8,9,10,12]:
    x=base.copy(); x['mold_adj']=x.mold_temp_c-np.where(post,b,0)
    f='rate ~ mold_adj + I(mold_adj**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
    m=smf.glm(f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
    x['mu']=m.predict(x); x['pres']=(x.rate-x.mu)/np.sqrt(x.mu*(1-x.mu)/x.units_produced)
    l1=x[x.line=='L1']
    print('bias',b,'L1 pre',round(l1[l1.date<'2025-04-14'].pres.mean(),2),'L1 post',round(l1[l1.date>='2025-04-14'].pres.mean(),2),'dev',round(m.deviance,1),'mold coef',round(m.params['mold_adj'],4))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
d0=pd.read_pickle('$TMPDIR/s/d2.pkl')
post=(d0.line=='L1')&(d0.date>='2025-04-14')
for b in [0,4,6,8,9,10,12]:
    x=d0.copy(); x['mold_adj']=x.mold_temp_c-np.where(post,b,0)
    f='rate ~ mold_adj + I(mold_adj**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
    m=smf.glm(f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
    x['mu']=m.predict(x); x['pres']=(x.rate-x.mu)/np.sqrt(x.mu*(1-x.mu)/x.units_produced)
    l1=x[x.line=='L1']
    print('bias',b,'L1 pre',round(l1[l1.date<'2025-04-14'].pres.mean(),2),'L1 post',round(l1[l1.date>='2025-04-14'].pres.mean(),2),'dev',round(m.deviance,1),'mold coef',round(m.params['mold_adj'],4))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
d0=pd.read_pickle('$TMPDIR/s/d2.pkl')
raw=clean()
# rework-implied defects, only for L3 after 07-21
imp=raw.set_index(['batch_id','line','date']).rework_cost_eur
l3post=(d0.line=='L3')&(d0.date>='2025-07-21')
x=d0.copy()
x['def_true']=x.defective_units.astype(float)
idx=x.index[l3post]
x.loc[idx,'def_true']=(x.loc[idx,'rework_cost_eur']/4.22).round()
x['rate_true']=x.def_true/x.units_produced
print('L3 post recorded rate',round(x[l3post].defective_units.sum()/x[l3post].units_produced.sum(),4),'implied true',round(x[l3post].def_true.sum()/x[l3post].units_produced.sum(),4))
f='rate_true ~ mold_temp_c + I(mold_temp_c**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
m=smf.glm(f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
x['mu']=m.predict(x); x['pres']=(x.rate_true-x.mu)/np.sqrt(x.mu*(1-x.mu)/x.units_produced)
for ln,cut in [('L2','2025-06-16'),('L3','2025-07-21'),('L1','2025-04-14')]:
    g=x[x.line==ln]; print(ln,'pre',round(g[g.date<cut].pres.mean(),2),'post',round(g[g.date>=cut].pres.mean(),2))
print('dev',round(m.deviance,1))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
d0=pd.read_pickle('$TMPDIR/s/d2.pkl')
post=(d0.line=='L2')&(d0.date>='2025-06-16')
f='rate ~ mold_adj + I(mold_adj**2) + hum_adj + I(hum_adj**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
for kind in ['mold','hum']:
  for b in ([-12,-8,-4,0,4,8,12] if kind=='mold' else [-20,-10,0,10,20]):
    x=d0.copy(); x['mold_adj']=x.mold_temp_c; x['hum_adj']=x.humidity_ok
    if kind=='mold': x['mold_adj']=x.mold_temp_c+np.where(post,b,0)
    else: x['hum_adj']=(x.humidity_ok+np.where(post,b,0)).clip(lower=0)
    m=smf.glm(f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
    x['mu']=m.predict(x); x['pres']=(x.rate-x.mu)/np.sqrt(x.mu*(1-x.mu)/x.units_produced)
    g=x[x.line=='L2']
    print(kind,b,'L2 pre',round(g[g.date<'2025-06-16'].pres.mean(),2),'post',round(g[g.date>='2025-06-16'].pres.mean(),2),'dev',round(m.deviance,1))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf
df=clean()
d=df.dropna(subset=['mold_temp_c']).copy()
d['wk']=d.date.dt.to_period('W').astype(str)
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
m=smf.ols('mold_temp_c ~ C(line) + C(wk) + ambient_temp_c + C(shift) + l1post',data=d).fit()
print('L1 post bias (C):',round(m.params['l1post'],2),'+-',round(m.bse['l1post'],2))
d['l1pre']=((d.line=='L1')&(d.date<'2025-04-14')).astype(int)
m2=smf.ols('mold_temp_c ~ C(line) + C(wk) + ambient_temp_c + C(shift) + l1post + l1pre',data=d).fit()
print(round(m2.params[['l1post','l1pre']],2).to_dict())
# does the offset look constant over time after the replacement?
post=d[(d.line=='L1')&(d.date>='2025-04-14')].copy()
others=d[d.line!='L1']
mo=smf.ols('mold_temp_c ~ C(wk) + ambient_temp_c + C(shift) + C(line)',data=others).fit()
post['pred_other']=mo.predict(post.assign(line='L2'))
post['diff']=post.mold_temp_c-post.pred_other
print(post.groupby(post.date.dt.to_period('M'))['diff'].agg(['mean','size']).round(2).to_string())
pre=d[(d.line=='L1')&(d.date<'2025-04-14')].copy()
pre['diff']=pre.mold_temp_c-mo.predict(pre.assign(line='L2'))
print('L1 pre diff mean', round(pre['diff'].mean(),2))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle('$TMPDIR/s/d2.pkl')
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
f='rate ~ mold_temp_c + I(mold_temp_c**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2) + l1post'
m=smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
t=m.summary2().tables[1]
print(t.loc[['mold_temp_c','I(mold_temp_c ** 2)','l1post']].round(4).to_string())
b=m.params['mold_temp_c']; 
# linear implied offset at ~215C: d logit / d mold = b + 2*c*215
c=m.params['I(mold_temp_c ** 2)']; sl=b+2*c*215
print('local mold slope at 215C', round(sl,4), 'implied bias', round(m.params['l1post']/sl,2))
" 2>&1 | grep -v Warn

python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
import statsmodels.formula.api as smf
df=clean()
d=df.dropna(subset=['mold_temp_c']).copy()
d['wk']=d.date.dt.to_period('W').astype(str)
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
for f in ['mold_temp_c ~ C(line) + C(wk) + C(shift) + ambient_temp_c + l1post',
          'mold_temp_c ~ C(line) + C(wk) + l1post',
          'mold_temp_c ~ C(line) + C(wk) + C(shift) + ambient_temp_c + humidity_ok + cycle_time_s + l1post',
          'mold_temp_c ~ C(line) + C(wk) + C(shift) + ambient_temp_c + cycle_time_s + l1post',
          'mold_temp_c ~ C(line) + C(wk) + C(shift) + ambient_temp_c + C(supplier_code) + l1post']:
    dd=d.dropna(subset=['humidity_ok']) if 'humidity' in f else d
    m=smf.ols(f,data=dd).fit()
    print(round(m.params['l1post'],2), round(m.bse['l1post'],2), f)
d2=d[d.line.isin(['L2','L4'])|((d.line=='L1'))].copy()
" 2>&1 | grep -v Warn

cat > $TMPDIR/s/final.py <<'EOF'
import sys, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/tmp/claude-0/-home-claude/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/s')
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm

L1_BIAS = 6.14          # L1 mold sensor reads high after 2025-04-14 (regression offset)
UNIT_REWORK = 4.22      # plant rework cost per defective unit (median before L3 change)
pre_dried = {'SP-01': 0, 'SP-02': 1, 'SP-03': 1}
recipe = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}

def build():
    df = clean()
    # mold: L3 is in Fahrenheit, L1 sensor offset after replacement
    df['mold_c'] = np.where(df.line == 'L3', (df.mold_raw - 32) * 5 / 9, df.mold_raw)
    df.loc[df.mold_raw == 0, 'mold_c'] = np.nan
    l1post = (df.line == 'L1') & (df.date >= '2025-04-14')
    df['mold_actual'] = df.mold_c - np.where(l1post, L1_BIAS, 0)
    df.loc[df.mold_raw == 0, 'mold_actual'] = np.nan
    # defects: L3 recorded counts from 2025-07-21 are inconsistent with rework cost; rework-implied count used for modelling
    l3post = (df.line == 'L3') & (df.date >= '2025-07-21')
    df['def_actual'] = df.defective_units.astype(float)
    df.loc[l3post, 'def_actual'] = df.loc[l3post, 'rework_cost_eur'] / UNIT_REWORK
    df['rate_actual'] = df.def_actual / df.units_produced
    # days since last mold cleaning of the line
    mt = pd.read_csv(RAW + 'maintenance.csv', parse_dates=['date'])
    cl = mt[mt.event == 'mold_cleaning']
    def dsc(r):
        c = cl[(cl.line == r.line) & (cl.date <= r.date)]
        return np.nan if c.empty else (r.date - c.date.max()).days
    df['dsc'] = df.apply(dsc, axis=1)
    df['pre_dried'] = df.supplier_code.map(pre_dried)
    df['recipe'] = df.supplier_code.map(recipe)
    return df

if __name__ == '__main__':
    df = build()
    print('rows', len(df), 'humidity valid', df.humidity_ok.notna().sum(), 'mold valid', df.mold_actual.notna().sum(), 'dsc missing', df.dsc.isna().sum())
    print(df.mold_actual.describe().round(2).to_dict())
    print('median mold actual', round(df.mold_actual.median(), 4))
    print('overall recorded rate', round(df.defective_units.sum() / df.units_produced.sum(), 6))
    print('overall actual-target rate', round(df.def_actual.sum() / df.units_produced.sum(), 6))
    df.to_pickle('/tmp/claude-0/-home-claude/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/s/final.pkl')
EOF
python3 $TMPDIR/s/final.py

sed -i "s#/tmp/claude-0/-home-claude/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/s#$TMPDIR/s#g" $TMPDIR/s/final.py && python3 $TMPDIR/s/final.py && python3 -c "
import sys,warnings; warnings.filterwarnings('ignore'); sys.path.insert(0,'$TMPDIR/s')
from clean import *
df=load()
print('A4 uncorrected L1 median (zeros removed, L3 converted):')
import final
d=final.build()
x=d.copy(); x['m2']=np.where(x.line=='L3',(x.mold_raw-32)*5/9,x.mold_raw); x.loc[x.mold_raw==0,'m2']=np.nan
print(round(x.m2.median(),3), x.m2.notna().sum())
"

cat > $TMPDIR/s/fit.py <<'EOF'
import sys, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, '/tmp/claude-0/s')
import os
sys.path.insert(0, os.environ['TMPDIR'] + '/s')
from final import *
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
df = build()
d = df.dropna(subset=['humidity_ok', 'mold_actual']).copy()
d['shift'] = d['shift']
def fit(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
EOF
python3 -c "
import os,sys; sys.argv=['x']; exec(open(os.environ['TMPDIR']+'/s/fit.py').read())
base='rate_actual ~ mold_actual + I(mold_actual**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
m=fit(base)
print('n',len(d),'scale',round(m.scale,2))
print(m.summary2().tables[1].round(4).to_string())
"

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit.py').read())
import statsmodels.api as sm
base='rate_actual ~ mold_actual + I(mold_actual**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
m=fit(base)
def wald(names):
    R=np.zeros((len(names),len(m.params)))
    for i,n in enumerate(names): R[i,list(m.params.index).index(n)]=1
    return m.wald_test(R,scalar=True)
print('mold joint', wald(['mold_actual','I(mold_actual ** 2)']))
print('cycle joint', wald(['cycle_time_s','I(cycle_time_s ** 2)']))
print('ambient joint', wald(['ambient_temp_c','I(ambient_temp_c ** 2)']))
print('humidity joint', wald(['humidity_ok','I(humidity_ok ** 2)']))
# machine age
m2=fit(base+' + machine_age_years')
print('machine_age p', m2.pvalues['machine_age_years'].round(4), m2.params['machine_age_years'].round(5))
# operator nested within line vs line
m3=fit(base.replace('C(line)','C(operator_id)'))
dd=(m.deviance-m3.deviance)/m.scale; print('operator beyond line: dfdev',round(dd,2),'df',m.df_resid-m3.df_resid,'F approx', round((dd/(m.df_resid-m3.df_resid))/1,3))
print('cycle grid', d.groupby(pd.cut(d.cycle_time_s,8)).rate_actual.agg(['mean','size']).round(4).to_string())
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit.py').read())
from scipy import stats
base='rate_actual ~ mold_actual + I(mold_actual**2) + humidity_ok + I(humidity_ok**2) + cycle_time_s + I(cycle_time_s**2) + ambient_temp_c + I(ambient_temp_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)'
m=fit(base)
def jt(names):
    idx=[list(m.params.index).index(n) for n in names]
    b=m.params.values[idx]; V=m.cov_params().values[np.ix_(idx,idx)]
    c=float(b@np.linalg.solve(V,b)); return round(c,2), len(idx), float(stats.chi2.sf(c,len(idx)))
print('mold',jt(['mold_actual','I(mold_actual ** 2)']))
print('cycle',jt(['cycle_time_s','I(cycle_time_s ** 2)']))
print('ambient',jt(['ambient_temp_c','I(ambient_temp_c ** 2)']))
print('humidity',jt(['humidity_ok','I(humidity_ok ** 2)']))
# cycle as spline and with recipe deviation
f2=base.replace('cycle_time_s + I(cycle_time_s**2)','bs(cycle_time_s,df=4)')
m2=fit(f2)
print('cycle spline df4 dev',round(m2.deviance,1),'vs quad',round(m.deviance,1))
d['cdev']=d.cycle_time_s-d.recipe
f3=base.replace('cycle_time_s + I(cycle_time_s**2)','cdev + I(cdev**2)')
m3=fit(f3,data=d.assign(cdev=d.cdev))
print('cdev quad dev',round(m3.deviance,1), m3.params[['cdev','I(cdev ** 2)']].round(5).to_dict())
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit.py').read())
from scipy import stats
d['cyc_c']=d.cycle_time_s-d.cycle_time_s.mean()
d['hum_c']=d.humidity_ok-d.humidity_ok.mean()
d['mold_c2']=d.mold_actual-d.mold_actual.mean()
d['amb_c']=d.ambient_temp_c-d.ambient_temp_c.mean()
full=('rate_actual ~ mold_c2 + I(mold_c2**2) + hum_c + I(hum_c**2) + cyc_c + I(cyc_c**2) + amb_c + I(amb_c**2) + C(shift) + C(supplier_code) + C(line) + dsc + I(dsc**2)')
mf=fit(full,data=d.dropna(subset=['mold_c2','hum_c','cyc_c','amb_c']))
print('full', round(mf.deviance,1), round(mf.scale,3), mf.df_resid)
def drop(term_list,label):
    f=full
    for t in term_list: f=f.replace(' + '+t,'')
    m=fit(f,data=d.dropna(subset=['mold_c2','hum_c','cyc_c','amb_c']))
    dd=(m.deviance-mf.deviance)/mf.scale; k=m.df_resid-mf.df_resid
    F=(dd/k)/1.0
    p=stats.chi2.sf(dd,k)
    print(label,'dDev/scale',round(dd,2),'df',k,'p(chi2)',round(p,6))
drop(['mold_c2','I(mold_c2**2)'],'mold')
drop(['cyc_c','I(cyc_c**2)'],'cycle')
drop(['amb_c','I(amb_c**2)'],'ambient')
drop(['hum_c','I(hum_c**2)'],'humidity')
drop(['C(shift)'],'shift')
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit.py').read())
from scipy import stats
d['cyc_c']=d.cycle_time_s-d.cycle_time_s.mean()
d['hum_c']=d.humidity_ok-d.humidity_ok.mean()
d['mold_c2']=d.mold_actual-d.mold_actual.mean()
d['amb_c']=d.ambient_temp_c-d.ambient_temp_c.mean()
dd0=d.dropna(subset=['mold_c2','hum_c','cyc_c','amb_c'])
base_terms=['hum_c + I(hum_c**2)','cyc_c + I(cyc_c**2)','amb_c + I(amb_c**2)','C(shift)','C(supplier_code)','C(line)','dsc + I(dsc**2)']
mold_terms=['mold_c2 + I(mold_c2**2)']
full=lambda terms: 'rate_actual ~ '+' + '.join(terms)
mf=fit(full(mold_terms+base_terms),data=dd0)
m0=fit(full(base_terms),data=dd0)
dd=(m0.deviance-mf.deviance)/mf.scale
print('mold drop: dDev/scale',round(dd,3),'df 2','p',round(stats.chi2.sf(dd,2),4))
mf1=fit(full(['mold_c2']+base_terms+[]),data=dd0)
print('linear mold only: coef',round(mf1.params['mold_c2'],4),'z',round(mf1.tvalues['mold_c2'],3),'p',round(mf1.pvalues['mold_c2'],4))
mf2=fit(full(mold_terms+base_terms),data=dd0)
print('quad model mold coef',mf2.params[['mold_c2','I(mold_c2 ** 2)']].round(5).to_dict(), mf2.pvalues[['mold_c2','I(mold_c2 ** 2)']].round(3).to_dict())
" 2>&1 | grep -v Warn

cat > $TMPDIR/s/fit2.py <<'EOF'
import os, sys, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, os.environ['TMPDIR'] + '/s')
from final import *
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
pd.set_option('display.width', 250)

def prep(df):
    d = df.dropna(subset=['humidity_ok', 'mold_actual', 'dsc']).copy()
    for c, src in [('mold', 'mold_actual'), ('hum', 'humidity_ok'), ('cyc', 'cycle_time_s'), ('amb', 'ambient_temp_c'), ('dsc_s', 'dsc'), ('age', 'machine_age_years')]:
        d[c] = (d[src] - d[src].mean()) / d[src].std()
        d[c + '2'] = d[c] ** 2
    return d

def fit(f, data, weights='units_produced', target='rate_actual'):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data[weights]).fit(scale='X2')

def drop_test(full_terms, drop_terms, data, target='rate_actual'):
    mf = fit(f"{target} ~ " + ' + '.join(full_terms), data)
    mr = fit(f"{target} ~ " + ' + '.join([t for t in full_terms if t not in drop_terms]), data)
    dd = (mr.deviance - mf.deviance) / mf.scale
    k = len(drop_terms)
    return round(dd, 2), k, stats.chi2.sf(dd, k)

if __name__ == '__main__':
    df = build()
    d = prep(df)
    print('rows', len(d))
EOF
python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit2.py').read())
d=prep(build())
core=['mold','mold2','hum','hum2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2']
f='rate_actual ~ '+' + '.join(core)+' + C(shift) + C(supplier_code) + C(line)'
m=fit(f,d)
print(m.summary2().tables[1].round(4).to_string())
print('scale',round(m.scale,3),'dev',round(m.deviance,1))
"

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit2.py').read())
raw=build()
core=['mold','mold2','hum','hum2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2']
f='rate_actual ~ '+' + '.join(core)+' + C(shift) + C(supplier_code) + C(line)'
d=prep(raw)
m=fit(f,d); d['mu']=m.predict(d); d['pres']=(d.rate_actual-d.mu)/np.sqrt(d.mu*(1-d.mu)/d.units_produced)
print('final residual by line pre/post breaks:')
for ln,cut in [('L1','2025-04-14'),('L2','2025-06-16'),('L3','2025-07-21')]:
    g=d[d.line==ln]; print(ln, round(g[g.date<cut].pres.mean(),2), round(g[g.date>=cut].pres.mean(),2))
# scan L1 bias using the well-conditioned model: recompute mold with bias b, refit
res=[]
for b in [0,4,5,6,7,8,10]:
    x=prep(raw.assign(mold_actual=raw.mold_c-np.where((raw.line=='L1')&(raw.date>='2025-04-14'),b,0)))
    mm=fit(f,x); x['mu']=mm.predict(x); x['pres']=(x.rate_actual-x.mu)/np.sqrt(x.mu*(1-x.mu)/x.units_produced)
    g=x[x.line=='L1']
    print('bias',b,'L1 pre',round(g[g.date<'2025-04-14'].pres.mean(),2),'post',round(g[g.date>='2025-04-14'].pres.mean(),2),'dev',round(mm.deviance,1))
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit2.py').read())
raw=build()
core=['mold','mold2','hum','hum2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2']
f='rate_actual ~ '+' + '.join(core)+' + C(shift) + C(supplier_code) + C(line)'
d=prep(raw)
m=fit(f,d); d['mu']=m.predict(d); d['pres']=(d.rate_actual-d.mu)/np.sqrt(d.mu*(1-d.mu)/d.units_produced)
for ln,g in d.groupby('line'):
    g=g.sort_values('date'); r=g.pres.values; dates=g.date.values; best=None
    for k in range(40,len(r)-40):
        a,b=r[:k],r[k:]
        t=(b.mean()-a.mean())/np.sqrt(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))
        if best is None or abs(t)>abs(best[0]): best=(round(t,2),str(pd.Timestamp(dates[k]).date()),round(a.mean(),2),round(b.mean(),2))
    print(ln,best)
# raw-defect version for reference
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit2.py').read())
raw=build()
d=prep(raw)
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
core=['mold','mold2','hum','hum2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2']
base=core+['C(shift)','C(supplier_code)','C(line)','l2post']
m0=fit('rate_actual ~ '+' + '.join(base),d)
print('base dev',round(m0.deviance,1),'scale',round(m0.scale,3))
print(m0.summary2().tables[1].loc[['hum','hum2','mold','cyc','amb','dsc_s','C(shift)[T.Night]','l2post']].round(4).to_string())
# supplier-specific humidity curves
mS=fit('rate_actual ~ '+' + '.join([b for b in base if b not in ['hum','hum2']])+' + C(supplier_code):hum + C(supplier_code):hum2 + hum + hum2',d)
mS2=fit('rate_actual ~ '+' + '.join([b for b in base if b not in ['hum','hum2']])+' + hum + hum2',d)
print('humidity by supplier LR: dd/scale', round((mS2.deviance-mS.deviance)/mS.scale,2),'df',mS2.df_resid-mS.df_resid)
from scipy import stats
print('p', stats.chi2.sf((mS2.deviance-mS.deviance)/mS.scale, mS2.df_resid-mS.df_resid))
print('pre-dried test: same as supplier-specific (pre_dried only varies by supplier)')
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit2.py').read())
raw=build()
d=prep(raw)
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
core=['mold','mold2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2']
base=core+['C(shift)','C(line)','l2post']
for sup,g in d.groupby('supplier_code'):
    m=fit('rate_actual ~ '+' + '.join(base+['hum','hum2']),g)
    b=m.params; t=m.pvalues
    opt_sd=-b['hum']/(2*b['hum2'])
    mu,sd=d.humidity_ok.mean(), d.humidity_ok.std()
    print(sup, len(g), 'hum',round(b['hum'],4),'hum2',round(b['hum2'],4),'p hum2',round(t['hum2'],4),'opt humidity %', round(mu+opt_sd*sd,2))
print('mean/sd humidity', round(d.humidity_ok.mean(),3), round(d.humidity_ok.std(),3))
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/fit2.py').read())
import patsy
raw=build()
d=prep(raw)
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
core=['mold','mold2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2']
g=d[d.supplier_code=='SP-01'].copy()
m=fit('rate_actual ~ '+' + '.join(core+['C(shift)','C(line)','l2post','hum','hum2']),g)
b=m.params; V=m.cov_params()
x=np.linspace(-2.5,4.5,2001)  # standardized humidity grid
hs=(x*d.humidity_ok.std()+d.humidity_ok.mean())
eta=b['hum']*x+b['hum2']*x**2
# grid min in %
i=np.argmin(eta); print('quad grid min %', round(hs[i],2))
# delta-method SE of optimum (in standardized then % )
s=d.humidity_ok.std(); mu=d.humidity_ok.mean()
xo=-b['hum']/(2*b['hum2']); gvec=np.array([ -1/(2*b['hum2']), b['hum']/(2*b['hum2']**2)])
se=np.sqrt(gvec@V.loc[['hum','hum2'],['hum','hum2']].values@gvec)*s
print('optimum %', round(mu+xo*s,2), 'SE (pct pts)', round(se,2))
# cubic spline check
spl=smf.glm('rate_actual ~ bs(humidity_ok,df=6) + '+' + '.join(core+['C(shift)','C(line)','l2post']),data=g,family=sm.families.Binomial(),var_weights=g.units_produced).fit(scale='X2')
grid=pd.DataFrame({'humidity_ok':np.arange(12.1,72,0.1)})
for c in core: grid[c]=g[c].mean()
grid['shift']='Day'; grid['line']='L1'; grid['l2post']=0; grid['supplier_code']='SP-01'
grid['mold']=g.mold.mean(); grid['mold2']=g.mold2.mean(); grid['cyc']=g.cyc.mean(); grid['cyc2']=g.cyc2.mean(); grid['amb']=g.amb.mean(); grid['amb2']=g.amb2.mean(); grid['dsc_s']=g.dsc_s.mean(); grid['dsc_s2']=g.dsc_s2.mean()
p=spl.predict(grid)
print('spline minimum at humidity %', round(grid.humidity_ok[np.argmin(p.values)],2), 'min rate', round(p.min(),4))
print('observed Alpha range', round(g.humidity_ok.min(),1), round(g.humidity_ok.max(),1))
" 2>&1 | grep -v Warn

cat > $TMPDIR/s/model.py <<'EOF'
import os, sys
exec(open(os.environ['TMPDIR'] + '/s/fit2.py').read())
raw = build()
d = prep(raw)
d['l2post'] = ((d.line == 'L2') & (d.date >= '2025-06-16')).astype(int)
FORM = ('rate_actual ~ mold + mold2 + cyc + cyc2 + amb + amb2 + dsc_s + dsc_s2 + C(shift) + C(line) + l2post'
        ' + C(supplier_code) * (hum + hum2)')
def final_fit(data=None):
    return fit(FORM, d if data is None else data)
EOF
python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/model.py').read())
from scipy import stats
m=final_fit()
print('scale',round(m.scale,3),'dev',round(m.deviance,1))
def lr(drop, label, extra=None):
    f_full=FORM+(' + '+extra if extra else '')
    mf=fit(f_full,d); 
    f_red=FORM
    for t in drop: f_red=f_red.replace(' + '+t,'')
    mr=fit(f_red,d)
    dd=(mr.deviance-mf.deviance)/mf.scale; k=mr.df_resid-mf.df_resid
    print(label,'dd',round(dd,2),'df',k,'p',round(stats.chi2.sf(dd,k),5))
lr(['amb','amb2'],'ambient')
lr(['cyc','cyc2'],'cycle')
lr(['mold','mold2'],'mold')
lr(['C(shift)'],'shift')
lr([],'machine age',extra='age')
lr([],'machine age (raw)',extra='machine_age_years')
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/model.py').read())
from scipy import stats
TERMS=['mold','mold2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2','C(shift)','C(line)','l2post','C(supplier_code):hum','C(supplier_code):hum2','hum','hum2','C(supplier_code)']
def f_of(terms): return 'rate_actual ~ '+' + '.join(terms)
full=['mold','mold2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2','C(shift)','C(line)','l2post','C(supplier_code)','C(supplier_code):hum','C(supplier_code):hum2','hum','hum2']
mf=fit(f_of(full),d)
def lr(drop,label,extra=None):
    terms=[t for t in full if t not in drop]+(extra or [])
    mr=fit(f_of(terms),d); dd=(mr.deviance-mf.deviance)/mf.scale; k=mr.df_resid-mf.df_resid
    print(label,'dd',round(dd,2),'df',k,'p',round(stats.chi2.sf(dd,k),6))
print('check base dev', round(mf.deviance,1), 'scale', round(mf.scale,3))
lr(['amb','amb2'],'ambient')
lr(['cyc','cyc2'],'cycle')
lr(['mold','mold2'],'mold')
lr(['mold2'],'mold (linear only test)')
lr(['C(shift)'],'shift')
lr([],'machine_age',extra=['age'])
lr(['dsc_s','dsc_s2'],'dsc (ref)')
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/model.py').read())
from scipy import stats
def f_of(terms): return 'rate_actual ~ '+' + '.join(terms)
full=['mold','mold2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2','C(shift)','C(line)','l2post','C(supplier_code)','C(supplier_code):hum','C(supplier_code):hum2','hum','hum2']
mf=fit(f_of(full),d)
ma=fit(f_of(full+['age','age2']),d)
dd=(mf.deviance-ma.deviance)/mf.scale
print('machine age (age, age2): dd',round(dd,2),'df 2 p',round(stats.chi2.sf(dd,2),4))
ma1=fit(f_of(full+['age']),d); print('age linear coef p', round(ma1.pvalues['age'],4))
mo=fit(f_of([t if t!='C(line)' else 'C(operator_id)' for t in full]),d)
dd2=(mo.deviance-mf.deviance)/mf.scale; k=mf.df_resid-mo.df_resid
print('operator beyond line: dd',round(dd2,2),'df',k,'p',round(stats.chi2.sf(dd2,k),4))
" 2>&1 | grep -v Warn

python3 -c "
import os,sys; exec(open(os.environ['TMPDIR']+'/s/model.py').read())
from scipy import stats
def f_of(terms): return 'rate_actual ~ '+' + '.join(terms)
full=['mold','mold2','cyc','cyc2','amb','amb2','dsc_s','dsc_s2','C(shift)','C(line)','l2post','C(supplier_code)','C(supplier_code):hum','C(supplier_code):hum2','hum','hum2']
mf=fit(f_of(full),d)
mo=fit(f_of([t if t!='C(line)' else 'C(operator_id)' for t in full]),d)
dd=abs(mo.deviance-mf.deviance)/mf.scale; print('operator beyond line chi2',round(dd,2),'df',int(mf.df_resid-mo.df_resid),'p',round(stats.chi2.sf(dd,mf.df_resid-mo.df_resid),4))
# operator effect per operator relative to line average (in model with operator)
ops=mo.params[mo.params.index.str.startswith('C(operator_id)')]
pv=mo.pvalues[mo.pvalues.index.str.startswith('C(operator_id)')]
print(pd.DataFrame({'coef':ops.round(3),'p':pv.round(3)}).to_string())
# Test with nested operator-within-line for each line separately, summarised
" 2>&1 | grep -v Warn
