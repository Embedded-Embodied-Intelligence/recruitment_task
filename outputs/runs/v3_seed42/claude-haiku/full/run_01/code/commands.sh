ls -la && for f in *.csv; do echo "== $f"; wc -l "$f"; head -5 "$f"; done

python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc=b[c].value_counts()
    print('\n##',c,'nunique',b[c].nunique(),'empty',(b[c].str.strip()=='').sum())
    if b[c].nunique()<40: print(vc.to_dict())
    else: print(b[c].sample(15,random_state=1).tolist())
print('dup batch rows', b.duplicated().sum(), 'dup batch_id', b.batch_id.duplicated().sum())
s=pd.read_csv('suppliers.csv',dtype=str); print(s)
m=pd.read_csv('maintenance.csv',dtype=str,keep_default_na=False); print(m.event.value_counts().to_dict(), m.line.value_counts().to_dict()); print(m.note.value_counts().to_dict()); print(m.date.str.len().value_counts().to_dict())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=b[b.duplicated(keep=False)].sort_values('batch_id'); print('exact dup rows',len(d), 'ids',d.batch_id.nunique())
dd=b[b.batch_id.duplicated(keep=False)]; print('dup id rows',len(dd))
# are all dup-id groups exact dup?
print('nonexact dup groups', (dd.groupby('batch_id').apply(lambda g: len(g.drop_duplicates())>1)).sum())
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x=pd.to_numeric(b[c],errors='coerce'); bad=b[c][x.isna()&(b[c]!='')]
    print(c,'nonnumeric:',bad.unique()[:10], 'n',x.isna().sum(), 'min',x.min(),'max',x.max())
print(b.production_date.min(), b.production_date.max())
pd.to_datetime(b.production_date, errors='raise')
print(b[b.humidity_pct==''].line.value_counts().to_dict())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
b['hum']=pd.to_numeric(b.humidity_pct,errors='coerce'); b['mt']=pd.to_numeric(b.mold_temp)
print('unique',len(b))
print('hum sentinel <0:',(b.hum<0).sum(), b.hum[b.hum<0].unique(), 'hum>100',(b.hum>100).sum(),'hum NaN',b.hum.isna().sum())
print('hum values <=0:', b[b.hum<=0].hum.value_counts().to_dict())
print(b.hum.describe())
print(np.histogram(b.mt.dropna(),bins=[0,1,50,100,150,180,200,230,260,300,350,380,420,460]))
print('mt==0', (b.mt==0).sum(), b[b.mt<50][['batch_id','line','production_date','mold_temp']].head(20).to_string())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
b['mt']=pd.to_numeric(b.mold_temp); b['date']=pd.to_datetime(b.production_date)
b['F']=b.mt>300
print(b.groupby('line').F.agg(['sum','count']))
f=b[b.F]; print('F date range',f.date.min(),f.date.max())
print(f.groupby('line').date.agg(['min','max','count']))
print(b[b.F].groupby(b.date.dt.to_period('M')).size().to_dict())
m=pd.read_csv('maintenance.csv',dtype=str,keep_default_na=False)
print(m[m.event!='mold_cleaning'].to_string())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
b['mt']=pd.to_numeric(b.mold_temp); b['date']=pd.to_datetime(b.production_date)
print('L3 nonF:', b[(b.line=='L3')&(b.mt<=300)].mt.value_counts().to_dict())
b=b[(b.mt>0)&(b.line!='L3')]
b['per']=b.date.dt.to_period('M')
print(b.groupby(['line','per']).mt.median().unstack(0).round(1))
l1=b[b.line=='L1'].copy()
for lo,hi in [('2025-01-01','2025-04-13'),('2025-04-14','2025-09-21'),('2025-09-22','2025-09-30')]:
    s=l1[(l1.date>=lo)&(l1.date<=hi)].mt; print(lo,hi,len(s),round(s.mean(),2),round(s.median(),2))
"

python3 -c "import pandas, numpy, scipy; print(pandas.__version__, numpy.__version__, scipy.__version__)"; python3 -c "import statsmodels; print('sm', statsmodels.__version__)"; python3 -c "import sklearn; print('sk', sklearn.__version__)"; echo $TMPDIR; python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
for c in ['units_produced','defective_units','qc_inspection_min','rework_cost_eur','cycle_time_s']: b[c]=pd.to_numeric(b[c])
print('defective>units', (b.defective_units>b.units_produced).sum())
b['rate']=b.defective_units/b.units_produced
print(b[['rate','qc_inspection_min','rework_cost_eur','defective_units','units_produced','cycle_time_s']].corr().round(3))
"

python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
for c in ['units_produced','defective_units','qc_inspection_min','rework_cost_eur','cycle_time_s','ambient_temp_c','machine_age_years']: b[c]=pd.to_numeric(b[c])
b['cost_per_def']=b.rework_cost_eur/b.defective_units
print(b.cost_per_def.describe().round(3))
b['rate']=b.defective_units/b.units_produced
m=smf.ols('qc_inspection_min ~ defective_units + units_produced + cycle_time_s + ambient_temp_c + machine_age_years',b).fit(); print(m.params.round(4).to_dict(), round(m.rsquared,3))
m2=smf.ols('qc_inspection_min ~ rate + units_produced + cycle_time_s + ambient_temp_c + machine_age_years',b).fit(); print('rate version r2',round(m2.rsquared,3), m2.params.round(4).to_dict())
m3=smf.ols('qc_inspection_min ~ defective_units',b).fit(); print('def only r2',round(m3.rsquared,3))
"

python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
for c in ['mold_temp','ambient_temp_c','cycle_time_s','humidity_pct','machine_age_years']: b[c]=pd.to_numeric(b[c])
b=b[(b.mold_temp>0)].copy()
b['mt']=np.where(b.mold_temp>300,(b.mold_temp-32)*5/9,b.mold_temp)
b['date']=pd.to_datetime(b.production_date)
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
b['mon']=b.date.dt.month.astype(str)
d=b.dropna(subset=['hum'])
m=smf.ols('mt ~ ambient_temp_c + cycle_time_s + hum + C(line) + C(mon) + post',d).fit()
print(m.params[['ambient_temp_c','cycle_time_s','hum','post']].round(3).to_dict(), 'post se',round(m.bse['post'],3))
# step-date scan on L1
l1=b[b.line=='L1'].copy(); best=[]
for dt in pd.date_range('2025-03-01','2025-06-30'):
    l1['p']=(l1.date>=dt).astype(int)
    f=smf.ols('mt ~ ambient_temp_c + cycle_time_s + p + C(mon)',l1.dropna(subset=['ambient_temp_c'])).fit()
    best.append((f.ssr,dt.date(),round(f.params['p'],2)))
best.sort(); print(best[:5])
"

mkdir -p /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py <<'EOF'
import numpy as np
import pandas as pd

DATA = '/tmp/edabench_claude_7ei66ua1'
SCR = '/tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad'


def load_raw():
    b = pd.read_csv(f'{DATA}/batches.csv', dtype=str, keep_default_na=False)
    return b


def clean():
    raw = load_raw()
    n_raw = len(raw)
    b = raw.drop_duplicates().copy()
    n_exact_dup = n_raw - len(b)
    assert b.batch_id.is_unique

    b['date'] = pd.to_datetime(b.production_date)
    b['line'] = b.line.str.strip().str.upper()

    shift = b['shift'].str.strip().str.lower()
    b['shift'] = np.select([shift.isin(['d', 'day']), shift.isin(['n', 'night'])],
                           ['Day', 'Night'], default='UNKNOWN')

    b['operator_id'] = b.operator_id.str.strip().str.upper()

    sup = pd.read_csv(f'{DATA}/suppliers.csv', dtype=str)
    b['supplier_code'] = b.supplier_code.str.strip().str.upper()
    b = b.merge(sup[['supplier_code', 'supplier_name', 'pre_dried']], on='supplier_code', how='left')
    assert b.supplier_name.notna().all()

    num = ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'humidity_pct', 'cycle_time_s',
           'units_produced', 'defective_units', 'qc_inspection_min', 'rework_cost_eur']
    for c in num:
        b[c] = pd.to_numeric(b[c], errors='coerce')

    # humidity: blank or -1 sentinel -> missing
    b['humidity'] = b.humidity_pct.where(b.humidity_pct >= 0)

    # mold temperature: 0.0 sentinel -> missing; L3 exports Fahrenheit (values > 300)
    mt = b.mold_temp.where(b.mold_temp != 0)
    mt = mt.where(~(b.mold_temp > 300), (mt - 32) * 5 / 9)
    # L1 mold sensor replaced 2025-04-14; calibration check 2025-09-22 found +8.0 degC bias
    l1_bias = (b.line == 'L1') & (b.date >= '2025-04-14')
    mt = mt.where(~l1_bias, mt - 8.0)
    b['mold_temp_c'] = mt

    b['rate'] = b.defective_units / b.units_produced
    b.attrs['n_raw'] = n_raw
    b.attrs['n_exact_dup'] = n_exact_dup
    return b.reset_index(drop=True)
EOF
cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import clean
b=clean()
print(len(b), b.attrs, b.shift.value_counts().to_dict(), b.supplier_name.value_counts().to_dict())
print('hum invalid', b.humidity.isna().sum(), 'mt invalid', b.mold_temp_c.isna().sum(), b.mold_temp_c.describe().round(2).to_dict())
print('A3', b.defective_units.sum()/b.units_produced.sum())
print('A4 median', b.mold_temp_c.median())
"

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from clean import clean
b=clean()
print(len(b), b.attrs, b['shift'].value_counts().to_dict(), b.supplier_name.value_counts().to_dict())
print('hum invalid', b.humidity.isna().sum(), 'mt invalid', b.mold_temp_c.isna().sum(), b.mold_temp_c.describe().round(2).to_dict())
print('A3', b.defective_units.sum()/b.units_produced.sum())
print('A4 median', b.mold_temp_c.median())
"

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import warnings; warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
from clean import clean
b=clean()
d=b.dropna(subset=['humidity','mold_temp_c']).copy()
d['op']=d.operator_id; print('n',len(d))
base='mold_temp_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(op) + C(shift) + C(line) + C(supplier_name)'
f=lambda rhs: smf.glm('rate ~ '+rhs, d, family=sm.families.Binomial(), var_weights=d.units_produced).fit()
full=f(base)
print(full.summary().tables[1])
print('dev',full.deviance,'aic',full.aic)
terms={'mold_temp_c':'mold_temp_c','humidity':'humidity','cycle_time_s':'cycle_time_s','machine_age_years':'machine_age_years','ambient_temp_c':'ambient_temp_c','operator':'C(op)','shift':'C(shift)','line':'C(line)','supplier':'C(supplier_name)'}
for k,t in terms.items():
    rhs=base
    rhs=rhs.replace(t+' + ','').replace(' + '+t,'')
    r=f(rhs); lr=2*(r.llf-full.llf) if False else (r.deviance-full.deviance)
    df=full.df_model-r.df_model
    print(k,'LR',round(lr,2),'df',df,'p',stats.chi2.sf(lr,df))
" 2>&1 | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat >> clean.py <<'EOF'


def mold_cleanings():
    m = pd.read_csv(f'{DATA}/maintenance.csv', dtype=str, keep_default_na=False)
    m['date'] = pd.to_datetime(m.date)
    m['line'] = m.line.str.strip().str.upper()
    return m[m.event.str.strip() == 'mold_cleaning'][['date', 'line']].sort_values(['line', 'date']).reset_index(drop=True)


def add_days_since_cleaning(b):
    """Days since the last mold cleaning on the batch's line, counting a cleaning on the same day."""
    cl = mold_cleanings()
    out = []
    for line, g in b.groupby('line'):
        c = cl[cl.line == line].date.values
        idx = np.searchsorted(c, g.date.values, side='right') - 1
        last = pd.to_datetime(c[idx]) if (idx >= 0).all() else None
        out.append(pd.Series((g.date.values - c[idx]).astype('timedelta64[D]').astype(int), index=g.index))
    b['days_since_clean'] = pd.concat(out).reindex(b.index)
    return b
EOF
python3 -c "
from clean import *
cl=mold_cleanings(); cl['gap']=cl.groupby('line').date.diff().dt.days
print(cl.groupby('line').gap.describe().round(1))
print(cl[cl.gap>14])
print(cl.groupby('line').date.agg(['min','max','count']))
b=add_days_since_cleaning(clean())
print(b.days_since_clean.describe().round(1).to_dict())
print(b.groupby('line').days_since_clean.max())
"

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > fit.py <<'EOF'
import warnings; warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
from clean import clean, add_days_since_cleaning


def prep():
    b = add_days_since_cleaning(clean())
    d = b.dropna(subset=['humidity', 'mold_temp_c']).copy()
    return d


def glm(terms, d):
    return smf.glm('rate ~ ' + ' + '.join(terms), d, family=sm.families.Binomial(), var_weights=d.units_produced).fit()


def lr_test(full_terms, drop, d):
    full = glm(full_terms, d)
    red = glm([t for t in full_terms if t not in drop], d)
    lr = red.deviance - full.deviance
    df = len(drop) if False else full.df_resid - red.df_resid
    return lr, df, stats.chi2.sf(lr, df)
EOF
python3 -c "
from fit import *
d=prep()
C=['mold_temp_c','humidity','cycle_time_s','machine_age_years','ambient_temp_c','C(operator_id)','C(shift)','C(line)','C(supplier_name)']
extra=['days_since_clean']
for name,terms in [('base',C),('base+days',C+extra)]:
    m=glm(terms,d); print(name,'dev',round(m.deviance,1),'df_resid',m.df_resid)
m=glm(C+extra,d)
print(m.summary().tables[1])
groups={'mold_temp_c':['mold_temp_c'],'humidity':['humidity'],'cycle_time_s':['cycle_time_s'],'machine_age_years':['machine_age_years'],'ambient_temp_c':['ambient_temp_c'],'operator':['C(operator_id)'],'shift':['C(shift)'],'line':['C(line)'],'supplier':['C(supplier_name)'],'days_since_clean':['days_since_clean']}
for k,g in groups.items():
    print(k, [round(x,6) if isinstance(x,float) else x for x in lr_test(C+extra,g,d)])
" 2>&1 | grep -v Warning | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && sed -i 's/df = len(drop) if False else full.df_resid - red.df_resid/df = red.df_resid - full.df_resid/' fit.py && python3 -c "
from fit import *
import numpy as np
d=prep()
d['mt2']=(d.mold_temp_c-210)**2; d['hum2']=(d.humidity-30)**2; d['ct2']=(d.cycle_time_s-28)**2; d['amb2']=(d.ambient_temp_c-20)**2; d['dsc2']=d.days_since_clean**2
d['mage2']=d.machine_age_years**2
C=['mold_temp_c','humidity','cycle_time_s','machine_age_years','ambient_temp_c','C(operator_id)','C(shift)','C(line)','C(supplier_name)','days_since_clean']
Q=C+['mt2','hum2','ct2','amb2','dsc2','mage2']
full=glm(Q,d)
for k,g in {'mold_temp_c':['mold_temp_c','mt2'],'humidity':['humidity','hum2'],'cycle_time_s':['cycle_time_s','ct2'],'ambient':['ambient_temp_c','amb2'],'machine_age':['machine_age_years','mage2'],'days':['days_since_clean','dsc2'],'operator':['C(operator_id)'],'shift':['C(shift)'],'supplier':['C(supplier_name)']}.items():
    red=glm([t for t in Q if t not in g],d); lr=red.deviance-full.deviance; df=red.df_resid-full.df_resid
    print(k,'LR',round(lr,2),'df',df,'p',stats.chi2.sf(lr,df))
print('quadratic-model coefs:'); print(full.params[['mold_temp_c','mt2','humidity','hum2','cycle_time_s','ct2','ambient_temp_c','days_since_clean','dsc2']].round(5).to_dict())
" 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from fit import *
import numpy as np
d=prep()
print(d.groupby('shift')[['mold_temp_c','humidity','cycle_time_s','ambient_temp_c','machine_age_years','days_since_clean','units_produced','rate']].mean().round(3).T)
print(d.groupby('operator_id')[['mold_temp_c','cycle_time_s','humidity','rate']].mean().round(3).head(8))
print('shift-level rate by line:'); print(d.groupby(['line','shift']).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack().round(4))
print('by month shift rate'); d['m']=d.date.dt.month
print(d.groupby(['m','shift']).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack().round(4))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat >> fit.py <<'EOF'

SPL = ['cr(mold_temp_c, df=4)', 'cr(humidity, df=4)', 'cr(cycle_time_s, df=4)', 'cr(ambient_temp_c, df=4)',
       'cr(days_since_clean, df=4)', 'machine_age_years', 'C(operator_id)', 'C(shift)', 'C(line)', 'C(supplier_name)']
EOF
python3 -c "
from fit import *
import numpy as np
d=prep()
m=glm(SPL,d)
print('dev',round(m.deviance,1),'aic',round(m.aic,1),'df_resid',m.df_resid)
d['pred']=m.predict(d)
d['res']=d.defective_units-d.pred*d.units_produced
d['wk']=d.date.dt.to_period('M')
g=d.groupby(['line','wk']).apply(lambda g: pd.Series({'obs':g.defective_units.sum(),'exp':(g.pred*g.units_produced).sum(),'n':len(g)}))
g['ratio']=g.obs/g.exp
print(g.ratio.unstack(0).round(3))
d.to_pickle('scr_d.pkl')
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && sed -i '1a import numpy as np\nimport pandas as pd' fit.py && python3 -c "
from fit import *
d=prep()
m=glm(SPL,d)
d['pred']=m.predict(d)
d['wk']=d.date.dt.to_period('M')
rows={}
for (ln,wk),g in d.groupby(['line','wk']):
    rows[(ln,str(wk))]=g.defective_units.sum()/(g.pred*g.units_produced).sum()
import pandas as pd
print(pd.Series(rows).unstack(0).round(3))
d.to_pickle('scr_d.pkl')
" 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > scan.py <<'EOF'
from fit import *
d = prep()
base = glm(SPL, d)
res = []
for ln in ['L1', 'L2', 'L3', 'L4']:
    best = None
    for dt in pd.date_range('2025-02-01', '2025-09-15'):
        x = ((d.line == ln) & (d.date >= dt)).astype(int)
        if x.sum() < 30 or (d.line == ln).sum() - x.sum() < 30:
            continue
        d['step'] = x
        m = glm(SPL + ['step'], d)
        if best is None or m.deviance < best[0]:
            best = (m.deviance, str(dt.date()), round(m.params['step'], 3), round(m.bse['step'], 3))
    res.append((ln, best, round(base.deviance - best[0], 1)))
    print(ln, best, 'dev drop', round(base.deviance - best[0], 1))
EOF
python3 scan.py 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 110 python3 -c "
from fit import *
d=prep()
base=[t for t in SPL if 'supplier' not in t and 'humidity' not in t]
A=base+['cr(humidity, df=4)','C(supplier_name)']
B=base+['cr(humidity, df=4)*C(supplier_name)']
ma=glm(A,d); mb=glm(B,d)
print('no interaction dev',round(ma.deviance,1),'interaction dev',round(mb.deviance,1),'df diff',ma.df_resid-mb.df_resid, 'p', stats.chi2.sf(ma.deviance-mb.deviance, ma.df_resid-mb.df_resid))
for s,g in d.groupby('supplier_name'):
    m=glm(['cr(humidity, df=4)']+[t for t in base if 'supplier' not in t and 'humidity' not in t],g)
    print(s,'n',len(g),'dev',round(m.deviance,1))
" 2>&1 | grep -v -i warn | grep -v wls

sleep 100; cat /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b2uri7n2d.output | grep -v -i warn | grep -v wls

grep -v -i warn /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b2uri7n2d.output | grep -v wls; echo; echo done-check

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 100 python3 -c "
from fit import *
d=prep()
l2=d[d.line=='L2'].copy(); l2['post']=l2.date>='2025-06-16'
print(l2.groupby('post').apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum(),'supp_alpha':(g.supplier_name=='Alpha').mean(),'hum':g.humidity.mean(),'mt':g.mold_temp_c.mean(),'amb':g.ambient_temp_c.mean(),'cyc':g.cycle_time_s.mean(),'night':(g['shift']=='Night').mean(),'age':g.machine_age_years.mean(),'dsc':g.days_since_clean.mean()})).round(3).T)
r=l2.groupby(l2.date.dt.to_period('W')).apply(lambda g: g.defective_units.sum()/g.units_produced.sum())
print(r.round(3).to_string())
" 2>&1 | grep -v -i warn | grep -v wls

until grep -q -E "^L4" /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b2uri7n2d.output 2>/dev/null; do sleep 5; done; grep -v -i warn /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b2uri7n2d.output | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat >> fit.py <<'EOF'


def add_l2_step(d):
    d['l2_step'] = ((d.line == 'L2') & (d.date >= '2025-06-16')).astype(int)
    return d


FINAL = ['cr(mold_temp_c, df=4)', 'cr(cycle_time_s, df=4)', 'cr(ambient_temp_c, df=4)',
         'cr(days_since_clean, df=4)', 'machine_age_years', 'C(operator_id)', 'C(shift)', 'C(line)',
         'cr(humidity, df=4)*C(supplier_name)', 'l2_step']
EOF
timeout 115 python3 -c "
from fit import *
d=add_l2_step(prep())
full=glm(FINAL,d); print('dev',round(full.deviance,1),'df_resid',full.df_resid)
print(full.params[[p for p in full.params.index if 'l2_step' in p or 'machine' in p]].round(4).to_dict(), full.bse['l2_step'].round(4))
tests={'mold_temp_c':['cr(mold_temp_c, df=4)'],'humidity':['cr(humidity, df=4)*C(supplier_name)'],'cycle_time_s':['cr(cycle_time_s, df=4)'],'machine_age_years':['machine_age_years'],'ambient_temp_c':['cr(ambient_temp_c, df=4)'],'operator_id':['C(operator_id)'],'shift':['C(shift)']}
for k,g in tests.items():
    red=glm([t for t in FINAL if t not in g],d); lr=red.deviance-full.deviance; df=red.df_resid-full.df_resid
    print(k,'LR',round(lr,2),'df',df,'p',stats.chi2.sf(lr,df))
" 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 115 python3 -c "
from fit import *
d=add_l2_step(prep())
LIN=['mold_temp_c','cycle_time_s','ambient_temp_c','days_since_clean','machine_age_years','C(operator_id)','C(shift)','C(line)','humidity*C(supplier_name)','l2_step']
full=glm(LIN,d)
print(full.params[['mold_temp_c','cycle_time_s','ambient_temp_c','days_since_clean','machine_age_years','C(shift)[T.Night]','l2_step']].round(4).to_dict())
print(full.pvalues[['ambient_temp_c','machine_age_years']].round(4).to_dict())
print('mold_temp ~ ambient regression check:')
import statsmodels.formula.api as smf
m=smf.ols('mold_temp_c ~ ambient_temp_c + cycle_time_s + machine_age_years + C(line) + C(shift) + C(operator_id) + days_since_clean + humidity',d.dropna(subset=['mold_temp_c'])).fit()
print(m.params[['ambient_temp_c','cycle_time_s','machine_age_years','days_since_clean','humidity']].round(4).to_dict(), m.pvalues[['ambient_temp_c','machine_age_years','days_since_clean']].round(4).to_dict())
" 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 115 python3 -c "
from fit import *
d=add_l2_step(prep())
print('corr machine_age with others:'); print(d[['machine_age_years','days_since_clean','mold_temp_c','cycle_time_s','humidity','ambient_temp_c','units_produced']].corr().round(3)['machine_age_years'].to_dict())
print(d.groupby('line').machine_age_years.agg(['mean','std','min','max']).round(2))
d['ageb']=pd.cut(d.machine_age_years,[0,3,6,9,12,15,25])
nb=[]
LIN=['mold_temp_c','cycle_time_s','ambient_temp_c','days_since_clean','C(operator_id)','C(shift)','C(line)','humidity*C(supplier_name)','l2_step']
base=glm(LIN,d); d['pred']=base.predict(d)
d['ratio']=d.defective_units/(d.pred*d.units_produced)
print(d.groupby('ageb').apply(lambda g: pd.Series({'n':len(g),'obs_over_exp':g.defective_units.sum()/(g.pred*g.units_produced).sum()})).round(3))
" 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 115 python3 -c "
from fit import *
d=add_l2_step(prep())
LIN=['mold_temp_c','cycle_time_s','ambient_temp_c','days_since_clean','C(operator_id)','C(shift)','C(line)','humidity*C(supplier_name)','l2_step']
base=glm(LIN,d); d['pred']=base.predict(d)
for ln,g in d.groupby('line'):
    m=glm(['machine_age_years','mold_temp_c','cycle_time_s','days_since_clean','C(operator_id)','C(shift)','humidity*C(supplier_name)','l2_step'],g)
    print(ln,'age coef',round(m.params['machine_age_years'],4),'p',round(m.pvalues['machine_age_years'],4))
g=d[d.line!='L4']
g=g.assign(ageb=pd.cut(g.machine_age_years,[0,2,4,6,8,10]))
print(g.groupby('ageb').apply(lambda x: round(x.defective_units.sum()/(x.pred*x.units_produced).sum(),3)).to_dict())
" 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 115 python3 -c "
from fit import *
d=add_l2_step(prep())
d['lu']=np.log(d.units_produced)
print(d.groupby('line').units_produced.mean().round(0).to_dict())
LIN=['mold_temp_c','cycle_time_s','ambient_temp_c','days_since_clean','machine_age_years','C(operator_id)','C(shift)','C(line)','humidity*C(supplier_name)','l2_step']
full=glm(LIN+['lu'],d)
print('lu coef',round(full.params['lu'],4),'p',round(full.pvalues['lu'],4))
for t in ['machine_age_years','ambient_temp_c']:
    r=glm([x for x in LIN+['lu'] if x!=t],d); lr=r.deviance-full.deviance; print(t,'LR',round(lr,2),'p',stats.chi2.sf(lr,1))
print('no-lu machine age p', round(glm(LIN,d).pvalues['machine_age_years'],4))
" 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > final.py <<'EOF'
from fit import *
from clean import mold_cleanings

b = clean()
print('A1 unique batches', b.batch_id.nunique(), 'raw rows', b.attrs['n_raw'], 'exact dups removed', b.attrs['n_exact_dup'])
print('A2 humidity invalid', int(b.humidity.isna().sum()), '(blank', int(b.humidity_pct.eq(-1).sum()*0), ' sentinel -1 rows', int((b.humidity_pct == -1).sum()), ')')
print('A3 overall rate', b.defective_units.sum() / b.units_produced.sum())
print('A4 median mold temp C (actual)', b.mold_temp_c.median(), 'n', int(b.mold_temp_c.notna().sum()))

d = add_l2_step(add_days_since_cleaning(b).dropna(subset=['humidity', 'mold_temp_c']).copy())
FIN = ['cr(mold_temp_c, df=4)', 'cr(cycle_time_s, df=4)', 'ambient_temp_c', 'cr(days_since_clean, df=4)',
       'machine_age_years', 'C(operator_id)', 'C(shift)', 'C(line)', 'cr(humidity, df=4)*C(supplier_name)', 'l2_step']
m = glm(FIN, d)
print('final model dev', round(m.deviance, 1), 'n', len(d))
pred = m.predict(d)
print('calibration obs/exp', round(d.defective_units.sum() / (pred * d.units_produced).sum(), 4))
d['pred'] = pred
d.to_pickle('final_d.pkl')
EOF
timeout 115 python3 final.py 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > answers_c.py <<'EOF'
from fit import *
from clean import mold_cleanings, clean
from scipy.special import expit, logit

d = pd.read_pickle('final_d.pkl')
FIN = ['cr(mold_temp_c, df=4)', 'cr(cycle_time_s, df=4)', 'ambient_temp_c', 'cr(days_since_clean, df=4)',
       'machine_age_years', 'C(operator_id)', 'C(shift)', 'C(line)', 'cr(humidity, df=4)*C(supplier_name)', 'l2_step']
m = glm(FIN, d)

# C1: every batch assigned to one supplier, all else as observed
out = {}
for s in ['Alpha', 'Beta', 'Gamma']:
    x = d.copy(); x['supplier_name'] = s
    p = m.predict(x)
    out[s] = (p * x.units_produced).sum() / x.units_produced.sum()
print('C1 counterfactual overall rate by supplier', {k: round(v, 6) for k, v in out.items()})
print('C1 observed-supplier rate on same rows', round(d.defective_units.sum() / d.units_produced.sum(), 6))

# C2: Alpha only, humidity curve on logit scale; other terms additive so the optimum does not depend on them
a = d[d.supplier_name == 'Alpha']
hmin, hmax = a.humidity.min(), a.humidity.max()
grid = np.round(np.arange(hmin, hmax + 1e-9, 0.1), 2)
x = d.iloc[[0] * len(grid)].copy().reset_index(drop=True)
x['humidity'] = grid; x['supplier_name'] = 'Alpha'
r = m.predict(x)
i = int(np.argmin(r))
print('C2 Alpha humidity range', round(hmin, 1), round(hmax, 1), 'argmin', grid[i], 'rate', round(r[i], 6))
print('C2 rate at grid ends', round(r[0], 6), round(r[-1], 6))
for h in [10, 20, 25, 30, 35, 40, 45, 50, 60]:
    j = int(np.argmin(np.abs(grid - h)))
    print('  h', h, round(r[j], 5))

# C3: cleaning every 14 days at most
def cf_days(line_dates, days_list):
    pass

cl = mold_cleanings()
cal = pd.date_range('2024-12-01', '2025-09-30')
newdays = {}
for ln, g in cl.groupby('line'):
    acts = set(g.date)
    last = None
    for t in cal:
        if t in acts:
            last = t
        elif last is not None and (t - last).days >= 14:
            last = t
        newdays[(ln, t)] = (t - last).days if last is not None else np.nan
e = d.copy()
e['days_cf'] = [newdays[(ln, t)] for ln, t in zip(e.line, e.date)]
print('C3 new days range', e.days_cf.min(), e.days_cf.max(), 'mean old', round(e.days_since_clean.mean(), 3), 'mean new', round(e.days_cf.mean(), 3))
n = e.copy(); n['days_since_clean'] = n.days_cf
p_old = m.predict(e)
p_new = m.predict(n)
cf_exp = (p_new * e.units_produced).sum() / e.units_produced.sum()
print('C3 complete-case: observed', round(e.defective_units.sum() / e.units_produced.sum(), 6),
      'model old', round((p_old * e.units_produced).sum() / e.units_produced.sum(), 6),
      'model cf', round(cf_exp, 6))
# delta on observed rates over all 3000 batches
raw = clean(); raw = add_days_since_cleaning(raw)
raw = add_l2_step(raw)
raw['days_cf'] = [newdays[(ln, t)] for ln, t in zip(raw.line, raw.date)]
delta_eta = (m.predict(n) - m.predict(e)).values  # placeholder
EOF
timeout 115 python3 answers_c.py 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > answers_c.py <<'EOF'
from fit import *
from clean import mold_cleanings, clean

d = pd.read_pickle('final_d.pkl')
FIN = ['cr(mold_temp_c, df=4)', 'cr(cycle_time_s, df=4)', 'ambient_temp_c', 'cr(days_since_clean, df=4)',
       'machine_age_years', 'C(operator_id)', 'C(shift)', 'C(line)', 'cr(humidity, df=4)*C(supplier_name)', 'l2_step']
m = glm(FIN, d)

# C2: Alpha humidity curve (logit scale: other additive terms do not move the optimum)
a = d[d.supplier_name == 'Alpha']
grid = np.round(np.arange(a.humidity.min(), a.humidity.max() + 1e-9, 0.1), 2)
x = d.iloc[np.zeros(len(grid), dtype=int)].copy().reset_index(drop=True)
x['humidity'] = grid; x['supplier_name'] = 'Alpha'
r = np.asarray(m.predict(x))
i = int(np.argmin(r))
print('C2 spline optimum humidity', grid[i], 'rate', round(r[i], 6), 'range', grid[0], grid[-1])
for h in [15, 20, 25, 28, 30, 32, 35, 40, 50, 60, 70]:
    j = int(np.argmin(np.abs(grid - h)))
    print('   h', grid[j], round(r[j], 5))
# cross-check: quadratic Alpha-only logit model
q = glm(['humidity', 'I(humidity**2)', 'cr(mold_temp_c, df=4)', 'cr(cycle_time_s, df=4)', 'ambient_temp_c',
         'cr(days_since_clean, df=4)', 'machine_age_years', 'C(operator_id)', 'C(shift)', 'C(line)', 'l2_step'], a)
b1, b2 = q.params['humidity'], q.params['I(humidity ** 2)']
print('C2 quadratic Alpha-only optimum', round(-b1 / (2 * b2), 2))
# binned observed Alpha rate by humidity
ab = a.assign(hb=pd.cut(a.humidity, np.arange(10, 76, 5)))
print(ab.groupby('hb', observed=True).apply(lambda g: round(g.defective_units.sum() / g.units_produced.sum(), 4)).to_string())

# C3: cleaning every 14 days at most (per line, cleaning counts on its own day)
cl = mold_cleanings()
cal = pd.date_range('2024-12-01', '2025-09-30')
newdays = {}
for ln, g in cl.groupby('line'):
    acts = set(g.date)
    last = None
    for t in cal:
        if t in acts:
            last = t
        elif last is not None and (t - last).days >= 14:
            last = t
        newdays[(ln, t)] = (t - last).days
e = d.copy()
e['days_cf'] = [newdays[(ln, t)] for ln, t in zip(e.line, e.date)]
print('C3 cf days min/max', e.days_cf.min(), e.days_cf.max(), 'mean old/new', round(e.days_since_clean.mean(), 3), round(e.days_cf.mean(), 3))
n = e.copy(); n['days_since_clean'] = n.days_cf
p_old = np.asarray(m.predict(e)); p_new = np.asarray(m.predict(n))
U = e.units_produced.values
print('C3 complete-case observed', round(e.defective_units.sum() / U.sum(), 6),
      'model-old', round((p_old * U).sum() / U.sum(), 6), 'model-cf', round((p_new * U).sum() / U.sum(), 6))
EOF
timeout 115 python3 answers_c.py 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 - <<'EOF'
import re
src = open('answers_c.py').read()
src = src.replace("""cal = pd.date_range('2024-12-01', '2025-09-30')
newdays = {}
for ln, g in cl.groupby('line'):
    acts = set(g.date)
    last = None
    for t in cal:
        if t in acts:
            last = t
        elif last is not None and (t - last).days >= 14:
            last = t
        newdays[(ln, t)] = (t - last).days""",
"""cal = pd.date_range('2025-01-01', '2025-09-30')
newdays = {}
for ln, g in cl.groupby('line'):
    acts = set(g.date)
    last = g[g.date < cal[0]].date.max()
    for t in cal:
        if t in acts:
            last = t
        elif (t - last).days >= 14:
            last = t
        newdays[(ln, t)] = (t - last).days""")
open('answers_c.py', 'w').write(src)
EOF
timeout 115 python3 answers_c.py 2>&1 | grep -v -i warn | grep -v wls | tail -3

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > c3_all.py <<'EOF'
from fit import *
from clean import mold_cleanings, clean, add_days_since_cleaning
from scipy.special import expit, logit
d = pd.read_pickle('final_d.pkl')
FIN = ['cr(mold_temp_c, df=4)', 'cr(cycle_time_s, df=4)', 'ambient_temp_c', 'cr(days_since_clean, df=4)',
       'machine_age_years', 'C(operator_id)', 'C(shift)', 'C(line)', 'cr(humidity, df=4)*C(supplier_name)', 'l2_step']
m = glm(FIN, d)
cl = mold_cleanings()
cal = pd.date_range('2025-01-01', '2025-09-30')
newdays = {}
for ln, g in cl.groupby('line'):
    acts = set(g.date); last = g[g.date < cal[0]].date.max()
    for t in cal:
        if t in acts: last = t
        elif (t - last).days >= 14: last = t
        newdays[(ln, t)] = (t - last).days

allb = add_l2_step(add_days_since_cleaning(clean()))
allb['days_cf'] = [newdays[(ln, t)] for ln, t in zip(allb.line, allb.date)]
full_ix = allb.index.isin(d.index)
# complete rows: model-based delta
e = allb[full_ix].copy()
n = e.copy(); n['days_since_clean'] = n.days_cf
p_old = np.asarray(m.predict(allb[full_ix])); p_new = np.asarray(m.predict(n))
cf_def_complete = (p_new - p_old) * 0 + (np.asarray(e.units_produced) * p_new)
# incomplete rows: observed rate used as baseline, shift on logit scale by model days effect
f = allb[~full_ix].copy()
delta = np.asarray(m.predict(f.assign(days_since_clean=f.days_cf, humidity=35.0, mold_temp_c=210.0)) ) 
base_days = np.asarray(m.predict(f.assign(humidity=35.0, mold_temp_c=210.0)))
# logit-shift approximation using the same covariate pattern (imputed at medians) for the days effect
logit_shift = np.log(delta / (1 - delta)) - np.log(base_days / (1 - base_days))
r_obs = (f.defective_units / f.units_produced).values
p_inc_new = expit(logit(r_obs) + logit_shift)
cf_def_incomplete = f.units_produced.values * p_inc_new
U = allb.units_produced.sum()
tot_cf = cf_def_complete.sum() + cf_def_incomplete.sum()
print('complete-case cf', round(cf_def_complete.sum() / e.units_produced.sum(), 6))
print('all 3000 cf (complete model + incomplete observed-shift)', round(tot_cf / U, 6), 'n incomplete', (~full_ix).sum())
print('all-batch observed', round(allb.defective_units.sum() / U, 6))
# multiplicative alternative: scale observed overall by complete-case model ratio
ratio = (p_new * e.units_produced).sum() / (p_old * e.units_produced).sum()
print('scaled observed', round(allb.defective_units.sum() / U * ratio, 6))
EOF
timeout 115 python3 c3_all.py 2>&1 | grep -v -i warn | grep -v wls

cd /tmp/claude-0/-tmp-edabench-claude-7ei66ua1/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 115 python3 -c "
from fit import *
d=pd.read_pickle('final_d.pkl')
a=d[d.supplier_name=='Alpha']
base=['cr(mold_temp_c, df=4)','cr(cycle_time_s, df=4)','ambient_temp_c','cr(days_since_clean, df=4)','machine_age_years','C(operator_id)','C(shift)','C(line)','l2_step']
grid=np.round(np.arange(12,73,0.1),2)
for df in [3,4,5,6]:
    m=glm([f'cr(humidity, df={df})']+base,a)
    x=a.iloc[np.zeros(len(grid),dtype=int)].copy().reset_index(drop=True); x['humidity']=grid
    r=np.asarray(m.predict(x)); print('df',df,'optimum',grid[int(np.argmin(r))], round(r.min(),5))
" 2>&1 | grep -v -i warn | grep -v wls
