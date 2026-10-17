ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && cat maintenance.csv && echo && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('==',c,'unique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    if df[c].nunique()<40: print(vc.to_dict())
    else: print(df[c].head(3).tolist(), [x for x in df[c].unique() if not x.replace('.','',1).replace('-','',1).isdigit()][:15])
"

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv')
print(df.dtypes)
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d))
print(d.head(8).to_string())
# are duplicates identical?
print('exact-dup rows:', df.duplicated().sum())
print(df.describe().T.to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
print('rows',len(df),'unique ids',df.batch_id.nunique())
print('humidity -1:',(df.humidity_pct==-1).sum(),' humidity<0 or >100:',((df.humidity_pct<0)|(df.humidity_pct>100)).sum(),' NaN:',df.humidity_pct.isna().sum())
print('humidity values <5:',sorted(df.humidity_pct[df.humidity_pct<5].dropna().unique())[:20])
print('mold_temp==0:',(df.mold_temp==0).sum())
print('mold_temp hist:'); print(np.histogram(df.mold_temp,bins=[0,1,100,150,180,190,200,210,220,230,240,250,300,350,380,400,420,470]))
print(df[df.mold_temp>300][['production_date','line','mold_temp']].head(20).to_string())
print('defect>units',(df.defective_units>df.units_produced).sum())
print(df.groupby('line').mold_temp.describe().to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
df['d']=pd.to_datetime(df.production_date)
l3=df[df.line=='L3'].sort_values('d')
l3['F']=l3.mold_temp>300
print(l3.groupby(l3.d.dt.to_period('M')).agg(n=('F','size'),F=('F','sum'),mt_med=('mold_temp','median')).to_string())
f=l3[(l3.mold_temp>0)]
print('L3 F-first date', f[f.F].d.min(), 'last F', f[f.F].d.max(), 'first nonF after', f[~f.F].d.min(), 'max nonF', f[~f.F].d.max())
print('L3 nonF dates after first F:', (f[(~f.F)&(f.d>=f[f.F].d.min())]).shape[0])
print(df[df.line=='L3'].loc[lambda x: (x.mold_temp>0)&(x.mold_temp<300)].d.agg(['min','max']))
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
df['d']=pd.to_datetime(df.production_date)
df['mt']=np.where(df.line=='L3',(df.mold_temp-32)*5/9,df.mold_temp)
df.loc[df.mold_temp==0,'mt']=np.nan
df.loc[df.line=='L3','mt']=np.where(df.loc[df.line=='L3','mold_temp']==0,np.nan,df.loc[df.line=='L3','mt'])
print(df.groupby('line').mt.describe().to_string())
l1=df[df.line=='L1'].copy()
l1['pre']=l1.d<'2025-04-14'
print(l1.groupby('pre').mt.describe().to_string())
print(df[df.line!='L1'].groupby(df.d.dt.to_period('M')).mt.median().to_string())
print(df[df.line=='L1'].groupby(df.d.dt.to_period('M')).mt.median().to_string())
print(df[df.line=='L3'].groupby(df.d.dt.to_period('M')).mt.median().to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
df['d']=pd.to_datetime(df.production_date)
df['mt']=np.where(df.line=='L3',(df.mold_temp-32)*5/9,df.mold_temp)
df.loc[df.mold_temp==0,'mt']=np.nan
df['wk']=df.d.dt.to_period('W')
ref=df[df.line!='L1'].groupby('wk').mt.median().rename('ref')
l1=df[df.line=='L1'].groupby('wk').agg(l1=('mt','median'),n=('mt','size')).join(ref)
l1['diff']=l1.l1-l1.ref
print(l1.round(2).to_string())
"

mkdir -p "$TMPDIR" /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > $SCR/clean.py <<'EOF'
import pandas as pd, numpy as np
D = '/tmp/edabench_claude_o132jdrt/'

raw = pd.read_csv(D + 'batches.csv')
df = raw.drop_duplicates().copy()          # 60 exact duplicate rows
df['d'] = pd.to_datetime(df.production_date)

# shift labels: Day/D/day/DAY/' Day' and Night/N/night/NIGHT/'Night '
s = df['shift'].str.strip().str.lower()
df['shift'] = s.map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
assert df['shift'].notna().all()

# supplier codes: strip + upper ('sp-01', ' Sp-01', 'SP-01 ')
df['supplier_code'] = df.supplier_code.str.strip().str.upper()
sup = pd.read_csv(D + 'suppliers.csv')
df = df.merge(sup, on='supplier_code', how='left', validate='m:1')
assert df.supplier_name.notna().all()

# humidity: -1 is a sentinel for invalid, NaN is missing
df['humidity_valid'] = df.humidity_pct.notna() & (df.humidity_pct >= 0) & (df.humidity_pct <= 100)
df['hum'] = df.humidity_pct.where(df.humidity_valid)

# mold temp: 0 = missing; L3 logged in Fahrenheit; L1 sensor +8 C after replacement 2025-04-14
mt = df.mold_temp.where(df.mold_temp != 0)
f_mask = (df.line == 'L3') & mt.notna()
mt = mt.mask(f_mask, (mt - 32) * 5 / 9)
l1_post = (df.line == 'L1') & (df.d >= '2025-04-14') & mt.notna()
mt = mt.mask(l1_post, mt - 8.0)
df['mt'] = mt

df['defect_rate'] = df.defective_units / df.units_produced

# mold cleaning: days since last cleaning per line (cleaning done before first shift)
mc = pd.read_csv(D + 'maintenance.csv', parse_dates=['date'])
mc = mc[mc.event == 'mold_cleaning']
df['days_since_clean'] = np.nan
for ln, g in df.groupby('line'):
    cl = np.sort(mc.loc[mc.line == ln, 'date'].values)
    idx = g.index
    dts = g.d.values
    pos = np.searchsorted(cl, dts, side='right') - 1   # last cleaning on or before the day
    last = np.where(pos >= 0, cl[np.clip(pos, 0, None)], np.datetime64('NaT'))
    df.loc[idx, 'days_since_clean'] = (dts - last) / np.timedelta64(1, 'D')
EOF
cd $SCR && python3 -c "
from clean import *
print('unique batches', df.batch_id.nunique(), len(df))
print('A2 invalid humidity', (~df.humidity_valid).sum())
print('A3', df.defective_units.sum()/df.units_produced.sum())
print('A4 median mt', df.mt.median(), df.mt.notna().sum())
print(df.shift.value_counts().to_dict())
print(df.groupby('supplier_name').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()))
print(df.days_since_clean.describe())
"

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
print(df['shift'].value_counts().to_dict())
print(df.groupby('supplier_name').apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})))
print(df.days_since_clean.describe())
print(df.groupby('line').days_since_clean.max())
print(df[(df.line=='L1')&(df.d.between('2025-04-10','2025-04-18'))].groupby('d').mt.agg(['median','size']))
print(df[(df.line!='L1')&(df.d.between('2025-04-10','2025-04-18'))].groupby('d').mt.agg(['median','size']))
"

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import statsmodels.api as sm, statsmodels.formula.api as smf
print('statsmodels', sm.__version__)
" && python3 -c "
import warnings; warnings.filterwarnings('ignore')
from clean import *
import statsmodels.formula.api as smf
m = df.dropna(subset=['mt','hum']).copy()
m['fail']=m.units_produced-m.defective_units
f = 'defective_units + fail ~ mt + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
g = smf.glm(f, data=m, family=sm.families.Binomial() if False else __import__('statsmodels.api').api.families.Binomial()).fit(scale='X2')
print(g.summary())
" 2>&1 | head -120

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import warnings; warnings.filterwarnings('ignore')
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
m = df.dropna(subset=['mt','hum']).copy()
print('n',len(m))
f = 'defect_rate ~ mt + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
g = smf.glm(f, data=m, family=sm.families.Binomial(), var_weights=m.units_produced).fit(scale='X2')
print(g.summary().tables[1])
print('dispersion', g.scale)
" 2>&1

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
m = df.dropna(subset=['mt','hum']).copy()
import patsy
y,X = patsy.dmatrices('defect_rate ~ mt + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean', m, return_type='dataframe')
print('X shape',X.shape,'rank',np.linalg.matrix_rank(X.values))
print(X.columns[np.linalg.svd(X.values,full_matrices=False)[2][-1].argsort()[-3:]].tolist())
# check if days_since_clean is constant per line-week or any perfect collinearity with date
print(m.groupby('line').days_since_clean.apply(lambda s: s.nunique()))
" 2>&1

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
pd.set_option('display.width',250)
print(pd.crosstab(df.operator_id, df.line).to_string())
print(pd.crosstab(df.operator_id, df['shift']).T.to_string())
print(pd.crosstab(df.line, df.supplier_name))
print(pd.crosstab(df.line, df['shift']))
" 2>&1

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
m = df.dropna(subset=['mt','hum']).copy()
base='defect_rate ~ mt + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(operator_id)'
fam=sm.families.Binomial()
g = smf.glm(base, data=m, family=fam, var_weights=m.units_produced).fit(scale='X2')
print('rank ok?', g.df_model, 'dispersion', round(g.scale,3))
print(g.summary().tables[1])
# nonlinearity checks in mold temperature, humidity, cycle time
for extra in ['+ I(mt**2)','+ I(hum**2)','+ I(cycle_time_s**2)','+ I(days_since_clean**2)','+ I(ambient_temp_c**2)','+ I(machine_age_years**2)']:
    h = smf.glm(base+extra, data=m, family=fam, var_weights=m.units_produced).fit(scale='X2')
    print(extra, 'pvalue', round(h.pvalues.iloc[-1],5), 'dev', round(h.deviance,1))
print('base dev', round(g.deviance,1))
" 2>&1

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import *
pd.set_option('display.width',250)
m=df.dropna(subset=['mt','hum']).copy()
m['hb']=pd.cut(m.hum,[-0.1,5,10,15,20,25,30,35,40,45,50,55,60,75])
g=m.groupby(['hb','supplier_name'],observed=True).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()}))
print(g.unstack().round(4).to_string())
m['mb']=pd.cut(m.mt,[180,195,200,205,210,215,220,225,230,240])
print(m.groupby('mb',observed=True).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()})).round(4).to_string())
" 2>&1

cd /tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > $TMPDIR/../scratchpad/fit.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
def fit(f, data=m):
    return smf.glm(f, data=data, family=fam, var_weights=data.units_produced).fit()
full_terms = ['mt','hum','I(hum**2)','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)','C(supplier_name)','days_since_clean','C(operator_id)']
F = 'defect_rate ~ ' + ' + '.join(full_terms)
g = fit(F)
scale = g.pearson_chi2 / g.df_resid
print('full dev', round(g.deviance,2), 'pearson dispersion', round(scale,3), 'df_resid', g.df_resid)
groups = {
 'mold_temp':['mt'], 'humidity':['hum','I(hum**2)'], 'cycle_time':['cycle_time_s'],
 'machine_age':['machine_age_years'], 'ambient':['ambient_temp_c'], 'shift':['C(shift)'],
 'supplier':['C(supplier_name)'], 'days_since_clean':['days_since_clean'], 'operator(vs line-only)':None,
}
for name, drop in groups.items():
    if drop is None:
        h = fit('defect_rate ~ mt + hum + I(hum**2) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)')
        k = h.df_resid - g.df_resid
    else:
        keep=[t for t in full_terms if t not in drop]
        h = fit('defect_rate ~ ' + ' + '.join(keep))
        k = h.df_resid - g.df_resid
    lr = (h.deviance - g.deviance)/scale
    p = stats.chi2.sf(lr, k)
    print(f'{name:28s} df={k:3d} scaled LR={lr:9.2f} p={p:.3g}')
EOF
python3 $TMPDIR/../scratchpad/fit.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > $SCR/fit.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
def fit(f, data=m):
    return smf.glm(f, data=data, family=fam, var_weights=data.units_produced).fit()
full_terms = ['mt','hum','I(hum**2)','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)','C(supplier_name)','days_since_clean','C(operator_id)']
F = 'defect_rate ~ ' + ' + '.join(full_terms)
g = fit(F)
scale = g.pearson_chi2 / g.df_resid
print('full dev', round(g.deviance,2), 'pearson dispersion', round(scale,3), 'df_resid', g.df_resid)
groups = {
 'mold_temp':['mt'], 'humidity':['hum','I(hum**2)'], 'cycle_time':['cycle_time_s'],
 'machine_age':['machine_age_years'], 'ambient':['ambient_temp_c'], 'shift':['C(shift)'],
 'supplier':['C(supplier_name)'], 'days_since_clean':['days_since_clean'], 'operator(vs line-only)':None,
}
for name, drop in groups.items():
    if drop is None:
        h = fit('defect_rate ~ mt + hum + I(hum**2) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)')
    else:
        keep=[t for t in full_terms if t not in drop]
        h = fit('defect_rate ~ ' + ' + '.join(keep))
    k = h.df_resid - g.df_resid
    lr = (h.deviance - g.deviance)/scale
    p = stats.chi2.sf(lr, k)
    print(f'{name:28s} df={k:3d} scaled LR={lr:9.2f} p={p:.3g}')
EOF
cd $SCR && python3 fit.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > regime.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
m = df.dropna(subset=['mt','hum']).copy()
g = smf.glm('defect_rate ~ mt + hum + I(hum**2) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)',
            data=m, family=sm.families.Binomial(), var_weights=m.units_produced).fit()
m['mu']=g.fittedvalues
m['pr']=(m.defective_units-m.units_produced*m.mu)/np.sqrt(m.units_produced*m.mu*(1-m.mu))
print('pearson dispersion', round((m.pr**2).mean(),3))
res=[]
for ln,gr in m.groupby('line'):
    gr=gr.sort_values('d').reset_index(drop=True)
    x=gr.pr.values; n=len(x); best=(0,None,None)
    for i in range(40,n-40):
        a,b=x[:i],x[i:]
        t=stats.ttest_ind(a,b,equal_var=False).statistic
        if abs(t)>abs(best[0]): best=(t,i,gr.d.iloc[i])
    res.append((ln,round(best[0],2),best[2],gr.pr.mean().round(3)))
    print(ln,'max |t| at split',best[1],'date',best[2].date() if best[2] is not None else None,'t=',round(best[0],2))
    # monthly mean residual
    print(gr.groupby(gr.d.dt.to_period('M')).pr.agg(['mean','size']).round(2).T.to_string())
EOF
python3 regime.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > l2.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
m = df.dropna(subset=['mt','hum']).copy()
g = smf.glm('defect_rate ~ mt + hum + I(hum**2) + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)',
            data=m, family=sm.families.Binomial(), var_weights=m.units_produced).fit()
m['mu']=g.fittedvalues
m['pr']=(m.defective_units-m.units_produced*m.mu)/np.sqrt(m.units_produced*m.mu*(1-m.mu))
l2=m[m.line=='L2'].sort_values(['d','batch_id'])
w=l2[(l2.d>='2025-06-01')&(l2.d<='2025-06-24')]
print(w.groupby('d').agg(n=('pr','size'),pr=('pr','mean'),rate=('defect_rate','mean'),mt=('mt','mean'),hum=('hum','mean'),ct=('cycle_time_s','mean'),dsc=('days_since_clean','mean')).round(3).to_string())
# candidate step dates: best split by sum of squared residual means
x=l2.pr.values; dates=l2.d.values
best=[]
for i in range(30,len(x)-30):
    t=stats.ttest_ind(x[:i],x[i:],equal_var=False).statistic
    best.append((abs(t),i,str(pd.Timestamp(dates[i]).date())))
best.sort(reverse=True); print(best[:5])
# last pre-step and first post-step batches with dates
i=best[0][1]
print('last pre', pd.Timestamp(dates[i-1]).date(), 'first post', pd.Timestamp(dates[i]).date())
print('L2 mean mt pre/post', l2.mt.iloc[:i].mean().round(2), l2.mt.iloc[i:].mean().round(2))
print('L2 hum pre/post', l2.hum.iloc[:i].mean().round(2), l2.hum.iloc[i:].mean().round(2))
print('L2 cycle pre/post', l2.cycle_time_s.iloc[:i].mean().round(2), l2.cycle_time_s.iloc[i:].mean().round(2))
print('L2 days_since pre/post', l2.days_since_clean.iloc[:i].mean().round(2), l2.days_since_clean.iloc[i:].mean().round(2))
print('L2 supplier mix pre/post'); print(pd.crosstab(l2.supplier_name, l2.d>=pd.Timestamp(dates[i])))
print(l2[['shift']].assign(p=l2.d>=pd.Timestamp(dates[i])).groupby('p')['shift'].value_counts(normalize=True).round(2))
EOF
python3 l2.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > step.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
m = df.dropna(subset=['mt','hum']).copy()
base='defect_rate ~ mt + hum + I(hum**2) + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)'
b = smf.glm(base, data=m, family=sm.families.Binomial(), var_weights=m.units_produced).fit()
l2d = sorted(m.loc[m.line=='L2','d'].unique())
rows=[]
for D in pd.to_datetime(l2d):
    if D < pd.Timestamp('2025-05-15') or D > pd.Timestamp('2025-07-15'): continue
    m['post']=((m.line=='L2')&(m.d>=D)).astype(int)
    h = smf.glm(base+'+ post', data=m, family=sm.families.Binomial(), var_weights=m.units_produced).fit()
    rows.append((str(D.date()), round(h.deviance,2), round(h.params['post'],3)))
rows.sort(key=lambda r:r[1])
for r in rows[:8]: print(r)
# also check that the step is not present on other lines with the same date
EOF
python3 step.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && python3 -c "
from clean import *
import statsmodels.formula.api as smf
import numpy as np
print(df[['defective_units','units_produced','defect_rate','qc_inspection_min','rework_cost_eur','mt','hum','cycle_time_s','ambient_temp_c']].corr().round(3).to_string())
r=smf.ols('rework_cost_eur ~ defective_units + units_produced', data=df).fit(); print('rework ~ defects+units R2',round(r.rsquared,4)); print(r.params.round(4).to_dict())
r2=smf.ols('rework_cost_eur ~ defective_units', data=df).fit(); print('rework ~ defects R2', round(r2.rsquared,4), r2.params.round(3).to_dict())
q=smf.ols('qc_inspection_min ~ defective_units + units_produced + mt + hum + cycle_time_s + C(line)', data=df).fit(); print('qc R2',round(q.rsquared,4), q.params.round(4).to_dict())
q2=smf.ols('qc_inspection_min ~ defect_rate + C(line)', data=df).fit(); print('qc~rate+line R2',round(q2.rsquared,4))
"

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && python3 -c "
from clean import *
import statsmodels.formula.api as smf
a=smf.ols('qc_inspection_min ~ defective_units', data=df).fit(); print('qc~defects R2',round(a.rsquared,4), a.params.round(4).to_dict())
b=smf.ols('qc_inspection_min ~ defective_units + C(line)+C(supplier_name)+mt+hum+cycle_time_s+ambient_temp_c+C(shift)+days_since_clean+machine_age_years', data=df).fit(); print('qc full R2',round(b.rsquared,4), 'defect coef', round(b.params['defective_units'],4), 'p', round(b.pvalues['defective_units'],4))
c=smf.ols('qc_inspection_min ~ C(line)+C(supplier_name)+mt+hum+cycle_time_s+ambient_temp_c+C(shift)+days_since_clean+machine_age_years', data=df).fit(); print('qc w/o defects R2',round(c.rsquared,4))
"

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > inter.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
m = df.dropna(subset=['mt','hum']).copy()
fam=sm.families.Binomial()
def fit(f): return smf.glm(f, data=m, family=fam, var_weights=m.units_produced).fit()
base='defect_rate ~ mt + hum + I(hum**2) + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)'
g=fit(base); scale=g.pearson_chi2/g.df_resid
print('base dev',round(g.deviance,1),'disp',round(scale,3))
for name,extra in {'sup x hum':' + C(supplier_name):hum', 'sup x hum2':' + C(supplier_name):I(hum**2)',
                   'sup x hum (both)':' + C(supplier_name):hum + C(supplier_name):I(hum**2)',
                   'sup x mt':' + C(supplier_name):mt','sup x cycle':' + C(supplier_name):cycle_time_s','sup x shift':' + C(supplier_name):C(shift)',
                   'sup x line':' + C(supplier_name):C(line)'}.items():
    h=fit(base+extra); k=h.df_resid-g.df_resid
    lr=(g.deviance-h.deviance)/scale
    print(f'{name:18s} k={k} scaledLR={lr:8.2f} p={stats.chi2.sf(lr,k):.3g}')
print(pd.crosstab(m.line,m.supplier_name))
EOF
python3 inter.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > final.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
df['post_L2'] = ((df.line == 'L2') & (df.d >= '2025-06-16')).astype(int)
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
def fit(f, data=m): return smf.glm(f, data=data, family=fam, var_weights=data.units_produced).fit()
F = ('defect_rate ~ mt + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(line) + post_L2 + days_since_clean'
     ' + C(supplier_name) * (hum + I(hum**2))')
g = fit(F); scale = g.pearson_chi2 / g.df_resid
print('dev', round(g.deviance,1), 'pearson disp', round(scale,3), 'df_resid', g.df_resid)
print(g.params.round(4).to_string())
print('p-values:'); print(g.pvalues.round(4).to_string())
for name, drop in {'mold_temp':['mt'],'humidity x supplier':['C(supplier_name) * (hum + I(hum**2))'],'cycle_time':['cycle_time_s'],
                    'machine_age':['machine_age_years'],'ambient':['ambient_temp_c'],'shift':['C(shift)'],
                    'days_since_clean':['days_since_clean']}.items():
    if name=='humidity x supplier':
        f2 = F.replace(' + C(supplier_name) * (hum + I(hum**2))','')
        f2 += ' + C(supplier_name)'
    else:
        f2 = F
        for t in drop: f2 = f2.replace(' + '+t,'').replace(t+' + ','')
    h = fit(f2); k = g.df_resid - h.df_resid
    lr = (h.deviance-g.deviance)/scale
    print(f'{name:22s} df={abs(k)} scaledLR={lr:9.2f} p={stats.chi2.sf(lr,abs(k)):.3g}')
EOF
python3 final.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > predict.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
D = '/tmp/edabench_claude_o132jdrt/'
df['post_L2'] = ((df.line == 'L2') & (df.d >= '2025-06-16')).astype(int)
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
def fit(f, data=m): return smf.glm(f, data=data, family=fam, var_weights=data.units_produced).fit()
F = ('defect_rate ~ mt + cycle_time_s + C(shift) + C(line) + post_L2 + days_since_clean'
     ' + C(supplier_name) * (hum + I(hum**2))')
g = fit(F); scale = g.pearson_chi2 / g.df_resid
print('final: dev', round(g.deviance,1), 'disp', round(scale,3))
print((g.params).round(4).to_string())
# operator check within this model (operators nest in lines; compare with line-only)
h_op = fit(F.replace('C(line)','C(operator_id)'))
lr = (g.deviance-h_op.deviance)/scale; k = g.df_resid-h_op.df_resid
print('operator (vs line) LR', round(lr,2), 'df', k, 'p', round(stats.chi2.sf(lr,k),4))
# machine age / ambient
for t in ['machine_age_years','ambient_temp_c']:
    h = fit(F + ' + ' + t)
    lr=(g.deviance-h.deviance)/scale
    print(t,'LR', round(lr,2),'p', round(stats.chi2.sf(lr,1),4))

# ---- prediction frame: all 3000 batches
# mold temp missing (0) -> line median (conv. units); humidity missing -> marginalise over observed humidity
P = df.copy()
P['mt'] = P.mt.fillna(P.groupby('line').mt.transform('median'))
valid_hum = P.loc[P.hum.notna(),'hum'].values
def expected_defect_rate(frame):
    frame = frame.copy(); frame['rid'] = np.arange(len(frame))
    ok = frame[frame.hum.notna()]
    miss = frame[frame.hum.isna()].drop(columns='hum').assign(k=1)
    hv = pd.DataFrame({'hum': valid_hum, 'k': 1})
    ex = miss.merge(hv, on='k').drop(columns='k')
    allrows = pd.concat([ok, ex], ignore_index=True)
    allrows['p'] = g.predict(allrows)
    pr = allrows.groupby('rid').p.mean()
    return pr.reindex(range(len(frame))).values
P['p_obs'] = expected_defect_rate(P)
def overall(p): return (p*P.units_produced).sum()/P.units_produced.sum()
print('actual overall A3', round(P.defective_units.sum()/P.units_produced.sum(),5), 'model overall', round(overall(P.p_obs.values),5))

# ---- C1: all resin from one supplier
for s in ['Alpha','Beta','Gamma']:
    Q = P.copy(); Q['supplier_name'] = s
    print('C1', s, round(overall(expected_defect_rate(Q)),5))

# ---- C2: Alpha humidity optimum (logit quadratic minimum), plus grid check
b1 = g.params['hum']; b2 = g.params['I(hum ** 2)']
print('C2 quadratic optimum for Alpha', round(-b1/(2*b2),3))
grid = np.arange(np.floor(valid_hum.min()), np.ceil(valid_hum.max())+0.1, 0.1)
ref = P.loc[P.supplier_name=='Alpha'].iloc[0:1].copy()
rows=[]
for hh in grid:
    r = P.loc[P.supplier_name=='Alpha'].copy(); r['hum']=hh
    rows.append(g.predict(r).mean())
rows=np.array(rows)
print('C2 grid argmin (avg over Alpha batches)', round(grid[rows.argmin()],2), 'rate', round(rows.min(),5))
print('grid range', grid.min(), grid.max())
EOF
python3 predict.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > op.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
df['post_L2'] = ((df.line == 'L2') & (df.d >= '2025-06-16')).astype(int)
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
def fit(f, data=m): return smf.glm(f, data=data, family=fam, var_weights=data.units_produced).fit()
F = ('defect_rate ~ mt + cycle_time_s + C(shift) + C(operator_id) + post_L2 + days_since_clean'
     ' + C(supplier_name) * (hum + I(hum**2))')
g = fit(F); scale=g.pearson_chi2/g.df_resid
# within-line operator effects: operator mean rate residual relative to line mean
m['mu']=g.fittedvalues
m['pr']=(m.defective_units-m.units_produced*m.mu)/np.sqrt(m.units_produced*m.mu*(1-m.mu))
t=m.groupby(['line','operator_id']).agg(n=('pr','size'),pr=('pr','mean'))
t['pr_dev']=t.pr-t.groupby(level=0).pr.transform('mean')
print(t.round(3).to_string())
# which operators deviate (per-operator LR within line: drop-one)
# compare with a model where line-specific operator effects are pooled
print(g.params.filter(like='operator').round(3).to_string())
# Alpha humidity shape: flexible check
for extra in ['+ I(hum**3)','+ I(hum**3) + I(hum**4)']:
    h=fit(F+extra)
    print(extra,'LR',round((g.deviance-h.deviance)/scale,2),'p',round(stats.chi2.sf((g.deviance-h.deviance)/scale,1 if 'hum**4' not in extra else 2),4))
EOF
python3 op.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > op2.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
df['post_L2'] = ((df.line == 'L2') & (df.d >= '2025-06-16')).astype(int)
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
F = ('defect_rate ~ mt + cycle_time_s + C(shift) + C(operator_id) + post_L2 + days_since_clean'
     ' + C(supplier_name) * (hum + I(hum**2))')
g = smf.glm(F, data=m, family=fam, var_weights=m.units_produced).fit()
scale = g.pearson_chi2/g.df_resid
# within-line contrasts: each operator vs first operator of its line (operator in line-set)
names=[n for n in g.params.index if 'operator' in n]
# joint Wald on all operator coefficients that are within-line (exclude the line-level baseline which is absorbed); 
# with nested design, the 20 within-line contrasts = operator-coef differences; test via restriction matrix
ops=sorted(m.operator_id.unique())
line_of={o:m.loc[m.operator_id==o,'line'].iloc[0] for o in ops}
base={'L1':'OP-01','L2':'OP-07','L3':'OP-13','L4':'OP-19'}
R=[]
for ln in ['L1','L2','L3','L4']:
    members=[o for o in ops if line_of[o]==ln]
    b=base[ln]
    for o in members:
        if o==b: continue
        # contrast: coef(o)-coef(b) ; coef(b)=0 (base in each line is absorbed only via intercept) 
        r=np.zeros(len(g.params)); 
        ci=list(g.params.index).index(f'C(operator_id)[T.{o}]')
        r[ci]=1
        if f'C(operator_id)[T.{b}]' in g.params.index:
            r[list(g.params.index).index(f'C(operator_id)[T.{b}]')]=-1
        R.append(r)
R=np.array(R)
# Note the line baseline is shared: operator dummies are relative to OP-01 overall, so compare within-line by R
ct = g.wald_test(R, scalar=True, use_f=False)
print('Wald (unscaled chi2)', round(float(ct.statistic),2), 'df', R.shape[0])
print('Wald scaled by dispersion', round(float(ct.statistic)/scale,2), 'p', round(stats.chi2.sf(float(ct.statistic)/scale, R.shape[0]),4))
EOF
python3 op2.py 2>&1 | tail -5

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > op3.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
df['post_L2'] = ((df.line == 'L2') & (df.d >= '2025-06-16')).astype(int)
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
def fit(f): return smf.glm(f, data=m, family=fam, var_weights=m.units_produced).fit()
base = ('defect_rate ~ mt + cycle_time_s + C(shift) + post_L2 + days_since_clean'
        ' + C(supplier_name) * (hum + I(hum**2))')
specs = {
 'A line FE': base+' + C(line)',
 'A line FE + mt^2': base+' + C(line) + I(mt**2)',
 'A line FE + line*mt': base+' + C(line)*mt',
 'A line FE + line*cycle': base+' + C(line)*cycle_time_s',
 'A line FE + line*days': base+' + C(line)*days_since_clean',
 'A line FE + line*shift': base+' + C(line)*C(shift)',
}
for name, f in specs.items():
    a = fit(f); scale=a.pearson_chi2/a.df_resid
    b = fit(f.replace('C(line)','C(operator_id)') if 'C(line)' in f and 'C(line)*' not in f else f.replace('C(line)*','C(operator_id)*'))
    lr=(a.deviance-b.deviance)/scale; k=a.df_resid-b.df_resid
    print(f'{name:24s} disp={scale:.3f}  operator-within LR={lr:6.2f} df={k} p={stats.chi2.sf(lr,k):.4f}  (line-only dev {a.deviance:.1f})')
EOF
python3 op3.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > op4.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
df['post_L2'] = ((df.line == 'L2') & (df.d >= '2025-06-16')).astype(int)
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
F = ('defect_rate ~ mt + cycle_time_s + C(shift) + C(operator_id) + post_L2 + days_since_clean'
     ' + C(supplier_name) * (hum + I(hum**2))')
g = smf.glm(F, data=m, family=fam, var_weights=m.units_produced).fit()
scale=g.pearson_chi2/g.df_resid
grp = pd.factorize(m.line+'|'+m.production_date)[0]
gc = smf.glm(F, data=m, family=fam, var_weights=m.units_produced).fit(cov_type='cluster', cov_kwds={'groups':grp})
ops=sorted(m.operator_id.unique()); line_of={o:m.loc[m.operator_id==o,'line'].iloc[0] for o in ops}
base={'L1':'OP-01','L2':'OP-07','L3':'OP-13','L4':'OP-19'}
idx=list(g.params.index); R=[]
for o in ops:
    b=base[line_of[o]]
    if o==b: continue
    r=np.zeros(len(idx)); r[idx.index(f'C(operator_id)[T.{o}]')]=1
    if b!='OP-01': r[idx.index(f'C(operator_id)[T.{b}]')]=-1
    R.append(r)
R=np.array(R)
w=gc.wald_test(R, scalar=True, use_f=False)
print('clustered Wald chi2', round(float(w.statistic),2), 'df', len(R), 'p', round(float(w.pvalue),4))
w2=g.wald_test(R, scalar=True, use_f=False)
print('dispersion-scaled Wald p', round(stats.chi2.sf(float(w2.statistic)/scale,len(R)),4))
print('clusters', len(np.unique(grp)))
EOF
python3 op4.py

SCR=/tmp/claude-0/-tmp-edabench-claude-o132jdrt/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $SCR && cat > c3.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
from clean import *
import numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
D = '/tmp/edabench_claude_o132jdrt/'
df['post_L2'] = ((df.line == 'L2') & (df.d >= '2025-06-16')).astype(int)
m = df.dropna(subset=['mt','hum']).copy()
fam = sm.families.Binomial()
F = ('defect_rate ~ mt + cycle_time_s + C(shift) + C(line) + post_L2 + days_since_clean'
     ' + C(supplier_name) * (hum + I(hum**2))')
g = smf.glm(F, data=m, family=fam, var_weights=m.units_produced).fit()

# counterfactual cleaning: real cleanings + a forced one whenever 14 days have passed since the last cleaning
mc = pd.read_csv(D + 'maintenance.csv', parse_dates=['date'])
mc = mc[mc.event == 'mold_cleaning']
df['days_cf'] = np.nan
for ln in df.line.unique():
    actual = set(mc.loc[mc.line == ln, 'date'].dt.normalize())
    last = None
    cal = {}
    for day in pd.date_range('2024-12-01', '2025-09-30'):
        if day in actual:
            last = day
        elif last is not None and (day - last).days >= 14:
            last = day                                   # forced cleaning before first shift
        cal[day] = last
    sel = df.line == ln
    df.loc[sel, 'days_cf'] = [(d - cal[d]).days for d in df.loc[sel, 'd']]
print('days_cf max', df.days_cf.max(), ' mean actual', round(df.days_since_clean.mean(),3), ' mean cf', round(df.days_cf.mean(),3))
print('batches with actual days > 13:', (df.days_since_clean>13).sum(), ' cf >13:', (df.days_cf>13).sum())

# prediction frame: missing mold temp -> line median; missing humidity -> average over observed humidity values
P = df.copy()
P['mt'] = P.mt.fillna(P.groupby('line').mt.transform('median'))
valid_hum = P.loc[P.hum.notna(),'hum'].values
def expected(frame, dcol):
    frame = frame.assign(days_since_clean=frame[dcol]).copy()
    frame['rid'] = np.arange(len(frame))
    ok = frame[frame.hum.notna()]
    miss = frame[frame.hum.isna()].drop(columns='hum').assign(k=1)
    ex = miss.merge(pd.DataFrame({'hum': valid_hum, 'k': 1}), on='k').drop(columns='k')
    allrows = pd.concat([ok, ex], ignore_index=True)
    allrows['p'] = g.predict(allrows)
    return allrows.groupby('rid').p.mean().reindex(range(len(frame))).values
def overall(p): return (p*P.units_produced).sum()/P.units_produced.sum()
p_act = expected(P, 'days_since_clean'); p_cf = expected(P, 'days_cf')
print('actual overall (A3)', round(P.defective_units.sum()/P.units_produced.sum(),5))
print('model overall, actual cleaning', round(overall(p_act),5))
print('model overall, cleaning every 14 days', round(overall(p_cf),5))
EOF
python3 c3.py
