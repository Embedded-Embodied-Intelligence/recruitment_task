cd /tmp/edabench_claude_hyk26n19; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv');print(b.dtypes);print(b.describe(include='all').T.to_string())
for c in ['shift','line','operator_id','supplier_code']:print(b[c].value_counts(dropna=False))
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
print(b.production_date.str.len().value_counts())
print(pd.read_csv('maintenance.csv').event.value_counts()); print(pd.read_csv('maintenance.csv').note.value_counts())
for c in ['humidity_pct','mold_temp','cycle_time_s']:
    x=pd.to_numeric(b[c],errors='coerce');print(c,b[c][x.isna()].value_counts(dropna=False).head(),x.describe())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/a.py <<'E'
import pandas as pd
pd.set_option('display.width',200)
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.nunique())
print(b.humidity_pct.value_counts().sort_index().head(8))
print(b.mold_temp.round(-1).value_counts().sort_index())
print(b[b.mold_temp<100].mold_temp.value_counts().head())
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning'])
print(b.groupby('line').mold_temp.median())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/a.py <<'E'
import pandas as pd
pd.set_option('display.width',200)
b=pd.read_csv('batches.csv').drop_duplicates()
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning'].to_string())
b['f']=b.mold_temp>300
print(b.groupby('line').f.mean())
print(b[b.f].groupby('line').production_date.agg(['min','max']))
print(b[(b.line=='L3')].groupby(b.production_date.str[:7]).f.mean())
print(b[b.mold_temp==0].groupby('line').production_date.agg(['min','max','count']))
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/a.py <<'E'
import pandas as pd
pd.set_option('display.width',200)
b=pd.read_csv('batches.csv').drop_duplicates()
b=b[b.mold_temp>0].copy()
b['t']=b.mold_temp.where(b.line!='L3',(b.mold_temp-32)*5/9)
b['d']=pd.to_datetime(b.production_date)
print(b.groupby(['line',b.d.dt.to_period('M')]).t.median().unstack(0))
l=b[b.line=='L1'].set_index('d').t.resample('W').median();print(l.to_string())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
pd.set_option('display.width',200)
b=pd.read_csv('batches.csv').drop_duplicates().copy()
b['d']=pd.to_datetime(b.production_date)
b['shift']=b['shift'].str.strip().str.lower().str[0].map({'d':'Day','n':'Night'})
b['sup']=b.supplier_code.str.strip().str.upper()
s=pd.read_csv('suppliers.csv');b=b.merge(s,left_on='sup',right_on='supplier_code',suffixes=('','_s'))
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
b.loc[(b.line=='L1')&(b.d>='2025-04-14'),'mt']-=8
b['h']=b.humidity_pct.where(b.humidity_pct>=0)
b['rate']=b.defective_units/b.units_produced
print(len(b),b.h.isna().sum(),b.defective_units.sum()/b.units_produced.sum(),b.mt.median())
print(b.mt.describe())
b.to_pickle('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b.pkl')
print(b[['rate','mt','h','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur','units_produced']].corr()['rate'])
print(b.groupby('supplier_name').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
print(b.groupby('shift').rate.mean(), b.groupby('line').rate.mean())
print(b.groupby('operator_id').rate.mean().describe())
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
pd.set_option('display.width',200)
b=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.d)].date
    return (r.d-c.max()).days if len(c) else np.nan
b['ds']=b.apply(ds,axis=1)
print(b.ds.describe()); print(m.groupby('line').date.apply(lambda x:x.sort_values().diff().dt.days.describe()))
b['fail']=b.units_produced-b.defective_units
b['dd']=(b.d-pd.Timestamp('2025-01-06')).dt.days
b.to_pickle('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b2.pkl')
f='rate ~ mt+h+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(supplier_name)+ds'
d=b.dropna(subset=['mt','h','ds'])
r=smf.glm('fail+defective_units ~ 1',data=d)
r=smf.glm('I(defective_units/units_produced) ~ mt+h+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+C(supplier_name)+ds',data=d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit(scale='X2')
print(r.summary())
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
pd.set_option('display.width',200)
b=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b2.pkl')
d=b.dropna(subset=['mt','h','ds']).copy()
def fit(f,d=d):
    return smf.glm('fail+defective_units ~ 0+'.replace('fail+defective_units','I(defective_units)+I(fail)')[:0]+'defective_units+fail ~ '+f,data=d,family=sm.families.Binomial()).fit(scale='X2')
f='mt+h+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(supplier_name)+ds'
r=fit(f);print(r.summary().tables[1])
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
from patsy import dmatrix
pd.set_option('display.width',200)
b=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b2.pkl')
d=b.dropna(subset=['mt','h','ds']).copy()
def fit(f,d=d):
    X=dmatrix(f,d,return_type='dataframe')
    return sm.GLM(np.column_stack([d.defective_units,d.fail]),X,family=sm.families.Binomial()).fit(scale='X2')
f='mt+h+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(supplier_name)+ds'
r=fit(f);print(r.summary().tables[1],r.scale)
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm
from patsy import dmatrix
pd.set_option('display.width',200)
b=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b2.pkl')
d=b.dropna(subset=['mt','h','ds']).copy()
def fit(f,d=d):
    X=dmatrix(f,d,return_type='dataframe')
    r=sm.GLM(d.rate,X,family=sm.families.Binomial(),freq_weights=d.units_produced).fit()
    s=r.pearson_chi2/(len(d)-X.shape[1])
    return r,s
f='mt+h+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(line)+C(supplier_name)+ds'
r,s=fit(f);print(s)
t=r.params/(r.bse*s**.5);print(pd.DataFrame({'c':r.params,'t':t}).round(3).to_string())
E
python3 -I $TMPDIR/e.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_hyk26n19; cat >> $TMPDIR/e.py <<'E'
print('-----')
d['res']=d.rate-r.fittedvalues
print(d.groupby(['line',d.d.dt.to_period('M')]).res.mean().unstack(0).round(4))
print(d.groupby('supplier_name').h.mean(), d.groupby('line').machine_age_years.agg(['mean','std']))
print(d.groupby(pd.cut(d.h,[0,10,20,30,40,50,60,80]))[['rate','res']].mean())
print(d.groupby(['supplier_name',pd.cut(d.h,[0,15,25,35,45,55,80])]).rate.mean().unstack(0))
print(d.groupby(pd.cut(d.ds,[-1,3,7,10,13,14,17,21,40]))[['rate','res']].mean())
print(d.groupby('operator_id')[['line','shift']].agg(lambda x:x.value_counts().index[0]).T.to_string())
print(d[['mt','ambient_temp_c','cycle_time_s','h','machine_age_years']].corr().round(2))
E
python3 -I $TMPDIR/e.py 2>&1|sed -n '/-----/,$p'

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm
from patsy import dmatrix
pd.set_option('display.width',200)
b=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/b2.pkl')
d=b.dropna(subset=['mt','h','ds']).copy()
d['hh']=d.h-35; d['dh']=np.maximum(d.ds-14,0)
def fit(f,d=d):
    X=dmatrix(f,d,return_type='dataframe')
    r=sm.GLM(d.rate,X,family=sm.families.Binomial(),freq_weights=d.units_produced).fit()
    s=r.pearson_chi2/(len(d)-X.shape[1])
    return r,s,X
base='mt+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+C(supplier_name)*(hh+I(hh**2))+ds+dh'
r,s,X=fit(base);print(s)
print(pd.DataFrame({'c':r.params,'t':r.params/(r.bse*s**.5)}).round(4).to_string())
# L2 changepoint scan
res=[]
for L in ['L1','L2','L3','L4']:
    for dt in pd.date_range('2025-02-01','2025-09-15',freq='3D'):
        d['post']=((d.line==L)&(d.d>=dt)).astype(int)
        r2,s2,_=fit(base+'+post');res.append((L,dt,r2.params['post'],r2.llf))
R=pd.DataFrame(res,columns=['L','dt','c','llf'])
print(R.loc[R.groupby('L').llf.idxmax()])
E
python3 -I $TMPDIR/f.py 2>&1|grep -v -i warn

cd /tmp/edabench_claude_hyk26n19; cat > $TMPDIR/g.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-hyk26n19/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/../../../../../tmp/edabench_claude_hyk26n19/../../dev/null').read()) if False else None
E
sed -n '1,/^base=/p' $TMPDIR/f.py > $TMPDIR/g.py
cat >> $TMPDIR/g.py <<'E'
base+='+ds'
res=[]
for dt in pd.date_range('2025-06-01','2025-06-30'):
    d['post']=((d.line=='L2')&(d.d>=dt)).astype(int)
    r2,s2,_=fit(base+'+post');res.append((dt,r2.params['post'],r2.llf))
print(pd.DataFrame(res).to_string())
E
sed -i 's/base=.*ds+dh.$/base="mt+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+C(supplier_name)*(hh+I(hh**2))+ds"/' $TMPDIR/g.py
sed -i '/^base+=/d' $TMPDIR/g.py
python3 -I $TMPDIR/g.py 2>&1|grep -v -i warn

cd /tmp/edabench_claude_hyk26n19; cat >> $TMPDIR/g.py <<'E'
print(sorted(d[(d.line=='L2')&(d.d>='2025-06-08')&(d.d<='2025-06-22')].production_date.unique()))
d['post']=((d.line=='L2')&(d.d>='2025-06-15')).astype(int)
r,s,X=fit(base+'+post');print(r.params['post'],s)
# residual before/after for L2 by day
r0,s0,_=fit(base)
d['res']=d.rate-r0.fittedvalues
x=d[d.line=='L2'].groupby('production_date').res.mean();print(x['2025-06-05':'2025-06-25'].round(3).to_string())
E
python3 -I $TMPDIR/g.py 2>&1|sed -n '/^\[/,$p'

cd /tmp/edabench_claude_hyk26n19; cat >> $TMPDIR/g.py <<'E'
print('=====')
d['post']=((d.line=='L2')&(d.d>='2025-06-16')).astype(int)
core='mt+cycle_time_s+ambient_temp_c+C(shift)+C(supplier_name)*(hh+I(hh**2))+ds+post'
for name,extra in [('line+age','+C(line)+machine_age_years'),('line','+C(line)'),('age','+machine_age_years'),('line+op','+C(line)+C(operator_id)'),('line+age+op','+C(line)+C(operator_id)+machine_age_years')]:
    r,s,X=fit(core+extra);print(name,r.llf,s,r.params.get('machine_age_years'),(r.params/(r.bse*s**.5)).get('machine_age_years'))
r,s,X=fit(core+'+C(line)+C(operator_id)');t=r.params/(r.bse*s**.5);print(t.filter(like='operator').abs().max())
E
python3 -I $TMPDIR/g.py 2>&1|sed -n '/=====/,$p'

cd /tmp/edabench_claude_hyk26n19; cat >> $TMPDIR/g.py <<'E'
print(pd.DataFrame({'c':r.params,'t':t}).filter(like='operator',axis=0).round(3).T.to_string())
d['rr']=d.rate-fit(core+'+C(line)')[0].fittedvalues
print(d.groupby(['line','operator_id']).rr.mean().round(4).to_string())
E
python3 -I $TMPDIR/g.py 2>&1|sed -n '/OP-02/,$p'|tail -40

cd /tmp/edabench_claude_hyk26n19; cat >> $TMPDIR/g.py <<'E'
print('#####')
core='mt+cycle_time_s+ambient_temp_c+C(shift)+C(line)+C(supplier_name)*(hh+I(hh**2))+post'
for nm,ex in [('lin','+ds'),('bins','+C(pd.cut(ds,[-1,3,7,10,13,17,21,40]))'),('hinge','+ds+dh'),('age','+ds+machine_age_years')]:
    r,s,X=fit(core+ex);print(nm,r.llf,s);print((r.params/(r.bse*s**.5)).tail(8).round(2).to_dict())
r4,s4,_=fit('mt+cycle_time_s+ambient_temp_c+C(shift)+C(supplier_name)*(hh+I(hh**2))+ds+machine_age_years',d[d.line=='L4']);print('L4 age',r4.params['machine_age_years'],r4.params['machine_age_years']/(r4.bse['machine_age_years']*s4**.5))
r,s,X=fit(core+'+ds')
bds=r.params['ds'];print('bds',bds,r.bse['ds']*s**.5)
# C1
tot={}
for sp in ['Alpha','Beta','Gamma']:
    dd=d.copy();dd['supplier_name']=sp
    Xs=dmatrix(X.design_info,dd,return_type='dataframe')
    p=r.predict(Xs);tot[sp]=(p*d.units_produced).sum()/d.units_produced.sum()
print(tot)
for sp in ['Alpha','Beta','Gamma']:
    k=r.params.filter(regex=r'hh');
# C2: Alpha optimum
hs=np.arange(10,75,0.1);dd=d.iloc[:1].copy()
rows=pd.concat([dd]*len(hs));rows['h']=hs;rows['hh']=hs-35;rows['supplier_name']='Alpha'
p=r.predict(dmatrix(X.design_info,rows,return_type='dataframe'));print('opt',hs[np.argmin(p.values)])
a=d[d.supplier_name=='Alpha'];print(a.h.min(),a.h.max())
# C3
al=b.copy();al['post']=0
p=al.rate.clip(1e-6,1-1e-6);lg=np.log(p/(1-p));new=al.ds%14
p2=1/(1+np.exp(-(lg-bds*(al.ds-new))))
print('C3',(p2*al.units_produced).sum()/al.units_produced.sum(), (al.defective_units.sum()/al.units_produced.sum()))
# C3 using expected defects ratio
E
python3 -I $TMPDIR/g.py 2>&1|sed -n '/#####/,$p'
