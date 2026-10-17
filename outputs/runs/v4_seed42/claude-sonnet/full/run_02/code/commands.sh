cd /tmp/edabench_claude_ikbnu98f; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_ikbnu98f; cat suppliers.csv; cat maintenance.csv | cut -d, -f2,3,4 | sort | uniq -c | sort -rn | head -20; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.batch_id.nunique(),d.duplicated().sum())
for c in ['production_date','line','shift','operator_id','supplier_code']:print(d[c].value_counts(dropna=False).head(25))
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
  x=pd.to_numeric(d[c],errors='coerce');print(c,x.isna().sum(),x.describe().to_dict());print(d[c][x.isna()].value_counts(dropna=False).head())
"

cd /tmp/edabench_claude_ikbnu98f; cat maintenance.csv | grep -v mold_cl; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
dd=d[d.batch_id.duplicated(keep=False)].sort_values('batch_id');print(len(dd),dd.drop_duplicates().shape);print(dd.head(6).T)
d=d.drop_duplicates('batch_id')
print(d.production_date.str.len().value_counts())
print(d[d.production_date.str.contains('/')].production_date.str[:2].astype(int).max(), d[d.production_date.str.contains('/')].production_date.str[3:5].astype(int).max())
m=pd.to_numeric(d.mold_temp)
print(pd.cut(m,[-1,1,100,150,190,250,300,350,400,500]).value_counts().sort_index())
h=pd.to_numeric(d.humidity_pct);print((h<=0).sum(),h.isna().sum(),h[h<=0].value_counts())
print(d.groupby('line').mold_temp.apply(lambda s:pd.to_numeric(s).describe()))
"

cd /tmp/edabench_claude_ikbnu98f; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates('batch_id').reset_index(drop=True)
s=d[d.production_date.str.contains('/')]
print(len(s));print(s.production_date.str[:2].astype(int).gt(12).sum(), s.production_date.str[3:5].astype(int).gt(12).sum())
print(d.iloc[::150][['production_date','line']].T.to_string())
print(d.production_date.str[:4].value_counts().head(3))
"

cd /tmp/edabench_claude_ikbnu98f; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates('batch_id').reset_index(drop=True)
s=d.production_date
sl=s.str.contains('/')
a=s.str[:2].astype(int,errors='ignore') if False else None
def f(x):
    if '/' not in x: return 'iso'
    p,q=int(x[:2]),int(x[3:5])
    return 'DM' if p>12 else 'MD' if q>12 else 'amb'
d['f']=s.map(f)
print(pd.crosstab(d.line,d.f)); print(pd.crosstab(d.supplier_code.str.strip().str.upper(),d.f))
iso=pd.to_datetime(s.where(~sl),errors='coerce')
print(iso.is_monotonic_increasing, iso.dropna().is_monotonic_increasing)
# row index vs month for unambiguous
"

cd /tmp/edabench_claude_ikbnu98f; mkdir -p $TMPDIR; cat > $TMPDIR/prep.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('/tmp/edabench_claude_ikbnu98f/batches.csv',dtype=str).drop_duplicates('batch_id').reset_index(drop=True)
def pdte(r):
    x=r.production_date
    if '/' not in x: return pd.Timestamp(x)
    return pd.to_datetime(x,format='%d/%m/%Y' if r.line=='L4' else '%m/%d/%Y')
d['date']=d.apply(pdte,axis=1)
d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
d['sc']=d.supplier_code.str.strip().str.upper()
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']: d[c]=pd.to_numeric(d[c])
d['hum']=d.humidity_pct.where(d.humidity_pct>0)
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.loc[d.line=='L3','mt']-32)/1.8
d['rate']=d.defective_units/d.units_produced
s=pd.read_csv('/tmp/edabench_claude_ikbnu98f/suppliers.csv');d=d.merge(s,left_on='sc',right_on='supplier_code',suffixes=('','_s'))
E
cat > $TMPDIR/a.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/prep.py').read())
print(len(d),d.hum.isna().sum(),d.defective_units.sum()/d.units_produced.sum(),d.mt.median(),d.date.min(),d.date.max())
print(d.groupby('line').mt.describe())
l1=d[d.line=='L1'].set_index('date').mt.resample('M').agg(['mean','std','count']);print(l1)
print(d[(d.mt<190)&(d.mt>0)][['line','date','mt','mold_temp']])
E
python3 $TMPDIR/a.py

cd /tmp/edabench_claude_ikbnu98f; sed -i "s/'M'/'ME'/" $TMPDIR/a.py; python3 $TMPDIR/a.py | tail -25

cd /tmp/edabench_claude_ikbnu98f; cat > $TMPDIR/b.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/prep.py').read())
l=d[d.line=='L1'].set_index('date').sort_index()
print(l.mt.resample('W').mean()['2025-02-20':'2025-05-20'])
print(l.rate.resample('W').mean()['2025-02-20':'2025-05-20'])
for ln in ['L1','L2','L3','L4']:
    x=d[d.line==ln].set_index('date').sort_index()
    print(ln,x.rate.resample('MS').mean().round(4).tolist())
E
python3 $TMPDIR/b.py

cd /tmp/edabench_claude_ikbnu98f; cat > $TMPDIR/c.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/prep.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
print(pd.crosstab(d.line,d.supplier_name,normalize='index').round(2))
print(d.groupby('supplier_name').rate.mean())
print(d.groupby('supplier_name')[['cycle_time_s','hum','mt']].mean())
print(d.groupby('line')[['cycle_time_s','hum','mt','machine_age_years','ambient_temp_c']].mean())
print(d[['rate','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur']].corr().round(2))
d['ok']=d.units_produced-d.defective_units
m=d.dropna(subset=['hum','mt']).copy()
m['dt']=m.cycle_time_s-m.recipe_cycle_time_s
f='ok+defective_units ~ mt+I(mt**2)+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+shift+C(line)+C(supplier_name)'
r=smf.glm(f,m,family=sm.families.Binomial()).fit()
print(r.summary().tables[1])
E
python3 $TMPDIR/c.py

cd /tmp/edabench_claude_ikbnu98f; cat > $TMPDIR/d.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/prep.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['ok']=d.units_produced-d.defective_units
d['dt']=d.cycle_time_s-d.recipe_cycle_time_s
print(d.groupby('line').machine_age_years.describe())
m=d.dropna(subset=['hum','mt']).copy()
m['hum2']=m.hum**2;m['mt2']=m.mt**2;m['dt2']=m.dt**2
def fit(f,x=m):
    return smf.glm(f,x,family=sm.families.Binomial()).fit(scale='X2')
for s in ['Alpha','Beta','Gamma']:
    x=m[m.supplier_name==s]
    r=fit('defective_units+ok ~ hum+hum2+mt+mt2+dt+dt2+machine_age_years+ambient_temp_c+shift+C(operator_id)',x)
    print(s);print(r.summary().tables[1].as_text().split('\n')[0:0]);print(r.params[~r.params.index.str.contains('operator')].round(4).to_dict());print(r.pvalues[~r.pvalues.index.str.contains('operator')].round(4).to_dict())
E
python3 $TMPDIR/d.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_ikbnu98f; cat > $TMPDIR/e.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/prep.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['ok']=d.units_produced-d.defective_units
d['dt']=d.cycle_time_s-d.recipe_cycle_time_s
print(pd.crosstab(d.operator_id,d['shift']).head(30).T.to_string())
m=d.dropna(subset=['hum','mt']).copy()
def bins(c,q): m[c+'_b']=pd.qcut(m[c],q).astype(str)
for c,q in [('hum',10),('mt',8),('dt',8),('ambient_temp_c',6),('machine_age_years',6)]: bins(c,q)
for c in ['hum','mt','dt','ambient_temp_c']:
    r=smf.glm(f'defective_units+ok ~ C({c}_b)+C(line)+C(supplier_name)+shift+C(operator_id)'+''.join(f'+{o}' for o in ['hum','mt','dt','ambient_temp_c','machine_age_years'] if o!=c),m,family=sm.families.Binomial()).fit()
    p=r.params.filter(like=f'{c}_b');print(c);print(p.round(3).to_string())
E
python3 $TMPDIR/e.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_ikbnu98f; cat > $TMPDIR/f.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/prep.py').read())
import statsmodels.formula.api as smf
d['per']=np.where((d.line=='L1')&(d.date<'2025-04-14'),'L1pre',np.where(d.line=='L1','L1post',d.line))
d['mo']=d.date.dt.month
print(d.groupby('per')[['mt','ambient_temp_c']].mean())
r=smf.ols('mt~ambient_temp_c+C(per)',d).fit();print(r.params,r.resid.std())
print(d.groupby('mo').ambient_temp_c.mean())
x=d[d.line=='L1'].copy();x['wk']=(x.date-pd.Timestamp('2025-04-14')).dt.days
r=smf.ols('mt~ambient_temp_c+I(wk>=0)+wk',x).fit();print(r.params,r.bse)
x2=x[x.wk<0];print(smf.ols('mt~ambient_temp_c+wk',x2).fit().params)
x2=x[x.wk>=0];print(smf.ols('mt~ambient_temp_c+wk',x2).fit().params)
E
python3 $TMPDIR/f.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_ikbnu98f; python3 $TMPDIR/f.py 2>&1 | grep -v Warn

echo $TMPDIR; ls $TMPDIR | head -30

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; mkdir -p $S; ls $S; cd /tmp/edabench_claude_ikbnu98f
cat > $S/prep.py <<'E'
import pandas as pd,numpy as np
D='/tmp/edabench_claude_ikbnu98f/'
d=pd.read_csv(D+'batches.csv',dtype=str).drop_duplicates('batch_id').reset_index(drop=True)
def pdte(r):
    x=r.production_date
    if '/' not in x: return pd.Timestamp(x)
    return pd.to_datetime(x,format='%d/%m/%Y' if r.line=='L4' else '%m/%d/%Y')
d['date']=d.apply(pdte,axis=1)
d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
d['sc']=d.supplier_code.str.strip().str.upper()
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']: d[c]=pd.to_numeric(d[c])
d['hum']=d.humidity_pct.where(d.humidity_pct>0)
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.loc[d.line=='L3','mt']-32)/1.8
d['rate']=d.defective_units/d.units_produced
d['ok']=d.units_produced-d.defective_units
s=pd.read_csv(D+'suppliers.csv');d=d.merge(s,left_on='sc',right_on='supplier_code',suffixes=('','_s'))
d['dt']=d.cycle_time_s-d.recipe_cycle_time_s
E
cat > $S/f.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
import statsmodels.formula.api as smf
d['per']=np.where((d.line=='L1')&(d.date<'2025-04-14'),'L1pre',np.where(d.line=='L1','L1post',d.line))
print(d.groupby('per')[['mt','ambient_temp_c']].mean())
r=smf.ols('mt~ambient_temp_c+C(per)',d).fit();print(r.params,r.resid.std())
x=d[d.line=='L1'].copy();x['wk']=(x.date-pd.Timestamp('2025-04-14')).dt.days
for a,b in [(x[x.wk<0],'pre'),(x[x.wk>=0],'post')]:
    print(b,smf.ols('mt~ambient_temp_c+wk',a).fit().params.round(3).to_dict())
E
python3 $S/f.py 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
cat > $S/g.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
m=d.dropna(subset=['hum','mt']).copy()
m['hum2']=m.hum**2;m['dt2']=m.dt**2
f='defective_units+ok ~ hum+hum2+mt+dt+dt2+machine_age_years+ambient_temp_c+shift+C(supplier_name)+C(line)'
r=smf.glm(f,m,family=sm.families.Binomial()).fit(scale='X2');print(r.params.round(4).to_dict());print(r.pvalues.round(4).to_dict())
m['res']=(m.defective_units-r.fittedvalues*m.units_produced)/m.units_produced
m['wk']=m.date.dt.to_period('2W').dt.start_time
for ln in ['L1','L2','L3','L4']:
    print(ln,(m[m.line==ln].groupby('wk').res.mean()*1000).round(0).astype(int).tolist())
E
python3 $S/g.py 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
python3 - <<'E'
import pandas as pd
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
m=m[m.event=='mold_cleaning']
for l,g in m.groupby('line'):
    g=g.sort_values('date');print(l,g.date.dt.strftime('%m-%d').tolist(),g.date.diff().dt.days.tolist())
E

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
cat >> $S/prep.py <<'E'
mm=pd.read_csv(D+'maintenance.csv',parse_dates=['date']);mm=mm[mm.event=='mold_cleaning']
def dsc(r):
    c=mm[(mm.line==r.line)&(mm.date<=r.date)].date.max();return (r.date-c).days
d['dsc']=d.apply(dsc,axis=1)
E
cat > $S/h.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
print(d.dsc.describe())
m=d.dropna(subset=['hum','mt']).copy()
m['hum2']=m.hum**2;m['dt2']=m.dt**2
m['db']=pd.cut(m.dsc,[-1,2,4,6,8,10,12,14,16,20,25,30,40])
f='defective_units+ok ~ C(db)+hum+hum2+mt+dt+dt2+ambient_temp_c+shift+C(supplier_name)+C(line)'
r=smf.glm(f,m,family=sm.families.Binomial()).fit(scale='X2');print(r.params.round(3).to_string())
m['res']=(m.defective_units-r.fittedvalues*m.units_produced)/m.units_produced
m['wk']=m.date.dt.to_period('W').dt.start_time
for ln in ['L1','L2','L3','L4']:
    print(ln,(m[m.line==ln].groupby('wk').res.mean()*1000).round(0).astype(int).tolist())
E
python3 $S/h.py 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
cat >> $S/h.py <<'E'
for ln in ['L2','L3']:
    x=m[m.line==ln].sort_values('date')
    best=None
    for dte in sorted(x.date.unique())[10:-10]:
        a=x[x.date<dte].res;b=x[x.date>=dte].res
        sse=((a-a.mean())**2).sum()+((b-b.mean())**2).sum()
        if best is None or sse<best[0]: best=(sse,dte)
    print(ln,best[1],x[x.date<best[1]].res.mean(),x[x.date>=best[1]].res.mean())
    dd=x[(x.date>=best[1]-pd.Timedelta(days=8))&(x.date<best[1]+pd.Timedelta(days=8))]
    print(dd.groupby('date')[['rate','res','mt','hum','dsc','units_produced']].mean().round(3))
E
python3 $S/h.py 2>&1 | grep -v Warn | tail -50

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
cat > $S/i.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
import statsmodels.formula.api as smf
d['qpd']=d.qc_inspection_min
for ln,dt in [('L2','2025-06-16'),('L3','2025-07-21')]:
    x=d[d.line==ln].copy();x['post']=x.date>=dt
    print(ln,x.groupby('post')[['rate','qc_inspection_min','rework_cost_eur','units_produced','mt','hum','ambient_temp_c','cycle_time_s','machine_age_years','dsc']].mean().round(3).T)
print(smf.ols('qc_inspection_min~rate',d).fit().params, smf.ols('qc_inspection_min~defective_units+units_produced',d).fit().params)
print(smf.ols('rework_cost_eur~defective_units+units_produced',d).fit().rsquared)
E
python3 $S/i.py 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
cat > $S/j.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
m=d.dropna(subset=['hum','mt']).copy()
m['hum2']=m.hum**2;m['dt2']=m.dt**2
m['l3p']=((m.line=='L3')&(m.date>='2025-07-21')).astype(int)
m['l1p']=((m.line=='L1')&(m.date>='2025-04-14')).astype(int)
base='defective_units+ok ~ dsc+hum+hum2+mt+dt+dt2+ambient_temp_c+shift+C(supplier_name)+C(line)+l3p'
res=[]
for c in pd.date_range('2025-05-20','2025-07-10'):
    m['l2p']=((m.line=='L2')&(m.date>=c)).astype(int)
    r=smf.glm(base+'+l2p',m,family=sm.families.Binomial()).fit();res.append((r.deviance,c))
res.sort();print(res[:5])
c=res[0][1];m['l2p']=((m.line=='L2')&(m.date>=c)).astype(int)
x=m[(m.line=='L2')].sort_values('date');print(x[(x.date>=c-pd.Timedelta(days=4))&(x.date<=c+pd.Timedelta(days=2))].groupby('date').rate.mean())
for extra in ['','+l1p']:
  r=smf.glm(base+'+l2p'+extra,m,family=sm.families.Binomial()).fit(scale='X2');print(r.params.round(4).to_dict());print(r.pvalues.round(4).to_dict())
E
python3 $S/j.py 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
cat > $S/k.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
m=d.dropna(subset=['hum','mt']).copy()
m['hum2']=m.hum**2;m['dt2']=m.dt**2;m['ct2']=m.cycle_time_s**2;m['mt2']=m.mt**2
m['l3p']=((m.line=='L3')&(m.date>='2025-07-21')).astype(int)
m['l1p']=((m.line=='L1')&(m.date>='2025-04-14')).astype(int)
m['l2p']=((m.line=='L2')&(m.date>='2025-06-16')).astype(int)
m['ageC']=m.machine_age_years-m.groupby('line').machine_age_years.transform('mean')
def F(f,x=m): return smf.glm('defective_units+ok ~ '+f,x,family=sm.families.Binomial()).fit(scale='X2')
b='dsc+hum+hum2+mt+shift+C(supplier_name)+C(line)+l3p+l2p+l1p+ambient_temp_c'
for name,extra in [('dt',' +dt+dt2'),('ct',' +cycle_time_s+ct2'),('ct_lin',' +cycle_time_s'),('dt_lin','+dt')]:
    r=F(b+'+'+extra);print(name,r.deviance,r.params.filter(regex='dt|cycle|ct2').round(4).to_dict(),r.pvalues.filter(regex='dt|cycle|ct2').round(4).to_dict())
b2=b+'+dt'
r=F(b2+'+ageC');print('age',r.params['ageC'],r.pvalues['ageC'])
r=F(b2+'+machine_age_years');print('ageraw',r.params['machine_age_years'],r.pvalues['machine_age_years'], r.params['C(line)[T.L4]'])
r=F(b2+'+mt2');print('mt2',r.params['mt2'],r.pvalues['mt2'])
r=F(b2+'+C(operator_id)');print('op')
from scipy import stats
r0=F(b2);r1=F(b2+'+C(operator_id)');print(r0.deviance,r1.deviance,r0.df_resid-r1.df_resid, 'F-ish', ((r0.deviance-r1.deviance)/(r0.df_resid-r1.df_resid))/r1.scale)
print(r0.params.round(4).to_dict());print(r0.pvalues.round(4).to_dict())
r=F(b2+'+ambient_temp_c:mt');
E
python3 $S/k.py 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
python3 - <<'E' 2>&1 | grep -v Warn
src=open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/k.py').read().split("def F")[0]
exec(src)
def F(f,x=m): return smf.glm('rate ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
b='dsc+hum+hum2+mt+shift+C(supplier_name)+C(line)+l3p+l2p+l1p+ambient_temp_c+dt'
r0=F(b);print(r0.scale);print(pd.DataFrame({'b':r0.params,'p':r0.pvalues}).round(4))
for e in ['ageC','mt2','dt2','C(operator_id)','ambient_temp_c:mt','C(supplier_name):hum','C(supplier_name):hum2']:
    r=F(b+'+'+e);print(e,(r0.deviance-r.deviance)/(r0.df_resid-r.df_resid)/r.scale, r0.df_resid-r.df_resid)
    if e in('ageC','mt2'):print(r.params[e],r.pvalues[e])
E

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
python3 - <<'E' 2>&1 | grep -v Warn
src=open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/k.py').read().split("def F")[0]
exec(src)
def F(f,x=m): return smf.glm('rate ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
b='dsc+mt+shift+C(line)+l3p+l2p+l1p+ambient_temp_c+dt+C(supplier_name)*(hum+hum2)'
r=F(b);print(r.scale);print(pd.DataFrame({'b':r.params,'p':r.pvalues}).round(4))
x=m[m.line=='L4'];r4=F('machine_age_years+dsc+mt+shift+dt+C(supplier_name)*(hum+hum2)',x);print(r4.params['machine_age_years'],r4.pvalues['machine_age_years'])
r4=F('machine_age_years+dsc+mt+shift+dt+hum+hum2+C(supplier_name)',m[m.line!='L4']);print('no L4',r4.params['machine_age_years'],r4.pvalues['machine_age_years'])
r=F('machine_age_years+dsc+mt+shift+l3p+l2p+l1p+dt+C(supplier_name)*(hum+hum2)');print('noline',r.params['machine_age_years'],r.pvalues['machine_age_years'])
E

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
python3 - <<'E' 2>&1 | grep -v Warn
src=open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/k.py').read().split("def F")[0]
exec(src)
def F(f,x=m): return smf.glm('rate ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
m['hb']=pd.cut(m.hum,[0,10,15,20,25,30,35,40,45,50,55,60,80])
print(m.hum.describe(), m.groupby('supplier_name').hum.describe())
out={}
for s in ['Alpha','Beta','Gamma']:
    x=m[m.supplier_name==s]
    r=F('C(hb)-1+dsc+mt+shift+C(line)+l3p+l2p+l1p+dt',x)
    out[s]=r.params.filter(like='hb')
o=pd.DataFrame(out);o.index=[i.split('(')[-1] for i in o.index];print(o.round(2));print(m.groupby(['hb','supplier_name'],observed=True).size().unstack())
E

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
python3 - <<'E' 2>&1 | grep -v Warn
src=open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/k.py').read().split("def F")[0]
exec(src)
def F(f,x=m): return smf.glm('rate ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
for s in ['Alpha','Beta','Gamma']:
    x=m[m.supplier_name==s]
    r=F('hum+hum2+dsc+mt+shift+C(line)+l3p+l2p+l1p+dt',x)
    b=r.cov_params();print(s,-r.params.hum/(2*r.params.hum2))
    # bootstrap-ish delta
    import numpy as np
    sm_=np.random.multivariate_normal(r.params[['hum','hum2']],b.loc[['hum','hum2'],['hum','hum2']],5000);o=-sm_[:,0]/(2*sm_[:,1]);print(np.percentile(o,[2.5,50,97.5]))
x=m[m.supplier_name=='Alpha']
r=F('hum+hum2+I(hum**3)+dsc+mt+shift+C(line)+l3p+l2p+l1p+dt',x);print(r.pvalues['I(hum ** 3)'])
g=np.arange(12,73,0.5);import itertools
best=[]
for hh in [28,30,32]:
    pass
# profile: V-shape check via grid of centered abs
for c in range(24,40):
    x=x.assign(a=(x.hum-c).abs(),q=(x.hum-c)**2)
    r=F('a+dsc+mt+shift+C(line)+l3p+l2p+l1p+dt',x);print(c,round(r.deviance,1),end=' | ')
E

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
python3 - <<'E' 2>&1 | grep -v Warn
src=open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/k.py').read().split("def F")[0]
exec(src)
from scipy.special import expit,logit
def F(f,x=m): return smf.glm('rate ~ '+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
m['over']=(m.dsc-14).clip(lower=0)
base='mt+shift+C(line)+l3p+l2p+l1p+dt+C(supplier_name)*(hum+hum2)'
r1=F(base+'+dsc');r2=F(base+'+dsc+over');r3=F(base+'+over')
print(r1.deviance,r1.params.dsc,r2.deviance,r2.params[['dsc','over']].to_dict(),r2.pvalues[['dsc','over']].to_dict(),r3.deviance)
r=r1
# C1
res={}
for s in ['Alpha','Beta','Gamma']:
    x=m.copy();x['supplier_name']=s;x['dt']=0
    p=r.predict(x);res[s]=(p*m.units_produced).sum()/m.units_produced.sum()
print(res)
# C3
beta=r.params.dsc
for lab,new in [('mod',m.dsc%14),('cap',m.dsc.clip(upper=14))]:
    x=m.copy();x['dsc']=new
    pf=r.predict(m);pc=r.predict(x)
    cf=(pc*m.units_produced).sum();fit=(pf*m.units_produced).sum();act=m.defective_units.sum()
    print(lab,'ratio',cf/fit, 'on complete', act/m.units_produced.sum()*cf/fit, 'mean dsc',new.mean(),m.dsc.mean())
# all-batch version using full data
dd=d.copy();dd['new']=dd.dsc%14
for lab,new in [('mod',dd.dsc%14),('cap',dd.dsc.clip(upper=14))]:
    dl=beta*(new-dd.dsc)
    q=expit(logit(dd.rate)+dl)
    print(lab,'all batches',(q*dd.units_produced).sum()/dd.units_produced.sum())
    print(lab,'noncomplete-ratio',(dd.defective_units.sum()*0+ (dd.defective_units*np.exp(dl)).sum())/dd.units_produced.sum())
E

S=/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; cd /tmp/edabench_claude_ikbnu98f
python3 - <<'E' 2>&1 | grep -v Warn
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
import statsmodels.formula.api as smf
d['l1p']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
x=d[d.line=='L1'].dropna(subset=['mt']).copy()
r=smf.ols('mt~ambient_temp_c+l1p',x).fit();print(r.params,r.bse)
r=smf.ols('mt~ambient_temp_c*l1p',x).fit();print(r.params,r.bse)
r=smf.ols('mt~ambient_temp_c+l1p+C(line)',d.dropna(subset=['mt'])).fit();print(r.params)
y=d[d.line!='L1'].dropna(subset=['mt']);r=smf.ols('mt~ambient_temp_c+C(line)',y).fit();print(r.params,r.resid.std())
# post vs predicted using L2,L4 line
y2=d[d.line.isin(['L2','L4'])].dropna(subset=['mt']);r2=smf.ols('mt~ambient_temp_c',y2).fit();print(r2.params)
for nm,g in [('pre',x[x.l1p==0]),('post',x[x.l1p==1])]:print(nm,(g.mt-r2.predict(g)).mean())
for off in [0,5,6.4,8]:
    mt=d.mt.copy();mt[d.l1p==1]-=off;print(off,mt.median())
E

cd /tmp/edabench_claude_ikbnu98f; python3 - <<'E' 2>&1 | grep -v Warn
exec(open('/tmp/claude-0/-tmp-edabench-claude-ikbnu98f/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/prep.py').read())
p=(d.line=='L1')&(d.date>='2025-04-14')
for off in [7,7.5,7.7,8]:
    mt=d.mt.copy();mt[p]-=off;print(off,mt.median())
E
