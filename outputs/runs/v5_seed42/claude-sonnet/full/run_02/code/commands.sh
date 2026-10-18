cd /tmp/edabench_claude_j4q8iwd6; ls; for f in *.csv; do echo $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/a.py <<'E'
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.describe().T)
for c in ['shift','line','operator_id','supplier_code']: print(d[c].value_counts(dropna=False))
print(d.production_date.str.len().value_counts())
print(d[d.batch_id.duplicated(keep=False)].sort_values('batch_id').head(12).to_string())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(d[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(d[c][x.isna()].value_counts(dropna=False).head())
E
python3 -I $TMPDIR/a.py; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('batches.csv',dtype=str)
print(d[d.production_date.str[2]=='/'].production_date.str[:2].astype(int).describe())
a=d[d.production_date.str[2]=='/']
print(a.groupby('line').size())
x=a.production_date.str.split('/',expand=True).astype(int)
print(((x[0]>12)).sum(),(x[1]>12).sum())
print(a[(x[0]<=12)&(x[1]<=12)].head(10).to_string())
print(d.groupby('line').apply(lambda g:g.production_date.str[2].value_counts().to_dict()))
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning']); 
d['mt']=d.mold_temp.astype(float)
d['dt']=d.production_date
print(d.groupby('line').mt.describe())
print(d[d.mt<100].groupby('line').size())
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('batches.csv',dtype=str)
def pdt(r):
    s=r.production_date
    if s[2]!='/': return pd.Timestamp(s)
    return pd.to_datetime(s,format='%m/%d/%Y' if r.line=='L1' else '%d/%m/%Y')
d['date']=d.apply(pdt,axis=1)
print(d.date.min(),d.date.max())
d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
d['sup']=d.supplier_code.str.strip().str.upper()
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']: d[c]=pd.to_numeric(d[c])
d=d.drop(columns=['production_date','supplier_code'])
n0=len(d);d=d.drop_duplicates();print(n0,len(d),d.batch_id.nunique())
print(d.duplicated(['line','date','shift','operator_id','units_produced']).sum())
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['mt']=d.mold_temp.where(d.mold_temp>50)
d.loc[d.line=='L3','mt']=(d.mt-32)*5/9
print('A1',len(d),'A2',d.hum.isna().sum(),'A3',d.defective_units.sum()/d.units_produced.sum(),'A4',d.mt.median())
print(d.groupby('line').mt.describe())
d['rate']=d.defective_units/d.units_produced
d.to_pickle('/tmp/edabench_claude_j4q8iwd6/../clean.pkl') if False else d.to_pickle(__import__('os').environ['TMPDIR']+'/clean.pkl')
print(d[d.line=='L1'].set_index('date').mt.resample('M').agg(['mean','std']))
print(d.groupby('sup').rate.mean(), d.groupby('shift').rate.mean())
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np,os
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
l=d[d.line=='L1'].set_index('date').sort_index()
print(l.mt.resample('2W').agg(['mean','std','count']))
print(d.groupby(['line',d.date.dt.month]).rate.mean().unstack().round(4))
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
d['post']=(d.date>='2025-04-14').astype(int)
for L in ['L1','L2','L3','L4']:
    g=d[d.line==L].dropna(subset=['mt'])
    print(L,smf.ols('mt~ambient_temp_c+post',g).fit().params.round(2).to_dict())
l=d[(d.line=='L1')&(d.date>='2025-04-01')&(d.date<'2025-04-30')].groupby('date').mt.mean();print(l.round(1).to_string())
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
d['post']=(d.date>='2025-04-14').astype(int)
d['nd']=d.units_produced-d.defective_units
d=d.rename(columns={'machine_age_years':'age','ambient_temp_c':'amb','cycle_time_s':'ct'})
g=d.dropna(subset=['mt','hum']).copy()
g['mt2']=(g.mt-211)**2;g['h2']=(g.hum-30)**2
f='nd+defective_units~'
m=smf.glm('I(defective_units/units_produced)~mt+mt2+hum+h2+ct+age+amb+C(shift)+C(operator_id)+C(sup)+C(line)',g,family=sm.families.Binomial(),freq_weights=g.units_produced).fit()
print(m.summary().tables[1])
E
python3 -I $TMPDIR/f.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
d=d.rename(columns={'machine_age_years':'age','ambient_temp_c':'amb','cycle_time_s':'ct'})
d['rec']=d.sup.map({'SP-01':30,'SP-02':30,'SP-03':36});d['cd']=d.ct-d.rec
print(d.groupby('sup')[['ct','hum','mt','amb']].mean())
print(d.groupby('line')[['age','amb','ct','hum']].agg(['mean','std']))
print(pd.crosstab(d.operator_id,d.line).head(30))
print(d[['mt','hum','ct','amb','age','qc_inspection_min','rework_cost_eur','rate']].corr().round(2))
g=d.dropna(subset=['mt','hum']).copy()
g['mt2']=(g.mt-211)**2;g['h2']=(g.hum-30)**2
def fit(f,data=g):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),freq_weights=data.units_produced).fit(scale='X2')
m=fit('mt+hum+h2+cd+age+amb+C(shift)+C(line)+C(sup)');print(m.summary().tables[1],m.scale)
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
d=d.rename(columns={'machine_age_years':'age','ambient_temp_c':'amb','cycle_time_s':'ct'})
d['rec']=d.sup.map({'SP-01':30,'SP-02':30,'SP-03':36});d['cd']=d.ct-d.rec
d['y']=list(zip(d.defective_units,d.units_produced-d.defective_units))
d['h2']=(d.hum-30)**2
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['mon']=d.date.dt.month
g=d.dropna(subset=['mt','hum']).copy()
def fit(f,data=g):
    m=smf.glm('d_ ~'+f,data.assign(d_=data.defective_units/data.units_produced),family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
    return m
m=fit('mt+l1post+hum+h2+cd+age+amb+C(shift)+C(line)+C(sup)');print(m.summary().tables[1],m.scale)
# L1 only mt slope pre/post
for L in ['L1','L2','L3','L4']:
  x=g[g.line==L]; print(L,fit('mt+hum+h2+cd+amb',x).params[['mt','amb']].round(4).to_dict())
x=g[g.line=='L1']
print(fit('mt*l1post+hum+h2+cd+amb',x).params.round(4).to_dict())
E
python3 -I $TMPDIR/h.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
d=d.rename(columns={'machine_age_years':'age','ambient_temp_c':'amb','cycle_time_s':'ct'})
d['rec']=d.sup.map({'SP-01':30,'SP-02':30,'SP-03':36});d['cd']=d.ct-d.rec
d['h2']=(d.hum-30)**2
post=((d.line=='L1')&(d.date>='2025-04-14'))
d['mtc']=d.mt-7.0*post
d['m']=d.date.dt.to_period('M').astype(str)
g=d.dropna(subset=['mtc','hum']).copy()
g['r']=g.defective_units/g.units_produced
m=smf.glm('r~mtc+hum+h2+cd+amb+C(shift)+C(line)+C(sup)',g,family=sm.families.Binomial(),var_weights=g.units_produced).fit(scale='X2')
print(m.params.round(4).to_dict())
g['res']=np.log(g.defective_units+.5)-np.log(g.units_produced*m.fittedvalues+.5)
g['w']=g.date.dt.to_period('W').dt.start_time
print(g.groupby(['w','line']).res.mean().unstack().round(2).to_string())
E
python3 -I $TMPDIR/i.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/j.py <<'E'
import pandas as pd,numpy as np,os
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
for L in ['L1','L2','L3','L4']:
    print(L,[x.strftime('%m-%d') for x in m[m.line==L].date.sort_values()])
d['w']=d.date.dt.to_period('2W').dt.start_time
for L in ['L2','L3']:
    x=d[d.line==L]
    print(x.groupby('w')[['qc_inspection_min','rework_cost_eur','rate','units_produced']].mean().round(3).to_string())
E
python3 -I $TMPDIR/j.py

cd /tmp/edabench_claude_j4q8iwd6; python3 -I $TMPDIR/j.py

cd /tmp/edabench_claude_j4q8iwd6; echo $TMPDIR; cat > $TMPDIR/k.py <<'E'
import pandas as pd,numpy as np,os
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
for L in ['L1','L2','L3','L4']:
    print(L,[x.strftime('%m-%d') for x in m[m.line==L].date.sort_values()])
d['w']=d.date.dt.to_period('2W').dt.start_time
for L in ['L2','L3']:
    x=d[d.line==L]
    print(x.groupby('w')[['qc_inspection_min','rework_cost_eur','rate','units_produced']].mean().round(3).to_string())
E
python3 -I $TMPDIR/k.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/l.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
d=d.rename(columns={'machine_age_years':'age','ambient_temp_c':'amb','cycle_time_s':'ct'})
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days
d['ds']=d.apply(ds,axis=1)
print(d.ds.describe())
d['rec']=d.sup.map({'SP-01':30,'SP-02':30,'SP-03':36});d['cd']=d.ct-d.rec
d['h2']=(d.hum-30)**2
post=((d.line=='L1')&(d.date>='2025-04-14'))
d['mtc']=d.mt-7.0*post
d.to_pickle(os.environ['TMPDIR']+'/clean2.pkl')
print(d.groupby('ds').rate.mean().round(4).to_string())
l3=d[d.line=='L3'].set_index('date').sort_index().qc_inspection_min
print(l3['2025-07-10':'2025-07-25'].to_string())
E
python3 -I $TMPDIR/l.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/m.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean2.pkl')
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
g=d.dropna(subset=['mtc','hum']).copy(); g['r']=g.rate
def fit(f,data=g):
    return smf.glm('r~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
# L2 changepoint scan
best=[]
for dt in pd.date_range('2025-05-25','2025-07-10'):
    g['reg']=((g.line=='L2')&(g.date>=dt)).astype(int)
    m=fit('reg+mtc+hum+h2+cd+amb+C(shift)+C(line)+C(sup)+C(pd.cut(ds,[-1,3,7,10,14,21,30,100]))')
    best.append((m.llf if hasattr(m,'llf') else 0,dt,m.deviance))
best.sort(key=lambda t:t[2]);print(best[:5])
E
python3 -I $TMPDIR/m.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/n.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean2.pkl')
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['dsb']=pd.cut(d.ds,[-1,2,5,8,11,14,17,21,28,100]).astype(str)
d['pd_']=(d.sup=='SP-02').astype(int)
g=d.dropna(subset=['mtc','hum']).copy(); g['r']=g.rate
def fit(f,data=g):
    return smf.glm('r~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
m=fit('reg+mtc+hum+h2+cd+amb+age+C(shift)+C(line)+C(sup)+C(dsb)')
print(m.summary().tables[1],m.scale)
m=fit('reg+mtc+I((mtc-211)**2)+hum+h2+cd+I(cd**2)+amb+C(shift)+C(line)+C(sup)+C(dsb)+C(operator_id)')
print(m.params.round(4).to_string())
E
python3 -I $TMPDIR/n.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/o.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean2.pkl')
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['dsb']=pd.cut(d.ds,[-1,2,5,8,11,14,17,21,28,100]).astype(str)
g=d.dropna(subset=['mtc','hum']).copy(); g['r']=g.rate
base='reg+mtc+hum+h2+cd+C(shift)+C(line)+C(sup)+C(dsb)'
def fit(f): return smf.glm('r~'+f,g,family=sm.families.Binomial(),var_weights=g.units_produced).fit(scale='X2')
a=fit(base);b=fit(base+'+C(operator_id)')
print(a.deviance,b.deviance,a.df_resid-b.df_resid, 'F',((a.deviance-b.deviance)/(a.df_resid-b.df_resid))/b.scale)
from scipy import stats
print(stats.f.sf(((a.deviance-b.deviance)/(a.df_resid-b.df_resid))/b.scale,a.df_resid-b.df_resid,b.df_resid))
# ds linear within 0-14 vs beyond
E
python3 -I $TMPDIR/o.py

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/clean2.pkl')
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['dsb']=pd.cut(d.ds,[-1,2,5,8,11,14,17,21,28,100]).astype(str)
g=d.dropna(subset=['mtc','hum']).copy(); g['r']=g.rate
def fit(f,data=g): return smf.glm('r~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
base='reg+mtc+cd+C(shift)+C(line)+C(dsb)'
m=fit(base+'+C(sup)*(hum+h2)')
print(m.params.round(4).to_string())
for f in ['+C(sup)*cd','+C(sup)*mtc','+hum:h2','+C(sup)*I((hum-30)**3)']:
    print(f, fit(base+'+C(sup)*(hum+h2)'+f).deviance, m.deviance)
# counterfactual
rec={'SP-01':30,'SP-02':30,'SP-03':36}
names={'SP-01':'Alpha','SP-02':'Beta','SP-03':'Gamma'}
for keep in [0,1]:
  for s in rec:
    x=g.copy();x['sup']=s
    if not keep: x['cd']=0
    p=m.predict(x); print(names[s],keep,(p*x.units_produced).sum()/x.units_produced.sum())
# Alpha humidity optimum
a=m.params
x=pd.DataFrame({'hum':np.arange(0,80,.5)});x['h2']=(x.hum-30)**2
for s in rec:
    b=g.iloc[:1].copy()
    r=pd.concat([b]*len(x),ignore_index=True);r['hum']=x.hum;r['h2']=x.h2;r['sup']=s
    p=m.predict(r);print(s,x.hum[p.argmin()], g.hum.min(),g.hum.max())
E
python3 -I $TMPDIR/p.py 2>&1 | grep -v Warn | grep -v wls

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/q.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
D=pd.read_pickle(os.environ['TMPDIR']+'/clean2.pkl')
D['reg']=((D.line=='L2')&(D.date>='2025-06-16')).astype(int)
d=D[~((D.line=='L3')&(D.date>='2025-07-21'))]
g=d.dropna(subset=['mtc','hum']).copy(); g['r']=g.rate
def fit(f,data=g): return smf.glm('r~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
base='reg+mtc+cd+C(shift)+C(line)+C(sup)*(hum+h2)'
g['dsc']=g.ds.clip(upper=35)
m=fit(base+'+C(dsc)')
c=m.params.filter(like='dsc');print(c.round(3).to_string())
print(g.ds.value_counts().sort_index().head(40).to_dict())
# alpha-only optimum
a=g[g.sup=='SP-01'];ma=fit('reg+mtc+cd+C(shift)+C(line)+C(dsc)+hum+h2',a);print(ma.params[['hum','h2']],30-ma.params['hum']/(2*ma.params['h2']))
ma=fit('reg+mtc+cd+C(shift)+C(line)+C(dsc)+hum+I(hum**2)',a);print(-ma.params['hum']/(2*ma.params['I(hum ** 2)']))
E
python3 -I $TMPDIR/q.py 2>&1 | grep -v Warn | grep -v wls

cd /tmp/edabench_claude_j4q8iwd6; cat >> $TMPDIR/q.py <<'E'
print('---C3')
for name,form,fn in [('lin','+ds',lambda x:x.ds),('dummy','+C(dsc)',None),('bins','+C(pd.cut(dsc,[-1,2,5,8,11,14,17,21,28,100]))',None)]:
    m=fit(base+form)
    X=D.copy();X['dsc']=X.ds.clip(upper=35)
    p0=m.predict(X);Y=X.copy();Y['ds']=Y.ds%14;Y['dsc']=Y.ds
    p1=m.predict(Y)
    new=(X.defective_units*p1/p0)
    print(name,X.defective_units.sum()/X.units_produced.sum(),new.sum()/X.units_produced.sum(), m.params.get('ds'))
    # cap variant
    Y['ds']=X.ds.clip(upper=14);Y['dsc']=Y.ds;p2=m.predict(Y);print(' cap',(X.defective_units*p2/p0).sum()/X.units_produced.sum())
E
python3 -I $TMPDIR/q.py 2>&1 | grep -v Warn | grep -v wls | sed -n '/C3/,$p'

cd /tmp/edabench_claude_j4q8iwd6; cat > $TMPDIR/r.py <<'E'
import pandas as pd,numpy as np,os
d=pd.read_pickle(os.environ['TMPDIR']+'/clean2.pkl')
post=((d.line=='L1')&(d.date>='2025-04-14'))
for o in [0,7,8,10.7]: print(o,(d.mt-o*post).median())
E
python3 -I $TMPDIR/r.py
