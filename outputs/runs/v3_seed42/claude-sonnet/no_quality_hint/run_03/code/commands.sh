cd /tmp/edabench_claude_oj1doe_j; ls; for f in *.csv; do echo == $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.batch_id.nunique(),len(b))
for c in ['shift','line','operator_id','supplier_code']: print(b[c].value_counts(dropna=False).to_dict())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    n=pd.to_numeric(b[c],errors='coerce'); print(c,n.isna().sum(),n.describe().round(1).to_dict()); print(b[c][n.isna()].value_counts(dropna=False).head(5).to_dict())
print(b.production_date.str.len().value_counts())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id');print(d.head(8).to_string())
print(open('maintenance.csv').read()[:300]); m=pd.read_csv('maintenance.csv');print(m.event.value_counts(),m.note.value_counts())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b))
print(pd.cut(b.mold_temp,[-1,1,50,100,150,190,200,210,220,230,250,300,350,380,400,430,500]).value_counts().sort_index())
print(b.groupby('line').mold_temp.describe())
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning'])
print(b[b.mold_temp<150].head())
print(b.humidity_pct.lt(0).sum(), (b.humidity_pct>100).sum(),b.humidity_pct.isna().sum())
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
pd.set_option('display.width',250)
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning'].to_string())
b=pd.read_csv('batches.csv').drop_duplicates()
print(b.humidity_pct.isna().sum(), (b.humidity_pct<0).sum(), b.humidity_pct[b.humidity_pct<=0].value_counts().head())
print(b.humidity_pct.sort_values().head(180).iloc[[0,100,120,125,130,170]].tolist())
print(b[b.mold_temp==0].line.value_counts())
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b['d']=pd.to_datetime(b.production_date)
x=b[(b.mold_temp>100)&(b.line=='L1')]
print(x.groupby(x.d.dt.to_period('M')).mold_temp.agg(['median','count']))
y=x[(x.d>'2025-04-01')&(x.d<'2025-04-30')];print(y.groupby('d').mold_temp.median().to_string())
y=x[(x.d>'2025-09-10')];print(y.groupby('d').mold_temp.median().to_string())
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
pd.set_option('display.width',250)
b=pd.read_csv('batches.csv').drop_duplicates()
b['d']=pd.to_datetime(b.production_date)
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['sc']=b.supplier_code.str.strip().str.upper()
s=pd.read_csv('suppliers.csv');b=b.merge(s,left_on='sc',right_on='supplier_code',suffixes=('','_s'))
mt=b.mold_temp.where(b.mold_temp>100)
mt=mt.where(b.line!='L3',(mt-32)*5/9)
mt=mt.where(~((b.line=='L1')&(b.d>='2025-04-14')),mt-8)
b['mt']=mt
print('A4',mt.median(), mt.isna().sum())
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
print('A2',b.hum.isna().sum())
print('A3',b.defective_units.sum()/b.units_produced.sum())
b['rate']=b.defective_units/b.units_produced
m=pd.read_csv('maintenance.csv');m=m[m.event=='mold_cleaning'];m['date']=pd.to_datetime(m.date)
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.d)].date.max(); return (r.d-c).days
b['ds']=b.apply(ds,axis=1)
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
print(b.ds.describe())
print(b.groupby(pd.cut(b.ds,[-1,0,2,4,6,8,10,12,14,16,20,30,60])).rate.agg(['mean','count']))
print(b.groupby('name' if 0 else 'supplier_name').rate.mean())
print(b.groupby(['line',b.d.dt.to_period('M')]).rate.mean().unstack(0).round(4))
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['mtf']=b.mt.fillna(b.mt.median()); b['mtm']=b.mt.isna()*1
b['hf']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna()*1
b['fail']=b.units_produced-b.defective_units
b['h2']=(b.hf-30)**2/100; b['m2']=(b.mtf-211)**2/100
b['dsc']=b.ds
f='defective_units + fail ~ mtf+m2+hf+h2+hm+mtm+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(supplier_name)+ds+C(line)'
r=smf.glm(f,b,family=sm.families.Binomial()).fit()
print(r.summary().tables[1])
E
python3 -I $TMPDIR/f.py

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['fail']=b.units_produced-b.defective_units
b['mtf']=b.mt.fillna(b.mt.median())
print(b[['mtf','hum','cycle_time_s','machine_age_years','ambient_temp_c','ds','units_produced']].corr().round(2))
print(b.groupby('shift')[['mtf','hum','cycle_time_s','ambient_temp_c','rate']].mean())
print(b.groupby('line')[['mtf','hum','cycle_time_s','machine_age_years','ambient_temp_c','rate']].mean())
print(b.groupby('supplier_name')[['mtf','hum','cycle_time_s','ambient_temp_c','rate']].mean())
print(pd.crosstab(b.operator_id,b.line).iloc[:,:].T.to_string())
print(pd.crosstab(b.line,b.supplier_name))
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['fail']=b.units_produced-b.defective_units
b['mtf']=b.mt.fillna(b.mt.median()); b['hf']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna()*1
b['m2']=(b.mtf-211)**2/100;b['h2']=(b.hf-30)**2/100
base='defective_units + fail ~ mtf+m2+hf+h2+hm+cycle_time_s+ambient_temp_c+machine_age_years+ds+C(shift)+C(supplier_name)'
def fit(f,**k): return smf.glm(f,b,family=sm.families.Binomial()).fit(scale='X2')
r0=fit(base+'+C(line)')
print(r0.scale)
b['res']=(b.defective_units-r0.predict(b)*b.units_produced)/b.units_produced
r1=fit(base)  # no line
b['res1']=(b.defective_units-r1.predict(b)*b.units_produced)/b.units_produced
b['wk']=b.d.dt.to_period('M')
print(b.groupby(['wk','line']).res.mean().unstack().round(4))
print(b.groupby(['wk','line']).res1.mean().unstack().round(4))
ro=fit(base+'+C(line)+C(operator_id)')
print(ro.compare_lr_test(r0) if hasattr(ro,'compare_lr_test') else '')
from scipy import stats
print('op test', (r0.deviance-ro.deviance)/ro.scale, 'df',r0.df_resid-ro.df_resid)
E
python3 -I $TMPDIR/h.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['fail']=b.units_produced-b.defective_units
b['mtf']=b.mt.fillna(b.mt.median()); b['hf']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna()*1
b['m2']=(b.mtf-211)**2/100;b['h2']=(b.hf-30)**2/100
base='defective_units + fail ~ mtf+m2+hf+h2+hm+cycle_time_s+ambient_temp_c+ds+C(shift)+C(supplier_name)+C(line)'
for L in ['L2','L4','L1','L3']:
  out=[]
  for dt in pd.date_range('2025-02-01','2025-09-10',freq='D'):
    b['p']=((b.line==L)&(b.d>=dt))*1
    r=smf.glm(base+'+p',b,family=sm.families.Binomial()).fit()
    out.append((r.llf,dt,r.params['p']))
  o=max(out);print(L,o[1].date(),o[2],o[0]-smf.glm(base,b,family=sm.families.Binomial()).fit().llf)
  if L=='L2':
    for x in sorted(out,reverse=True)[:6]:print(x[1].date(),x[0])
E
python3 -I $TMPDIR/i.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/j.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['fail']=b.units_produced-b.defective_units
b['mtf']=b.mt.fillna(b.mt.median()); b['hf']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna()*1
b['p']=((b.line=='L2')&(b.d>='2025-06-16'))*1
b['m2']=(b.mtf-211)**2/100;b['h2']=(b.hf-30)**2/100
b['al']=(b.supplier_name=='Alpha')*1
def fit(f): return smf.glm(f,b,family=sm.families.Binomial()).fit()
base='defective_units + fail ~ mtf+m2+hf+h2+hm+cycle_time_s+ambient_temp_c+machine_age_years+ds+C(shift)+C(supplier_name)+C(line)+p'
r=fit(base);print(r.params.round(4).to_string(),r.llf)
# interactions humidity with supplier
r2=fit(base+'+hf:al+h2:al');print(r2.params[['hf:al','h2:al']],r2.llf)
for t in ['mtf:ds','C(supplier_name):ds','C(line):ds','I(ds**2)','C(line):mtf','C(shift):hf','mtf:ambient_temp_c']:
  print(t,fit(base+'+'+t).llf-r.llf)
ro=fit(base+'+C(operator_id)');print('op',2*(ro.llf-r.llf))
# model-wise: ambient vs mold
print(fit(base.replace('+ambient_temp_c','')).llf-r.llf)
print(fit(base.replace('+mtf+m2','')).llf-r.llf)
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_oj1doe_j; cat >> $TMPDIR/j.py <<'E'
print('-----')
base2='defective_units + fail ~ mtf+m2+hm+cycle_time_s+machine_age_years+ds+C(shift)+C(supplier_name)+C(line)+p'
r3=fit(base2+'+(hf+h2):C(supplier_name)');print(r3.params.round(4).to_string(),r3.llf)
for t in ['C(operator_id)','ambient_temp_c','hf:ds','hm:al','hf:mtf','I(hf**3):al']:
  rr=fit(base2+'+(hf+h2):C(supplier_name)+'+t);print(t,rr.llf-r3.llf)
ro=fit(base2+'+(hf+h2):C(supplier_name)+C(operator_id)');print(ro.params.filter(like='operator').round(3).to_string())
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v Warn | sed -n '/-----/,$p'

cd /tmp/edabench_claude_oj1doe_j; cat >> $TMPDIR/j.py <<'E'
print('=====')
print('disp',r3.pearson_chi2/r3.df_resid)
b['res']=b.defective_units-r3.predict(b)*b.units_produced
# nonparam humidity per supplier: fit with humidity bins
b['hb']=pd.cut(b.hum,[-1,5,10,15,20,25,30,35,40,45,50,60,80])
rb=fit('defective_units + fail ~ mtf+m2+hm+cycle_time_s+ds+C(shift)+C(line)+p+C(supplier_name)*C(hb)')
for s in ['Alpha','Beta','Gamma']:
  x=b[(b.supplier_name==s)&b.hum.notna()]
  g=x.groupby('hb',observed=True).agg(d=('defective_units','sum'),u=('units_produced','sum'),n=('d','size'));g['r']=g.d/g.u;print(s);print(g.r.round(4).to_string())
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v Warn | sed -n '/=====/,$p'

cd /tmp/edabench_claude_oj1doe_j; cat >> $TMPDIR/j.py <<'E'
print('#####')
a=b[(b.supplier_name=='Alpha')&b.hum.notna()].copy()
cov='mtf+m2+cycle_time_s+ds+C(shift)+C(line)+p'
for name,term in [('quad','hum+I(hum**2)'),('cubic','hum+I(hum**2)+I(hum**3)'),('quartic','hum+I(hum**2)+I(hum**3)+I(hum**4)'),('spline','bs(hum,df=5)'),('spline7','bs(hum,df=7)')]:
  rr=smf.glm('defective_units + fail ~ '+cov+'+'+term,a,family=sm.families.Binomial()).fit()
  grid=pd.DataFrame({'hum':np.arange(10,72,0.5)})
  for c in ['mtf','m2','cycle_time_s','ds']: grid[c]=a[c].mean()
  grid['shift']='Day';grid['line']='L1';grid['p']=0
  pr=rr.predict(grid);print(name,grid.hum[pr.argmin()],rr.llf)
  if name=='spline': print(pd.Series(pr.values,grid.hum).iloc[::6].round(4).to_string())
# piecewise: V-shape
best=None
for k in np.arange(25,50,1.0):
  a['u']=np.maximum(a.hum-k,0);a['l']=np.maximum(k-a.hum,0)
  rr=smf.glm('defective_units + fail ~ '+cov+'+u+l',a,family=sm.families.Binomial()).fit();print(k,round(rr.llf,1)) if k%3==0 else 0
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v Warn | sed -n '/#####/,$p'

cd /tmp/edabench_claude_oj1doe_j; cat > $TMPDIR/k.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['fail']=b.units_produced-b.defective_units
b['mtf']=b.mt.fillna(b.mt.median()); b['hf']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna()*1
b['p']=((b.line=='L2')&(b.d>='2025-06-16'))*1
b['m2']=(b.mtf-211)**2/100;b['h2']=(b.hf-30)**2/100
def fit(f): return smf.glm(f,b,family=sm.families.Binomial()).fit()
f='defective_units + fail ~ mtf+m2+hm+cycle_time_s+machine_age_years+ds+C(shift)+C(supplier_name)+C(line)+p+(hf+h2):C(supplier_name)'
r=fit(f)
tot=lambda x,pr:(pr*x.units_produced).sum()/x.units_produced.sum()
print('fitted',tot(b,r.predict(b)),'actual',b.defective_units.sum()/b.units_produced.sum())
for s in ['Alpha','Beta','Gamma']:
  x=b.copy();x['supplier_name']=s;print(s,tot(x,r.predict(x)))
x=b.copy();x['ds']=np.where(x.ds>=14,x.ds%14,x.ds);pr=r.predict(x)
print('C3 model',tot(x,pr))
# ratio-adjusted: actual * pred_new/pred_old
po=r.predict(b);print('C3 scaled',(b.defective_units.sum())*(pr*x.units_produced).sum()/(po*b.units_produced).sum()/b.units_produced.sum())
# alt: cap at 13 / piecewise
for cap in [lambda d:np.minimum(d,14),lambda d:np.minimum(d,13)]:
  x=b.copy();x['ds']=cap(x.ds);print(tot(x,r.predict(x)))
# check ds shape nonparam
b['dsb']=pd.cut(b.ds,[-1,3,7,10,13,16,20,25,40])
r2=fit(f.replace('+ds+','+C(dsb)+'));print(r2.params.filter(like='dsb').round(3).to_string(),r2.llf-r.llf)
E
python3 -I $TMPDIR/k.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_oj1doe_j; cat >> $TMPDIR/k.py <<'E'
print('----')
for edges in ([-1,3,7,10,13,16,20,25,40],[-1,1,3,5,7,9,11,13,16,20,25,40]):
  b['dsb']=pd.cut(b.ds,edges)
  r2=fit(f.replace('+ds+','+C(dsb)+'))
  x=b.copy();x['ds']=np.where(x.ds>=14,x.ds%14,x.ds);x['dsb']=pd.cut(x.ds,edges)
  print(tot(x,r2.predict(x)))
b['dq']=b.ds;b['dq2']=b.ds**2
r3=fit(f.replace('+ds+','+ds+dq2+'));x=b.copy();x['ds']=np.where(x.ds>=14,x.ds%14,x.ds);x['dq2']=x.ds**2;print('quad',tot(x,r3.predict(x)),r3.params[['ds','dq2']].tolist())
E
python3 -I $TMPDIR/k.py 2>&1 | grep -v Warn | sed -n '/----/,$p'
