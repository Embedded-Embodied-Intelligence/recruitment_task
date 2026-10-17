cd /tmp/edabench_claude_d2_q491x; ls; for f in *.csv; do echo == $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv');print(b.dtypes);print(b.describe(include='all').T)
for c in ['line','shift','operator_id','supplier_code']:print(b[c].value_counts(dropna=False))
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
print(b.humidity_pct.astype(str).sort_values().unique()[:10],b.humidity_pct.astype(str).sort_values().unique()[-10:])
print(b.mold_temp.sort_values().unique()[:10],b.mold_temp.sort_values().unique()[-10:])
print(open('maintenance.csv').read())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.duplicated().sum())
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['sup']=b.supplier_code.str.strip().str.upper()
b['date']=pd.to_datetime(b.production_date)
b['rate']=b.defective_units/b.units_produced
print((b.humidity_pct.isna()|(b.humidity_pct<0)).sum(), b.humidity_pct.lt(0).sum(), b.humidity_pct.max())
print(b.mold_temp.describe()); print(b.groupby('line').mold_temp.describe())
print((b.mold_temp<100).sum(), (b.mold_temp>300).sum())
print(b[b.mold_temp>300].groupby('line').size(), b[b.mold_temp<100].mold_temp.unique())
print(b.groupby(['line',b.date.dt.to_period('M')]).mold_temp.median().unstack())
print(b.groupby(['line',b.date.dt.to_period('M')]).rate.mean().unstack())
print(b.units_produced.describe(), (b.defective_units>b.units_produced).sum())
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
b['wk']=b.date.dt.to_period('W')
print(b[b.line=='L1'].groupby('wk')[['mt','rate']].mean().loc['2025-03-24':'2025-05-12'])
print(b[b.line=='L1'].groupby('wk')[['mt','rate']].mean().tail(8))
print(b.groupby('line').mt.median())
for l in ['L1','L2','L3','L4']:
    print(l,b[b.line==l].groupby('wk').rate.mean().round(3).values)
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/b.pkl')
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
b.loc[(b.line=='L1')&(b.date>='2025-04-14'),'mt']-=8
print('A4',b.mt.median(), 'A3',b.defective_units.sum()/b.units_produced.sum())
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def dsc(r):
    d=m[(m.line==r.line)&(m.date<=r.date)].date.max(); return (r.date-d).days
b['dsc']=b.apply(dsc,axis=1)
print(b.dsc.describe())
b['name']=b.sup.map({'SP-01':'Alpha','SP-02':'Beta','SP-03':'Gamma'})
b['opn']=b.operator_id
b['y']=b.defective_units/b.units_produced
b['age']=b.machine_age_years
b.to_pickle(T+'/b2.pkl')
d=b.dropna(subset=['mt','hum']).copy()
d['hum2']=d.hum**2
def fit(f,d=d):
    return smf.glm(f,d,family=sm.families.Binomial(),freq_weights=None).fit() 
f='y~mt+hum+hum2+cycle_time_s+age+ambient_temp_c+C(opn)+C(shift)+C(name)+C(line)+dsc+qc_inspection_min'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
print(r.summary().tables[1])
E
python3 -I $TMPDIR/d.py 2>&1 | grep -v "C(opn)"

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/b2.pkl')
print(pd.crosstab(b.opn,b.line).head(30))
print(b[['qc_inspection_min','rework_cost_eur','y','mt','hum','cycle_time_s','ambient_temp_c','age','dsc']].corr().round(2))
d=b.dropna(subset=['mt','hum']).copy();d['hum2']=d.hum**2
d['t']=(d.date-d.date.min()).dt.days/100
def fit(f):
    return smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
r=fit('y~mt+hum*C(name)+I(hum**2)*C(name)+cycle_time_s+age+ambient_temp_c+C(shift)+C(line)+dsc+C(opn)')
print(r.summary().tables[1])
E
python3 -I $TMPDIR/e.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/b2.pkl')
d=b.dropna(subset=['mt','hum']).copy();d['hum2']=d.hum**2
def fit(f,d=d):
    return smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='y~mt+hum*C(name)+I(hum**2)*C(name)+cycle_time_s+age+ambient_temp_c+C(line)+dsc'
r0=fit(base)
for extra in ['+C(shift)','+C(shift)+C(opn)']:
    r=fit(base+extra); print(extra, r.deviance, r.df_resid, r0.deviance)
# operator within line: test
r1=fit(base+'+C(shift)'); r2=fit(base+'+C(shift)+C(opn)')
print('opn F', (r1.deviance-r2.deviance)/(r1.df_resid-r2.df_resid)/r2.scale, r1.df_resid-r2.df_resid)
# dsc shape
d['dscb']=pd.cut(d.dsc,[-1,0,2,4,6,8,10,12,14,16,20,40])
r=fit('y~mt+hum*C(name)+I(hum**2)*C(name)+cycle_time_s+age+ambient_temp_c+C(line)+C(shift)+C(dscb)');print(r.params.filter(like='dscb'))
d['dscp']=np.maximum(d.dsc-14,0)
r=fit(base+'+C(shift)+dscp');print(r.params[['dsc','dscp']],r.bse[['dsc','dscp']])
# age & line
r=fit(base.replace('+age','')+'+C(shift)');print('noage dev',r.deviance)
# nonlinearity mt, cycle
r=fit(base+'+C(shift)+I(mt**2)+I(cycle_time_s**2)+I(ambient_temp_c**2)');print(r.params.filter(regex='\*\*|mt|cycle'),r.pvalues.filter(regex='\*\*'))
# regime: residual by line/week
rf=fit(base+'+C(shift)')
d['res']=(d.y-rf.fittedvalues)
d['wk']=d.date.dt.to_period('W')
for l in ['L1','L2','L3','L4']:
    print(l,(d[d.line==l].groupby('wk').res.mean()*100).round(1).values)
d.to_pickle(T+'/d.pkl')
E
python3 -I $TMPDIR/f.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,os
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
x=d[d.line=='L2'].sort_values('date')
g=x.groupby('date').res.agg(['mean','size'])
print(g.loc['2025-06-01':'2025-06-25'])
best=None
dates=sorted(x.date.unique())
for t in dates[10:-10]:
    a=x[x.date<t].res;c=x[x.date>=t].res
    s=((a-a.mean())**2).sum()+((c-c.mean())**2).sum()
    if best is None or s<best[0]:best=(s,t)
print(best)
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
base='y~mt+hum*C(name)+I(hum**2)*C(name)+cycle_time_s+ambient_temp_c+C(line)+dsc+C(shift)'
res=[]
for t in pd.date_range('2025-06-08','2025-06-26'):
    d['st']=((d.line=='L2')&(d.date>=t)).astype(int)
    r=smf.glm(base+'+st',d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
    res.append((t.date(),r.deviance,r.params['st']))
for x in res:print(x)
E
python3 -I $TMPDIR/h.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
print(d[(d.line=='L2')&(d.date>='2025-06-10')&(d.date<='2025-06-18')].groupby('date').size())
d['st']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
f='y~mt+hum*C(name)+I(hum**2)*C(name)+cycle_time_s+ambient_temp_c+C(line)+dsc+C(shift)+st'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
print(r.params.round(4).to_string())
tot=lambda x:(r.predict(x)*x.units_produced).sum()
base=tot(d);print('base',base/d.units_produced.sum(),d.defective_units.sum()/d.units_produced.sum())
for n in ['Alpha','Beta','Gamma']:
    x=d.copy();x['name']=n;print(n,tot(x)/d.units_produced.sum())
p=r.params;
for n,(a,b2) in {'Alpha':(p['hum'],p['I(hum ** 2)'])}.items():print(n,-a/(2*b2))
x=d.copy();x['dsc']=x.dsc%14;c=tot(x);print('C3 pred',c/d.units_produced.sum(), 'ratio-adj',d.defective_units.sum()/d.units_produced.sum()*c/base)
# adjust additive: observed minus savings, all units
print('additive',(d.defective_units.sum()-(base-c))/d.units_produced.sum())
print(d.hum.min(),d.hum.max())
E
python3 -I $TMPDIR/i.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_d2_q491x; cat > $TMPDIR/j.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ['TMPDIR']
d=pd.read_pickle(T+'/d.pkl')
d['st']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
F=lambda f,x=d:smf.glm(f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
f='y~mt+hum*C(name)+I(hum**2)*C(name)+cycle_time_s+ambient_temp_c+age+C(opn)+C(line)+dsc+C(shift)+st'
r=F(f);print(r.pvalues[['mt','cycle_time_s','ambient_temp_c','age','C(shift)[T.Night]']])
r2=F(f.replace('+C(opn)',''));print('opn F',(r2.deviance-r.deviance)/(r2.df_resid-r.df_resid)/r.scale)
a=d[d.name=='Alpha']
for f in ['y~mt+hum+I(hum**2)+cycle_time_s+C(line)+dsc+C(shift)+st','y~mt+hum+I(hum**2)+I(hum**3)+cycle_time_s+C(line)+dsc+C(shift)+st']:
    r=F(f,a);print(r.params['hum'],r.params['I(hum ** 2)'],-r.params['hum']/2/r.params['I(hum ** 2)'])
    h=np.arange(12,72.4,.1);x=a.iloc[[0]].copy();x=pd.concat([x]*len(h));x['hum']=h
    print(h[np.argmin(r.predict(x).values)])
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_d2_q491x; cat >> $TMPDIR/j.py <<'E'
print('----')
f='y~mt+hum*C(name)+I(hum**2)*C(name)+cycle_time_s+C(line)+dsc+C(shift)+st'
r0=F(f);r=F(f+'+C(opn)')
print('opn F',(r0.deviance-r.deviance)/(r0.df_resid-r.df_resid)/r.scale)
print(r.pvalues.filter(like='opn').round(3).to_string())
E
python3 -I $TMPDIR/j.py 2>&1 | sed -n '/----/,$p'
