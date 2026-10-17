ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat > $TMPDIR/profile.py <<'EOF'
import pandas as pd
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 30)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc = b[c].value_counts(dropna=False)
    print(f"\n--- {c}: nunique={b[c].nunique()}  empty={(b[c].str.strip()=='').sum()}")
    if b[c].nunique() < 40: print(vc.to_string())
    else: print(b[c].sample(8, random_state=1).tolist())
print("\nfull-row duplicates:", b.duplicated().sum())
print("batch_id duplicates:", b.batch_id.duplicated().sum(), "unique ids:", b.batch_id.nunique())
print(b[b.batch_id.duplicated(keep=False)].sort_values('batch_id').head(12).to_string())
print("\nmaintenance:"); m = pd.read_csv('maintenance.csv', dtype=str, keep_default_na=False)
print(m.event.value_counts().to_string()); print(m.line.value_counts().to_string()); print(m.note.value_counts().to_string())
print(m.date.str.len().value_counts())
print(pd.read_csv('suppliers.csv', dtype=str).to_string())
EOF
python3 $TMPDIR/profile.py

cat > $TMPDIR/p2.py <<'EOF'
import pandas as pd, numpy as np, re
pd.set_option('display.width', 250)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x = pd.to_numeric(b[c].str.strip().replace('', np.nan), errors='coerce')
    print(c, 'non-numeric:', (x.isna() & (b[c].str.strip()!='')).sum(), 'blank:', (b[c].str.strip()=='').sum())
    print(x.describe(percentiles=[.01,.05,.5,.95,.99]).round(2).to_dict())
    print('  <0:', (x<0).sum(), ' sample low/high:', sorted(x.dropna().unique())[:5], sorted(x.dropna().unique())[-5:])
# date format classes
def cls(s):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', s): return 'iso'
    m = re.fullmatch(r'(\d{2})/(\d{2})/(\d{4})', s)
    if m:
        a, bb = int(m.group(1)), int(m.group(2))
        if a>12: return 'dmy'
        if bb>12: return 'mdy'
        return 'ambig'
    return 'other:'+s
c = b.production_date.map(cls)
print(c.value_counts())
print(b.production_date[c.str.startswith('other')].unique()[:20])
# mold temp distribution
mt = pd.to_numeric(b.mold_temp, errors='coerce')
print(np.histogram(mt.dropna(), bins=[0,100,150,180,190,200,210,220,230,240,250,300,350,380,400,500,1000]))
print(b.loc[mt>300, ['line','mold_temp','production_date']].head(10).to_string())
print('humidity values outside 0..100:', sorted(pd.to_numeric(b.humidity_pct, errors='coerce').dropna().loc[lambda s:(s<0)|(s>100)].unique()))
print('defect > produced:', (pd.to_numeric(b.defective_units)>pd.to_numeric(b.units_produced)).sum())
EOF
python3 $TMPDIR/p2.py

cat > $TMPDIR/p3.py <<'EOF'
import pandas as pd, numpy as np, re
pd.set_option('display.width', 250)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
b['row']=range(len(b))
def cls(s):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', s): return 'iso'
    a,bb,_ = map(int, s.split('/'))
    if a>12: return 'dmy'
    if bb>12: return 'mdy'
    return 'ambig'
b['fmt']=b.production_date.map(cls)
iso = b[b.fmt=='iso'].copy(); iso['d']=pd.to_datetime(iso.production_date)
print('ISO dates monotonic in row order? spearman:', iso.row.corr(iso.d.map(pd.Timestamp.toordinal), method='spearman'))
print(iso.groupby(pd.cut(iso.row,10)).d.agg(['min','max']).to_string())
# are dmy/mdy consistent with ISO trend when parsed?
def parse(s, f):
    if f=='iso': return pd.Timestamp(s)
    if f=='dmy': return pd.to_datetime(s, format='%d/%m/%Y')
    if f=='mdy': return pd.to_datetime(s, format='%m/%d/%Y')
for f in ['dmy','mdy']:
    sub=b[b.fmt==f]; d=sub.production_date.map(lambda s: parse(s,f))
    print(f, d.min().date(), d.max().date(), 'spearman row vs date', round(sub.row.corr(d.map(pd.Timestamp.toordinal), method='spearman'),3))
# ambiguous: compare both readings' distance to the ISO trend in row order
amb=b[b.fmt=='ambig']
print(amb.head(3)[['batch_id','production_date','row']].to_string())
# per-line chronological check: use line-specific row order
EOF
python3 $TMPDIR/p3.py

cat > $TMPDIR/p4.py <<'EOF'
import pandas as pd, numpy as np, re
pd.set_option('display.width', 250)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
b['row']=np.arange(len(b))
def cands(s):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', s): return [pd.Timestamp(s)]
    a,bb,y = map(int, s.split('/'))
    out=[]
    for m,d in [(bb,a),(a,bb)]:   # mdy, dmy
        try: out.append(pd.Timestamp(year=y,month=m,day=d))
        except ValueError: pass
    return sorted(set(out))
b['cands']=b.production_date.map(cands)
b['ord']=b.cands.map(len)
lo,hi=pd.Timestamp('2025-01-06'),pd.Timestamp('2025-09-30')
b['cands']=b.cands.map(lambda c:[x for x in c if lo<=x<=hi] or c)
def resolve(sub_rows_known, row, cand_list, k=25):
    if len(cand_list)==1: return cand_list[0]
    idx=np.searchsorted(sub_rows_known.row.values,row)
    near=sub_rows_known.iloc[max(0,idx-k):idx+k]
    med=near.d.map(pd.Timestamp.toordinal).median()
    return min(cand_list,key=lambda x:abs(x.toordinal()-med))
known=b[b.ord==1].copy(); known['d']=known.cands.map(lambda c:c[0])
# validation: pretend unambiguous dmy/mdy rows are ambiguous, check the rule recovers them
amb_known=known[known.production_date.str.contains('/')]
ok=0;n=0
for i,r in amb_known.iterrows():
    kn=known.drop(i)
    pick=resolve(kn,r.row,[pd.Timestamp(r.d) ,pd.Timestamp(r.d)+pd.Timedelta(days=0)] if False else None) if False else None
    # alternative reading of the same string
    a,bb,y=map(int,r.production_date.split('/'))
    alt=[]
    for m,d in [(bb,a),(a,bb)]:
        try: alt.append(pd.Timestamp(year=y,month=m,day=d))
        except ValueError: pass
    alt=[x for x in alt if x!=r.d] 
    cl=[r.d]+alt
    cl=sorted(set(cl))
    if len(cl)==1 : continue
    n+=1; ok+= resolve(kn,r.row,cl)==r.d
print('validation: recovered',ok,'of',n,'ambiguous-with-known-answer' )
EOF
python3 $TMPDIR/p4.py

cat > $TMPDIR/dates.py <<'EOF'
import pandas as pd, numpy as np, re
LO,HI=pd.Timestamp('2025-01-06'),pd.Timestamp('2025-09-30')
def readings(s):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', s): return [pd.Timestamp(s)]
    a,bb,y=map(int,s.split('/'))
    out=set()
    for m,d in [(bb,a),(a,bb)]:
        try: out.add(pd.Timestamp(year=y,month=m,day=d))
        except ValueError: pass
    return sorted(out)
def in_range(c): return [x for x in c if LO<=x<=HI] or c
def resolve_all(b):
    b=b.copy(); b['row']=np.arange(len(b))
    b['cand']=b.production_date.map(lambda s: in_range(readings(s)))
    b['fixed']=b.cand.map(lambda c: c[0] if len(c)==1 else pd.NaT)
    def pick(row,cand,known,k=25):
        if len(cand)==1: return cand[0]
        i=np.searchsorted(known.row.values,row)
        near=known.iloc[max(0,i-k):i+k].d
        med=near.map(pd.Timestamp.toordinal).median()
        return min(cand,key=lambda x:abs(x.toordinal()-med))
    known=b[b.fixed.notna()][['row','fixed']].rename(columns={'fixed':'d'})
    b['date']=[pick(r,c,known) for r,c in zip(b.row,b.cand)]
    return b
if __name__=='__main__':
    b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
    # validation: among rows whose true reading is unambiguous (dmy/mdy), hide the truth and re-resolve
    truth=b.production_date.map(lambda s: None)
    r=resolve_all(b)
    # unambiguous-format rows: true date = the one with day>12 or month>12
    def true_date(s):
        if re.fullmatch(r'\d{4}-\d{2}-\d{2}', s): return pd.Timestamp(s)
        a,bb,y=map(int,s.split('/'))
        if a>12: return pd.Timestamp(year=y,month=bb,day=a)
        if bb>12: return pd.Timestamp(year=y,month=a,day=bb)
        return None
    tv=b.production_date.map(true_date)
    mask=tv.notna()&(tv.map(lambda x: x is not None))
    ok=0; n=0
    for i in np.where(mask)[0]:
        if len(readings(b.production_date[i]))<2: continue
        known=r[r.fixed.notna() & (r.index!=i)][['row','fixed']].rename(columns={'fixed':'d'})
        # treat i as ambiguous, both readings allowed
        cand=in_range(readings(b.production_date[i]))
        if len(cand)<2: continue
        n+=1
        from math import isnan
        kk=known; row=i
        idx=np.searchsorted(kk.row.values,row); near=kk.iloc[max(0,idx-25):idx+25].d
        med=near.map(pd.Timestamp.toordinal).median()
        pick=min(cand,key=lambda x:abs(x.toordinal()-med))
        ok+= pick==tv[i]
    print('validation: correct',ok,'of',n)
    print(r.date.dt.to_period('M').value_counts().sort_index().to_string())
    print('ambig still in range both:', sum(len(in_range(readings(s)))==2 for s in b.production_date[b.production_date.str.count('/')==2]))
    r.to_pickle('/tmp/edabench_claude_d5jor3y2/.resolved_dates.pkl') if False else None
EOF
python3 $TMPDIR/dates.py

cat > $TMPDIR/validate.py <<'EOF'
import pandas as pd, numpy as np, re, sys
sys.path.insert(0, '/tmp')
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
iso=b[b.production_date.str.match(r'^\d{4}-\d{2}-\d{2}$')].copy()
iso['row']=iso.index
iso['d']=pd.to_datetime(iso.production_date)
LO,HI=pd.Timestamp('2025-01-06'),pd.Timestamp('2025-09-30')
# known-date rows (ISO) as the reference trend
ref=iso[['row','d']].sort_values('row')
testable=iso[(iso.d.dt.day<=12)]
ok=0;n=0;tot=[]
for _,r in testable.iterrows():
    # both slash readings of the true date
    s1=r.d.strftime('%m/%d/%Y'); s2=r.d.strftime('%d/%m/%Y')
    cand=sorted({r.d, pd.Timestamp(year=r.d.year,month=r.d.day,day=r.d.month)}) if r.d.day!=r.d.month else [r.d]
    if len(cand)<2: continue
    cand=[c for c in cand if LO<=c<=HI]
    if len(cand)<2: continue
    ref2=ref[ref.row!=r.row]
    i=np.searchsorted(ref2.row.values,r.row)
    near=ref2.iloc[max(0,i-25):i+25].d
    med=near.map(pd.Timestamp.toordinal).median()
    pick=min(cand,key=lambda x:abs(x.toordinal()-med))
    n+=1; ok+= pick==r.d
print('validation correct', ok, 'of', n, ' rate', round(ok/n,3))
EOF
python3 $TMPDIR/validate.py

cat > $TMPDIR/mt.py <<'EOF'
import pandas as pd, numpy as np, re
pd.set_option('display.width',250)
m=pd.read_csv('maintenance.csv',dtype=str,keep_default_na=False)
print(m[m.event!='mold_cleaning'].to_string())
print(m[m.event=='mold_cleaning'].sort_values(['line','date']).groupby('line').date.apply(list).to_string())
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
b['mt']=pd.to_numeric(b.mold_temp,errors='coerce')
b['row']=np.arange(len(b))
# approximate date for ordering only (ISO parsed; ambiguous slashes left NaT)
b['iso']=pd.to_datetime(b.production_date,format='%Y-%m-%d',errors='coerce')
for L in ['L1','L2','L3','L4']:
    s=b[(b.line==L)&(b.mt>0)]
    hi=s.mt>300
    print(L,'n',len(s),'F-like(>300):',hi.sum(), 'first F row:', s[hi].row.min() if hi.any() else None,'last F row:', s[hi].row.max() if hi.any() else None)
    # C-range values within the same range as the F-like ones
    print('  ', L, 'share F among rows>300 per row-decile:', s.groupby(pd.cut(s.row,8)).apply(lambda g:round((g.mt>300).mean(),2)).tolist())
print('zero mold_temp by line:', b[b.mt==0].line.value_counts().to_dict())
EOF
python3 $TMPDIR/mt.py

python3 -c "import statsmodels, sklearn; print('sm', statsmodels.__version__, 'sk', sklearn.__version__)"; python3 -c "import pandas, numpy; print(pandas.__version__, numpy.__version__)"; echo $TMPDIR

python3 -c "import statsmodels; print(statsmodels.__version__)" 2>&1; python3 -c "import scipy; print(scipy.__version__)" 2>&1 | tail -1

mkdir -p /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd /tmp/edabench_claude_d5jor3y2 && cat > /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py <<'EOF'
import pandas as pd, numpy as np, re
DIR='/tmp/edabench_claude_d5jor3y2/'
LO,HI=pd.Timestamp('2025-01-06'),pd.Timestamp('2025-09-30')

def readings(s):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', s): return [pd.Timestamp(s)]
    a,bb,y=map(int,s.split('/'))
    out=set()
    for m,d in [(bb,a),(a,bb)]:
        try: out.add(pd.Timestamp(year=y,month=m,day=d))
        except ValueError: pass
    return sorted(out)

def resolve_dates(raw):
    cand=[[x for x in readings(s) if LO<=x<=HI] or readings(s) for s in raw.production_date]
    fixed=pd.Series([c[0] if len(c)==1 else pd.NaT for c in cand], index=raw.index)
    known=pd.DataFrame({'row':np.arange(len(raw))[fixed.notna().values],'d':fixed.dropna().map(pd.Timestamp.toordinal).values})
    out=[]
    for i,c in enumerate(cand):
        if len(c)==1: out.append(c[0]); continue
        j=np.searchsorted(known.row.values,i)
        med=np.median(known.d.values[max(0,j-25):j+25])
        out.append(min(c,key=lambda x:abs(x.toordinal()-med)))
    return pd.to_datetime(pd.Series(out,index=raw.index))

def load():
    raw=pd.read_csv(DIR+'batches.csv',dtype=str,keep_default_na=False)
    n_raw=len(raw)
    raw=raw.drop_duplicates()                       # exact duplicate exports
    raw=raw.reset_index(drop=True)
    d=raw.copy()
    d['date']=resolve_dates(raw)
    shift=d['shift'].str.strip().str.lower().str[0].map({'d':'Day','n':'Night'})
    d['shift']=shift
    d['supplier_code']=d.supplier_code.str.strip().str.upper()
    for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
        d[c]=pd.to_numeric(d[c].str.strip().replace('',np.nan))
    # humidity: blank or -1 sentinel is not a valid reading
    d.loc[d.humidity_pct<0,'humidity_pct']=np.nan
    d.loc[(d.humidity_pct>100),'humidity_pct']=np.nan
    # mold temp: 0 = missing; line L3 logs Fahrenheit
    d.loc[d.mold_temp<=0,'mold_temp']=np.nan
    f=d.line.eq('L3')
    d.loc[f,'mold_temp']=(d.loc[f,'mold_temp']-32)*5/9
    d['mold_temp_c']=d.mold_temp
    sup=pd.read_csv(DIR+'suppliers.csv')
    d=d.merge(sup,on='supplier_code',how='left',validate='m:1')
    d['rate']=d.defective_units/d.units_produced
    d.attrs['n_raw']=n_raw
    return d.sort_values(['date','line']).reset_index(drop=True)

def maint():
    m=pd.read_csv(DIR+'maintenance.csv',parse_dates=['date'])
    return m
EOF
cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import clean, pandas as pd
d=clean.load()
print(d.shape, d.batch_id.nunique(), d.attrs)
print(d.shift.value_counts(dropna=False).to_dict()); print(d.supplier_code.value_counts().to_dict())
print('missing humidity:', d.humidity_pct.isna().sum(), ' missing mold:', d.mold_temp.isna().sum())
print('mold median:', round(d.mold_temp.median(),4), 'L3 mean', round(d[d.line=='L3'].mold_temp.mean(),2), 'others', round(d[d.line!='L3'].mold_temp.mean(),2))
print('A3 overall:', d.defective_units.sum()/d.units_produced.sum(), d.defective_units.sum(), d.units_produced.sum())
print(d.supplier_name.isna().sum(), 'unmatched suppliers')
print(d.date.min(), d.date.max(), d.date.dt.to_period('M').value_counts().sort_index().to_dict())
"

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import clean, pandas as pd
d=clean.load()
print(d.shape, d.batch_id.nunique(), d.attrs)
print(d['shift'].value_counts(dropna=False).to_dict()); print(d.supplier_code.value_counts().to_dict())
print('missing humidity:', d.humidity_pct.isna().sum(), ' missing mold:', d.mold_temp.isna().sum())
print('mold median:', round(d.mold_temp.median(),4), 'L3 mean', round(d[d.line=='L3'].mold_temp.mean(),2), 'others', round(d[d.line!='L3'].mold_temp.mean(),2))
print('A3 overall:', d.defective_units.sum()/d.units_produced.sum(), d.defective_units.sum(), d.units_produced.sum())
print(d.supplier_name.isna().sum(), 'unmatched suppliers')
print(d.date.min(), d.date.max(), d.date.dt.to_period('M').value_counts().sort_index().to_dict())
"

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > explore1.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['def']=x.defective_units; x['ok']=x.units_produced-x.defective_units
f='def + ok ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)'
m=smf.glm('defective_units + ok ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(operator_id)+C(line)+C(supplier_code)',data=x,family=sm.families.Binomial()).fit(scale='X2')
print(m.summary2().tables[1].loc[lambda t: ~t.index.str.startswith('C(operator')].round(4).to_string())
print('dispersion X2:', round(m.scale,3))
# operator joint test
m0=smf.glm('defective_units + ok ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift)+C(line)+C(supplier_code)',data=x,family=sm.families.Binomial()).fit(scale='X2')
print('operators jointly, F-test-ish dev diff p:', round(float(sm.stats.anova_lm(m0,m) if False else 0),3))
from scipy.stats import chi2
dd=(m0.deviance-m.deviance)/m.scale; dfd=m0.df_resid-m.df_resid
print('shift-free: operator df',dfd,'chi2 p', round(chi2.sf(dd,dfd),4))
# leakage check: rate vs qc and rework
print(x[['rate','qc_inspection_min','rework_cost_eur','defective_units']].corr().round(3).to_string())
print(smf.ols('qc_inspection_min ~ rate + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift)+C(line)+C(supplier_code)',data=x).fit().summary2().tables[1].round(4).to_string())
EOF
python3 explore1.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > glm.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy.stats import chi2
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
print('rows used', len(x), 'units', x.units_produced.sum())
def fit(f, data=x):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit()
full=fit('rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)')
t=full.summary2().tables[1]
print(t.round(4).to_string())
print('pearson dispersion', round(full.pearson_chi2/full.df_resid,3))
EOF
python3 glm.py 2>&1 | grep -v Warning

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > glm2.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy.stats import chi2
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['pre']=(x.pre_dried=='yes').astype(int)
def fit(f, data=x):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
base='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)'
forms={
 'base':base,
 '+mold2':base+' + I(mold_temp**2)',
 '+hum2':base+' + I(humidity_pct**2)',
 '+cyc2':base+' + I(cycle_time_s**2)',
 '+age2':base+' + I(machine_age_years**2)',
 '+amb2':base+' + I(ambient_temp_c**2)',
 '+hum*pre':base+' + humidity_pct:pre',
 '+sup*hum':base+' + humidity_pct:C(supplier_code)',
 '+mold*line':base+' + mold_temp:C(line)',
}
res={}
for k,f in forms.items():
    m=fit('rate ~ '+f); res[k]=m
    print(f"{k:12s} dev={m.deviance:12.2f} aic={m.aic:12.2f} df={m.df_model}")
b=res['base']
for k in forms:
    if k=='base': continue
    dd=b.deviance-res[k].deviance; dfd=res[k].df_model-b.df_model
    print(k,'LR chi2',round(dd/res[k].scale,2),'df',dfd,'p',round(chi2.sf(dd/res[k].scale,dfd),5))
EOF
python3 glm2.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > shape.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['pre']=(x.pre_dried=='yes').astype(int)
x['hb']=(x.humidity_pct//5*5).astype(int)
x['mb']=(x.mold_temp//5*5).astype(int)
x['cb']=(x.cycle_time_s//3*3).astype(int)
x['ab']=(x.ambient_temp_c//3*3).astype(int)
x['agb']=(x.machine_age_years//3*3).astype(int)
# raw empirical rate by humidity bin and supplier
g=x.groupby(['hb','supplier_code']).agg(n=('rate','size'),def_=('defective_units','sum'),u=('units_produced','sum'))
g['rate']=g.def_/g.u
print(g.rate.unstack().round(4).to_string())
print(x.groupby('hb').apply(lambda t: t.defective_units.sum()/t.units_produced.sum()).round(4).to_string())
# mold temp shape by line
print(x.groupby(['mb','line']).apply(lambda t: t.defective_units.sum()/t.units_produced.sum()).unstack().round(4).to_string())
EOF
python3 shape.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > flex.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy.stats import chi2
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['pre']=(x.pre_dried=='yes').astype(int)
x['cdev']=x.cycle_time_s-x.recipe_cycle_time_s
def fit(f, data=x):
    return smf.glm('rate ~ '+f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
core=('humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + mold_temp*C(line)'
      ' + cycle_time_s + machine_age_years + ambient_temp_c + C(shift)')
m_core=fit(core)
print('core dev', round(m_core.deviance,1), 'disp', round(m_core.scale,2))
print(m_core.summary2().tables[1].round(4).to_string())
for add,name in [(' + C(operator_id)','operator'),(' + ambient_temp_c:humidity_pct','amb*hum'),(' + cdev','cdev'),(' + C(line)','line'),(' + C(supplier_code)','sup'),(' + mold_temp:humidity_pct','mold*hum')]:
    m=fit(core+add)
    dd=(m.deviance-m_core.deviance)/m_core.scale
    dfd=m.df_model-m_core.df_model
    print(f'{name:10s} adds df {dfd:.0f} LR={-dd if False else dd:.2f} p={chi2.sf(-dd if dd<0 else dd, abs(dfd)):.4g}')
EOF
python3 flex.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > flex2.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy.stats import chi2
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['agb']=(x.machine_age_years//2).astype(int).astype(str)
def fit(f, data=x):
    return smf.glm('rate ~ '+f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
core='C(hb)*C(supplier_code) + C(mb)*C(line) + C(ab) + C(cb) + C(agb) + C(shift)'
mc=fit(core)
print('core dev',round(mc.deviance,1),'df',mc.df_model,'disp',round(mc.scale,2))
def test(add, name, drop=None):
    m=fit(add) if drop is None else fit(drop)
    lr=(m.deviance-mc.deviance)/mc.scale if drop is None else (mc.deviance-m.deviance)/mc.scale
    return lr
# drop-tests on the full binned model: refit without each term
for term,f in [('shift','C(hb)*C(supplier_code) + C(mb)*C(line) + C(ab) + C(cb) + C(agb)'),
               ('ambient','C(hb)*C(supplier_code) + C(mb)*C(line) + C(cb) + C(agb) + C(shift)'),
               ('age','C(hb)*C(supplier_code) + C(mb)*C(line) + C(ab) + C(cb) + C(shift)'),
               ('cycle','C(hb)*C(supplier_code) + C(mb)*C(line) + C(ab) + C(agb) + C(shift)')]:
    m=fit(f); lr=(m.deviance-mc.deviance)/mc.scale; dfd=mc.df_model-m.df_model
    print(f'drop {term:8s} LR={lr:8.2f} df={dfd:.0f} p={chi2.sf(lr,dfd):.4g}')
# operator on top of core
m=fit(core+' + C(operator_id)'); lr=(mc.deviance-m.deviance)/mc.scale if False else (mc.deviance-m.deviance)/mc.scale
print('add operator LR', round(-lr,2), 'df', m.df_model-mc.df_model, 'p', round(chi2.sf(abs(lr), m.df_model-mc.df_model),4))
EOF
python3 flex2.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > amb.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
print(x[['ambient_temp_c','humidity_pct','mold_temp','cycle_time_s','machine_age_years','rate']].corr().round(3).to_string())
print(smf.ols('humidity_pct ~ ambient_temp_c + C(line) + C(supplier_code) + C(shift)',data=x).fit().summary2().tables[1].round(3).to_string())
print(smf.ols('mold_temp ~ ambient_temp_c + machine_age_years + cycle_time_s + C(line)+C(supplier_code)+C(shift)+humidity_pct',data=x).fit().summary2().tables[1].round(3).to_string())
print(smf.ols('cycle_time_s ~ C(supplier_code)+C(line)+C(shift)+machine_age_years+ambient_temp_c',data=x).fit().summary2().tables[1].round(3).to_string())
# ambient effect within suppliers and lines (defect rate by ambient bin, pre-dried vs not)
x['ab']=(x.ambient_temp_c//4*4)
print(x.groupby(['ab','pre_dried']).apply(lambda t: t.defective_units.sum()/t.units_produced.sum()).unstack().round(4).to_string())
EOF
python3 amb.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > amb2.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy.stats import chi2
pd.set_option('display.width',250)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
def fit(f, data):
    return smf.glm('rate ~ '+f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
for L in [None,'L1','L2','L4','L3']:
    s=x if L is None else x[x.line==L]
    base='C(hb)*C(supplier_code) + C(mb) + C(cb) + C(shift)' if L else 'C(hb)*C(supplier_code) + C(mb)*C(line) + C(cb) + C(shift)'
    m0=fit(base, s); m1=fit(base+' + C(ab)', s)
    lr=(m0.deviance-m1.deviance)/m1.scale; dfd=m1.df_model-m0.df_model
    print(L or 'ALL', 'ambient LR', round(lr,2), 'df', dfd, 'p', round(chi2.sf(lr,dfd),5), 'n',len(s))
# simple linear ambient slope inside mold-temp strata, all lines
s=x.copy()
print(smf.glm('rate ~ C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(shift)+ambient_temp_c',data=s,family=sm.families.Binomial(),var_weights=s.units_produced).fit(scale='X2').params[['ambient_temp_c']])
EOF
python3 amb2.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > resid.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250); pd.set_option('display.max_rows',500)
d=clean.load()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['month']=x.date.dt.month
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
print(x.groupby(['line','month']).ambient_temp_c.mean().unstack().round(1).to_string())
# model without ambient and without time
f='rate ~ C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(shift)'
m=smf.glm(f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
x['exp_']=m.predict(x)*x.units_produced
x['obs']=x.defective_units
mon=x.groupby(['line','month']).agg(obs=('obs','sum'),exp=('exp_','sum'))
mon['O/E']=(mon.obs/mon.exp).round(3)
print(mon['O/E'].unstack().to_string())
# and the same with ambient added
print('ambient added to base:')
m2=smf.glm(f+' + ambient_temp_c',data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
print(m2.params[['ambient_temp_c']], m2.bse[['ambient_temp_c']])
EOF
python3 resid.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > maint.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width',250)
m=pd.read_csv('/tmp/edabench_claude_d5jor3y2/maintenance.csv',parse_dates=['date'])
c=m[m.event=='mold_cleaning'].sort_values(['line','date'])
for L,g in c.groupby('line'):
    gaps=g.date.diff().dt.days
    print(L, 'n',len(g), 'first',g.date.min().date(),'last',g.date.max().date(),'max gap',gaps.max(), 'gaps>14:', (gaps>14).sum())
    print('   dates:', [s.strftime('%m-%d') for s in g.date])
    print('   gaps:', gaps.dropna().astype(int).tolist())
print(m.duplicated(['date','line','event']).sum(), 'duplicate maintenance rows')
EOF
python3 maint.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > cp.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy.stats import chi2
pd.set_option('display.width',250)
d=clean.load()
mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
def dsc(row):
    c=cl[(cl.line==row.line)&(cl.date<=row.date)].date
    return (row.date-c.max()).days if len(c) else np.nan
d['dsc']=d.apply(dsc,axis=1)
print('days since clean summary:', d.dsc.describe().round(1).to_dict())
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
x['dsb']=np.minimum(x.dsc,40).astype(int).astype(str)
x['t']=(x.date-pd.Timestamp('2025-01-01')).dt.days
def fit(f,data=x): return smf.glm('rate ~ '+f,data=data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
core='C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(ab)+C(shift)'
m0=fit(core)
m1=fit(core+' + dsc')
print('dsc slope effect: coef', round(m1.params['dsc'],5), 'z', round(m1.tvalues['dsc'],2))
m2=fit(core+' + dsc + C(line):t')
print('line trends, dev drop vs m1', round((m1.deviance-m2.deviance)/m2.scale,2))
# change-point scan per line, with dsc in model
res=[]
for L in ['L1','L2','L3','L4']:
    best=None
    for dt in pd.date_range('2025-02-01','2025-09-01',freq='D'):
        x['step']=((x.line==L)&(x.date>=dt)).astype(int)
        m=fit(core+' + dsc + step',data=x)
        lr=(m1.deviance-m.deviance)/m.scale
        if best is None or lr>best[1]: best=(dt.date(),lr,m.params['step'],m.tvalues['step'])
    res.append((L,)+best); print(L,'best step date',best[0],'LR',round(best[1],1),'coef',round(best[2],3),'t',round(best[3],2))
EOF
python3 cp.py 2>&1 | grep -v -i warn

sleep 100; cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b1hp0v6xb.output 2>/dev/null | grep -v -i warn | tail -20

cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b1hp0v6xb.output 2>/dev/null | grep -v -i warn | tail -20; echo; ls -la /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/ 2>/dev/null

grep -v -i warn /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b1hp0v6xb.output | tail -6; echo ---; grep -v -i warn /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bi2zv9p1p.output | tail -4

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > cum.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250); pd.set_option('display.max_rows',300)
d=clean.load()
mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
def dsc(row):
    c=cl[(cl.line==row.line)&(cl.date<=row.date)].date
    return (row.date-c.max()).days
d['dsc']=d.apply(dsc,axis=1)
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
core='C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(ab)+C(shift)+dsc'
m=smf.glm('rate ~ '+core,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
x['E']=m.predict(x)*x.units_produced
x['O']=x.defective_units
x['wk']=x.date.dt.to_period('M')
t=x.groupby(['line','wk']).agg(O=('O','sum'),E=('E','sum'))
t['OE']=(t.O/t.E).round(3)
print(t.OE.unstack().to_string())
# half-month windows for L2 around June
x['hm']=x.date.dt.strftime('%m-')+np.where(x.date.dt.day<=15,'a','b')
l2=x[x.line=='L2'].groupby('hm').agg(O=('O','sum'),E=('E','sum')); l2['OE']=(l2.O/l2.E).round(3)
print(l2.to_string())
print('dsc coef', round(m.params['dsc'],4))
EOF
python3 cum.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > l3.py <<'EOF'
import clean, pandas as pd, numpy as np
pd.set_option('display.width',250)
d=clean.load()
d['m']=d.date.dt.month
g=d.groupby(['line','m']).agg(n=('rate','size'),units=('units_produced','mean'),cyc=('cycle_time_s','mean'),
  hum=('humidity_pct','mean'),mold=('mold_temp','mean'),amb=('ambient_temp_c','mean'),age=('machine_age_years','mean'),
  rate=('rate','mean'),shift_night=('shift',lambda s:(s=='Night').mean()))
print(g.round(2).to_string())
EOF
python3 l3.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > dscshape.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=clean.load()
mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
def dsc(row):
    c=cl[(cl.line==row.line)&(cl.date<=row.date)].date
    return (row.date-c.max()).days
d['dsc']=d.apply(dsc,axis=1)
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
x['db']=np.minimum(x.dsc,35).astype(int).astype(str)
# drop dsc, fit model with dsc as bins, then read off coefficients
f='rate ~ C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(ab)+C(shift)+C(db)'
m=smf.glm(f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
p=m.params.filter(like='C(db)')
print(pd.Series(np.r_[0,p.values],index=range(0,35)).round(3).to_string() if False else pd.DataFrame({'dsc':[int(s.split('T.')[1].rstrip(']')) for s in p.index],'coef':p.values}).sort_values('dsc').round(3).to_string())
# counts by dsc
print(x.dsc.value_counts().sort_index().to_string())
EOF
python3 dscshape.py 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > oe2.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
d=clean.load()
mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
d['dsc']=d.apply(lambda r:(r.date-cl[(cl.line==r.line)&(cl.date<=r.date)].date.max()).days,axis=1)
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
x['db']=np.minimum(x.dsc,35).astype(int).astype(str)
x['wk']=x.date.dt.month
for name,f in [('binned dsc','C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(ab)+C(shift)+C(db)'),
               ('binned dsc, no ambient','C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(shift)+C(db)')]:
    m=smf.glm('rate ~ '+f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
    x['E']=m.predict(x)*x.units_produced
    t=x.groupby(['line','wk']).apply(lambda g: g.defective_units.sum()/g.E.sum()).unstack().round(3)
    print(name); print(t.to_string())
EOF
python3 oe2.py 2>&1 | grep -v -i warn

pkill -f cp.py; sleep 1; pgrep -fa "python3" | head; nproc

pgrep -fa "cp.py|oe2.py" ; echo "exit $?"; nproc

grep -v -i warn /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bu9ry56m7.output | tail -30

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > detail.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250); pd.set_option('display.max_rows',400)
d=clean.load()
mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
cdates={L:np.sort(g.date.values) for L,g in cl.groupby('line')}
def dsc(r):
    c=cdates[r.line]; c=c[c<=np.datetime64(r.date)]
    return (np.datetime64(r.date)-c.max()).astype('timedelta64[D]').astype(int)
d['dsc']=d.apply(dsc,axis=1)
x=d.dropna(subset=['humidity_pct','mold_temp']).copy()
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
core='C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(ab)+C(shift)+dsc'
m=smf.glm('rate ~ '+core,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
x['E']=m.predict(x)*x.units_produced
x['wk']=x.date.dt.to_period('W').dt.start_time.dt.strftime('%m-%d')
for L in ['L2','L3']:
    s=x[x.line==L]
    t=s.groupby('wk').agg(n=('rate','size'),O=('defective_units','sum'),E=('E','sum'),dsc=('dsc','mean'),mold=('mold_temp','mean'),
        supA=('supplier_code',lambda v:(v=='SP-01').mean()),sup2=('supplier_code',lambda v:(v=='SP-02').mean()),
        amb=('ambient_temp_c','mean'),hum=('humidity_pct','mean'))
    t['OE']=(t.O/t.E).round(2)
    print(L); print(t.round(2).to_string())
EOF
timeout 110 python3 detail.py 2>&1 | grep -v -i warn

ps -eo pid,etime,pcpu,args | grep -E "python3 [a-z0-9_]+\.py" | grep -v grep | cut -c1-160

ps -eo pid,etime,pcpu,comm | grep -i python | head; echo; tail -c 600 /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bu9ry56m7.output | grep -v -i warn | tail -5

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && (python3 -W ignore detail.py > detail.out 2>&1 &) ; sleep 5; echo started

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat detail.out | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat detail.out | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat detail.out | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && timeout 100 bash -c 'until [ -s detail.out ]; do :; done'; cat detail.out | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat detail.out | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && ls -la detail.out; for p in /proc/[0-9]*; do c=$(tr '\0' ' ' < $p/cmdline 2>/dev/null); case "$c" in *detail.py*) echo "$(basename $p): $c";; esac; done | head

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && time python3 -W ignore detail.py 2>&1 | tail -80

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > scan.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=clean.load()
mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
cdates={L:np.sort(g.date.values) for L,g in cl.groupby('line')}
def dsc(r):
    c=cdates[r.line]; c=c[c<=np.datetime64(r.date)]
    return int((np.datetime64(r.date)-c.max()).astype('timedelta64[D]').astype(int))
d['dsc']=d.apply(dsc,axis=1)
x=d.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
def fit(f):
    return smf.glm('rate ~ '+f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
base='C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(ab)+C(shift)'
for label,extra in [('no dsc',''),('linear dsc',' + dsc')]:
    m0=fit(base+extra)
    print('==',label,'dev',round(m0.deviance,1),flush=True)
    for L in ['L1','L2','L3','L4']:
        best=(None,-1,None)
        for dt in pd.date_range('2025-03-01','2025-09-15',freq='3D'):
            x['st']=((x.line==L)&(x.date>=dt)).astype(int)
            m=fit(base+extra+' + st')
            lr=(m0.deviance-m.deviance)/m.scale
            if lr>best[1]: best=(dt.date(),lr,m.params['st'])
        print(L,'best step from',best[0],'LR',round(best[1],1),'coef',round(best[2],3),flush=True)
EOF
timeout 280 python3 scan.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -u scan.py > scan.out 2>&1; echo done

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > joint.py <<'EOF'
import clean, pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
from scipy.stats import chi2
warnings.filterwarnings('ignore')
d=clean.load()
mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
cdates={L:np.sort(g.date.values) for L,g in cl.groupby('line')}
def dsc(r):
    c=cdates[r.line]; c=c[c<=np.datetime64(r.date)]
    return int((np.datetime64(r.date)-c.max()).astype('timedelta64[D]').astype(int))
d['dsc']=d.apply(dsc,axis=1)
x=d.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
x['hb']=(x.humidity_pct//2.5).astype(int).astype(str)
x['mb']=(x.mold_temp//4).astype(int).astype(str)
x['cb']=(x.cycle_time_s//1.5).astype(int).astype(str)
x['ab']=(x.ambient_temp_c//2).astype(int).astype(str)
x['s2']=((x.line=='L2')&(x.date>=pd.Timestamp('2025-06-16'))).astype(int)
x['s3']=((x.line=='L3')&(x.date>=pd.Timestamp('2025-07-21'))).astype(int)
def fit(f):
    return smf.glm('rate ~ '+f,data=x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
base='C(hb)*C(supplier_code)+C(mb)*C(line)+C(cb)+C(ab)+C(shift)'
for name,f in [('dsc only',base+' + dsc'),('dsc + s2',base+' + dsc + s2'),('dsc + s2 + s3',base+' + dsc + s2 + s3'),('s2 + s3 no dsc',base+' + s2 + s3'),('s2 no dsc',base+' + s2'),('dsc+ s2 + ambient', base+' + dsc + s2')]:
    m=fit(f)
    keys=[k for k in ['dsc','s2','s3','ab'] if k in m.params.index]
    print(f'{name:18s} dev={m.deviance:9.1f} ', {k:(round(m.params[k],4),round(m.tvalues[k],1)) for k in keys if k!='ab'})
EOF
timeout 280 python3 -u joint.py

cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/b7g15ycfe.output 2>/dev/null; echo; cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/scan.out

cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/scan.out

for p in /proc/[0-9]*; do c=$(tr '\0' ' ' < $p/cmdline 2>/dev/null); case "$c" in "python3 -u scan.py"*) echo kill $(basename $p); kill $(basename $p);; esac; done; echo ok

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > fast.py <<'EOF'
"""Fast binomial-GLM helper: numpy design matrices, frequency-weighted IRLS (quasi, Pearson dispersion)."""
import clean, pandas as pd, numpy as np, warnings
from scipy.stats import chi2
warnings.filterwarnings('ignore')

def load_all():
    d=clean.load()
    mt=clean.maint(); cl=mt[mt.event=='mold_cleaning']
    cdates={L:np.sort(g.date.values) for L,g in cl.groupby('line')}
    def dsc(r):
        c=cdates[r.line]; c=c[c<=np.datetime64(r.date)]
        return int((np.datetime64(r.date)-c.max()).astype('timedelta64[D]').astype(int))
    d['dsc']=d.apply(dsc,axis=1)
    d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(int)
    d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
    d['hb']=(d.humidity_pct//2.5)
    d['mb']=(d.mold_temp//4)
    d['cb']=(d.cycle_time_s//1.5)
    d['ab']=(d.ambient_temp_c//2)
    return d

def dummies(s, prefix, drop_first=True):
    D=pd.get_dummies(s.astype(str), prefix=prefix, drop_first=drop_first).astype(float)
    return D

def irls(X, y, w, maxit=50):
    """y = proportion, w = units. Returns beta, pearson-chi2 dispersion, deviance."""
    n_iter=0
    mu=np.clip(y,1e-4,1-1e-4)
    eta=np.log(mu/(1-mu))
    beta=np.zeros(X.shape[1])
    for _ in range(maxit):
        mu=1/(1+np.exp(-eta))
        W=w*mu*(1-mu)
        z=eta+(y-mu)/(mu*(1-mu))
        XtW=X.T*W
        new=np.linalg.solve(XtW@X+1e-8*np.eye(X.shape[1]), XtW@z)
        if np.max(np.abs(new-beta))<1e-8: beta=new; break
        beta=new; eta=X@beta
    mu=1/(1+np.exp(-(X@beta)))
    pearson=np.sum(w*(y-mu)**2/(mu*(1-mu)))
    dfres=len(y)-X.shape[1]
    dev=2*np.sum(w*(y*np.log(np.clip(y,1e-12,1)/mu)+(1-y)*np.log(np.clip(1-y,1e-12,1)/(1-mu))))
    return beta, pearson/dfres, dev, mu

def design(d, terms):
    """terms: list of arrays/dataframes already built."""
    return np.column_stack([np.ones(len(d))]+[t.values if hasattr(t,'values') else t for t in terms])
EOF
cat > fasttest.py <<'EOF'
import time, numpy as np, pandas as pd
from fast import *
d=load_all()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
y=(x.defective_units/x.units_produced).values; w=x.units_produced.values.astype(float)
t0=time.time()
hyb=dummies(x.hb.astype(str)+'_'+x.supplier_code,'hs')
mline=dummies(x.mb.astype(str)+'_'+x.line,'ml')
cy=dummies(x.cb.astype(str),'cy'); ab=dummies(x.ab.astype(str),'ab'); sh=dummies(x['shift'],'sh')
X=np.column_stack([np.ones(len(x)),hyb.values,mline.values,cy.values,ab.values,sh.values,x.dsc.values,x.s2.values])
b,disp,dev,mu=irls(X,y,w)
print('fit time',round(time.time()-t0,2),'disp',round(disp,2),'dev',round(dev,1),'dsc',round(b[-2],4),'s2',round(b[-1],4))
EOF
python3 fasttest.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > scan2.py <<'EOF'
import numpy as np, pandas as pd
from fast import *
d=load_all()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
y=(x.defective_units/x.units_produced).values; w=x.units_produced.values.astype(float)
base=np.column_stack([np.ones(len(x)),dummies(x.hb.astype(str)+'_'+x.supplier_code,'hs').values,
    dummies(x.mb.astype(str)+'_'+x.line,'ml').values,dummies(x.cb.astype(str),'cy').values,
    dummies(x.ab.astype(str),'ab').values,dummies(x['shift'],'sh').values])
def run(extra, label):
    X0=np.column_stack([base]+extra) if extra else base
    _,_,dev0,_=irls(X0,y,w)
    print('==',label,'dev0',round(dev0,1),flush=True)
    for L in ['L1','L2','L3','L4']:
        best=(None,-1,None)
        for dt in pd.date_range('2025-03-01','2025-09-20',freq='2D'):
            st=((x.line==L)&(x.date>=dt)).astype(float).values
            X=np.column_stack([X0,st])
            b,disp,dev,_=irls(X,y,w)
            lr=(dev0-dev)/disp
            if lr>best[1]: best=(dt.date(),lr,b[-1])
        print(L,'best step from',best[0],'LR',round(best[1],1),'coef',round(best[2],3),flush=True)
run([x.dsc.values[:,None]],'with linear dsc')
run([],'no dsc')
EOF
timeout 280 python3 -u scan2.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > sensor.py <<'EOF'
import numpy as np, pandas as pd, statsmodels.formula.api as smf, warnings
warnings.filterwarnings('ignore')
import clean
pd.set_option('display.width',250)
d=clean.load().dropna(subset=['mold_temp']).copy()
d['t']=(d.date-pd.Timestamp('2025-01-01')).dt.days
# mold temp vs ambient by line: fit on all, then residual by time
m=smf.ols('mold_temp ~ ambient_temp_c + C(line) + cycle_time_s + C(supplier_code)',data=d).fit()
d['res']=m.resid
for L in ['L1','L2','L3','L4']:
    s=d[d.line==L]
    print(L, 'resid mean by 2-week window (Mar-May):')
    w=s[(s.date>='2025-03-01')&(s.date<='2025-05-31')].groupby(pd.Grouper(key='date',freq='7D')).res.agg(['mean','size']).round(2)
    print(w.T.to_string())
# step scan on mold residual for L1 and L2 (mean shift)
for L,lo,hi in [('L1','2025-03-01','2025-05-31'),('L2','2025-05-01','2025-07-31')]:
    s=d[(d.line==L)].sort_values('date')
    best=None
    for dt in pd.date_range(lo,hi):
        a=s[s.date<dt].res; b=s[s.date>=dt].res
        if len(a)<20 or len(b)<20: continue
        tstat=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best is None or abs(tstat)>abs(best[1]): best=(dt.date(),tstat,b.mean()-a.mean())
    print(L,'mold-residual best mean shift at',best[0],'t',round(best[1],2),'shift',round(best[2],2))
EOF
timeout 200 python3 -u sensor.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > scan3.py <<'EOF'
import numpy as np, pandas as pd
from fast import *
d=load_all()
x=d.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
y=(x.defective_units/x.units_produced).values; w=x.units_produced.values.astype(float)
base=np.column_stack([np.ones(len(x)),dummies(x.hb.astype(str)+'_'+x.supplier_code,'hs').values,
    dummies(x.mb.astype(str)+'_'+x.line,'ml').values,dummies(x.cb.astype(str),'cy').values,
    dummies(x.ab.astype(str),'ab').values,dummies(x['shift'],'sh').values, x.dsc.values])
_,_,dev0,_=irls(base,y,w)
print('base dev',round(dev0,1),flush=True)
for L in ['L1','L2','L3','L4']:
    res=[]
    for dt in pd.date_range('2025-02-15','2025-09-10',freq='1D'):
        st=((x.line==L)&(x.date>=dt)).astype(float).values
        X=np.column_stack([base,st])
        b,disp,dev,_=irls(X,y,w)
        res.append((dt.date(),(dev0-dev)/disp,b[-1]))
    r=pd.DataFrame(res,columns=['date','LR','coef'])
    top=r.sort_values('LR',ascending=False).head(3)
    print(L,'top start dates:'); print(top.round(3).to_string(index=False),flush=True)
EOF
python3 -u scan3.py > scan3.out 2>&1; echo ok

cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/scan3.out

cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/scan3.out

cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/scan3.out

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > spline_model.py <<'EOF'
"""Final-model helper: patsy natural splines so the fitted model can predict counterfactual rows."""
import numpy as np, pandas as pd, patsy, warnings
from fast import load_all, irls
warnings.filterwarnings('ignore')

def make_frame():
    d=load_all()
    d=d.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
    return d

RHS=("cr(humidity_pct, df=6):C(supplier_code) + cr(mold_temp, df=5):C(line) + cr(cycle_time_s, df=4)"
     " + cr(ambient_temp_c, df=4) + C(shift) + cr(dsc, df=5)")

def fit_model(d, extra_steps=()):
    rhs=RHS+''.join(' + '+s for s in extra_steps)
    dm=patsy.dmatrix(rhs, d, return_type='dataframe')
    y=(d.defective_units/d.units_produced).values; w=d.units_produced.values.astype(float)
    beta,disp,dev,mu=irls(dm.values,y,w)
    return dict(beta=beta,disp=disp,dev=dev,design_info=dm.design_info,names=dm.columns,rhs=rhs,extra=extra_steps)

def predict(model, d):
    dm=patsy.build_design_matrices([model['design_info']], d, return_type='dataframe')[0]
    eta=dm.values@model['beta']
    return 1/(1+np.exp(-eta))
EOF
cat > check_spline.py <<'EOF'
from spline_model import *
d=make_frame()
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(int)
m0=fit_model(d)
m1=fit_model(d,['s2'])
print('no step dev',round(m0.dev,1),'disp',round(m0.disp,2),' with s2 dev',round(m1.dev,1),'disp',round(m1.disp,2),' s2 coef',round(m1.beta[list(m1.names).index('s2')],3))
pr=predict(m1,d); print('pred total rate', round((pr*d.units_produced).sum()/d.units_produced.sum(),5), 'obs', round(d.defective_units.sum()/d.units_produced.sum(),5))
EOF
timeout 110 python3 check_spline.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && sed -i "s/m0\.dev/m0['dev']/; s/m0\.disp/m0['disp']/; s/m1\.dev/m1['dev']/; s/m1\.disp/m1['disp']/; s/m1\.beta\[list(m1\.names)/m1['beta'][list(m1['names'])/; s/index('s2')\]/index('s2')]/; s/model\['design_info'\]/model['design_info']/" check_spline.py && sed -i "s/round(m1\['beta'\]\[list(m1\['names'\])\.index('s2')\],3)/round(m1['beta'][list(m1['names']).index('s2')],3)/" check_spline.py && timeout 110 python3 check_spline.py; cat scan3.out

cat /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/scan3.out

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > steps_spline.py <<'EOF'
from spline_model import *
d=make_frame()
d['s1']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
for steps in [['s2'],['s2','s3'],['s1','s2','s3']]:
    m=fit_model(d,steps)
    print(steps,'dev',round(m['dev'],1),'disp',round(m['disp'],2),{s:round(m['beta'][list(m['names']).index(s)],3) for s in steps})
m=fit_model(d,['s1','s2','s3'])
print('dsc spline effect on one-line grid:')
EOF
timeout 280 python3 steps_spline.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > sens2.py <<'EOF'
import numpy as np, pandas as pd, statsmodels.formula.api as smf, warnings
warnings.filterwarnings('ignore')
import clean
d=clean.load().dropna(subset=['mold_temp']).copy()
m=smf.ols('mold_temp ~ ambient_temp_c + C(line) + cycle_time_s + C(supplier_code)',data=d).fit()
d['res']=m.resid
for L,lo,hi in [('L1','2025-03-01','2025-06-30'),('L2','2025-05-01','2025-08-31'),('L3','2025-06-01','2025-09-30'),('L4','2025-05-01','2025-09-30')]:
    s=d[d.line==L].sort_values('date')
    best=None
    for dt in pd.date_range(lo,hi):
        a=s[s.date<dt].res; b=s[s.date>=dt].res
        if len(a)<20 or len(b)<20: continue
        t=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best is None or abs(t)>abs(best[1]): best=(dt.date(),t,b.mean()-a.mean())
    print(L,'best mold-residual step',best[0],'t',round(best[1],2),'shift',round(best[2],2))
EOF
timeout 200 python3 sens2.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > amb_line.py <<'EOF'
import spline_model as sm_
from spline_model import *
d=make_frame()
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
base=sm_.RHS
def run(rhs, steps, label):
    sm_.RHS=rhs
    m=fit_model(d,steps)
    print(label, 'dev',round(m['dev'],1),{s:round(m['beta'][list(m['names']).index(s)],3) for s in steps}, flush=True)
run(base+" + cr(ambient_temp_c, df=4):C(line)", [], 'ambient x line, no steps')
run(base+" + cr(ambient_temp_c, df=4):C(line)", ['s2'], 'ambient x line + s2')
run(base+" + cr(ambient_temp_c, df=4):C(line)", ['s3'], 'ambient x line + s3')
run(base+" + cr(ambient_temp_c, df=4):C(line)", ['s2','s3'], 'ambient x line + s2 + s3')
EOF
timeout 280 python3 amb_line.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > oper.py <<'EOF'
import spline_model as sm_
from spline_model import *
import patsy
d=make_frame()
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
L3=d[d.line=='L3'].copy(); L3['per']=np.where(L3.date>=pd.Timestamp('2025-07-21'),'post','pre')
print(pd.crosstab(L3.operator_id,L3.per).to_string())
m=fit_model(d,['s2','s3'])
m2=fit_model(d,['s2','s3','C(operator_id)'])
print('with operators: dev',round(m2['dev'],1),'vs',round(m['dev'],1))
print({s:round(m2['beta'][list(m2['names']).index(s)],3) for s in ['s2','s3']})
EOF
timeout 280 python3 oper.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > mold_fine.py <<'EOF'
import spline_model as sm_
from spline_model import *
d=make_frame()
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
d['s1']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
base=sm_.RHS.replace("cr(mold_temp, df=5):C(line)","cr(mold_temp, df=10):C(line)")
sm_.RHS=base
m=fit_model(d,['s2','s3'])
print('fine mold, steps s2 s3 dev',round(m['dev'],1),{s:round(m['beta'][list(m['names']).index(s)],3) for s in ['s2','s3']},flush=True)
m=fit_model(d,[])
print('fine mold no steps dev',round(m['dev'],1),flush=True)
for L in ['L2','L3']:
    s=d[d.line==L]
    print(L,'mold>=220 share pre/post:', 
      round((s[s.date<pd.Timestamp('2025-06-15' if L=='L2' else '2025-07-21')].mold_temp>=220).mean(),3),
      round((s[s.date>=pd.Timestamp('2025-06-15' if L=='L2' else '2025-07-21')].mold_temp>=220).mean(),3))
EOF
timeout 280 python3 mold_fine.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > final.py <<'EOF'
import numpy as np, pandas as pd
from spline_model import *
d=make_frame()
d['s1']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
STEPS=['s1','s2','s3']
M=fit_model(d,STEPS)
print('final model dev',round(M['dev'],1),'disp',round(M['disp'],2))
print({s:round(M['beta'][list(M['names']).index(s)],3) for s in STEPS})
pb=predict(M,d); base_rate=(pb*d.units_produced).sum()/d.units_produced.sum()
print('baseline predicted overall rate',round(base_rate,5),'observed',round(d.defective_units.sum()/d.units_produced.sum(),5))

# C1: every batch from one supplier, cycle time = recipe of that grade
recipe={'SP-01':30,'SP-02':30,'SP-03':36}
for sup in ['SP-01','SP-02','SP-03']:
    c=d.copy(); c['supplier_code']=sup; c['cycle_time_s']=recipe[sup]
    p=predict(M,c)
    print('C1',sup, round((p*c.units_produced).sum()/c.units_produced.sum(),5))

# C2: Alpha batches, humidity grid over observed range; other covariates per batch (logit additive so argmin is shared)
lo,hi=d.humidity_pct.min(),d.humidity_pct.max()
grid=np.round(np.arange(np.ceil(lo),hi,0.1),2)
a=d[d.supplier_code=='SP-01']
rates=[]
for h in grid:
    c=a.copy(); c['humidity_pct']=h
    p=predict(M,c)
    rates.append((h,(p*c.units_produced).sum()/c.units_produced.sum()))
r=pd.DataFrame(rates,columns=['h','rate'])
print('C2 argmin humidity for Alpha:', r.loc[r.rate.idxmin()].round(5).to_dict(), 'grid range', grid.min(), grid.max())
print(r.iloc[::25].round(5).to_string(index=False))

# C3: extra cleaning every 14 days -> days since last cleaning becomes dsc mod 14
c=d.copy(); c['dsc']=c.dsc%14
p=predict(M,c)
print('C3 rate with 14-day cleaning', round((p*c.units_produced).sum()/c.units_produced.sum(),5))
EOF
timeout 290 python3 final.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > b1.py <<'EOF'
import numpy as np, pandas as pd, patsy
from scipy.stats import chi2
import spline_model as sm_
from spline_model import *
d=make_frame()
d['s1']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
S=['s1','s2','s3']
full=sm_.RHS
def lr(rhs_new, extra=[], label=''):
    sm_.RHS=rhs_new
    m=fit_model(d,S+extra)
    return m
M0=lr(full)
base_dev=M0['dev']; disp=M0['disp']
tests={
 'ambient': full.replace(" + cr(ambient_temp_c, df=4)",""),
 'shift': full.replace(" + C(shift)",""),
 'cycle': full.replace(" + cr(cycle_time_s, df=4)",""),
 'mold': full.replace(" + cr(mold_temp, df=5):C(line)",""),
 'humidity': full.replace(" + cr(humidity_pct, df=6):C(supplier_code)",""),
}
for k,rhs in tests.items():
    m=lr(rhs)
    dfd=len(M0['names'])-len(m['names'])
    stat=(m['dev']-base_dev)/disp
    print(f"drop {k:9s} LR={stat:9.2f} df={dfd} p={chi2.sf(stat,dfd):.3g}",flush=True)
sm_.RHS=full
# age and operator added
dd=d.copy()
for k,extra in [('age','cr(machine_age_years, df=3)'),('operator','C(operator_id)')]:
    dm=patsy.dmatrix(full+' + '+extra, dd, return_type='dataframe')
    y=(dd.defective_units/dd.units_produced).values; w=dd.units_produced.values.astype(float)
    from fast import irls
    _,_,dev,_=irls(dm.values,y,w)
    dfd=dm.shape[1]-M0['beta'].shape[0]
    stat=(base_dev-dev)/disp
    print(f"add  {k:9s} LR={stat:9.2f} df={dfd} p={chi2.sf(stat,dfd):.3g}",flush=True)
EOF
timeout 290 python3 b1.py

cd /tmp/claude-0/-tmp-edabench-claude-d5jor3y2/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > b1b.py <<'EOF'
import numpy as np, pandas as pd, patsy
from scipy.stats import chi2
import spline_model as sm_
from spline_model import *
from fast import irls
d=make_frame()
d['s1']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
S=['s1','s2','s3']
full=sm_.RHS
y=(d.defective_units/d.units_produced).values; w=d.units_produced.values.astype(float)
def dev_of(rhs):
    dm=patsy.dmatrix(rhs+''.join(' + '+s for s in S), d, return_type='dataframe')
    b,disp,dev,_=irls(dm.values,y,w)
    return dev,disp,dm.shape[1]
base_dev,disp,p0=dev_of(full)
print('full dev',round(base_dev,1),'disp',round(disp,2),'params',p0)
tests={
 'humidity':full.replace("cr(humidity_pct, df=6):C(supplier_code) + ",""),
 'ambient': full.replace(" + cr(ambient_temp_c, df=4)",""),
 'shift':   full.replace(" + C(shift)",""),
 'cycle':   full.replace(" + cr(cycle_time_s, df=4)",""),
 'mold':    full.replace(" + cr(mold_temp, df=5):C(line)",""),
 'dsc':     full.replace(" + cr(dsc, df=5)",""),
}
for k,rhs in tests.items():
    dev,_,p=dev_of(rhs); dfd=p0-p; stat=(dev-base_dev)/disp
    print(f"drop {k:9s} LR={stat:9.2f} df={dfd} p={chi2.sf(stat,dfd):.3g}",flush=True)
for k,extra in [('age',' + cr(machine_age_years, df=3)'),('operator',' + C(operator_id)')]:
    dev,_,p=dev_of(full+extra); dfd=p-p0; stat=(base_dev-dev)/disp
    print(f"add  {k:9s} LR={stat:9.2f} df={dfd} p={chi2.sf(stat,dfd):.3g}",flush=True)
EOF
timeout 290 python3 b1b.py
