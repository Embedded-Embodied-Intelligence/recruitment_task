cd /tmp/edabench_claude_6ltz992a; ls; for f in *.csv; do echo == $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.shape,b.batch_id.nunique())
for c in ['production_date','line','shift','operator_id','supplier_code']:
    print(b[c].value_counts(dropna=False).head(30))
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    n=pd.to_numeric(b[c],errors='coerce')
    print(c,n.isna().sum(),n.describe().to_dict(), b[c][n.isna()].unique()[:10])
d=b[b.duplicated('batch_id',keep=False)].sort_values('batch_id');print(d.head(10).to_string())
print(len(d))
E
python3 -I $TMPDIR/a.py; cat suppliers.csv; cat maintenance.csv | awk -F, '{print $3,$4}' | sort | uniq -c

cd /tmp/edabench_claude_6ltz992a; grep -v ",mold_cleaning," maintenance.csv; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.nunique())
print(b.mold_temp.describe()); print((b.mold_temp==0).sum(),(b.mold_temp>300).sum())
print(b.groupby('line').mold_temp.describe())
print(b[b.mold_temp<100].mold_temp.value_counts().head())
print(b[b.mold_temp>300].groupby('line').size(), b[b.mold_temp>300].mold_temp.describe())
print((b.humidity_pct<0).sum(), b.humidity_pct.isna().sum(), b[b.humidity_pct<0].humidity_pct.unique(), b.humidity_pct.max())
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b['date']=pd.to_datetime(b.production_date)
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp); b.loc[b.mold_temp==0,'mt']=np.nan
print(b.groupby('line').mt.median())
l=b[b.line=='L1'].set_index('date').mt.resample('2W').agg(['median','count']);print(l)
print(b.groupby('line').apply(lambda g:g.set_index('date').mt.resample('M').median()).unstack(0))
print(b[b.mold_temp==0].line.value_counts())
bad=b.humidity_pct.isna()|(b.humidity_pct<0);print(bad.sum())
print(b.defective_units.sum()/b.units_produced.sum())
E
python3 -I $TMPDIR/c.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b['date']=pd.to_datetime(b.production_date)
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp); b.loc[b.mold_temp==0,'mt']=np.nan
b['wk']=b.date.dt.to_period('W')
t=b.groupby(['wk','line']).mt.median().unstack()
t['amb']=b.groupby('wk').ambient_temp_c.mean()
print(t.loc['2025-03-17':'2025-06-09'].round(1))
print(t.loc['2025-08-25':].round(1))
E
python3 -I $TMPDIR/c.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np
import statsmodels.formula.api as smf
b=pd.read_csv('batches.csv').drop_duplicates()
b['date']=pd.to_datetime(b.production_date)
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp); b.loc[b.mold_temp==0,'mt']=np.nan
b.loc[(b.line=='L1')&(b.date>='2025-04-14'),'mt']-=8
print('median',b.mt.median(), b.mt.notna().sum())
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['sup']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['rate']=b.defective_units/b.units_produced
print(b.defective_units.sum()/b.units_produced.sum())
print(b.groupby('line').apply(lambda g:g.set_index('date').rate.resample('MS').mean()).T.round(4))
print(b.groupby('sup').rate.mean(), b.groupby('shift').rate.mean())
# days since cleaning
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def ds(r):
    d=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-d.max()).days if len(d) else np.nan
b['dsc']=b.apply(ds,axis=1)
print(b.dsc.describe(), b.dsc.isna().sum())
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
print(b.groupby(pd.cut(b.dsc,[-1,3,7,10,14,18,25,40,100])).rate.agg(['mean','count']))
E
python3 -I $TMPDIR/d.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['ok']=b.units_produced-b.defective_units
b['mt2']=(b.mt-211)**2
b['dscc']=np.minimum(b.dsc,100)
b['over']=np.maximum(b.dsc-14,0)
d=b.dropna(subset=['mt','hum']).copy()
d['hum2']=d.hum**2
f='rate~mt+mt2+hum+hum2+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)+dsc+over+qc_inspection_min'
r=smf.glm('I(defective_units/units_produced)~mt+mt2+hum+hum2+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)+dsc+over',d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit(scale='X2' if False else None)
print(r.summary().tables[1])
E
python3 -I $TMPDIR/e.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
print(b.groupby('line').machine_age_years.describe())
print(b.groupby('line')[['ambient_temp_c','cycle_time_s','hum','mt']].mean())
print(b[['ambient_temp_c','hum','mt','cycle_time_s','machine_age_years','dsc','qc_inspection_min']].corr().round(2))
print(pd.crosstab(b.sup,b.line,normalize='columns').round(2))
print(b.groupby('sup').hum.mean(), b.groupby('shift')[['hum','mt','cycle_time_s','ambient_temp_c']].mean())
print(b.groupby('sup').apply(lambda g:g.groupby(pd.cut(g.hum,[0,10,20,30,40,50,80])).rate.mean()).round(3))
E
python3 -I $TMPDIR/e.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['mt2']=(b.mt-211)**2
d=b.dropna(subset=['mt','hum']).copy()
d['y']=d.defective_units/d.units_produced
d['h']=(d.hum-30)/10; d['age']=d.machine_age_years
def fit(f,dd=d):
    return smf.glm(f,dd,family=sm.families.Binomial(),freq_weights=dd.units_produced).fit(scale='X2')
r=fit('y~mt+mt2+C(sup)*(h+I(h**2))+cycle_time_s+age+ambient_temp_c+C(shift)+C(line)+dsc+I(np.maximum(dsc-14,0))')
print(r.summary().tables[1]); print(r.scale)
r=fit('y~mt+mt2+C(sup)*(h+I(h**2))+cycle_time_s+age+ambient_temp_c+C(shift)+dsc+I(np.maximum(dsc-14,0))+C(line,Treatment("L1"))',d[d.line!='L4'])
print(r.params.round(3))
r=fit('y~mt+mt2+C(sup)*(h+I(h**2))+cycle_time_s+age+ambient_temp_c+C(shift)+dsc',d[d.line=='L4'])
print(r.params.round(3),r.bse.round(3))
E
python3 -I $TMPDIR/e.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
d=b.dropna(subset=['mt','hum']).copy()
d['y']=d.defective_units/d.units_produced
d['h']=d.hum; d['age']=d.machine_age_years
d['pre']=(d.sup!='SP-01').astype(int)
def fit(f,dd=d):
    return smf.glm(f,dd,family=sm.families.Binomial(),freq_weights=dd.units_produced).fit(scale='X2')
f='y~bs(mt,df=4)+C(sup)*bs(h,df=5)+cycle_time_s+age+ambient_temp_c+C(shift)+C(line)+dsc+I(np.maximum(dsc-14,0))'
r=fit(f)
d['res']=d.y-r.predict(d)
d['wk']=d.date.dt.to_period('2W')
print(d.pivot_table(index='wk',columns='line',values='res',aggfunc='mean').round(4))
print(r.deviance/r.df_resid, r.scale)
E
python3 -I $TMPDIR/e.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat >> $TMPDIR/e.py <<'E'
g=d[d.line=='L2'].sort_values('date')
print(g[(g.date>='2025-06-08')&(g.date<='2025-06-22')].groupby('date').res.agg(['mean','count']).round(4))
best=[]
for t in sorted(g.date.unique()):
    a=g[g.date<t].res;c=g[g.date>=t].res
    if len(a)>30 and len(c)>30: best.append((((a-a.mean())**2).sum()+((c-c.mean())**2).sum(),t))
print(sorted(best)[:3])
E
python3 -I $TMPDIR/e.py 2>&1|tail -22

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['reg']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
d=b.dropna(subset=['mt','hum']).copy()
d['y']=d.defective_units/d.units_produced
d['h']=d.hum; d['age']=d.machine_age_years
def fit(f,dd=d):
    return smf.glm(f,dd,family=sm.families.Binomial(),freq_weights=dd.units_produced).fit(scale='X2')
base='y~bs(mt,df=4)+C(sup)*bs(h,df=5)+cycle_time_s+age+ambient_temp_c+C(shift)+C(line)+reg+dsc+I(np.maximum(dsc-14,0))'
r=fit(base);print(r.params.filter(regex='^(?!.*bs)').round(4));print(r.bse.filter(regex='^(?!.*bs)').round(4));print(r.scale)
for drop in ['cycle_time_s','age','ambient_temp_c','C(shift)']:
    r2=fit(base.replace('+'+drop,''))
    print(drop, r2.deviance-r.deviance)  # scaled test
r3=fit(base+'+C(operator_id)')
print('oper',(r.deviance-r3.deviance)/r.scale, 23)
r4=fit(base.replace('+age','')+'+age:C(line)'); 
print(r4.params.filter(regex='age'),r4.bse.filter(regex='age'))
r5=fit(base+'+qc_inspection_min');print(r5.params['qc_inspection_min'])
E
python3 -I $TMPDIR/f.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['reg']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
d=b.dropna(subset=['mt','hum']).copy()
d['ok']=d.units_produced-d.defective_units; d['bad']=d.defective_units
d['h']=d.hum; d['age']=d.machine_age_years; d['od']=np.maximum(d.dsc-14,0)
def fit(f,dd=d):
    return smf.glm('I(bad)+I(ok)~'.replace('I(bad)+I(ok)','bad+ok')+f,dd,family=sm.families.Binomial()).fit(scale='X2')
base='bs(mt,df=4)+C(sup)*bs(h,df=5)+cycle_time_s+age+ambient_temp_c+C(shift)+C(line)+reg+dsc+od'
r=fit(base);print(r.scale)
print(pd.DataFrame({'b':r.params,'t':r.tvalues}).filter(regex='^(?!.*bs)',axis=0).round(3).loc[lambda x:~x.index.str.contains('bs\\(')])
for drop in ['cycle_time_s','age','ambient_temp_c','C(shift)','od']:
    r2=fit(base.replace('+'+drop,''))
    dd=(r2.deviance-r.deviance)/r.scale; print(drop,dd,stats.chi2.sf(dd,1))
r3=fit(base+'+C(operator_id)');dd=(r.deviance-r3.deviance)/r.scale;print('oper',dd,stats.chi2.sf(dd,23))
r3=fit(base+'+C(sup)*C(shift)');dd=(r.deviance-r3.deviance)/r.scale;print('sup:shift',dd)
E
python3 -I $TMPDIR/f.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; python3 - <<'E'
import re,os
p=os.environ['TMPDIR']+'/f.py'
s=open(p).read()
s=s.replace("""    return smf.glm('I(bad)+I(ok)~'.replace('I(bad)+I(ok)','bad+ok')+f,dd,family=sm.families.Binomial()).fit(scale='X2')""","""    import patsy
    y,X=patsy.dmatrices('I(bad/units_produced)~'+f,dd,return_type='dataframe')
    return sm.GLM(y.iloc[:,0],X,family=sm.families.Binomial(),var_weights=dd.units_produced.values).fit(scale='X2')""")
open(p,'w').write(s)
E
python3 -I $TMPDIR/f.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat >> $TMPDIR/f.py <<'E'
print('---- dsc shape')
sp='bs(mt,df=4)+C(sup)*bs(h,df=5)+cycle_time_s+C(shift)+C(line)+reg+'
for dsf in ['dsc','dsc+od','bs(dsc,df=5)','C(np.minimum(dsc,30)//3)']:
    r=fit(sp+dsf); print(dsf,r.deviance, r.scale)
rs=fit(sp+'bs(dsc,df=5)')
t=d.copy()
for k in [0,2,5,8,11,13,14,16,20,25,30]:
    t['dsc']=k; t['od']=0
    import patsy
    X=patsy.build_design_matrices([rs.model.data.design_info],t)[0]
    print(k, np.average(rs.predict(X),weights=t.units_produced).round(4))
E
python3 -I $TMPDIR/f.py 2>&1|sed -n '/----/,$p'

cd /tmp/edabench_claude_6ltz992a; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,os,patsy
import statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['reg']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['h']=b.hum; b['y']=b.defective_units/b.units_produced
d=b.dropna(subset=['mt','h']).copy()
f='bs(mt,df=4,include_intercept=False)+C(sup)*bs(h,df=6)+cycle_time_s+C(shift)+C(line)+reg+dsc'
y,X=patsy.dmatrices('y~'+f,d,return_type='dataframe')
r=sm.GLM(y.iloc[:,0],X,family=sm.families.Binomial(),var_weights=d.units_produced.values).fit(scale='X2')
di=X.design_info
def pred(df): 
    return r.predict(patsy.build_design_matrices([di],df,return_type='dataframe')[0])
# C1
for s in ['SP-01','SP-02','SP-03']:
    t=d.copy();t['sup']=s;p=pred(t);print(s,(p*t.units_produced).sum()/t.units_produced.sum())
print('actual pred',(pred(d)*d.units_produced).sum()/d.units_produced.sum(), d.defective_units.sum()/d.units_produced.sum())
# C2
a=d[d.sup=='SP-01']
for s in ['SP-01','SP-02','SP-03']:
    g=np.arange(d.h.min(),d.h.max()+.01,1.0)
    out=[]
    for hv in g:
        t=d[d.sup==s].copy();t['h']=hv;p=pred(t);out.append((p*t.units_produced).sum()/t.units_produced.sum())
    print(s,g[np.argmin(out)],np.round(out[::5],4))
print(d.h.min(),d.h.max())
# C3 on all 3000 using imputed covariates for ratios
A=b.copy()
A['mt']=A.mt.fillna(A.groupby('line').mt.transform('median')); A['h']=A.h.fillna(A.groupby('sup').h.transform('median'))
p0=pred(A); B=A.copy(); B['dsc']=np.where(B.dsc>=14,B.dsc%14,B.dsc); p1=pred(B)
exp_def=A.defective_units*(p1/p0)
print('C3',exp_def.sum()/A.units_produced.sum(), (A.dsc>=14).sum(), (A.dsc>14).sum())
B['dsc']=np.where(A.dsc>14,A.dsc%14,A.dsc);print('C3b',(A.defective_units*pred(B)/p0).sum()/A.units_produced.sum())
print(r.params['dsc'])
E
python3 -I $TMPDIR/g.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_6ltz992a; cat >> $TMPDIR/g.py <<'E'
a=d[d.sup=='SP-01']
for f2 in ['bs(mt,df=4)+h+I(h**2)+cycle_time_s+C(shift)+C(line)+reg+dsc','bs(mt,df=4)+h+I(h**2)+I(h**3)+cycle_time_s+C(shift)+C(line)+reg+dsc']:
    y,X2=patsy.dmatrices('y~'+f2,a,return_type='dataframe')
    r2=sm.GLM(y.iloc[:,0],X2,family=sm.families.Binomial(),var_weights=a.units_produced.values).fit(scale='X2')
    g=np.arange(12.1,72.4,.1);best=None
    cs=r2.params
    z=cs['h']*g+cs['I(h ** 2)']*g**2+(cs['I(h ** 3)']*g**3 if 'I(h ** 3)' in cs else 0)
    print(g[np.argmin(z)], -cs['h']/(2*cs['I(h ** 2)']))
E
python3 -I $TMPDIR/g.py 2>&1|tail -2
