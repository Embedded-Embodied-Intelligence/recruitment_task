ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc=b[c].value_counts()
    print('---',c,'nunique',b[c].nunique(),'empty',(b[c].str.strip()=='').sum())
    if b[c].nunique()<40: print(vc.to_dict())
    else: print(b[c].sample(12,random_state=1).tolist())
print('dup full rows',b.duplicated().sum(),'dup batch_id',b.batch_id.duplicated().sum())
print(open('suppliers.csv').read()); print(pd.read_csv('maintenance.csv',dtype=str).event.value_counts())
print(pd.read_csv('maintenance.csv',dtype=str).note.value_counts(dropna=False))
"

python3 -c "
import pandas as pd, re
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=b.drop_duplicates()
print('after exact dedupe',len(d),'unique ids',d.batch_id.nunique())
# conflicting duplicates?
g=d.groupby('batch_id').size(); print('ids with >1 distinct rows',(g>1).sum())
# date formats
pat=d.production_date.map(lambda s: 'ISO' if re.fullmatch(r'\d{4}-\d\d-\d\d',s) else ('NN/NN/YYYY' if re.fullmatch(r'\d\d/\d\d/\d{4}',s) else 'other:'+s))
print(pat.value_counts())
sl=d.production_date[d.production_date.str.match(r'^\d\d/')]
a=sl.str[:2].astype(int); c=sl.str[3:5].astype(int)
print('first>12',(a>12).sum(),'second>12',(c>12).sum(),'both<=12',((a<=12)&(c<=12)).sum())
for col in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(d[col],errors='coerce')
    print(col,'nonnum',(x.isna()&(d[col].str.strip()!='')).sum(),'min',x.min(),'max',x.max(),'describe',x.quantile([.01,.5,.99]).round(2).tolist())
print(d[pd.to_numeric(d.humidity_pct,errors='coerce').isna() & (d.humidity_pct!='')].humidity_pct.value_counts())
"

python3 -c "
import pandas as pd, re
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
b['fmt']=b.production_date.map(lambda s: 'ISO' if '-' in s else 'slash')
b['sl']=b.production_date.map(lambda s: 'x' if '-' in s else ('DM' if int(s[:2])>12 else ('MD' if int(s[3:5])>12 else 'amb')))
print(pd.crosstab(b.line,b.sl))
print(pd.crosstab(b.line,b.fmt))
b['idx']=b.index
print(pd.crosstab(pd.cut(b.idx,6),b.sl))
print('humidity -1',(b.humidity_pct=='-1.0').sum(),(b.humidity_pct=='-1').sum(),'blank',(b.humidity_pct=='').sum(), 'zero',(b.humidity_pct.isin(['0','0.0'])).sum())
print('mold zero',(b.mold_temp.isin(['0','0.0'])).sum())
m=pd.to_numeric(b.mold_temp); print(pd.cut(m,[-1,0.5,100,150,250,300,350,400,500]).value_counts().sort_index())
"

cat > $TMPDIR/load.py <<'EOF'
import pandas as pd, numpy as np
def parse_date(row):
    s=row.production_date
    if '-' in s: return pd.to_datetime(s,format='%Y-%m-%d')
    if row.line=='L1': return pd.to_datetime(s,format='%m/%d/%Y')
    if row.line=='L4': return pd.to_datetime(s,format='%d/%m/%Y')
    raise ValueError(s)
def load():
    b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
    b['date']=b.apply(parse_date,axis=1)
    b['shift']=b['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
    b['supplier_code']=b.supplier_code.str.strip().str.upper()
    for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
        b[c]=pd.to_numeric(b[c].replace('',np.nan))
    b['operator_id']=b.operator_id.str.strip().str.upper()
    return b
EOF
PYTHONPATH=$TMPDIR python3 -c "
from load import *
b=load()
print(b.date.min(),b.date.max(), b.date.isna().sum())
print(b['shift'].value_counts(dropna=False))
print(b.supplier_code.value_counts())
print(b.operator_id.nunique())
print(b.assign(hot=b.mold_temp>300).groupby('line').hot.agg(['sum','mean']))
hot=b[b.mold_temp>300]; print(hot.groupby('line').date.agg(['min','max','count']))
print(b[(b.mold_temp>0)&(b.mold_temp<300)].groupby('line').date.agg(['min','max']))
print(b[b.mold_temp<=0].groupby('line').size(), b[b.mold_temp<=0].date.agg(['min','max']))
print('humidity blank',b.humidity_pct.isna().sum(),'-1',(b.humidity_pct==-1).sum())
print(b[b.humidity_pct.isna()].line.value_counts(), b[b.humidity_pct==-1].line.value_counts())
"

grep -v mold_cleaning maintenance.csv; PYTHONPATH=$TMPDIR python3 -c "
from load import *
b=load()
v=b[b.mold_temp>0].copy()
v['mC']=np.where(v.line=='L3',(v.mold_temp-32)*5/9,v.mold_temp)
print(v.groupby('line').mC.describe().round(2))
print(v[v.line=='L3'].mold_temp.describe().round(1))
print('L3 F range',v[v.line=='L3'].mold_temp.min(),v[v.line=='L3'].mold_temp.max())
"

PYTHONPATH=$TMPDIR python3 -c "
from load import *
b=load()
print('A1 unique batches',b.batch_id.nunique())
print('A2 humidity invalid',(b.humidity_pct.isna()|(b.humidity_pct<0)).sum(), 'blank',b.humidity_pct.isna().sum(),'neg',(b.humidity_pct<0).sum())
print('A3 rate',b.defective_units.sum(),b.units_produced.sum(), b.defective_units.sum()/b.units_produced.sum())
mt=b.mold_temp.where(b.mold_temp>0)
mC=np.where(b.line=='L3',(mt-32)*5/9,mt)
print('A4 median C',np.nanmedian(mC), 'n',np.sum(~np.isnan(mC)))
b['rate']=b.defective_units/b.units_produced
print(b[['rate','qc_inspection_min','rework_cost_eur','defective_units','units_produced']].corr().round(3))
b['rw_per_def']=b.rework_cost_eur/b.defective_units
print(b.rw_per_def.describe().round(3))
print(np.corrcoef(b.rework_cost_eur/b.units_produced, b.rate)[0,1])
print(b.groupby(pd.qcut(b.rate,5)).qc_inspection_min.mean().round(2))
print(b[['units_produced','defective_units']].assign(bad=lambda d:d.defective_units>d.units_produced).bad.sum(), (b.units_produced<=0).sum())
"

python3 -c "import statsmodels, sklearn, scipy; print(statsmodels.__version__, sklearn.__version__)" 2>&1; PYTHONPATH=$TMPDIR python3 -c "
from load import *
b=load()
b['mold_C']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp).astype(float)
b.loc[b.mold_temp<=0,'mold_C']=np.nan
b.loc[b.humidity_pct<0,'humidity_pct']=np.nan
b['rate']=b.defective_units/b.units_produced
b.to_pickle('$TMPDIR/clean.pkl')
for c in ['mold_C','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']:
    print(c, b.groupby(pd.qcut(b[c],6,duplicates='drop')).apply(lambda d: d.defective_units.sum()/d.units_produced.sum()).round(4).tolist())
for c in ['operator_id','shift','supplier_code','line']:
    print(c, b.groupby(c).apply(lambda d: round(d.defective_units.sum()/d.units_produced.sum(),4)).to_dict())
"

python3 -c "
import statsmodels.formula.api as smf, statsmodels.api as sm, pandas as pd, numpy as np
b=pd.read_pickle('$TMPDIR/clean.pkl')
b['ok']=b.humidity_pct.notna()&b.mold_C.notna()
d=b[b.ok].copy()
d['fail']=d.units_produced-d.defective_units
f='defective_units + fail ~ mold_C + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)'
m=smf.glm('defective_units + fail ~ mold_C + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)',data=d,family=sm.families.Binomial()).fit()
print(m.summary2().tables[1].round(4).to_string())
print('dispersion', m.pearson_chi2/m.df_resid)
" 2>&1 | head -80

PYTHONPATH=$TMPDIR python3 -c "
import pandas as pd, numpy as np
b=pd.read_pickle('$TMPDIR/clean.pkl')
print(pd.crosstab(b.operator_id,b.line))
print(pd.crosstab(b.operator_id,b['shift']).T)
print(pd.crosstab(b.supplier_code,b.line))
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
print(m[m.event=='mold_cleaning'].groupby('line').date.agg(['count','min','max']))
print(m[m.event=='mold_cleaning'].groupby('line').date.apply(lambda s: s.sort_values().diff().dt.days.describe()[['min','max','mean']]))
" 2>&1 | head -120

cat > $TMPDIR/prep.py <<'EOF'
import pandas as pd, numpy as np
b=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.pkl')
m=pd.read_csv('/tmp/edabench_claude_qla960oa/maintenance.csv',parse_dates=['date'])
cl=m[m.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
b['days_since_clean']=b.apply(dsc,axis=1)
b['fail']=b.units_produced-b.defective_units
b['ok']=b.humidity_pct.notna()&b.mold_C.notna()
b['sup_name']=b.supplier_code.map({'SP-01':'Alpha','SP-02':'Beta','SP-03':'Gamma'})
b['t']=(b.date-pd.Timestamp('2025-01-06')).dt.days
EOF
PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm
print(b.days_since_clean.describe())
print(b.days_since_clean.isna().sum())
b.to_pickle('$TMPDIR/prep.pkl')
d=b[b.ok]
print(d.groupby(pd.cut(d.days_since_clean,[-1,3,7,10,14,20,30,60])).apply(lambda x: round(x.defective_units.sum()/x.units_produced.sum(),4)))
print(d.groupby(pd.cut(d.days_since_clean,[-1,3,7,10,14,20,30,60])).size())
l1=b[b.line=='L1']; l1=l1.assign(post=l1.date>=pd.Timestamp('2025-04-14'))
print(l1.groupby('post').mold_C.describe().round(2))
print(b.groupby(['line']).apply(lambda x: x[x.date>=pd.Timestamp('2025-04-14')].mold_C.mean()))
" 2>&1 | head -80

echo $TMPDIR && sed -i "s#/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.pkl#'+__import__('os').environ['TMPDIR']+'/clean.pkl#; s#b=pd.read_pickle('+#b=pd.read_pickle(''+#" $TMPDIR/prep.py && head -3 $TMPDIR/prep.py

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
print(b.days_since_clean.describe().round(2).to_dict())
print('nan days',b.days_since_clean.isna().sum())
b.to_pickle(__import__('os').environ['TMPDIR']+'/prep.pkl')
d=b[b.ok]
bins=[-1,3,7,10,14,20,30,60]
print(d.groupby(pd.cut(d.days_since_clean,bins)).apply(lambda x: pd.Series({'n':len(x),'rate':round(x.defective_units.sum()/x.units_produced.sum(),4)})))
l1=b[b.line=='L1']
print(l1.groupby(l1.date>=pd.Timestamp('2025-04-14')).mold_C.describe().round(2))
print(b.groupby(['line',b.date>=pd.Timestamp('2025-04-14')]).mold_C.mean().round(2))
"

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf
d=b[b.mold_C.notna()].copy()
d['post']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['month']=d.date.dt.month
print(d.groupby(['line','month']).mold_C.mean().unstack(0).round(1))
print(d.groupby(['line','month']).ambient_temp_c.mean().unstack(0).round(1))
r=smf.ols('mold_C ~ C(line) + ambient_temp_c + t + post',data=d).fit()
print(r.params.round(3).to_dict(), r.bse.round(3)['post'])
r2=smf.ols('mold_C ~ C(line) + ambient_temp_c + t',data=d[d.line!='L1']).fit()
print(r2.params.round(3).to_dict())
w=d[(d.line=='L1')&(abs((d.date-pd.Timestamp('2025-04-14')).dt.days)<=20)]
print(w.groupby(w.date).mold_C.mean().round(1).to_string())
" 2>&1 | head -120

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=b[b.ok].copy()
f0='defective_units + fail ~ mold_C + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + days_since_clean + C(operator_id)'
m=smf.glm(f0,data=d,family=sm.families.Binomial()).fit()
print('rank',np.linalg.matrix_rank(m.model.exog), m.model.exog.shape)
print(m.summary2().tables[1].round(4).to_string())
print('disp',round(m.pearson_chi2/m.df_resid,3))
d['mu']=m.predict(d)
d['res']=(d.defective_units-d.units_produced*d.mu)/np.sqrt(d.units_produced*d.mu*(1-d.mu))
d.to_pickle(__import__('os').environ['TMPDIR']+'/fit.pkl')
print(d.groupby('line').res.agg(['mean','std']).round(3))
print(d.groupby([d.line,d.date.dt.month]).res.mean().unstack(0).round(2))
" 2>&1 | head -120

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit.pkl')
base='mold_C + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + days_since_clean'
mL=smf.glm('defective_units + fail ~ '+base+' + C(line)',data=d,family=sm.families.Binomial()).fit()
mO=smf.glm('defective_units + fail ~ '+base+' + C(operator_id)',data=d,family=sm.families.Binomial()).fit()
mLO=smf.glm('defective_units + fail ~ '+base+' + C(line) + C(operator_id)',data=d,family=sm.families.Binomial()).fit()
print('rank LO',np.linalg.matrix_rank(mLO.model.exog))
print('dev line',mL.deviance,'dev op',mO.deviance,'df',mL.df_resid, mO.df_resid)
print('AIC line',mL.aic,'op',mO.aic)
print(mL.summary2().tables[1].round(4).to_string())
# operator within line: LR test of operator given line via drop-one-line approach
" 2>&1 | head -60

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
d=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit.pkl').sort_values('date')
out=[]
for ln,g in d.groupby('line'):
    g=g.sort_values('date').reset_index(drop=True)
    r=g.res.values; dt=g.date.values
    best=None
    for i in range(30,len(g)-30):
        a=r[:i]; c=r[i:]
        t=(c.mean()-a.mean())/np.sqrt(a.var(ddof=1)/len(a)+c.var(ddof=1)/len(c))
        if best is None or abs(t)>abs(best[1]): best=(i,t,pd.Timestamp(dt[i]).date(),round(c.mean()-a.mean(),3))
    print(ln,best)
    # also by date cumulative sums
    cs=pd.Series(r,index=g.date).resample('W').mean()
    print(cs.round(2).to_string()[:0])
    out.append(g.assign(line_=ln))
" 2>&1 | head -60

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
b=b.sort_values('date')
for ln,dt in [('L2','2025-06-15'),('L3','2025-07-21'),('L1','2025-04-14'),('L4','2025-08-09')]:
    g=b[b.line==ln].copy(); g['post']=g.date>=pd.Timestamp(dt)
    s=g.groupby('post').apply(lambda x: pd.Series({'n':len(x),'rate':round(x.defective_units.sum()/x.units_produced.sum(),4),'units_mean':round(x.units_produced.mean(),1),'mold_C':round(x.mold_C.mean(),2),'hum':round(x.humidity_pct.mean(),2),'amb':round(x.ambient_temp_c.mean(),2),'cyc':round(x.cycle_time_s.mean(),2),'night':round((x['shift']=='Night').mean(),3),'dsc':round(x.days_since_clean.mean(),2),'sup':x.supplier_code.value_counts().to_dict(),'ops':x.operator_id.nunique()}))
    print(ln,dt); print(s.to_string())
"

grep -E "2025-0[5-9]" maintenance.csv | sort -t, -k2,2 -k1,1 ; PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=b[b.ok].copy()
d['dsc_b']=pd.cut(d.days_since_clean,[-1,3,7,10,14,17,21,28,40]).astype(str)
f='defective_units + fail ~ mold_C + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(dsc_b) + C(line)'
m=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
print(m.summary2().tables[1].round(3).to_string()); print('disp',round(m.pearson_chi2/m.df_resid,2))
d['mu']=m.predict(d); d['res']=(d.defective_units-d.units_produced*d.mu)/np.sqrt(d.units_produced*d.mu*(1-d.mu))
d.to_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl')
print(d.groupby(['line',d.date.dt.to_period('M')]).res.mean().unstack(0).round(2))
"

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
d=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl')
w=d.groupby(['line',d.date.dt.to_period('W')]).agg(res=('res','mean'),n=('res','size'),rate=('defective_units','sum'))
w['rate']=d.groupby(['line',d.date.dt.to_period('W')]).apply(lambda x: x.defective_units.sum()/x.units_produced.sum())
print(w.res.unstack(0).round(1).to_string())
" 2>&1 | head -80

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl')
d['s1']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
base='mold_C + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(dsc_b) + C(line)'
for extra in ['','+s1','+s2','+s3','+s1+s2+s3']:
    m=smf.glm('defective_units + fail ~ '+base+extra,data=d,family=sm.families.Binomial()).fit()
    disp=m.pearson_chi2/m.df_resid
    print(extra or 'none', 'dev',round(m.deviance,1),'disp',round(disp,2), {k:(round(m.params[k],3),round(m.tvalues[k]/np.sqrt(disp),2)) for k in ['s1','s2','s3'] if k in m.params})
" 2>&1 | head -30

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
d=b.copy()
d['rw_per_def']=d.rework_cost_eur/d.defective_units
d['qc_per_def']=d.qc_inspection_min/d.defective_units
d['per_unit']=d.rework_cost_eur/d.units_produced
d['mon']=d.date.dt.to_period('M')
print(d.groupby(['line','mon']).rw_per_def.median().unstack(0).round(2).to_string())
print(d.groupby(['line','mon']).qc_inspection_min.mean().unstack(0).round(2).to_string())
" 2>&1 | head -60

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
d=b.copy().sort_values('date')
d['rw_per_def']=d.rework_cost_eur/d.defective_units
for ln in ['L1','L2','L3','L4']:
    g=d[d.line==ln]
    best=None
    x=g.rw_per_def.values; dt=g.date.values
    for i in range(30,len(g)-30):
        a=x[:i]; c=x[i:]
        s=(c.mean()-a.mean())/np.sqrt(a.var(ddof=1)/len(a)+c.var(ddof=1)/len(c))
        if best is None or abs(s)>abs(best[1]): best=(i,s,str(pd.Timestamp(dt[i]).date()),round(a.mean(),2),round(c.mean(),2))
    print(ln,best)
g=d[(d.line=='L3')&(d.date>=pd.Timestamp('2025-07-10'))&(d.date<=pd.Timestamp('2025-08-05'))]
print(g[['date','defective_units','units_produced','rework_cost_eur','rw_per_def','qc_inspection_min']].assign(rate=lambda x:x.defective_units/x.units_produced).round(3).to_string())
" 2>&1 | head -120

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl')
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
f='defective_units + fail ~ bs(mold_C,4) + bs(humidity_pct,4) + bs(ambient_temp_c,4) + cycle_time_s + machine_age_years + C(shift) + C(supplier_code) + C(dsc_b) + C(line)'
import patsy
m0=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
m1=smf.glm(f+'+s2+s3',data=d,family=sm.families.Binomial()).fit()
dis=m1.pearson_chi2/m1.df_resid
print('spline model dev',round(m0.deviance,1),'with steps',round(m1.deviance,1),'disp',round(dis,2))
print({k:(round(m1.params[k],3), round(m1.tvalues[k]/np.sqrt(dis),2)) for k in ['s2','s3']})
" 2>&1 | head -30

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl')
d['s2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['s3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
d['mB']=pd.cut(d.mold_C,[180,195,200,205,210,215,220,225,230,245]).astype(str)
d['hB']=pd.cut(d.humidity_pct,[0,10,15,20,25,30,35,40,45,50,55,60,65,75]).astype(str)
d['aB']=pd.cut(d.ambient_temp_c,[9,12,15,18,21,24,27,31]).astype(str)
d['cB']=pd.cut(d.cycle_time_s,[17,22,25,28,30,32,34,36,40,46]).astype(str)
d['mA']=pd.cut(d.machine_age_years,[0,2,4,6,8,10,12,15,18,22]).astype(str)
f='defective_units + fail ~ C(mB)+C(hB)+C(aB)+C(cB)+C(mA)+C(shift)+C(supplier_code)+C(dsc_b)+C(line)+s2+s3'
m=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
dis=m.pearson_chi2/m.df_resid
print('disp',round(dis,2),'dev',round(m.deviance,1))
p=m.params; t=m.tvalues/np.sqrt(dis)
out=pd.DataFrame({'coef':p.round(3),'z':t.round(1)})
print(out.to_string())
" 2>&1 | head -120

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, warnings
warnings.filterwarnings('ignore')
d=b.copy()
d['post3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(int)
d['post2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['rate']=d.defective_units/d.units_produced
for nm,g in d.groupby(['line',d.date>=pd.Timestamp('2025-07-21')]):
    pass
r=smf.ols('qc_inspection_min ~ defective_units + units_produced + C(line)',data=d[d.post3==0]).fit()
print('pre fit R2',round(r.rsquared,3)); print(r.params.round(4).to_dict())
d['qc_pred']=r.predict(d)
print(d.groupby(['line',d.date>=pd.Timestamp('2025-07-21')]).apply(lambda x: pd.Series({'qc':x.qc_inspection_min.mean(),'pred':x.qc_pred.mean()})).round(2))
rr=smf.ols('rework_cost_eur ~ defective_units + C(line)',data=d[d.post3==0]).fit()
print('rework pre',rr.params.round(3).to_dict())
" 2>&1 | head -40

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl')
d['post2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15')))
d['post3']=((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21')))
d['mB']=pd.cut(d.mold_C,[180,195,200,205,210,215,220,225,230,245]).astype(str)
d['hB']=pd.cut(d.humidity_pct,[0,10,15,20,25,30,35,40,45,50,55,60,65,75]).astype(str)
d['cB']=pd.cut(d.cycle_time_s,[17,22,25,28,30,32,34,36,40,46]).astype(str)
f='defective_units + fail ~ C(mB)+C(hB)+C(cB)+C(shift)+C(supplier_code)+C(dsc_b)+C(line)+ambient_temp_c'
tr=d[~(d.post2|d.post3)]
m=smf.glm(f,data=tr,family=sm.families.Binomial()).fit()
print('disp train',round(m.pearson_chi2/m.df_resid,2))
d['pred']=m.predict(d)
d['rw_def_implied']=d.rework_cost_eur/4.21
for nm,mask in [('L2 post',d.post2),('L3 post',d.post3),('L2 pre',(d.line=='L2')&~d.post2),('L3 pre',(d.line=='L3')&~d.post3)]:
    g=d[mask]
    print(nm,'n',len(g),'recorded rate',round(g.defective_units.sum()/g.units_produced.sum(),4),'pred',round((g.pred*g.units_produced).sum()/g.units_produced.sum(),4),'implied-by-rework rate',round(g.rw_def_implied.sum()/g.units_produced.sum(),4))
" 2>&1 | head -30

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d0=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl')
d0=d0.copy()
d0['s1']=((d0.line=='L1')&(d0.date>=pd.Timestamp('2025-04-14')))
d0['post2']=((d0.line=='L2')&(d0.date>=pd.Timestamp('2025-06-15')))
d0['post3']=((d0.line=='L3')&(d0.date>=pd.Timestamp('2025-07-21')))
d0=d0[~(d0.post2|d0.post3)]
res=[]
for delta in [0,2,4,5,6,7,8,9,10,12,14]:
    d=d0.copy(); d['mc']=d.mold_C-np.where(d.s1,delta,0)
    d['mB']=pd.cut(d.mc,[180,195,200,205,210,215,220,225,230,245]).astype(str)
    f='defective_units + fail ~ C(mB)+humidity_pct+cycle_time_s+C(shift)+C(supplier_code)+C(dsc_b)+C(line)+ambient_temp_c'
    m=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
    d['s1x']=d.s1.astype(int)
    m2=smf.glm(f+'+s1x',data=d,family=sm.families.Binomial()).fit()
    res.append((delta,round(m.deviance,1),round(m2.params['s1x'],3)))
print(res)
" 2>&1 | tail -5

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d0=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl').copy()
d0['s1']=((d0.line=='L1')&(d0.date>=pd.Timestamp('2025-04-14')))
d0['post2']=((d0.line=='L2')&(d0.date>=pd.Timestamp('2025-06-15')))
d0['post3']=((d0.line=='L3')&(d0.date>=pd.Timestamp('2025-07-21')))
d0=d0[~(d0.post2|d0.post3)]
rows=[]
for delta in np.arange(4,10.01,0.5):
    d=d0.copy(); d['mc']=d.mold_C-np.where(d.s1,delta,0)
    f='defective_units + fail ~ bs(mc,5)+bs(humidity_pct,5)+cycle_time_s+C(shift)+C(supplier_code)+C(dsc_b)+C(line)+ambient_temp_c'
    m=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
    rows.append((round(delta,1),round(m.deviance,2)))
print(rows)
" 2>&1 | tail -3

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d0=pd.read_pickle(__import__('os').environ['TMPDIR']+'/fit2.pkl').copy()
d0['s1']=((d0.line=='L1')&(d0.date>=pd.Timestamp('2025-04-14')))
d0['post2']=((d0.line=='L2')&(d0.date>=pd.Timestamp('2025-06-15')))
d0['post3']=((d0.line=='L3')&(d0.date>=pd.Timestamp('2025-07-21')))
d0=d0[~(d0.post2|d0.post3)]
rows=[]
for delta in np.arange(4,10.01,0.5):
    d=d0.copy(); d['mc']=d.mold_C-np.where(d.s1,delta,0)
    f='defective_units + fail ~ bs(mc,5)+bs(humidity_pct,5)+cycle_time_s+C(shift)+C(supplier_code)+C(dsc_b)+C(line)+ambient_temp_c'
    m=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
    rows.append((round(delta,1),round(m.deviance,2)))
print(rows)
" 2>&1 | tail -3

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, warnings
warnings.filterwarnings('ignore')
d=b[b.mold_C.notna()].copy()
d['post']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['dstr']=d.date.dt.strftime('%Y-%m-%d')
r=smf.ols('mold_C ~ C(line) + C(dstr) + post',data=d).fit()
print('same-day L1 post offset',round(r.params['post'],2),'se',round(r.bse['post'],2))
r2=smf.ols('mold_C ~ C(line) + C(dstr) + post',data=d[(d.date>=pd.Timestamp('2025-03-01'))&(d.date<=pd.Timestamp('2025-06-30'))]).fit()
print('window Mar-Jun',round(r2.params['post'],2),round(r2.bse['post'],2))
# median sensitivity
mc=b.mold_C.copy()
base=np.nanmedian(mc); print('median raw conv',round(base,3))
for off in [0,6,7,7.5,8]:
    x=mc.copy(); x[(b.line=='L1')&(b.date>=pd.Timestamp('2025-04-14'))]-=off
    print(off, round(np.nanmedian(x),3))
" 2>&1 | tail -12

PYTHONPATH=$TMPDIR python3 -c "
from prep import *
import statsmodels.formula.api as smf, warnings
warnings.filterwarnings('ignore')
b=b.copy()
d=b[b.mold_C.notna()].copy()
d['post']=((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(int)
d['dstr']=d.date.dt.strftime('%Y-%m-%d')
r=smf.ols('mold_C ~ C(line) + C(dstr) + post',data=d).fit()
print('same-day L1 post offset',round(r.params['post'],2),'se',round(r.bse['post'],2))
w=d[(d.date>=pd.Timestamp('2025-03-01'))&(d.date<=pd.Timestamp('2025-06-30'))]
r2=smf.ols('mold_C ~ C(line) + C(dstr) + post',data=w).fit()
print('window Mar-Jun',round(r2.params['post'],2),round(r2.bse['post'],2))
mc=b.mold_C.copy()
print('median raw conv',round(np.nanmedian(mc),3))
for off in [0,6,7,7.5,8]:
    x=mc.copy(); x[(b.line=='L1')&(b.date>=pd.Timestamp('2025-04-14'))]-=off
    print(off, round(np.nanmedian(x),3))
" 2>&1 | tail -12

cat $TMPDIR/prep.py; ls -la $TMPDIR | head -30

SCR=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; mkdir -p "$SCR" && ls -la "$SCR" && echo OK

SCR=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > $SCR/eda_prep.py <<'EOF'
import numpy as np
import pandas as pd

SRC = '/tmp/edabench_claude_qla960oa'
L1_SENSOR_DATE = pd.Timestamp('2025-04-14')
L2_STEP_DATE = pd.Timestamp('2025-06-15')
L3_QC_DATE = pd.Timestamp('2025-07-21')


def parse_date(row):
    s = row.production_date
    if '-' in s:
        return pd.to_datetime(s, format='%Y-%m-%d')
    if row.line == 'L1':
        return pd.to_datetime(s, format='%m/%d/%Y')
    if row.line == 'L4':
        return pd.to_datetime(s, format='%d/%m/%Y')
    raise ValueError(f'unexpected date format for line {row.line}: {s}')


def load_raw():
    raw = pd.read_csv(f'{SRC}/batches.csv', dtype=str, keep_default_na=False)
    raw = raw.drop_duplicates().reset_index(drop=True)
    return raw


def load():
    b = load_raw()
    b['date'] = b.apply(parse_date, axis=1)
    b['shift'] = b['shift'].str.strip().str.lower().map(
        {'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
    b['supplier_code'] = b.supplier_code.str.strip().str.upper()
    b['operator_id'] = b.operator_id.str.strip().str.upper()
    num = ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'humidity_pct',
           'cycle_time_s', 'units_produced', 'defective_units',
           'qc_inspection_min', 'rework_cost_eur']
    for c in num:
        b[c] = pd.to_numeric(b[c].replace('', np.nan))
    # sentinels: humidity -1 = missing, mold_temp 0 = missing
    b.loc[b.humidity_pct < 0, 'humidity_pct'] = np.nan
    b.loc[b.mold_temp <= 0, 'mold_temp'] = np.nan
    # L3 mold sensor reports Fahrenheit
    b['mold_C'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
    b['mold_C'] = b.mold_C.astype(float)
    b['fail'] = b.units_produced - b.defective_units
    b['rate'] = b.defective_units / b.units_produced
    b['ok'] = b.humidity_pct.notna() & b.mold_C.notna()
    b['sup_name'] = b.supplier_code.map({'SP-01': 'Alpha', 'SP-02': 'Beta', 'SP-03': 'Gamma'})
    m = pd.read_csv(f'{SRC}/maintenance.csv', parse_dates=['date'])
    cl = m[m.event == 'mold_cleaning']

    def dsc(r):
        c = cl[(cl.line == r.line) & (cl.date <= r.date)].date
        return (r.date - c.max()).days if len(c) else np.nan
    b['days_since_clean'] = b.apply(dsc, axis=1)
    b['dsc_b'] = pd.cut(b.days_since_clean, [-1, 3, 7, 10, 14, 17, 21, 28, 40]).astype(str)
    b['t'] = (b.date - pd.Timestamp('2025-01-06')).dt.days
    return b
EOF
cd /tmp/edabench_claude_qla960oa && PYTHONPATH=$SCR python3 -c "
from eda_prep import *
b=load()
print(len(b), b.batch_id.nunique(), b.ok.sum(), b.days_since_clean.isna().sum())
print(round(b.defective_units.sum()/b.units_produced.sum(),6), round(np.nanmedian(b.mold_C),3))
print(b.shift.value_counts().to_dict(), b.sc if 'sc' in b else b.supplier_code.value_counts().to_dict())
"

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_prep import *
import statsmodels.formula.api as smf, warnings
warnings.filterwarnings('ignore')
b=load()
d=b[b.mold_C.notna()].copy()
d['post']=((d.line=='L1')&(d.date>=L1_SENSOR_DATE)).astype(int)
d['dstr']=d.date.dt.strftime('%Y-%m-%d')
r=smf.ols('mold_C ~ C(line) + C(dstr) + post',data=d).fit()
print('same-day L1 post offset',round(r.params['post'],2),'se',round(r.bse['post'],2))
w=d[(d.date>=pd.Timestamp('2025-03-01'))&(d.date<=pd.Timestamp('2025-07-31'))]
r2=smf.ols('mold_C ~ C(line) + C(dstr) + post',data=w).fit()
print('window Mar-Jul',round(r2.params['post'],2),round(r2.bse['post'],2))
print('line-by-line same-day L1 vs others (no L3 conversion issue):')
nl=d[d.line!='L3']
r3=smf.ols('mold_C ~ C(line) + C(dstr) + post',data=nl).fit()
print('excl L3',round(r3.params['post'],2),round(r3.bse['post'],2))
" 2>&1 | tail -6

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_prep import *
b=load()
post=(b.line=='L1')&(b.date>=L1_SENSOR_DATE)
for off in [0,6,6.5,7,7.5,8]:
    x=b.mold_C-np.where(post,off,0)
    print(off, round(np.nanmedian(x),3), 'n', int(x.notna().sum()))
" 2>&1 | tail -8

SCR=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > $SCR/eda_model.py <<'EOF'
import warnings
import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
from eda_prep import load, L1_SENSOR_DATE, L2_STEP_DATE, L3_QC_DATE

warnings.filterwarnings('ignore')
L1_OFFSET = 7.0


def build():
    b = load()
    b['mold_adj'] = b.mold_C - np.where((b.line == 'L1') & (b.date >= L1_SENSOR_DATE), L1_OFFSET, 0)
    b['s1'] = ((b.line == 'L1') & (b.date >= L1_SENSOR_DATE)).astype(int)
    b['s2'] = ((b.line == 'L2') & (b.date >= L2_STEP_DATE)).astype(int)
    b['s3'] = ((b.line == 'L3') & (b.date >= L3_QC_DATE)).astype(int)
    return b


def fit(formula, data):
    m = smf.glm(formula, data=data, family=sm.families.Binomial()).fit()
    return m


def quasi_F(m_small, m_big, data_n):
    dis = m_big.pearson_chi2 / m_big.df_resid
    ddf = m_small.df_resid - m_big.df_resid
    F = (m_small.deviance - m_big.deviance) / ddf / dis
    from scipy import stats
    p = stats.f.sf(F, ddf, m_big.df_resid)
    return round(F, 2), int(ddf), float(p)
EOF
cd /tmp/edabench_claude_qla960oa && PYTHONPATH=$SCR python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy()
d['fail']=d.units_produced-d.defective_units
core='bs(mold_adj,5)+bs(humidity_pct,5)+bs(cycle_time_s,4)+C(shift)+C(supplier_code)+C(dsc_b)+s2+s3'
full=fit('defective_units + fail ~ '+core+'+bs(ambient_temp_c,4)+bs(machine_age_years,4)+C(operator_id)+C(line)',d)
print('full rank ok', full.df_resid, 'disp', round(full.pearson_chi2/full.df_resid,2))
tests={
 'ambient': core+'+bs(machine_age_years,4)+C(operator_id)+C(line)',
 'machine_age': core+'+bs(ambient_temp_c,4)+C(operator_id)+C(line)',
 'operator (given line)': core+'+bs(ambient_temp_c,4)+bs(machine_age_years,4)+C(line)',
 'shift': None,
}
" 2>&1 | tail -4

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
Y='defective_units + fail ~ '
core='bs(mold_adj,5)+bs(humidity_pct,5)+bs(cycle_time_s,4)+C(supplier_code)+C(dsc_b)+s2+s3'
big_terms={'mold':'bs(mold_adj,5)','humidity':'bs(humidity_pct,5)','cycle':'bs(cycle_time_s,4)','ambient':'bs(ambient_temp_c,4)','machine_age':'bs(machine_age_years,4)','shift':'C(shift)'}
allmain=' + '.join(big_terms.values())
full_f=Y+allmain+'+C(supplier_code)+C(dsc_b)+s2+s3+C(line)'
F=fit(full_f,d)
print('full disp',round(F.pearson_chi2/F.df_resid,2))
for nm,term in big_terms.items():
    small=Y+' + '.join(v for k,v in big_terms.items() if k!=nm)+'+C(supplier_code)+C(dsc_b)+s2+s3+C(line)'
    S=fit(small,d)
    print(nm, 'F,df,p', quasi_F(S,F,len(d)))
S=fit(Y+allmain+'+C(supplier_code)+C(dsc_b)+s2+s3',d)
Op=fit(Y+allmain+'+C(supplier_code)+C(dsc_b)+s2+s3+C(operator_id)',d)
print('operator vs line-only (both with continuous terms): F,df,p', quasi_F(F,Op,len(d)))
print('operator vs no-operator (incl line):', quasi_F(S,Op,len(d)))
" 2>&1 | tail -12

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]  # train on rows without the L3 post-07-21 recording change
Y='defective_units + fail ~ '
core='bs(mold_adj,5)+bs(humidity_pct,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+s2+C(line)+C(supplier_code)'
A=fit(Y+core,d)
print('disp',round(A.pearson_chi2/A.df_resid,2))
B=fit(Y+core+'+bs(humidity_pct,5):C(supplier_code)',d)
print('supplier x humidity F,df,p', quasi_F(A,B,len(d)))
C=fit(Y+core+'+bs(mold_adj,5):C(supplier_code)',d)
print('supplier x mold', quasi_F(A,C,len(d)))
D=fit(Y+core+'+bs(cycle_time_s,4):C(supplier_code)',d)
print('supplier x cycle', quasi_F(A,D,len(d)))
Hm=d[d.supplier_code=='SP-01']
Ha=fit(Y+'bs(humidity_pct,5)+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2',Hm)
print('humidity range valid', d.humidity_pct.min(), d.humidity_pct.max())
g=np.arange(np.ceil(d.humidity_pct.min()),np.floor(d.humidity_pct.max())+0.01,0.5)
" 2>&1 | tail -8

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]
Y='defective_units + fail ~ '
al=d[d.supplier_code=='SP-01'].copy()
print('Alpha n',len(al))
for form in ['bs(humidity_pct,5)','bs(humidity_pct,7)','humidity_pct+I(humidity_pct**2)']:
    m=fit(Y+form+'+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2',al)
    grid=pd.DataFrame({'humidity_pct':np.arange(12.1,72.31,0.05)})
    base=al.iloc[[0]].copy()
    # reference row: median mold/cycle/shift/dsc/line
    ref=pd.DataFrame({'humidity_pct':grid.humidity_pct,'mold_adj':al.mold_adj.median(),'cycle_time_s':al.cycle_time_s.median(),'shift':'Day','dsc_b':al.dsc_b.mode()[0],'line':'L1','s2':0,'ambient_temp_c':al.ambient_temp_c.median(),'machine_age_years':al.machine_age_years.median(),'supplier_code':'SP-01'})
    p=m.predict(ref)
    i=np.argmin(p.values)
    print(form,'argmin humidity',round(grid.humidity_pct.iloc[i],2),'rate at min',round(p.values[i],5))
" 2>&1 | tail -6

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]
Y='defective_units + fail ~ '
al=d[d.supplier_code=='SP-01'].copy()
print('Alpha humidity range',al.humidity_pct.min(),al.humidity_pct.max(),'overall',d.humidity_pct.min(),d.humidity_pct.max())
ctrl='+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2'
res={}
for form in ['bs(humidity_pct,5)','bs(humidity_pct,7)','humidity_pct+I(humidity_pct**2)']:
    m=fit(Y+form+ctrl,al)
    lo,hi=al.humidity_pct.min(),al.humidity_pct.max()
    grid=np.round(np.arange(lo,hi+1e-9,0.1),2)
    ref=al.iloc[:len(grid)].copy().reset_index(drop=True)
    ref=ref.assign(humidity_pct=grid)
    ref['mold_adj']=al.mold_adj.median(); ref['cycle_time_s']=al.cycle_time_s.median(); ref['shift']='Day'
    ref['dsc_b']=al.dsc_b.mode()[0]; ref['line']='L1'; ref['s2']=0
    p=m.predict(ref)
    i=int(np.argmin(p.values))
    print(form,'argmin',round(grid[i],2),'rate',round(p.values[i],5),'curve ends',round(p.values[0],4),round(p.values[-1],4))
" 2>&1 | tail -8

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]
Y='defective_units + fail ~ '
al=d[d.supplier_code=='SP-01'].copy()
ctrl='+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2'
for form in ['bs(humidity_pct,5)','bs(humidity_pct,7)','bs(humidity_pct,9)','humidity_pct+I(humidity_pct**2)','humidity_pct+I(humidity_pct**2)+I(humidity_pct**3)']:
    m=fit(Y+form+ctrl,al)
    print(form, 'AIC', round(m.aic,1))
al['hB']=pd.cut(al.humidity_pct,np.arange(10,76,5)).astype(str)
m=fit(Y+'C(hB)'+ctrl.replace('C(dsc_b)','C(dsc_b)'),al.assign(hB=al.hB))
cc={k:v for k,v in m.params.items() if k.startswith('C(hB)')}
print(sorted(cc.items(), key=lambda x: x[1])[:4])
mq=fit(Y+'humidity_pct+I(humidity_pct**2)'+ctrl,al)
b1=mq.params['humidity_pct']; b2=mq.params['I(humidity_pct ** 2)']
print('quadratic argmin',-b1/(2*b2), 'b2',b2, 'se', mq.bse['I(humidity_pct ** 2)'])
" 2>&1 | tail -12

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]
Y='defective_units + fail ~ '
al=d[d.supplier_code=='SP-01'].copy()
ctrl='+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2'
m=fit(Y+'bs(humidity_pct,9)'+ctrl,al)
grid=np.round(np.arange(al.humidity_pct.min(),al.humidity_pct.max(),0.05),2)
ref=pd.DataFrame({'humidity_pct':grid,'mold_adj':al.mold_adj.median(),'cycle_time_s':al.cycle_time_s.median(),'shift':'Day','dsc_b':al.dsc_b.mode()[0],'line':'L1','s2':0})
p=m.predict(ref).values
print('bs9 argmin',grid[np.argmin(p)],'min',round(p.min(),5), 'value at 30',round(p[np.argmin(abs(grid-30))],5))
# binned on 2.5-pt bins
al['hB2']=pd.cut(al.humidity_pct,np.arange(10,76,2.5))
bins=al.hB2.cat.categories
tab=al.groupby('hB2',observed=True).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()}))
print(tab[tab.n>=20].round(4).to_string())
" 2>&1 | tail -40

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]
Y='defective_units + fail ~ '
al=d[d.supplier_code=='SP-01'].copy()
ctrl='+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2'
grid=np.round(np.arange(al.humidity_pct.min(),al.humidity_pct.max(),0.05),2)
ref=pd.DataFrame({'humidity_pct':grid,'mold_adj':al.mold_adj.median(),'cycle_time_s':al.cycle_time_s.median(),'shift':'Day','dsc_b':al.dsc_b.mode()[0],'line':'L1','s2':0})
for k in range(4,13):
    m=fit(Y+f'bs(humidity_pct,{k})'+ctrl,al)
    p=m.predict(ref).values
    print(k,'AIC',round(m.aic,1),'argmin',grid[np.argmin(p)],'min',round(p.min(),5))
" 2>&1 | tail -10

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]
Y='defective_units + fail ~ '
al=d[d.supplier_code=='SP-01'].copy()
ctrl='+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2'
rows=[]
for h0 in np.arange(15,50.5,1.0):
    al['lo']=np.maximum(0,h0-al.humidity_pct); al['hi']=np.maximum(0,al.humidity_pct-h0)
    m=fit(Y+'lo+hi'+ctrl,al)
    rows.append((h0,round(m.aic,1),round(m.params['lo'],4),round(m.params['hi'],4)))
rows=sorted(rows,key=lambda r:r[1])
print(rows[:6])
best=rows[0][0]
al['lo']=np.maximum(0,best-al.humidity_pct); al['hi']=np.maximum(0,al.humidity_pct-best)
m=fit(Y+'lo+hi'+ctrl,al)
print('lo slope',round(m.params['lo'],4),'hi slope',round(m.params['hi'],4), 'z',round(m.tvalues['lo'],1),round(m.tvalues['hi'],1))
" 2>&1 | tail -4

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_model import *
d=build(); d=d[d.ok].copy(); d['fail']=d.units_produced-d.defective_units
d=d[d.s3==0]
Y='defective_units + fail ~ '
al=d[d.supplier_code=='SP-01'].copy()
al['hb']=pd.cut(al.humidity_pct,[12,17.5,22.5,27.5,32.5,37.5,42.5,47.5,52.5,57.5,62.5,72.5],include_lowest=True).astype(str)
ctrl='+bs(mold_adj,5)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2'
m=fit(Y+'C(hb, Treatment(reference=\"(32.5, 37.5]\"))'+ctrl,al)
out=[(k.split('[T.')[1][:-1],round(m.params[k],3),round(m.bse[k],3)) for k in m.params.index if k.startswith('C(hb')]
for o in sorted(out,key=lambda x: float(x[0].split(',')[0].strip('( ['))): print(o)
" 2>&1 | tail -14

SCR=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cat > $SCR/eda_cf.py <<'EOF'
from eda_model import *
RECIPE = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}
MAINT = pd.read_csv('/tmp/edabench_claude_qla960oa/maintenance.csv', parse_dates=['date'])
CLEAN = MAINT[MAINT.event == 'mold_cleaning']


def prepare():
    b = build()
    b['fail'] = b.units_produced - b.defective_units
    # impute missing covariates only for the expected-value sums (cannot model rows without them)
    b['hum_imp'] = b.humidity_pct.fillna(b.groupby(['line', 'supplier_code']).humidity_pct.transform('median'))
    b['mold_imp'] = b.mold_adj.fillna(b.groupby(['line', b.date.dt.month]).mold_adj.transform('median'))
    return b


def fit_model(b):
    tr = b[b.ok & (b.s3 == 0)].copy()
    f = ('defective_units + fail ~ bs(mold_adj,5)+bs(humidity_pct,5)*C(supplier_code)'
         '+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)+s2')
    return fit(f, tr)


def expected(m, data):
    x = data.copy()
    x['humidity_pct'] = x.hum_imp
    x['mold_adj'] = x.mold_imp
    p = m.predict(x)
    return p.values


def cleaning_dsc_14():
    """Return days since last cleaning if every line is also cleaned whenever 14 days have passed."""
    out = {}
    for ln, g in CLEAN.groupby('line'):
        actual = set(g.date)
        last = max(d for d in actual if d < pd.Timestamp('2025-01-06'))
        for day in pd.date_range('2025-01-06', '2025-09-30'):
            if day in actual:
                last = day
            elif (day - last).days >= 14:
                last = day
            out[(ln, day)] = (day - last).days
    return out
EOF
cd /tmp/edabench_claude_qla960oa && PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_cf import *
b=prepare()
m=fit_model(b)
print('disp',round(m.pearson_chi2/m.df_resid,2), 'n train', int(m.nobs))
print(m.params[[k for k in m.params.index if k in ('s2','C(line)[T.L2]','C(shift)[T.Night]')]].round(3).to_dict())
print('L2 s2 coef',round(m.params['s2'],3),'z',round(m.tvalues['s2'],1))
b['exp']=b.units_produced*expected(m,b)
print('model expected overall rate (all 3000)', round(b.exp.sum()/b.units_produced.sum(),5))
print('observed overall', round(b.defective_units.sum()/b.units_produced.sum(),5))
" 2>&1 | tail -8

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_cf import *
b=prepare()
tr0=b[b.ok & (b.s3==0)].copy()
tr0['fail']=tr0.units_produced-tr0.defective_units
base='defective_units + fail ~ bs(mold_adj,5)+bs(humidity_pct,5)*C(supplier_code)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+C(line)'
m0=fit(base,tr0.assign(s2=0))
res=[]
for dt in pd.date_range('2025-05-20','2025-07-10'):
    tr=tr0.copy()
    tr['sx']=((tr.line=='L2')&(tr.date>=dt)).astype(int)
    m=fit(base+'+sx',tr)
    res.append((dt.date(),round(m.deviance,2)))
res=sorted(res,key=lambda r:r[1])
print('best L2 step dates by deviance', res[:5])
print('no-step deviance', round(m0.deviance,2))
" 2>&1 | tail -3

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_cf import *
b=prepare()
m=fit_model(b)
U=b.units_produced.sum()
print('C1 counterfactual overall defect rate by supplier (all 3000 batches):')
for s,nm in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    x=b.copy(); x['supplier_code']=s; x['cycle_time_s']=RECIPE[s]
    p=expected(m,x)
    print(nm, round((x.units_produced*p).sum()/U,5))
# C3
dsc=cleaning_dsc_14()
x=b.copy()
x['days_since_clean']=[dsc[(r.line,r.date)] for r in b.itertuples()]
x['dsc_b']=pd.cut(x.days_since_clean,[-1,3,7,10,14,17,21,28,40]).astype(str)
print('C3 dsc max',x.days_since_clean.max(), 'mean',round(x.days_since_clean.mean(),2),'vs actual',round(b.days_since_clean.mean(),2))
p0=expected(m,b); p1=expected(m,x)
print('C3 baseline expected',round((b.units_produced*p0).sum()/U,5),'with 14-day cleaning',round((b.units_produced*p1).sum()/U,5))
print('C3 counterfactual observed-scale check (ratio method)', round((b.defective_units*p1/p0).sum()/U,5))
" 2>&1 | tail -10

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_cf import *
b=prepare()
d=b[b.ok & (b.s3==0)].copy()
Y='defective_units + fail ~ '
terms={'mold':'bs(mold_adj,5)','humidity':'bs(humidity_pct,5)*C(supplier_code)','cycle':'bs(cycle_time_s,4)','ambient':'bs(ambient_temp_c,4)','machine_age':'bs(machine_age_years,4)','shift':'C(shift)'}
rest='+C(dsc_b)+s2+C(line)'
F=fit(Y+' + '.join(terms.values())+rest,d)
print('full disp',round(F.pearson_chi2/F.df_resid,2))
for k in ['mold','humidity','cycle','ambient','machine_age','shift']:
    S=fit(Y+' + '.join(v for kk,v in terms.items() if kk!=k)+rest,d)
    print(k, quasi_F(S,F,len(d)))
Sop=fit(Y+' + '.join(terms.values())+'+C(dsc_b)+s2+C(operator_id)',d)
print('operator within line', quasi_F(F,Sop,len(d)))
" 2>&1 | tail -9

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_cf import *
b=prepare()
d=b[b.ok & (b.s3==0)].copy()
d['fail']=d.units_produced-d.defective_units
Y='defective_units + fail ~ '
terms='bs(mold_adj,5)+bs(humidity_pct,5)*C(supplier_code)+bs(cycle_time_s,4)+C(shift)+C(dsc_b)+s2'
Sop=fit(Y+terms+'+C(operator_id)',d)
p=Sop.params; se=Sop.bse
ops=[k for k in p.index if 'operator' in k]
rows=[]
for k in ops:
    op=k.split('[T.')[1][:-1]
    rows.append((op,round(p[k],3),round(se[k],3)))
print(sorted(rows))
print('ref OP-01 is baseline')
# within-line spread in rates
r=d.groupby(['line','operator_id']).apply(lambda x: round(x.defective_units.sum()/x.units_produced.sum(),4))
print(r.to_string())
" 2>&1 | tail -40

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_cf import *
b=prepare()
raw=load_raw()
print('A1',b.batch_id.nunique(),'A2',int((b.humidity_pct.isna()).sum()),'A3',round(b.defective_units.sum()/b.units_produced.sum(),6))
print('A4 median adj',round(np.nanmedian(b.mold_adj.where(b.mold_C.notna())),3), 'n',int(b.mold_C.notna().sum()))
m=fit_model(b); U=b.units_produced.sum()
dsc=cleaning_dsc_14()
x=b.copy(); x['days_since_clean']=[dsc[(r.line,r.date)] for r in b.itertuples()]
x['dsc_b']=pd.cut(x.days_since_clean,[-1,3,7,10,14,17,21,28,40]).astype(str)
print('C3',round((b.units_produced*expected(m,x)).sum()/U,6))
x2=b.copy(); x2['supplier_code']='SP-03'; x2['cycle_time_s']=36
print('C1 gamma',round((x2.units_produced*expected(m,x2)).sum()/U,6))
" 2>&1 | tail -6

PYTHONPATH=/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad python3 -c "
from eda_cf import *
b=prepare()
print('A1',b.batch_id.nunique(),'A2',int((b.humidity_pct.isna()).sum()),'A3',round(b.defective_units.sum()/b.units_produced.sum(),6))
print('A4 median adj',round(np.nanmedian(b.mold_adj.where(b.mold_C.notna())),3), 'n',int(b.mold_C.notna().sum()))
m=fit_model(b); U=b.units_produced.sum()
dsc=cleaning_dsc_14()
x=b.copy(); x['days_since_clean']=[dsc[(r.line,r.date)] for r in b.itertuples()]
x['dsc_b']=pd.cut(x.days_since_clean,[-1,3,7,10,14,17,21,28,40]).astype(str)
print('C3',round((b.units_produced*expected(m,x)).sum()/U,6))
x2=b.copy(); x2['supplier_code']='SP-03'; x2['cycle_time_s']=36
print('C1 gamma',round((x2.units_produced*expected(m,x2)).sum()/U,6))
" 2>&1 | tail -6
