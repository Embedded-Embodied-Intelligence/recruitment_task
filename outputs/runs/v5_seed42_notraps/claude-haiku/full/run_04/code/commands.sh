pwd && ls -la && wc -l *.csv && for f in *.csv; do echo "== $f"; head -5 "$f"; done

cat suppliers.csv; echo; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc=b[c].value_counts()
    print('--',c,'unique',b[c].nunique(),'top',vc.head(8).to_dict())
print('dup batch rows', b.duplicated().sum(), 'dup batch_id', b.batch_id.duplicated().sum())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units']:
    x=pd.to_numeric(b[c],errors='coerce')
    bad=b.loc[x.isna()&(b[c]!=''),c].unique()
    print(c,'nonnum',bad[:20],'empty',(b[c]=='').sum(),'min',x.min(),'max',x.max())
    print(x.describe().round(2).to_dict())
h=pd.to_numeric(b.humidity_pct,errors='coerce')
print('humidity out of 0-100:', ((h<0)|(h>100)).sum(), sorted(h.dropna())[:10], sorted(h.dropna())[-10:])
m=pd.to_numeric(b.mold_temp,errors='coerce')
print(np.histogram(m.dropna(),bins=20))
print(sorted(m.dropna())[:10], sorted(m.dropna())[-10:])
print('b.production_date', pd.to_datetime(b.production_date,errors='coerce').isna().sum())
"

cat maintenance.csv; echo; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv')
b['d']=pd.to_datetime(b.production_date)
print(b.groupby('line')[['mold_temp','humidity_pct','ambient_temp_c','cycle_time_s','defective_units','units_produced']].agg(['mean','min','max']).round(2).T)
print(b.groupby(b.d.dt.month)[['mold_temp','humidity_pct']].agg(['mean','min','max','count']).round(2))
print(b.production_date.min(), b.production_date.max())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
b['d']=pd.to_datetime(b.production_date)
b['rate']=b.defective_units/b.units_produced
b['post']=b.d>=pd.Timestamp('2025-04-14')
print(b.groupby(['line','post']).mold_temp.agg(['mean','median','std','count']).round(2))
print(b.groupby(['line','post']).humidity_pct.agg(['mean','median','count']).round(2))
# per-line 2-week rates
b['wk']=b.d.dt.to_period('M')
print(b.pivot_table(index='wk',columns='line',values='rate',aggfunc='mean').round(4))
print(b.pivot_table(index='wk',columns='line',values='mold_temp',aggfunc='mean').round(2))
"

python3 -c "
import pandas as pd, numpy as np, re
b=pd.read_csv('batches.csv')
print('dup content ignoring id:', b.drop(columns='batch_id').duplicated().sum())
print('defective>units', (b.defective_units>b.units_produced).sum())
print('bad id format', (~b.batch_id.str.match(r'^B-\d{6}$')).sum(), b.batch_id[~b.batch_id.str.match(r'^B-\d{6}$')].tolist()[:10])
print('humidity counts', b.humidity_pct.value_counts().head(3).to_dict())
print('mold counts', b.mold_temp.value_counts().head(3).to_dict())
print('cycle_time <30 & >30 counts', (b.cycle_time_s<30).sum(), (b.cycle_time_s>35).sum())
print(b.cycle_time_s.describe())
print('units by line', b.groupby('line').units_produced.describe())
# stuck sensor: consecutive identical humidity within line sorted by date
bs=b.sort_values(['line','production_date'])
same=(bs.humidity_pct.eq(bs.groupby('line').humidity_pct.shift()) & bs.humidity_pct.notna())
print('consecutive same humidity within line', same.sum())
print(b.loc[b.humidity_pct.between(12.0,12.2)].shape, b.loc[b.humidity_pct.isna()].line.value_counts().to_dict())
print(b.isna().sum())
"

python3 -c "import statsmodels, sklearn, scipy; print(statsmodels.__version__, sklearn.__version__, scipy.__version__)"; python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
m=b.mold_temp.dropna()
h,e=np.histogram(m,bins=np.arange(185,236,1))
for a,c in zip(e,h): print(int(a),'#'*(c//3), c)
"

python3 -c "import statsmodels; print(statsmodels.__version__)"; python3 -c "import scipy; print(scipy.__version__)"; python3 -c "import numpy, pandas; print(numpy.__version__, pandas.__version__)"; pip list 2>/dev/null | grep -i -E "statsmodels|scipy|sklearn|scikit" 

cd "$PWD" && cat > $TMPDIR/explore.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_csv('batches.csv')
s=pd.read_csv('suppliers.csv')
b=b.merge(s,on='supplier_code',how='left')
b['d']=pd.to_datetime(b.production_date)
b['rate']=b.defective_units/b.units_produced
b['ct_dev']=b.cycle_time_s-b.recipe_cycle_time_s
print(b.groupby('supplier_name').apply(lambda g: pd.Series({'n':len(g),'rate_pooled':g.defective_units.sum()/g.units_produced.sum(),'rate_mean':g.rate.mean()})))
print(b.groupby('shift').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()))
print(b.groupby('operator_id').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).sort_values().to_dict())
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
f='defective_units + (units_produced-defective_units) ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
m=smf.glm(f,data=d,family=sm.families.Binomial()).fit(scale='X2')
print(m.summary())
EOF
python3 $TMPDIR/explore.py 2>&1 | head -150

cat > $TMPDIR/common.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_csv('batches.csv')
s=pd.read_csv('suppliers.csv')
b=b.merge(s,on='supplier_code',how='left')
b['d']=pd.to_datetime(b.production_date)
b['rate']=b.defective_units/b.units_produced
b['ct_dev']=b.cycle_time_s-b.recipe_cycle_time_s
def glm(f,data):
    return smf.glm(f,data=data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
EOF
cat > $TMPDIR/m1.py <<'EOF'
import sys; sys.path.insert(0,'/private/var/folders/7h/28064gg93518rt30grsmrxk80000gn/T/edabench_claude_1s9nzijn/.tmp_x')
EOF
cd "$PWD" && cat > $TMPDIR/m1.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
f='rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
m=glm(f,d); print(m.summary())
EOF
python3 $TMPDIR/m1.py 2>&1 | head -80

cd "$PWD" && cat > $TMPDIR/rank.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
import patsy
print('supplier null after merge', b.supplier_name.isna().sum())
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
y,X=patsy.dmatrices('rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)',d,return_type='dataframe')
print(X.shape, np.linalg.matrix_rank(X.values))
print(pd.crosstab(d.operator_id,d.line))
print(pd.crosstab(d.operator_id,d.shift))
print(pd.crosstab(d.supplier_name,d.line))
print(pd.crosstab(d.line,d.shift))
EOF
python3 $TMPDIR/rank.py

cd "$PWD" && cat > $TMPDIR/m2.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
base='rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + C(operator_id)'
m=glm(base,d); print(m.summary().tables[1])
print('deviance',m.deviance,'df',m.df_resid,'llf',m.llf)
for name,f in {
 'quad_hum': base+' + I(humidity_pct**2)',
 'quad_mold': base+' + I(mold_temp**2)',
 'quad_ct': base+' + I(cycle_time_s**2)',
 'hum_x_supp': base+' + humidity_pct:C(supplier_name)',
 'mold_x_supp': base+' + mold_temp:C(supplier_name)',
 'ct_x_supp': base+' + cycle_time_s:C(supplier_name)',
}.items():
    mm=glm(f,d); print(name, 'llf', round(mm.llf,2), 'AIC-scaled dev', round(mm.deviance,2))
EOF
python3 $TMPDIR/m2.py 2>&1 | grep -v Warning

cd "$PWD" && cat > $TMPDIR/clean.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
mt=pd.read_csv('maintenance.csv',parse_dates=['date'])
mc=mt[mt.event=='mold_cleaning'][['date','line']].copy()
print(mt.event.value_counts())
gaps=[]
for ln,g in mc.groupby('line'):
    dates=sorted(g.date.tolist())
    prev=pd.Timestamp('2024-12-29') if ln=='L3' else None
    ds=sorted(g.date)
    print(ln, 'cleanings', len(ds), 'first',ds[0].date(), 'max gap', max((ds[i+1]-ds[i]).days for i in range(len(ds)-1)))
    gaps += [(ln,ds[i].date(),(ds[i+1]-ds[i]).days) for i in range(len(ds)-1)]
g=pd.DataFrame(gaps,columns=['line','from','gap'])
print(g.groupby('line').gap.describe())
print('gaps>14:', (g.gap>14).sum())
print(g[g.gap>14])
# days since last cleaning (cleaning on day counts, before first shift)
def dsl(row):
    ln=row.line; dt=row.d
    cand=mc[(mc.line==ln)&(mc.date<=dt)]
    if len(cand)==0: return np.nan
    return (dt-cand.date.max()).days
b['days_since']=b.apply(dsl,axis=1)
print(b.days_since.describe())
print(b.days_since.isna().sum())
b[['batch_id','line','days_since']].to_csv('$TMPDIR/dsl.csv',index=False)
b.groupby('days_since').apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()})).round(4).to_string()
EOF
python3 $TMPDIR/clean.py 2>&1 | head -150

cd "$PWD" && cat > $TMPDIR/dsl_rates.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
x=pd.read_csv("$TMPDIR/dsl.csv")
b=b.merge(x[['batch_id','days_since']],on='batch_id')
t=b.groupby('days_since').agg(n=('rate','size'),units=('units_produced','sum'),defs=('defective_units','sum'))
t['rate']=t.defs/t.units
print(t.round(4).to_string())
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
base='rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + C(operator_id)'
m=glm(base+' + days_since',d); print(m.params['days_since'], m.bse['days_since'], m.pvalues['days_since'])
m2=glm(base+' + C(days_since)',d)
print('C(days) llf', m2.llf, 'vs', glm(base,d).llf)
EOF
python3 $TMPDIR/dsl_rates.py 2>&1 | grep -v Warn | head -120

cd "$PWD" && cat > $TMPDIR/resid.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
x=pd.read_csv("$TMPDIR/dsl.csv")
b=b.merge(x[['batch_id','days_since']],on='batch_id')
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
base='rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + C(operator_id)'
m=glm(base,d)
d['mu']=m.fittedvalues
d['pr']=(d.defective_units-d.units_produced*d.mu)/np.sqrt(d.units_produced*d.mu*(1-d.mu))
print('pearson dispersion', (d.pr**2).sum()/m.df_resid)
for ln,g in d.groupby('line'):
    g=g.sort_values('d')
    w=g.set_index('d').pr.resample('MS').agg(['mean','count'])
    print(ln, 'monthly mean pearson:', w['mean'].round(2).tolist())
    cs=g.pr.cumsum()
    print(ln,'mean resid pre/post half', g.pr.iloc[:len(g)//2].mean().round(3), g.pr.iloc[len(g)//2:].mean().round(3))
d.to_pickle("$TMPDIR/d.pkl")
EOF
python3 $TMPDIR/resid.py 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/scan.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
d=pd.read_pickle("$TMPDIR/d.pkl")
base='rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + C(operator_id)'
m0=glm(base,d); disp=m0.pearson_chi2/m0.df_resid
res=[]
dates=sorted(d.d.unique())
for ln in ['L1','L2','L3','L4']:
    for t in dates[10:-10]:
        d['step']=((d.line==ln)&(d.d>=t)).astype(int)
        if d.step.sum()<150 or (1-d.step).sum()<150*0+1: continue
        m=glm(base+' + step',d)
        chi=(m0.deviance-m.deviance)/disp
        res.append((ln,pd.Timestamp(t).date(),round(m.params['step'],3),round(chi,2)))
r=pd.DataFrame(res,columns=['line','date','coef','chi2_1df'])
print(r.sort_values('chi2_1df',ascending=False).head(15).to_string())
EOF
python3 $TMPDIR/scan.py 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/shape.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
d=pd.read_pickle("$TMPDIR/d.pkl")
d['hb']=pd.cut(d.humidity_pct,[0,15,20,25,30,35,40,45,50,60,80])
print(d.groupby(['hb','supplier_name'],observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).unstack().round(4).to_string())
d['mb']=pd.cut(d.mold_temp,[185,195,200,205,210,215,220,235])
print(d.groupby('mb',observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
d['cb']=pd.cut(d.cycle_time_s,[17,25,28,30,32,35,50])
print(d.groupby('cb',observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
d['ab']=pd.cut(d.ambient_temp_c,[10,15,20,25,31])
print(d.groupby('ab',observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
d['mab']=pd.cut(d.machine_age_years,[0,3,6,9,12,18])
print(d.groupby('mab',observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
EOF
python3 $TMPDIR/shape.py 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/drop.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
from scipy import stats
d=pd.read_pickle("$TMPDIR/d.pkl")
full='rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + C(operator_id)'
m0=glm(full,d); phi=m0.pearson_chi2/m0.df_resid
print('phi',round(phi,3),'n',len(d))
terms={'mold_temp':'mold_temp','humidity_pct':'humidity_pct','cycle_time_s':'cycle_time_s','machine_age_years':'machine_age_years','ambient_temp_c':'ambient_temp_c','shift':'C(shift)','supplier':'C(supplier_name)','operator (vs line)':'C(operator_id)'}
for k,t in terms.items():
    if k.startswith('operator'):
        red='rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + C(line)'
    else:
        red=full.replace(' + '+t,'').replace(t+' + ','')
    mr=glm(red,d)
    chi=(mr.deviance-m0.deviance)/phi
    dfd=m0.df_model-mr.df_model
    print(f'{k:22s} df={dfd:.0f} chi2={chi:8.2f} p={stats.chi2.sf(chi,dfd):.4g}')
EOF
python3 $TMPDIR/drop.py 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/sensor.py <<EOF
import sys; sys.path.insert(0,"$TMPDIR")
from common import *
d=pd.read_pickle("$TMPDIR/d.pkl")
d['L1pre']=((d.line=='L1')&(d.d<pd.Timestamp('2025-04-14'))).astype(int)
d['L1pre_mt']=d.L1pre*d.mold_temp
base='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
d['shift_n']=(d.shift=='Night').astype(int)
b0=glm(base,d)
b1=glm(base+' + L1pre',d)
b2=glm(base+' + L1pre + L1pre_mt',d)
phi=b0.pearson_chi2/b0.df_resid
for nm,mm in [('base',b0),('L1pre',b1),('L1pre+slope',b2)]:
    print(nm, mm.llf, mm.params.get('L1pre'), mm.params.get('L1pre_mt'))
print('chi2 L1pre', (b1.deviance-b0.deviance)/phi, 'chi2 slope', (b2.deviance-b1.deviance)/phi)
print(b2.summary().tables[1])
EOF
python3 $TMPDIR/sensor.py 2>&1 | grep -v Warn

cd "$PWD" && sed -i "s/d\['shift_n'\]=(d.shift=='Night').astype(int)/d['shift_n']=(d['shift']=='Night').astype(int)/" $TMPDIR/sensor.py && python3 $TMPDIR/sensor.py 2>&1 | grep -v Warn

echo "[$TMPDIR]"; ls "$TMPDIR" | head

cd "$PWD" && cat > $TMPDIR/sensor2.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['L1pre']=((d.line=='L1')&(d.d<pd.Timestamp('2025-04-14'))).astype(int)
d['L1pre_mt']=d.L1pre*d.mold_temp
d['shift_n']=(d['shift']=='Night').astype(int)
base='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
b0=glm(base,d)
b1=glm(base+' + L1pre',d)
b2=glm(base+' + L1pre + L1pre_mt',d)
phi=b0.pearson_chi2/b0.df_resid
print('chi2 L1pre', (b0.deviance-b1.deviance)/phi, 'coef', b1.params['L1pre'])
print('chi2 slope', (b1.deviance-b2.deviance)/phi, 'coef', b2.params['L1pre_mt'])
EOF
python3 "$TMPDIR/sensor2.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/icc.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['wk']=d.d.dt.to_period('W')
for key in [['line','d'],['line','wk'],['d'],['line','d'] ]:
    g=d.groupby(key).pr
    n=g.transform('size'); 
    print(key, 'groups',g.ngroups, 'mean n', round(n.mean(),2))
    gm=g.transform('mean')
    # variance of group means vs expected under iid
    gmeans=g.mean(); gsz=g.size()
    z=(gmeans*np.sqrt(gsz))
    print('  var of group-sum z (should be ~1 if iid):', round((z**2).mean(),3))
EOF
python3 "$TMPDIR/icc.py" 2>&1 | grep -v Warn; python3 - <<'EOF'
import pandas as pd
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['wk']=d.d.dt.to_period('W')
d['mo']=d.d.dt.to_period('M')
for key in ['d','wk','mo']:
    g=d.groupby(['line',key]).agg(s=('defective_units','sum'),u=('units_produced','sum'),e=('mu',lambda x: 0))
    g['exp']=d.groupby(['line',key]).apply(lambda x:(x.units_produced*x.mu).sum())
    z=(g.s-g.exp)/np.sqrt(g.exp*(1-g.exp/g.u))
    print(key,'mean z^2 across line-groups',round((z**2).mean(),3), 'n',len(z))
EOF

cd "$PWD" && cat > $TMPDIR/spl.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['shift_n']=(d['shift']=='Night').astype(int)
lin='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
m0=glm(lin,d); print('linear phi',round(m0.pearson_chi2/m0.df_resid,3),'llf',round(m0.llf,2))
for nm,f in {
 'spl_hum':'rate ~ mold_temp + bs(humidity_pct,df=5) + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)',
 'spl_all':'rate ~ bs(mold_temp,df=4)+ bs(humidity_pct,df=5) + bs(cycle_time_s,df=4) + shift_n + C(supplier_name) + C(operator_id)',
 'hum_by_supp':'rate ~ mold_temp + humidity_pct*C(supplier_name) + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)',
 'spl_hum_by_supp':'rate ~ mold_temp + bs(humidity_pct,df=4)*C(supplier_name) + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)',
}.items():
    try:
        m=glm(f,d); print(nm,'phi',round(m.pearson_chi2/m.df_resid,3),'llf',round(m.llf,2),'df_model',m.df_model)
    except Exception as e: print(nm,'ERR',e)
EOF
python3 "$TMPDIR/spl.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/c2.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['shift_n']=(d['shift']=='Night').astype(int)
hs=np.linspace(d.humidity_pct.min(),d.humidity_pct.max(),60)
for nm,f in {
 'lin':'rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)',
 'spl_hum_by_supp':'rate ~ mold_temp + bs(humidity_pct,df=4)*C(supplier_name) + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)',
}.items():
    m=glm(f,d)
    g=pd.DataFrame({'humidity_pct':hs,'mold_temp':d.mold_temp.mean(),'cycle_time_s':d.cycle_time_s.mean(),'shift_n':0,'supplier_name':'Alpha','operator_id':'OP-01'})
    p=m.predict(g)
    i=p.values.argmin()
    print(nm,'argmin humidity',round(hs[i],2),'rate',round(p.values[i],5),'at max',round(p.values[-1],5),'at min',round(p.values[0],5))
    print(np.round(p.values[::6],4))
EOF
python3 "$TMPDIR/c2.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/inter.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['shift_n']=(d['shift']=='Night').astype(int)
lin='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
m0=glm(lin,d); phi=m0.pearson_chi2/m0.df_resid
from scipy import stats
for nm,t in {'hum:mold':'humidity_pct:mold_temp','hum:cycle':'humidity_pct:cycle_time_s','mold:cycle':'mold_temp:cycle_time_s','hum^2':'I(humidity_pct**2)','mold^2':'I(mold_temp**2)','ct^2':'I(cycle_time_s**2)','shift:hum':'humidity_pct:shift_n','shift:mold':'mold_temp:shift_n','shift:cycle':'cycle_time_s:shift_n'}.items():
    m=glm(lin+' + '+t,d); chi=(m.deviance-m0.deviance)/phi
    print(f'{nm:12s} coef={m.params.iloc[-1]:.6f} p={stats.chi2.sf(-chi,1) if False else stats.chi2.sf(abs((m0.deviance-m.deviance)/phi),1):.4g}')
ma=glm(lin.replace('C(supplier_name)','C(supplier_name)*humidity_pct'),d)
EOF
python3 "$TMPDIR/inter.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/supp_hum.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['shift_n']=(d['shift']=='Night').astype(int)
for s,g in d.groupby('supplier_name'):
    m=glm('rate ~ mold_temp + bs(humidity_pct,df=4) + cycle_time_s + shift_n + C(operator_id)',g)
    m1=glm('rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(operator_id)',g)
    hs=np.linspace(12.1,72.3,61)
    G=pd.DataFrame({'humidity_pct':hs,'mold_temp':g.mold_temp.mean(),'cycle_time_s':g.cycle_time_s.mean(),'shift_n':0,'operator_id':'OP-01'})
    p=m.predict(G).values
    print(s,'n',len(g),'lin coef hum',round(m1.params['humidity_pct'],4),'se',round(m1.bse['humidity_pct'],4),'spline argmin',round(hs[p.argmin()],1), 'pred at 12/40/72', np.round(p[[0,30,60]],4))
EOF
python3 "$TMPDIR/supp_hum.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/leak.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
from scipy import stats
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['good']=d.units_produced-d.defective_units
print('corr units vs rate', stats.pearsonr(d.units_produced,d.rate))
print('corr cycle vs rate', stats.pearsonr(d.cycle_time_s,d.rate))
print('corr cycle vs defective', stats.pearsonr(d.cycle_time_s,d.defective_units))
print('corr units vs defective', stats.pearsonr(d.units_produced,d.defective_units))
print('corr cycle vs humidity', stats.pearsonr(d.cycle_time_s,d.humidity_pct))
print('corr cycle vs mold', stats.pearsonr(d.cycle_time_s,d.mold_temp))
print('corr cycle vs ambient', stats.pearsonr(d.cycle_time_s,d.ambient_temp_c))
print('corr humidity vs ambient', stats.pearsonr(d.humidity_pct,d.ambient_temp_c))
print('corr mold vs humidity', stats.pearsonr(d.mold_temp,d.humidity_pct))
print('ct_dev describe', d.ct_dev.describe().round(2).to_dict())
print(d.groupby('shift').cycle_time_s.mean(), d.groupby('shift').mold_temp.mean(), d.groupby('shift').humidity_pct.mean())
print(d.groupby('supplier_name').humidity_pct.mean())
EOF
python3 "$TMPDIR/leak.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/dsl_mold.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
from scipy import stats
x=pd.read_csv("/tmp/claude-501/dsl.csv")
d=pd.read_pickle("/tmp/claude-501/d.pkl").merge(x[['batch_id','days_since']],on='batch_id')
print(stats.pearsonr(d.days_since,d.mold_temp), stats.pearsonr(d.days_since,d.humidity_pct))
print(d.groupby(pd.cut(d.days_since,[-1,3,7,10,14,20,40])).agg(mt=('mold_temp','mean'),hum=('humidity_pct','mean'),n=('rate','size')).round(2))
print(d.groupby('line').apply(lambda g: stats.pearsonr(g.days_since,g.mold_temp)[0]).round(3))
d['pr2']=d.pr
print(d.groupby(pd.cut(d.days_since,[-1,3,7,10,14,20,40])).pr.mean().round(3))
EOF
python3 "$TMPDIR/dsl_mold.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/dsl_mold.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
from scipy import stats
x=pd.read_csv("/tmp/claude-501/dsl.csv")
d=pd.read_pickle("/tmp/claude-501/d.pkl").drop(columns=[c for c in ['days_since'] if c in pd.read_pickle("/tmp/claude-501/d.pkl").columns]).merge(x[['batch_id','days_since']],on='batch_id')
print(stats.pearsonr(d.days_since,d.mold_temp), stats.pearsonr(d.days_since,d.humidity_pct))
print(d.groupby(pd.cut(d.days_since,[-1,3,7,10,14,20,40])).agg(mt=('mold_temp','mean'),hum=('humidity_pct','mean'),n=('rate','size')).round(2))
print(d.groupby('line').apply(lambda g: stats.pearsonr(g.days_since,g.mold_temp)[0]).round(3))
print(d.groupby(pd.cut(d.days_since,[-1,3,7,10,14,20,40])).pr.mean().round(3))
EOF
python3 "$TMPDIR/dsl_mold.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/overdue.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
from scipy import stats
x=pd.read_csv("/tmp/claude-501/dsl.csv")
d=pd.read_pickle("/tmp/claude-501/d.pkl").drop(columns=['days_since'],errors='ignore').merge(x[['batch_id','days_since']],on='batch_id')
d['shift_n']=(d['shift']=='Night').astype(int)
d['over14']=(d.days_since>14).astype(int)
d['over']=d.days_since.clip(lower=0)
lin='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
m0=glm(lin,d); phi=m0.pearson_chi2/m0.df_resid
for t in ['over14','days_since','I(days_since>14)']:
    m=glm(lin+' + '+t,d); chi=(m0.deviance-m.deviance)/phi
    print(t,'coef',round(m.params[t],5),'se',round(m.bse[t],5),'chi2',round(chi,2),'p',round(stats.chi2.sf(chi,1),4))
for thr in [10,11,12,13,14,15,16]:
    d['t']=(d.days_since>thr).astype(int)
    m=glm(lin+' + t',d); chi=(m0.deviance-m.deviance)/phi
    print('>',thr,'coef',round(m.params['t'],4),'chi2',round(chi,2),'n_over',d.t.sum())
EOF
python3 "$TMPDIR/overdue.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/dsl_line.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
from scipy import stats
x=pd.read_csv("/tmp/claude-501/dsl.csv")
d=pd.read_pickle("/tmp/claude-501/d.pkl").drop(columns=['days_since'],errors='ignore').merge(x[['batch_id','days_since']],on='batch_id')
d['shift_n']=(d['shift']=='Night').astype(int)
lin='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
m0=glm(lin,d); phi=m0.pearson_chi2/m0.df_resid
m=glm(lin+' + days_since:C(line)',d); chi=(m0.deviance-m.deviance)/phi
print('days x line chi2',round(chi,2),'df 3 p',round(stats.chi2.sf(chi,3),4))
for ln,g in d.groupby('line'):
    mm=glm(lin.replace(' + C(operator_id)','')+' + days_since',g)
    print(ln, round(mm.params['days_since'],5), round(mm.bse['days_since'],5))
d['late']=(d.days_since>14).astype(int)
m=glm(lin+' + late',d); print('late coef',m.params['late'],m.bse['late'])
EOF
python3 "$TMPDIR/dsl_line.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/final.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
from scipy import stats
raw=pd.read_csv('batches.csv')
print('A1 unique batches', raw.batch_id.nunique())
print('A2 humidity missing', raw.humidity_pct.isna().sum())
print('A3 overall rate', raw.defective_units.sum()/raw.units_produced.sum(), raw.defective_units.sum(), raw.units_produced.sum())
mt=raw.mold_temp.dropna()
print('A4 median mold temp', mt.median(), 'n', len(mt))

d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['shift_n']=(d['shift']=='Night').astype(int)
m=glm('rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)',d)
print(m.params[['mold_temp','humidity_pct','cycle_time_s','shift_n']].round(5).to_dict())
print('supplier params', m.params.filter(like='supplier').round(4).to_dict())
b_ct=m.params['cycle_time_s']
sup_eff={'Alpha':0.0,'Beta':m.params['C(supplier_name)[T.Beta]'],'Gamma':m.params['C(supplier_name)[T.Gamma]']}
rec=d.recipe_cycle_time_s  # per-grade recipe, 30 for all
sup_rec=d.supplier_code.map(s.set_index('supplier_code').recipe_cycle_time_s) if False else d.recipe_cycle_time_s
res={}
for X,bx in sup_eff.items():
    delta=(bx - d.supplier_name.map(sup_eff)) + b_ct*(30-d.cycle_time_s)
    p=d.rate
    odds=p/(1-p)*np.exp(delta)
    pcf=odds/(1+odds)
    res[X]=(d.units_produced*pcf).sum()/d.units_produced.sum()
print('C1 counterfactual rates', {k:round(v,5) for k,v in res.items()})

print('supplier naive pooled rate', raw.groupby('supplier_code').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(5).to_dict())
EOF
python3 "$TMPDIR/final.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/c3.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
mt=pd.read_csv('maintenance.csv',parse_dates=['date'])
mc=mt[mt.event=='mold_cleaning']
END=pd.Timestamp('2025-09-30')
newc=[]
for ln,g in mc.groupby('line'):
    cl=sorted(set(g.date))
    cl=[pd.Timestamp('2024-12-29')]+cl if ln=='L3' else cl
    cur=cl[0] if ln!='L3' else pd.Timestamp('2024-12-29')
    allc=sorted(cl)
    extra=[]
    last=allc[0]
    sched=list(allc)
    t=allc[0]
    while True:
        nxt=[c for c in allc if c>t]
        nextreal=nxt[0] if nxt else END+pd.Timedelta(days=1)
        if (nextreal-t).days>14 and t+pd.Timedelta(days=14)<nextreal and t+pd.Timedelta(days=14)<=END:
            t=t+pd.Timedelta(days=14); sched.append(t); extra.append(t)
        else:
            if not nxt: break
            t=nextreal
    newc+= [(ln,e) for e in extra]
    print(ln,'extra cleanings', [e.date().isoformat() for e in extra])
def dsl_for(sched_df):
    out={}
    for _,r in d0.iterrows():
        pass
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['shift_n']=(d['shift']=='Night').astype(int)
def days(row,sched):
    c=sched[(sched.line==row.line)&(sched.date<=row.d)]
    return (row.d-c.date.max()).days
old=mc[['date','line']]
newdf=pd.concat([old,pd.DataFrame([{'date':e,'line':l} for l,e in newc])])
sched_new=newdf.copy(); sched_new.columns=['date','line']
d['dsl_old']=d.apply(lambda r: days(r,old),axis=1)
d['dsl_new']=d.apply(lambda r: days(r,sched_new),axis=1)
print('overdue old',(d.dsl_old>14).sum(),'new',(d.dsl_new>14).sum(), 'mean dsl old/new', d.dsl_old.mean().round(3), d.dsl_new.mean().round(3))
lin='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
m=glm(lin+' + I((dsl_old>14).astype(int))',d)
bo=m.params.filter(like='dsl_old').iloc[0]
mm=glm(lin+' + dsl_old',d); bl=mm.params['dsl_old']
print('coefs overdue', bo, 'linear', bl)
raw=pd.read_csv('batches.csv')
p=d.rate
for nm,delta in {
  'overdue': bo*((d.dsl_new>14).astype(int)-(d.dsl_old>14).astype(int)),
  'linear': bl*(d.dsl_new-d.dsl_old),
  'none': 0*d.dsl_old}.items():
    odds=p/(1-p)*np.exp(delta); pcf=odds/(1+odds)
    print(nm, round((d.units_produced*pcf).sum()/d.units_produced.sum(),6))
print('A3 recorded', round(raw.defective_units.sum()/raw.units_produced.sum(),6))
EOF
python3 "$TMPDIR/c3.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/scan2.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
from scipy import stats
d=pd.read_pickle("/tmp/claude-501/d.pkl")
d['shift_n']=(d['shift']=='Night').astype(int)
base='rate ~ mold_temp + humidity_pct + cycle_time_s + shift_n + C(supplier_name) + C(operator_id)'
m0=glm(base,d); disp=m0.pearson_chi2/m0.df_resid
dates=sorted(d.d.unique())
rows=[]
for ln in ['L1','L2','L3','L4']:
    best=None
    for t in dates[15:-15]:
        ind=((d.line==ln)&(d.d>=t)).astype(int)
        if ind.sum()<100 or (1-ind).sum()<100: continue
        d['step']=ind
        m=glm(base+' + step',d)
        chi=(m0.deviance-m.deviance)/disp
        if best is None or chi>best[2]: best=(pd.Timestamp(t).date(),round(m.params['step'],3),round(chi,2))
    rows.append((ln,)+best)
print(pd.DataFrame(rows,columns=['line','best_date','coef','chi2']))
d['step']=((d.line=='L1')&(d.d>=pd.Timestamp('2025-04-14'))).astype(int)
m=glm(base+' + step',d); print('L1 sensor date step coef',round(m.params['step'],4),'chi2',round((m0.deviance-m.deviance)/disp,3))
EOF
python3 "$TMPDIR/scan2.py" 2>&1 | grep -v Warn

cd "$PWD" && cat > $TMPDIR/stuck.py <<'EOF'
import sys; sys.path.insert(0,"/tmp/claude-501")
from common import *
bs=b.sort_values(['line','d','batch_id'])
for col in ['humidity_pct','mold_temp']:
    same=bs[col].eq(bs.groupby('line')[col].shift()) & bs[col].notna()
    idx=bs.index[same]
    print(col, 'consecutive same', len(idx))
    print(bs.loc[bs.index.isin(idx)|bs.index.isin(bs.index[same].map(lambda i: i)),['batch_id','line','production_date',col]].head(20).to_string())
EOF
python3 "$TMPDIR/stuck.py" 2>&1 | grep -v Warn
