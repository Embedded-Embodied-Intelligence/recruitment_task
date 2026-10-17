ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && cat maintenance.csv | head -80 && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('\n##',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    if df[c].nunique()<40: print(vc.to_string())
    else: print(df[c].head(15).tolist())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d)); print(d.head(12).to_string())
print('exact dup rows', df.duplicated().sum())
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x=pd.to_numeric(df[c].str.strip(),errors='coerce')
    bad=df.loc[x.isna(),c].value_counts()
    print('\n',c,'non-numeric:',dict(bad.head(10)), 'n=',x.isna().sum())
    print(x.describe().round(2).to_dict())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['hum']=pd.to_numeric(df.humidity_pct.str.strip(),errors='coerce')
df['mt']=pd.to_numeric(df.mold_temp,errors='coerce')
print('rows',len(df),'unique ids',df.batch_id.nunique())
print('hum value counts <0 or >100 or ==0:', df.hum[(df.hum<=0)|(df.hum>100)].value_counts(dropna=False).to_dict())
print('hum missing', df.hum.isna().sum())
print('mt histogram'); print(np.histogram(df.mt,bins=[0,1,50,100,150,180,200,250,300,350,400,460])[0])
print('mt==0 rows', (df.mt==0).sum())
hi=df[df.mt>300]
print('mt>300 rows',len(hi)); print(hi.line.value_counts().to_dict()); print(hi.production_date.min(), hi.production_date.max())
print(hi[['batch_id','production_date','line','mt','ambient_temp_c']].head(10).to_string())
print('mt in 100-190 range rows', ((df.mt>100)&(df.mt<190)).sum())
print(df.loc[(df.mt>0)&(df.mt<150),['batch_id','production_date','line','mt']].head(10).to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp)
df['hum']=pd.to_numeric(df.humidity_pct.str.strip(),errors='coerce')
df['d']=pd.to_datetime(df.production_date)
l3=df[df.line=='L3'].sort_values('d')
f=l3[l3.mt>300]; c=l3[(l3.mt<300)&(l3.mt>0)]
print('L3 F rows date range',f.d.min(),f.d.max(),' C rows after first F:', (c.d>f.d.min()).sum(), ' C rows before last F:', (c.d<f.d.max()).sum())
# find L3 days that have both
mixed=l3.groupby('production_date').mt.agg(lambda s:(s>300).mean())
print('mixed days', mixed[(mixed>0)&(mixed<1)].to_string())
print('F->C transition: last F', f.d.max(), 'first C after', c[c.d>f.d.max()].d.min())
print(' mt by line median', df[df.mt>0].groupby('line').mt.median().to_dict())
for ln in ['L1','L2','L4']:
    s=df[(df.line==ln)&(df.mt>0)].sort_values('d')
    print(ln, s.groupby(s.d.dt.to_period('M')).mt.median().round(1).to_dict())
print('L3 C monthly', c.groupby(c.d.dt.to_period('M')).mt.median().round(1).to_dict())
print('L1 monthly med', df[(df.line=='L1')&(df.mt>0)].groupby(pd.to_datetime(df.production_date).dt.to_period('M')).mt.median().round(1).to_dict())
" 

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp)
df['d']=pd.to_datetime(df.production_date)
df['shiftn']=df['shift'].str.strip().str.lower().str[0].map({'d':'Day','n':'Night'})
df['supn']=df.supplier_code.str.strip().str.upper()
l3=df[(df.line=='L3')&(df.mt>0)].copy()
l3['isF']=l3.mt>300
print('L3 F share by shift', l3.groupby('shiftn').isF.mean().round(3).to_dict())
print('L3 F share by supplier', l3.groupby('supn').isF.mean().round(3).to_dict())
print('L3 F share by operator', l3.groupby('operator_id').isF.mean().round(2).to_dict())
print('L3 F share by month', l3.groupby(l3.d.dt.to_period('M')).isF.mean().round(2).to_dict())
print('L3 F vs C ambient', l3.groupby('isF').ambient_temp_c.describe().round(1).to_string())
print('L3 F/C converted to C median', np.where(l3.isF,(l3.mt-32)*5/9,l3.mt).round(1).mean())
c=l3[~l3.isF].mt; f=(l3[l3.isF].mt-32)*5/9
print('C-only median',c.median(),' F->C median',round(f.median(),2), 'C sd',round(c.std(),2),'F->C sd', round(f.std(),2))
print('zeros mold by line', df[df.mt==0].line.value_counts().to_dict())
print(df[df.mt==0][['batch_id','production_date','line','mold_temp']].head(5).to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp)
for c in ['cycle_time_s','ambient_temp_c','machine_age_years']: df[c]=pd.to_numeric(df[c])
df['d']=pd.to_datetime(df.production_date)
df=df[df.mt>0].copy()
df.loc[df.line=='L3','mt']=(df.loc[df.line=='L3','mt']-32)*5/9
df['wk']=df.d.dt.to_period('W')
# daily-level regression on L2,L4 controls: residual of mt vs cycle time and ambient, fitted on L2/L4
import numpy.linalg as la
ref=df[df.line.isin(['L2','L4'])]
X=np.c_[np.ones(len(ref)),ref.cycle_time_s,ref.ambient_temp_c,ref.machine_age_years]
b=la.lstsq(X,ref.mt,rcond=None)[0]; print('coef ref',b.round(3))
for ln in ['L1','L3']:
    s=df[df.line==ln]
    X2=np.c_[np.ones(len(s)),s.cycle_time_s,s.ambient_temp_c,s.machine_age_years]
    print(ln,'mean resid vs ref model', (s.mt-X2@b).mean().round(2))
s=df.copy(); s['res']=s.mt-np.c_[np.ones(len(s)),s.cycle_time_s,s.ambient_temp_c,s.machine_age_years]@b
l1=s[s.line=='L1'].sort_values('d')
print(l1.groupby(l1.d.dt.to_period('M')).res.agg(['mean','count']).round(2).to_string())
print('L1 residual by date around 04-14')
w=l1[(l1.d>='2025-03-25')&(l1.d<='2025-05-05')]
print(w.groupby('production_date').res.mean().round(1).to_string())
print('L2 L4 resid by month', s[s.line.isin(['L2','L4'])].groupby([s.line,s.d.dt.to_period('M')]).res.mean().round(2).unstack(0).to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
for c in ['units_produced','defective_units','rework_cost_eur','qc_inspection_min','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years']:
    df[c]=pd.to_numeric(df[c].str.strip(),errors='coerce')
df['d']=pd.to_datetime(df.production_date,errors='coerce')
print('bad dates',df.d.isna().sum(), df.d.min(), df.d.max())
print('units<=0',(df.units_produced<=0).sum(),' defect>units',(df.defective_units>df.units_produced).sum(), ' defect<0',(df.defective_units<0).sum())
print('humidity positive min', df.humidity_pct[df.humidity_pct>0].min(), 'humidity==0', (df.humidity_pct==0).sum())
print('hum>100',(df.humidity_pct>100).sum())
r=df.rework_cost_eur/df.defective_units
print('rework per defect', r.describe().round(3).to_dict())
print('corr qc with defect rate', np.corrcoef(df.qc_inspection_min, df.defective_units/df.units_produced)[0,1].round(3))
print('corr qc w defect count',np.corrcoef(df.qc_inspection_min, df.defective_units)[0,1].round(3))
print('corr rework w defect count',np.corrcoef(df.rework_cost_eur, df.defective_units)[0,1].round(3))
print('corr rework per unit vs rate', np.corrcoef(df.rework_cost_eur/df.units_produced, df.defective_units/df.units_produced)[0,1].round(3))
print('corr rework vs units', np.corrcoef(df.rework_cost_eur, df.units_produced)[0,1].round(3))
m=pd.read_csv('maintenance.csv')
print(m.event.value_counts().to_dict(), 'dups', m.duplicated().sum(), m.line.unique(), m.date.min(), m.date.max())
print(m[m.event!='mold_cleaning'])
"

mkdir -p "$TMPDIR" 2>/dev/null; SCR=/tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; mkdir -p $SCR && cat > $SCR/clean.py <<'EOF'
import pandas as pd, numpy as np
D = '/tmp/edabench_claude_fzkzc2p3/'

def load():
    raw = pd.read_csv(D + 'batches.csv', dtype=str, keep_default_na=False)
    raw['n_raw_rows'] = 1
    df = raw.drop_duplicates(subset=[c for c in raw.columns if c != 'n_raw_rows']).copy()
    df = df.drop(columns='n_raw_rows').reset_index(drop=True)
    df['d'] = pd.to_datetime(df.production_date)
    df['shift'] = df['shift'].str.strip().str.lower().str[0].map({'d': 'Day', 'n': 'Night'})
    df['supplier_code'] = df.supplier_code.str.strip().str.upper()
    sup = pd.read_csv(D + 'suppliers.csv', dtype=str)
    df = df.merge(sup[['supplier_code', 'supplier_name']], on='supplier_code', how='left')
    for c in ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'humidity_pct', 'cycle_time_s',
              'units_produced', 'defective_units', 'qc_inspection_min', 'rework_cost_eur']:
        df[c] = pd.to_numeric(df[c].str.strip().replace('', np.nan))
    df['humidity_raw'] = df.humidity_pct
    df.loc[df.humidity_pct < 0, 'humidity_pct'] = np.nan
    df['mold_temp_raw'] = df.mold_temp
    # 0.0 is a missing-value placeholder
    df.loc[df.mold_temp == 0, 'mold_temp'] = np.nan
    # L3 exports Fahrenheit
    l3 = (df.line == 'L3') & df.mold_temp.notna()
    df.loc[l3, 'mold_temp'] = (df.loc[l3, 'mold_temp'] - 32) * 5 / 9
    # L1 sensor replaced 2025-04-14; calibration check 2025-09-22 found +8.0 degC bias
    l1 = (df.line == 'L1') & (df.d > '2025-04-14') & df.mold_temp.notna()
    df.loc[l1, 'mold_temp'] = df.loc[l1, 'mold_temp'] - 8.0
    df['defect_rate'] = df.defective_units / df.units_produced
    df['days_since_clean'] = np.nan
    return df
EOF
cd $SCR && python3 -c "
from clean import *
df=load()
print(len(df), df.batch_id.nunique(), df.humidity_pct.isna().sum(), df.mold_temp.notna().sum())
print('A3', df.defective_units.sum()/df.units_produced.sum())
print('A4', df.mold_temp.median())
print(df.groupby('line').mold_temp.median().round(2).to_dict())
print(df['shift'].value_counts().to_dict(), df.supplier_name.value_counts().to_dict())
print('mt range', df.mold_temp.min(), df.mold_temp.max())
"

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "import statsmodels, sklearn; print(statsmodels.__version__, sklearn.__version__)" ; python3 -c "
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
df=load()
df['sup']=df.supplier_name
print(df.groupby('sup').apply(lambda g: pd.Series({'rate':g.defective_units.sum()/g.units_produced.sum(),'n':len(g),'hum_med':g.humidity_pct.median(),'mt':g.mold_temp.median()})).round(4))
print(df[['defect_rate','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','units_produced']].corr().round(3)['defect_rate'])
" 2>&1 | tail -30

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat >> clean.py <<'EOF'

def add_clean_age(df, cleanings):
    """days since the most recent mold cleaning on the same line, cleaning day counts as 0"""
    out = []
    for ln, g in df.groupby('line'):
        cd = np.sort(cleanings.loc[cleanings.line == ln, 'd'].values)
        idx = np.searchsorted(cd, g.d.values, side='right') - 1
        last = cd[idx]
        out.append(pd.Series((g.d.values - last) / np.timedelta64(1, 'D'), index=g.index))
    df['days_since_clean'] = pd.concat(out).reindex(df.index)
    return df

def load_maint():
    m = pd.read_csv(D + 'maintenance.csv')
    m['d'] = pd.to_datetime(m.date)
    return m
EOF
python3 -c "
from clean import *
df=load(); m=load_maint()
cl=m[m.event=='mold_cleaning']
df=add_clean_age(df,cl)
print(df.days_since_clean.describe().round(2).to_dict())
print('max per line', df.groupby('line').days_since_clean.max().to_dict())
print(df.groupby(pd.cut(df.days_since_clean,[-1,3,7,10,14,17,21,30,60])).defect_rate.agg(['mean','count']).round(4))
print('cleaning-gap check: intervals per line'); 
for ln,g in cl.groupby('line'): print(ln, g.d.diff().dt.days.describe()[['mean','max']].round(1).to_dict(), 'n',len(g))
"

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['y']=d.defective_units; d['n']=d.units_produced
d['fail']=d.n-d.y
f='defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
m=smf.glm('y + fail ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean', data=d, family=sm.families.Binomial()).fit(scale='X2')
print('n',len(d),'scale',round(m.scale,3))
print(m.summary2().tables[1].round(4).to_string())
" 2>&1 | grep -v Warning

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['y']=d.defective_units; d['fail']=d.units_produced-d.defective_units
print('--- what drives mold_temp (OLS)')
o=smf.ols('mold_temp ~ cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + humidity_pct + days_since_clean', data=d).fit()
print(o.summary2().tables[1].round(3).loc[['Intercept','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)[T.Night]','humidity_pct','days_since_clean','C(supplier_name)[T.Beta]','C(line)[T.L2]','C(line)[T.L3]','C(line)[T.L4]']].to_string())
print('R2',round(o.rsquared,3),'resid sd',round(o.resid.std(),2))
print('--- flexible mold temp (spline df=6) GLM, drop-one')
base='bs(mold_temp, df=6) + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
full=smf.glm('y + fail ~ '+base, data=d, family=sm.families.Binomial()).fit()
print('full dev',round(full.deviance,2),'df',full.df_resid)
for v in ['humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','C(operator_id)','C(shift)','C(supplier_name)','C(line)','days_since_clean']:
    rest=base.replace(' + '+v,'').replace(v+' + ','')
    r=smf.glm('y + fail ~ '+rest, data=d, family=sm.families.Binomial()).fit()
    print(f'{v:22s} dev increase {r.deviance-full.deviance:9.2f}  df {r.df_resid-full.df_resid}')
print(full.params.filter(regex='cycle|age|ambient|humid|shift|bs').round(4).to_string())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.formula.api as smf
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['pred_hum_ok']=d.humidity_pct
print('binomial sd of rate ~', np.sqrt((d.defect_rate*(1-d.defect_rate)/d.units_produced)).mean().round(5), ' observed rate sd', d.defect_rate.std().round(5))
base='bs(mold_temp, df=8) + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
m=smf.wls(f'defect_rate ~ {base}', data=d, weights=d.units_produced).fit()
print('full R2',round(m.rsquared,4),'resid sd',round(np.sqrt(m.scale),5))
for v in ['humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','C(operator_id)','C(shift)','C(supplier_name)','C(line)','days_since_clean']:
    rest=base.replace(' + '+v,'')
    r=smf.wls(f'defect_rate ~ {rest}', data=d, weights=d.units_produced).fit()
    print(f'{v:22s} R2 drop {m.rsquared-r.rsquared:.5f}  resid sd {np.sqrt(r.scale):.5f}')
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.formula.api as smf, statsmodels.api as sm
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
y=np.c_[d.defective_units, d.units_produced-d.defective_units]
m=smf.glm('defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean', data=d, freq_weights=d.units_produced, family=sm.families.Binomial()).fit()
print('freq-weight binomial dev/df', round(m.pearson_chi2/m.df_resid,3))
m2=smf.glm('defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean', data=d, freq_weights=d.units_produced, family=sm.families.Binomial()).fit(scale='X2')
print(m2.summary2().tables[1].round(4).loc[['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','days_since_clean','C(shift)[T.Night]','C(supplier_name)[T.Beta]','C(supplier_name)[T.Gamma]']].to_string())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.api as sm, patsy
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
Y=np.c_[d.defective_units, d.units_produced-d.defective_units].astype(float)
def fit(formula):
    X=patsy.dmatrix(formula, d, return_type='dataframe')
    m=sm.GLM(Y,X,family=sm.families.Binomial()).fit()
    return m, X
m,X=fit('mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean')
print('pearson chi2/df', round(m.pearson_chi2/m.df_resid,3), 'df',m.df_resid)
m2=sm.GLM(Y,X,family=sm.families.Binomial()).fit(scale='X2')
print(m2.summary2().tables[1].round(4).to_string())
" 2>&1 | grep -v -i warn | head -60

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.api as sm, patsy
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
print('age by line', df.groupby('line').machine_age_years.agg(['mean','std','min','max']).round(2).to_string())
print('defect rate by line', df.groupby('line').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print('operators by line counts'); print(pd.crosstab(df.operator_id, df.line).head(6).to_string())
print('shift by line', pd.crosstab(df['shift'], df.line, normalize='columns').round(2).to_string())
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
def fit(formula,dd):
    Y=np.c_[dd.defective_units, dd.units_produced-dd.defective_units].astype(float)
    X=patsy.dmatrix(formula, dd, return_type='dataframe')
    return sm.GLM(Y,X,family=sm.families.Binomial()).fit(scale='X2')
f='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + days_since_clean'
for ln in ['L2','L4','L1','L3']:
    dd=d[d.line==ln]
    m=fit(f,dd)
    t=m.summary2().tables[1]
    print(ln, 'n',len(dd), {k:(round(t.loc[k,'Coef.'],4), round(t.loc[k,'z'],1)) for k in ['mold_temp','ambient_temp_c','cycle_time_s','machine_age_years','humidity_pct','C(shift)[T.Night]','days_since_clean']})
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.formula.api as smf
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
print(pd.crosstab(df.operator_id, df.line).T.to_string())
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
for ln in ['L1','L2','L3','L4']:
    g=d[d.line==ln]
    o=smf.ols('mold_temp ~ ambient_temp_c',data=g).fit()
    print(ln,'mold~ambient slope',round(o.params.ambient_temp_c,3),'R2',round(o.rsquared,3),' ambient range',g.ambient_temp_c.min(),g.ambient_temp_c.max(), 'corr age',round(np.corrcoef(g.machine_age_years,g.ambient_temp_c)[0,1],3))
g=d[d.line=='L2'].copy()
g['ab']=pd.cut(g.ambient_temp_c,[10,15,18,20,22,24,26,28,31])
print(g.groupby('ab').agg(rate=('defect_rate','mean'),mt=('mold_temp','mean'),n=('defect_rate','size')).round(4).to_string())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['ab']=pd.cut(d.ambient_temp_c,[10,15,20,25,31])
t=d.groupby(['line','ab'],observed=True).apply(lambda g: pd.Series({'rate':g.defective_units.sum()/g.units_produced.sum(),'mt':g.mold_temp.mean(),'cyc':g.cycle_time_s.mean(),'dsc':g.days_since_clean.mean(),'n':len(g)})).round(4)
print(t.to_string())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.api as sm, patsy
from scipy import stats
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
Y=np.c_[d.defective_units, d.units_produced-d.defective_units].astype(float)
groups={'mold_temp':'bs(mold_temp, df=5)','humidity_pct':'humidity_pct','cycle_time_s':'bs(cycle_time_s, df=4)','machine_age_years':'machine_age_years','ambient_temp_c':'bs(ambient_temp_c, df=4)','days_since_clean':'bs(days_since_clean, df=4)','C(operator_id)':'C(operator_id)','C(shift)':'C(shift)','C(supplier_name)':'C(supplier_name)','C(line)':'C(line)'}
def X_of(keys): 
    return patsy.dmatrix(' + '.join(groups[k] for k in keys), d, return_type='dataframe')
allk=list(groups)
Xf=X_of(allk); mf=sm.GLM(Y,Xf,family=sm.families.Binomial()).fit()
phi=mf.pearson_chi2/mf.df_resid
print('full dev',round(mf.deviance,1),'phi',round(phi,2),'df',mf.df_resid)
for k in allk:
    Xr=X_of([x for x in allk if x!=k]); mr=sm.GLM(Y,Xr,family=sm.families.Binomial()).fit()
    ddf=mr.df_resid-mf.df_resid; F=((mr.deviance-mf.deviance)/ddf)/phi
    print(f'{k:20s} df {ddf:3.0f}  F {F:8.2f}  p {stats.f.sf(F,ddf,mf.df_resid):.2e}')
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.api as sm, patsy
from scipy import stats
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d0=df.dropna(subset=['mold_temp','humidity_pct']).copy()
groups={'mold_temp':'bs(mold_temp, df=5)','humidity_pct':'humidity_pct','cycle_time_s':'bs(cycle_time_s, df=4)','ambient_temp_c':'bs(ambient_temp_c, df=4)','days_since_clean':'bs(days_since_clean, df=4)','C(operator_id)':'C(operator_id)','C(shift)':'C(shift)','C(supplier_name)':'C(supplier_name)'}
for ln in ['L1','L2','L3','L4']:
    d=d0[d0.line==ln]
    Y=np.c_[d.defective_units, d.units_produced-d.defective_units].astype(float)
    allk=list(groups)
    X=lambda ks: patsy.dmatrix(' + '.join(groups[k] for k in ks), d, return_type='dataframe')
    mf=sm.GLM(Y,X(allk),family=sm.families.Binomial()).fit(); phi=mf.pearson_chi2/mf.df_resid
    out=[]
    for k in allk:
        mr=sm.GLM(Y,X([x for x in allk if x!=k]),family=sm.families.Binomial()).fit()
        ddf=mr.df_resid-mf.df_resid; F=((mr.deviance-mf.deviance)/ddf)/phi
        out.append(f'{k[:12]}={F:.1f}')
    print(ln,'phi',round(phi,1),' '.join(out))
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.api as sm, patsy
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
Y=np.c_[d.defective_units, d.units_produced-d.defective_units].astype(float)
f='bs(mold_temp, df=5) + humidity_pct + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(supplier_name) + C(line) + C(operator_id)'
X=patsy.dmatrix(f,d,return_type='dataframe')
m=sm.GLM(Y,X,family=sm.families.Binomial()).fit()
d['exp']=m.predict(X)*d.units_produced
d['obs']=d.defective_units
d['res_units']=d.obs-d.exp
# residual in units per line by month
t=d.groupby(['line',d.d.dt.to_period('M')]).apply(lambda g: pd.Series({'O/E':g.obs.sum()/g.exp.sum(),'n':len(g)})).round(3)
print(t.unstack(0).to_string())
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.api as sm, patsy
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
Y=np.c_[d.defective_units, d.units_produced-d.defective_units].astype(float)
f='bs(mold_temp, df=5) + humidity_pct + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(supplier_name) + C(line) + C(operator_id)'
X=patsy.dmatrix(f,d,return_type='dataframe')
m=sm.GLM(Y,X,family=sm.families.Binomial()).fit()
d['exp']=m.predict(X)*d.units_produced
l2=d[d.line=='L2'].sort_values('d').copy()
l2['r']=(l2.defective_units-l2.exp)/l2.units_produced
dates=sorted(l2.d.unique())
best=None
for cut in dates[10:-10]:
    a=l2.r[l2.d<cut]; b=l2.r[l2.d>=cut]
    t=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
    if best is None or abs(t)>abs(best[1]): best=(pd.Timestamp(cut).date(),t,a.mean(),b.mean(),len(a),len(b))
print('best split L2', best)
cut=pd.Timestamp(best[0])
print('before split O/E', round(l2[l2.d<cut].defective_units.sum()/l2[l2.d<cut].exp.sum(),3), 'after', round(l2[l2.d>=cut].defective_units.sum()/l2[l2.d>=cut].exp.sum(),3))
w=l2[(l2.d>='2025-05-20')&(l2.d<='2025-06-20')]
print(w.groupby('production_date').apply(lambda g: round(g.defective_units.sum()/g.exp.sum(),2)).to_string())
for ln in ['L1','L3','L4']:
    s=d[d.line==ln].sort_values('d'); s['r']=(s.defective_units-s.exp)/s.units_produced
    best2=None
    for cut2 in sorted(s.d.unique())[10:-10]:
        a=s.r[s.d<cut2]; b=s.r[s.d>=cut2]
        t=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best2 is None or abs(t)>abs(best2[1]): best2=(str(pd.Timestamp(cut2).date()),round(t,2))
    print(ln,'max split t',best2)
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
import statsmodels.api as sm, patsy
from scipy import stats
df=add_clean_age(load(), load_maint().query('event==\"mold_cleaning\"'))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
Y=np.c_[d.defective_units, d.units_produced-d.defective_units].astype(float)
base='bs(mold_temp, df=5) + humidity_pct + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(supplier_name) + C(line) + C(operator_id)'
# profile likelihood over candidate L2 start dates
res=[]
for cand in ['2025-06-01','2025-06-02','2025-06-05','2025-06-10','2025-06-13','2025-06-14','2025-06-15','2025-06-16','2025-06-20','2025-07-01']:
    d['step']=((d.line=='L2')&(d.d>=cand)).astype(float)
    X=patsy.dmatrix(base+' + step',d,return_type='dataframe')
    m=sm.GLM(Y,X,family=sm.families.Binomial()).fit()
    res.append((cand, round(m.deviance,2), round(m.params['step'],3)))
for r in res: print(r)
d['step']=((d.line=='L2')&(d.d>='2025-06-15')).astype(float)
groups={'mold_temp':'bs(mold_temp, df=5)','humidity_pct':'humidity_pct','cycle_time_s':'bs(cycle_time_s, df=4)','machine_age_years':'machine_age_years','ambient_temp_c':'bs(ambient_temp_c, df=4)','days_since_clean':'bs(days_since_clean, df=4)','C(operator_id)':'C(operator_id)','C(shift)':'C(shift)','C(supplier_name)':'C(supplier_name)','step':'step'}
allk=list(groups)
X=lambda ks: patsy.dmatrix(' + '.join(groups[k] for k in ks), d, return_type='dataframe')
mf=sm.GLM(Y,X(allk),family=sm.families.Binomial()).fit(); phi=mf.pearson_chi2/mf.df_resid
print('phi',round(phi,2))
for k in allk:
    mr=sm.GLM(Y,X([x for x in allk if x!=k]),family=sm.families.Binomial()).fit()
    ddf=mr.df_resid-mf.df_resid; F=((mr.deviance-mf.deviance)/ddf)/phi
    print(f'{k:20s} F {F:8.2f} p {stats.f.sf(F,ddf,mf.df_resid):.2e}')
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > model.py <<'EOF'
from clean import *
import statsmodels.api as sm, patsy
from scipy import stats

def prep():
    df = add_clean_age(load(), load_maint().query('event == "mold_cleaning"'))
    df['step'] = ((df.line == 'L2') & (df.d >= '2025-06-15')).astype(float)
    return df

def design(d, formula):
    return patsy.dmatrix(formula, d, return_type='dataframe')

def fit(d, formula):
    Y = np.c_[d.defective_units, d.units_produced - d.defective_units].astype(float)
    X = design(d, formula)
    m = sm.GLM(Y, X, family=sm.families.Binomial()).fit()
    return m, X
EOF
python3 -c "
from model import *
df=prep(); d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
F0='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step'
m0,_=fit(d, F0+' + C(supplier_name) + humidity_pct')
m1,_=fit(d, F0+' + C(supplier_name) * humidity_pct')
phi=m1.pearson_chi2/m1.df_resid
F=((m0.deviance-m1.deviance)/(m0.df_resid-m1.df_resid))/phi
print('humidity x supplier interaction F', round(F,2), 'p', stats.f.sf(F,2,m1.df_resid))
print(m1.summary2().tables[1].round(4).filter(regex='humid|supplier', axis=0).to_string())
for s in ['Alpha','Beta','Gamma']:
    g=d[d.supplier_name==s]
    b=m1.params
    print(s, 'hum range', g.humidity_pct.min(), g.humidity_pct.max())
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
df=prep(); d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
F0='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step + C(supplier_name)'
for name,f in [('linear x sup',F0+' + humidity_pct*C(supplier_name)'),('spline x sup',F0+' + bs(humidity_pct,df=4)*C(supplier_name)')]:
    m,X=fit(d,f); print(name,'dev',round(m.deviance,1),'phi',round(m.pearson_chi2/m.df_resid,2))
m,X=fit(d,F0+' + bs(humidity_pct,df=4)*C(supplier_name)')
grid=np.arange(12,73,6.0)
ref=d.copy()
for s in ['Alpha','Beta','Gamma']:
    rates=[]
    for h in grid:
        g=d[d.supplier_name==s].copy(); g['humidity_pct']=h
        Xg=design(g,F0+' + bs(humidity_pct,df=4)*C(supplier_name)')
        p=m.predict(Xg)
        rates.append(round(np.average(p,weights=g.units_produced),4))
    print(s, dict(zip(grid.round(0).astype(int), rates)))
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
df=prep(); d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
F0='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step + C(supplier_name)'
f=F0+' + bs(humidity_pct,df=4)*C(supplier_name)'
m,X=fit(d,f)
def pred(g):
    Xg=patsy.build_design_matrices([X.design_info], g, return_type='dataframe')[0]
    return m.predict(Xg)
grid=[12.1,15,20,25,30,35,40,45,50,55,60,65,72]
for s in ['Alpha','Beta','Gamma']:
    out=[]
    for h in grid:
        g=d[d.supplier_name==s].copy(); g['humidity_pct']=h
        out.append(round(np.average(pred(g),weights=g.units_produced),4))
    print(s, list(zip(grid,out)))
# raw Alpha rate by humidity bin
a=d[d.supplier_name=='Alpha'].copy()
a['hb']=pd.cut(a.humidity_pct,[12,20,25,30,35,40,45,50,60,75])
print(a.groupby('hb',observed=True).apply(lambda g: pd.Series({'raw':g.defective_units.sum()/g.units_produced.sum(),'n':len(g)})).round(4).to_string())
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
df=prep(); d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
F0='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step + C(supplier_name)'
f=F0+' + bs(humidity_pct,df=4)*C(supplier_name)'
m,X=fit(d,f)
def pred(g, mm=m, XX=X):
    Xg=patsy.build_design_matrices([XX.design_info], g, return_type='dataframe')[0]
    return mm.predict(Xg)
# fine grid argmin for Alpha
grid=np.arange(12.1,72.31,0.1)
g=d[d.supplier_name=='Alpha'].copy()
vals=[]
for h in grid:
    g['humidity_pct']=h
    vals.append(np.average(pred(g),weights=g.units_produced))
vals=np.array(vals); print('Alpha spline argmin', round(grid[vals.argmin()],1), round(vals.min(),5))
# quadratic cross-check
fq=F0+' + (humidity_pct+I(humidity_pct**2))*C(supplier_name)'
mq,Xq=fit(d,fq)
vals2=[]
for h in grid:
    g['humidity_pct']=h
    vals2.append(np.average(patsy.build_design_matrices([Xq.design_info], g, return_type='dataframe')[0].dot(mq.params) if False else mq.predict(patsy.build_design_matrices([Xq.design_info], g, return_type='dataframe')[0]),weights=g.units_produced))
vals2=np.array(vals2); print('Alpha quad argmin', round(grid[vals2.argmin()],1), 'quad dev',round(mq.deviance,1),'spline dev',round(m.deviance,1))
# C1: counterfactual supplier on complete cases
for s in ['Alpha','Beta','Gamma']:
    h=d.copy(); h['supplier_name']=s
    p=pred(h)
    print('C1 all->',s, 'overall rate', round((p*h.units_produced).sum()/h.units_produced.sum(),5))
print('actual overall (complete cases)', round(d.defective_units.sum()/d.units_produced.sum(),5), 'n',len(d))
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
df=prep(); d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
F0='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step + C(supplier_name)'
grid=np.arange(12.1,72.31,0.1)
g0=d[d.supplier_name=='Alpha'].copy()
for k in [3,4,6,8]:
    f=F0+f' + bs(humidity_pct,df={k})*C(supplier_name)'
    m,X=fit(d,f)
    vals=[]
    for h in grid:
        g=g0.copy(); g['humidity_pct']=h
        vals.append(np.average(m.predict(patsy.build_design_matrices([X.design_info], g, return_type='dataframe')[0]),weights=g.units_produced))
    vals=np.array(vals)
    print('df',k,'dev',round(m.deviance,1),'argmin Alpha',round(grid[vals.argmin()],1),round(vals.min(),5))
# also cubic polynomial
f=F0+' + (humidity_pct+I(humidity_pct**2)+I(humidity_pct**3))*C(supplier_name)'
m,X=fit(d,f); vals=[]
for h in grid:
    g=g0.copy(); g['humidity_pct']=h
    vals.append(np.average(m.predict(patsy.build_design_matrices([X.design_info], g, return_type='dataframe')[0]),weights=g.units_produced))
vals=np.array(vals); print('cubic dev',round(m.deviance,1),'argmin',round(grid[vals.argmin()],1))
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
df=prep(); d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
a=d[d.supplier_name=='Alpha'].copy()
base='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step'
res=[]
for k in np.arange(20,41,1.0):
    a['hi']=np.maximum(0,a.humidity_pct-k); a['lo']=np.maximum(0,k-a.humidity_pct)
    m,X=fit(a, base+' + hi + lo')
    res.append((k, round(m.deviance,2)))
print('hinge (abs-V) dev by knot', res)
best=min(res,key=lambda x:x[1]); print('best knot',best)
# quadratic on Alpha only
m,X=fit(a, base+' + humidity_pct + I(humidity_pct**2)')
print('alpha quad argmin', round(-m.params['humidity_pct']/(2*m.params['I(humidity_pct ** 2)']),2))
m,X=fit(a, base+' + bs(humidity_pct,df=6)')
grid=np.arange(12.1,72.3,0.1); g=a.copy(); vals=[]
for h in grid:
    g['humidity_pct']=h; vals.append(np.average(m.predict(patsy.build_design_matrices([X.design_info],g,return_type='dataframe')[0]),weights=g.units_produced))
print('alpha-only spline df6 argmin', round(grid[np.argmin(vals)],1))
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
df=prep(); d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
a=d[d.supplier_name=='Alpha'].copy()
base='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step'
m,X=fit(a, base)
a['exp']=m.predict(X)*a.units_produced
a['hb']=pd.cut(a.humidity_pct,np.arange(10,80,5))
t=a.groupby('hb',observed=True).apply(lambda g: pd.Series({'n':len(g),'O/E':round(g.defective_units.sum()/g.exp.sum(),3)}))
print(t.to_string())
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
df=prep()
cl=load_maint().query('event==\"mold_cleaning\"')
END=pd.Timestamp('2025-09-30')
# augmented schedule: add a cleaning every time 14 days would pass
aug=[]
for ln,g in cl.groupby('line'):
    dates=sorted(g.d)
    cur=dates[0]; sched=[cur]
    for c in dates[1:]:
        while (c-cur).days>14:
            cur=cur+pd.Timedelta(days=14); sched.append(cur)
        cur=c; sched.append(cur)
    while (END-cur).days>14:
        cur=cur+pd.Timedelta(days=14); sched.append(cur)
    aug += [(ln,x) for x in sched]
augdf=pd.DataFrame(aug,columns=['line','d'])
print('added cleanings', len(augdf)-len(cl), ' per line', (augdf.groupby('line').size()-cl.groupby('line').size()).to_dict())
new=add_clean_age(df.copy(), augdf)
df['dsc_new']=new.days_since_clean.values
print('old max', df.days_since_clean.max(), 'new max', df.dsc_new.max(), 'new mean', round(df.dsc_new.mean(),2))
print('actual overall defects / units', round(df.defective_units.sum()/df.units_produced.sum(),6))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
f='bs(mold_temp, df=5) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + C(line) + step + C(supplier_name) + bs(humidity_pct,df=4)*C(supplier_name)'
m,X=fit(d,f)
base=np.average(m.predict(X),weights=d.units_produced)
print('model baseline (complete cases)', round(base,5), ' actual cc', round(d.defective_units.sum()/d.units_produced.sum(),5))
g=d.copy(); g['days_since_clean']=g.dsc_new
Xg=patsy.build_design_matrices([X.design_info], g, return_type='dataframe')[0]
cf=np.average(m.predict(Xg),weights=g.units_produced)
print('C3 counterfactual complete-case rate', round(cf,5), ' ratio', round(cf/base,4))
print('scaled to full-period actual 0.059775:', round(0.0597752*cf/base,5))
" 2>&1 | grep -v -i -E 'warn|wls'

cd /tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from model import *
import statsmodels.formula.api as smf
df=prep()
print('A4 median mold temp (C, valid, corrected):', repr(df.mold_temp.median()), 'n valid', df.mold_temp.notna().sum())
print('A2 humidity invalid:', df.humidity_pct.isna().sum(), ' A1 unique:', df.batch_id.nunique())
o=smf.ols('qc_inspection_min ~ defective_units + units_produced + mold_temp + cycle_time_s + C(line) + C(shift) + humidity_pct', data=df.dropna(subset=['mold_temp','humidity_pct'])).fit()
print('qc OLS R2', round(o.rsquared,3), ' coef defective', round(o.params.defective_units,4), 'p', o.pvalues.defective_units)
o2=smf.ols('rework_cost_eur ~ defective_units + units_produced + mold_temp', data=df.dropna(subset=['mold_temp'])).fit()
print('rework OLS R2', round(o2.rsquared,3), 'coef defective', round(o2.params.defective_units,3))
o3=smf.ols('qc_inspection_min ~ units_produced + mold_temp + cycle_time_s + C(line) + C(shift)', data=df.dropna(subset=['mold_temp'])).fit()
print('qc R2 without defects', round(o3.rsquared,3))
" 2>&1 | grep -v -i -E 'warn|wls'
