cd /tmp/edabench_claude_tly7zoae; ls; for f in *.csv; do echo $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_tly7zoae; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.batch_id.nunique(),len(b))
for c in ['line','shift','operator_id','supplier_code']: print(b[c].value_counts(dropna=False).to_dict())
for c in ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','units_produced','defective_units','production_date']:
    x=pd.to_numeric(b[c],errors='coerce'); print(c,x.isna().sum(),x.describe().round(1).to_dict()); print(b[c][x.isna()].value_counts(dropna=False).head(8).to_dict())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id');print(d.head(10).to_string())
print(open('maintenance.csv').read()[:3000])
E
python3 -I $TMPDIR/a.py; cat suppliers.csv

cd /tmp/edabench_claude_tly7zoae; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b), b.batch_id.nunique())
b['d']=pd.to_datetime(b.production_date,errors='coerce',format='mixed');print(b.d.isna().sum(),b.d.min(),b.d.max())
print(b.production_date.str.len().value_counts())
print((b.mold_temp<100).sum(),(b.mold_temp>300).sum(), b[b.mold_temp<100].mold_temp.value_counts().head())
print(b.groupby('line').mold_temp.describe())
print(b.humidity_pct.describe(), (b.humidity_pct<=0).sum(), b.humidity_pct.isna().sum(), b.humidity_pct.value_counts().head(5))
print(b.groupby(['line',b.mold_temp>300]).size())
E
python3 -I $TMPDIR/p.py

cd /tmp/edabench_claude_tly7zoae; cat > $TMPDIR/p2.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b['d']=pd.to_datetime(b.production_date)
print(((b.humidity_pct<=0)|b.humidity_pct.isna()).sum(), (b.humidity_pct==0).sum())
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp); b.loc[b.mold_temp==0,'mt']=np.nan
print(b.mt.median(), b.mt.notna().sum())
b['dr']=b.defective_units/b.units_produced
print(b.defective_units.sum()/b.units_produced.sum())
b['m']=b.d.dt.to_period('M')
print(b.pivot_table(index='m',columns='line',values='mt',aggfunc='median').round(1))
print(b.pivot_table(index='m',columns='line',values='dr',aggfunc='mean').round(4))
l1=b[b.line=='L1'].set_index('d').mt.resample('W').median();print(l1.loc['2025-03-20':'2025-05-20'])
E
python3 -I $TMPDIR/p2.py

cd /tmp/edabench_claude_tly7zoae; cat > $TMPDIR/p3.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_csv('batches.csv').drop_duplicates()
s=pd.read_csv('suppliers.csv');m=pd.read_csv('maintenance.csv',parse_dates=['date'])
b['d']=pd.to_datetime(b.production_date)
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp); b.loc[b.mold_temp==0,'mt']=np.nan
b.loc[(b.line=='L1')&(b.d>='2025-04-14'),'mt']-=8
print(b.mt.median())
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sc']=b.supplier_code.str.strip().str.upper()
b=b.merge(s,left_on='sc',right_on='supplier_code',suffixes=('','_s'))
b['hum']=b.humidity_pct.where(b.humidity_pct>0)
cl=m[m.event=='mold_cleaning']
def ds(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.d)].date
    return (r.d-c.max()).days
b['ds']=b.apply(ds,axis=1)
print(b.ds.describe())
b['dr']=b.defective_units/b.units_produced
print(b.groupby(pd.cut(b.ds,[-1,3,7,10,14,18,25,40])).dr.agg(['mean','size']))
b['fail']=b.units_produced-b.defective_units
b['wk']=(b.d-b.d.min()).dt.days
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
x=b.dropna(subset=['mt','hum']).copy()
f='dr~mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+shift+C(line)+C(supplier_name)+ds+I(ds>14)+qc_inspection_min'
r=smf.glm(f,x,family=sm.families.Binomial(),freq_weights=x.units_produced).fit()
print(r.summary().tables[1])
E
python3 -I $TMPDIR/p3.py 2>&1 | grep -v "^C(operator"

cd /tmp/edabench_claude_tly7zoae; cat > $TMPDIR/p4.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
x=b.dropna(subset=['mt','hum']).copy()
x['pre']=(x.supplier_name!='Alpha').astype(int)
def fit(f,d=x):
    return smf.glm(f,d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit(scale='X')
r=fit('dr~mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+shift+C(line)+C(supplier_name)+ds')
t=r.summary2().tables[1];print(t[~t.index.str.contains('operator')].round(4))
print(t[t.index.str.contains('operator')]['P>|z|'].describe())
for k in ['Alpha','Beta','Gamma']:
    d=x[x.supplier_name==k]
    r2=fit('dr~mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+C(line)+ds',d)
    print(k,r2.params[['hum','I(hum ** 2)']].values, -r2.params['hum']/2/r2.params['I(hum ** 2)'])
E
python3 -I $TMPDIR/p4.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tly7zoae; sed -i "s/scale='X'/scale='x2'/" $TMPDIR/p4.py; python3 -I $TMPDIR/p4.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tly7zoae; cat > $TMPDIR/p5.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
x=b.dropna(subset=['mt','hum']).copy()
def fit(f,d=x):
    return smf.glm('dr~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='x2')
print(fit('mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+shift+C(line)+C(supplier_name)+ds').summary2().tables[1].round(4).to_string())
E
python3 -I $TMPDIR/p5.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tly7zoae; cat >> $TMPDIR/p5.py <<'E'
print(pd.crosstab(x.operator_id,x.line).T.to_string())
print(pd.crosstab(x.operator_id,x['shift']).T.to_string())
print(x[['mt','hum','ambient_temp_c','cycle_time_s','machine_age_years','wk']].corr().round(2))
print(x.groupby('line')[['machine_age_years','cycle_time_s','hum']].mean())
r=fit('mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+C(supplier_name)+ds')
x['res']=x.dr/r.fittedvalues
x['w']=(x.d.dt.to_period('W'))
for l in ['L1','L2','L3','L4']:
    print(l,x[x.line==l].groupby(x.d.dt.to_period('M')).res.mean().round(2).values)
E
python3 -I $TMPDIR/p5.py 2>&1 | sed -n '/^line\|^shift/,$p' | head -60

cd /tmp/edabench_claude_tly7zoae; cat >> $TMPDIR/p5.py <<'E'
print('-----')
print(x.groupby('line').machine_age_years.describe())
for f in ['mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+machine_age_years+C(supplier_name)+ds','mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+C(supplier_name)+ds+machine_age_years:C(line)']:
    print(fit(f).summary2().tables[1].round(4).to_string())
# changepoint L2 residual with ds in model
r=fit('mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+C(supplier_name)+ds')
x['res']=x.dr/r.fittedvalues
for l in ['L1','L2','L3','L4']:
    y=x[x.line==l].sort_values('d');best=[]
    for dt in sorted(y.d.unique())[20:-20]:
        a=y[y.d<dt];c=y[y.d>=dt]
        sse=((a.res-a.res.mean())**2).sum()+((c.res-c.res.mean())**2).sum()
        best.append((sse,dt,a.res.mean(),c.res.mean()))
    print(l,min(best), ((y.res-y.res.mean())**2).sum())
E
python3 -I $TMPDIR/p5.py 2>&1 | sed -n '/^-----/,$p'

cd /tmp/edabench_claude_tly7zoae; cat >> $TMPDIR/p5.py <<'E'
print('=====')
r=fit('mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+C(supplier_name)+C(pd.cut(ds,[-1,0,2,4,6,8,10,12,14,17,21,26,40]))')
print(r.params.filter(like='cut').round(3).to_string())
y=x[(x.line=='L2')&(x.d>='2025-06-05')&(x.d<='2025-06-25')].groupby('d').res.agg(['mean','size']);print(y)
E
python3 -I $TMPDIR/p5.py 2>&1 | sed -n '/^=====/,$p'

cd /tmp/edabench_claude_tly7zoae; cat >> $TMPDIR/p5.py <<'E'
print('#####')
x['reg']=((x.line=='L2')&(x.d>='2025-06-16')).astype(int)
for f in ['mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+C(supplier_name)+ds+reg','mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+C(supplier_name)+ds+reg+I(ds>14)']:
    r=fit(f);print(r.params.round(4).to_dict(), r.bse[['ds','reg']].round(4).to_dict())
r=fit('mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+C(supplier_name)+ds+reg')
bd=r.params['ds']
# per-supplier humidity optima
for k in ['Alpha','Beta','Gamma']:
    d=x[x.supplier_name==k];q=fit('mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+ds+reg',d)
    print(k,-q.params['hum']/2/q.params['I(hum ** 2)'])
d=x[x.supplier_name=='Alpha'];q=fit('mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+shift+C(line)+ds+reg+hum:ambient_temp_c',d);print(q.params['hum'])
print(x.hum.describe())
# C3 on all batches
b['dsn']=b.ds%14
def adj(D,beta):
    p=D.defective_units/D.units_produced; o=p/(1-p)*np.exp(beta*(D.dsn-D.ds)); return (o/(1+o)*D.units_produced).sum()/D.units_produced.sum()
print(b.defective_units.sum()/b.units_produced.sum(), adj(b,bd), adj(b,r.params['ds']*1))
# supplier counterfactual: predict all batches under each supplier
for k in ['Alpha','Beta','Gamma']:
    z=x.copy();z['supplier_name']=k;print(k,(r.predict(z)*z.units_produced).sum()/z.units_produced.sum())
E
python3 -I $TMPDIR/p5.py 2>&1 | sed -n '/^#####/,$p'
