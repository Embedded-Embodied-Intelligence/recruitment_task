cd /tmp/edabench_claude_tk48j3g_; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv');print(b.dtypes);print(b.describe(include='all').T.to_string())
for c in ['shift','line','operator_id','supplier_code']:print(b[c].value_counts(dropna=False))
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
print(b.humidity_pct.astype(str).value_counts().head(8))
print(pd.read_csv('maintenance.csv').event.value_counts())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.is_unique)
b['sh']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
print((b.humidity_pct.isna()|(b.humidity_pct<0)).sum(), b.humidity_pct.max())
print(np.histogram(b.mold_temp,bins=[-1,0.5,100,150,200,250,300,350,400,500]))
print(b[b.mold_temp>300].mold_temp.describe(), b[b.mold_temp>300].line.value_counts())
print(pd.read_csv('maintenance.csv').query("event!='mold_cleaning'"))
print(b.groupby('line').mold_temp.median())
print(b[b.mold_temp<100].mold_temp.value_counts().head())
print(b.units_produced.sort_values().tail(5).tolist(), b.qc_inspection_min.sort_values().tail(5).tolist())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_tk48j3g_; python3 -c "
import pandas as pd
pd.set_option('display.max_colwidth',300,'display.width',300)
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning'].to_string())
b=pd.read_csv('batches.csv').drop_duplicates()
l=b[b.line=='L3'];print(l.groupby(l.production_date.str[:7]).mold_temp.agg(['median','min','max']))
for n,g in b.groupby('line'):print(n,g[g.mold_temp==0].production_date.agg(['min','max','count']).tolist())
"

cd /tmp/edabench_claude_tk48j3g_; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv').drop_duplicates()
b=b[b.mold_temp>0]
b['t']=b.mold_temp.where(b.line!='L3',(b.mold_temp-32)/1.8)
b['m']=b.production_date.str[:7]
print(b.pivot_table(index='m',columns='line',values='t',aggfunc='median'))
l=b[b.line=='L1'].copy();l['w']=l.production_date.str[:7]+l.production_date.str[8:].astype(int).floordiv(10).astype(str)
print(l.groupby('w').t.median().to_string())
"

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b['sh']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['date']=pd.to_datetime(b.production_date)
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)/1.8
b.loc[(b.line=='L1')&(b.date>='2025-04-14'),'mt']-=8
print(b.mt.median(), b.defective_units.sum()/b.units_produced.sum(), b.hum.isna().sum())
b['r']=b.defective_units/b.units_produced
print(b[b.line=='L1'].groupby(b.date.dt.to_period('M')).mt.median())
b.to_pickle('b.pkl')
E
python3 -I $TMPDIR/p.py

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/m.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def dsc(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
b['dsc']=b.apply(dsc,axis=1)
print(b.dsc.describe(), b.dsc.isna().sum())
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210
b['mt2']=b.mtc**2
print(b[['mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','dsc','r']].corr().round(2))
d=b.dropna(subset=['hum','mt']).copy()
f='good+defective_units~mtc+mt2+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+sh+C(sup)+dsc+C(line)'
r=smf.glm(f,d,family=sm.families.Binomial()).fit()
print(r.summary().tables[1])
b.to_pickle('b2.pkl')
E
python3 -I $TMPDIR/m.py

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/m2.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['alpha']=(b.sup=='SP-01')
b['mtc']=b.mt-210
d=b.dropna(subset=['hum','mt']).copy()
print(d.groupby('sup').hum.mean(), d.groupby('line').machine_age_years.mean(), pd.crosstab(d.operator_id,d.line).head(30))
def fit(f,dd=d):
    r=smf.glm(f,dd,family=sm.families.Binomial()).fit(scale='X')
    return r
f='defective_units+good~mtc+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+sh+C(sup)+dsc+C(line)'
r=fit(f);print(r.scale);print(r.summary().tables[1])
E
python3 -I $TMPDIR/m2.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/m2.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['mtc']=b.mt-210
d=b.dropna(subset=['hum','mt']).copy()
print(d.groupby('line').machine_age_years.describe())
def fit(f,dd=d):
    return smf.glm(f,dd,family=sm.families.Binomial()).fit(scale='x2')
f='defective_units+good~mtc+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+sh+C(sup)+dsc'
r=fit(f);print(r.scale);print(r.summary().tables[1])
E
python3 -I $TMPDIR/m2.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/m3.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['mtc']=b.mt-210
d=b.dropna(subset=['hum','mt']).copy()
base='mtc+hum+I(hum**2)+cycle_time_s+ambient_temp_c+sh+C(sup)+dsc+C(line)'
def fit(f,dd=d):
    return smf.glm('defective_units+good~'+f,dd,family=sm.families.Binomial()).fit(scale='x2')
r0=fit(base);print(r0.scale, r0.deviance, r0.df_resid)
for add in ['machine_age_years','C(operator_id)']:
    r=fit(base+'+'+add);print(add,r.deviance,r.df_resid);print(r.params.filter(like=add[:6]).round(3).to_dict());print(r.pvalues.filter(like=add[:6]).round(3).max())
r=fit(base+'+C(sup):hum+C(sup):I(hum**2)');print(r.deviance,r.params.filter(like='hum').round(4))
# residual by line / time
d['res']=r0.resid_pearson/ (r0.scale**.5)
print(d.groupby(['line',d.date.dt.to_period('M')]).res.mean().unstack(0).round(2))
E
python3 -I $TMPDIR/m3.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b2.pkl')
def tab(col,bins,by=None):
    g=pd.cut(b[col],bins)
    k=[g] if by is None else [g,b[by]]
    t=b.groupby(k,observed=True).agg(d=('defective_units','sum'),u=('units_produced','sum'))
    t['r']=t.d/t.u
    print(t.r.unstack().round(4) if by else t.r.round(4).to_string())
tab('hum',[0,5,10,15,20,25,30,35,40,45,50,55,60,80],'sup')
tab('mt',[150,200,205,210,215,220,225,230,240,300])
tab('cycle_time_s',[15,24,26,28,30,32,34,36,50])
tab('ambient_temp_c',[10,14,18,22,26,31])
tab('dsc',[-1,2,5,8,11,14,17,20,40])
tab('machine_age_years',[0,3,5,7,9,12,16,25])
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/m4.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['hum','mt']).copy()
base='bs(mt,df=4)+bs(cycle_time_s,df=3)+bs(ambient_temp_c,df=3)+sh+C(sup)*bs(hum,df=5)+bs(dsc,df=5)+C(line)+machine_age_years'
def fit(f,dd):
    return smf.glm('defective_units+good~'+f,dd,family=sm.families.Binomial()).fit()
r0=fit(base,d);print(r0.deviance,r0.df_resid,r0.pearson_chi2)
d['res']=r0.resid_deviance
w=d[d.line=='L2'].sort_values('date');w['rm']=w.res.rolling(30).mean()
print(w.groupby(w.date.dt.to_period('W')).res.mean().round(2).to_string())
E
python3 -I $TMPDIR/m4.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tk48j3g_; cat >> $TMPDIR/m4.py <<'E'
x=w[(w.date>='2025-06-10')&(w.date<='2025-06-22')].groupby('date').res.mean().round(2);print(x)
best=None
for dt in pd.date_range('2025-06-10','2025-06-22'):
    dd=d.copy();dd['post']=((dd.line=='L2')&(dd.date>=dt)).astype(int)
    r=fit(base+'+post',dd);print(dt.date(),round(r.deviance,1),round(r.params['post'],3))
E
python3 -I $TMPDIR/m4.py 2>&1 | grep -v Warn | tail -32

cd /tmp/edabench_claude_tk48j3g_; cat >> $TMPDIR/m4.py <<'E'
print('----')
dd=d.copy();dd['post']=((dd.line=='L2')&(dd.date>='2025-06-16')).astype(int)
r=fit(base+'+post',dd);dd['res']=r.resid_deviance
print(dd[(dd.line=='L2')&(dd.date>='2025-06-12')&(dd.date<='2025-06-18')][['date','res','r']].to_string())
print(r.deviance, r.df_resid)
print(dd.groupby(['line',dd.date.dt.to_period('M')]).res.mean().unstack(0).round(2))
E
python3 -I $TMPDIR/m4.py 2>&1 | grep -v Warn | sed -n '/----/,$p'

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/m5.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['hum','mt']).copy()
d['post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
full='bs(mt,df=4)+bs(cycle_time_s,df=3)+bs(ambient_temp_c,df=3)+sh+C(sup)*bs(hum,df=5)+bs(dsc,df=5)+C(line)+machine_age_years+post+C(operator_id)'
def fit(f,dd=d):
    return smf.glm('defective_units+good~'+f,dd,family=sm.families.Binomial()).fit()
r=fit(full);print(r.deviance,r.df_resid,r.pearson_chi2)
terms=['bs(mt,df=4)','bs(cycle_time_s,df=3)','bs(ambient_temp_c,df=3)','sh','machine_age_years','C(operator_id)','C(line)']
for t in terms:
    f=full.replace('+'+t,'',1) if '+'+t in full else full
    if t=='C(line)': f=full.replace('C(line)+','')  # operator absorbs
    r2=fit(f);print(t,round(r2.deviance-r.deviance,1),r.df_resid-r2.df_resid)
print(r.params[['machine_age_years','sh[T.N]']],r.bse[['machine_age_years']])
E
python3 -I $TMPDIR/m5.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/m6.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle('b2.pkl')
d=b.dropna(subset=['hum','mt']).copy()
d['post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
T=['bs(mt,df=4)','bs(cycle_time_s,df=3)','bs(ambient_temp_c,df=3)','sh','C(sup)*bs(hum,df=5)','bs(dsc,df=5)','C(line)','machine_age_years','post','C(operator_id)']
def fit(ts):
    return smf.glm('defective_units+good~'+'+'.join(ts),d,family=sm.families.Binomial()).fit()
r=fit(T);phi=r.pearson_chi2/r.df_resid
for t in T:
    r2=fit([x for x in T if x!=t])
    k=r.df_model-r2.df_model;F=(r2.deviance-r.deviance)/k/phi
    print(t,round(F,2),k,stats.f.sf(F,k,r.df_resid))
E
python3 -I $TMPDIR/m6.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_tk48j3g_; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['post']=((b.line=='L2')&(b.date>='2025-06-15')).astype(int)
d=b.dropna(subset=['hum','mt']).copy()
f='defective_units+good~bs(mt,df=4)+bs(cycle_time_s,df=3)+sh+C(sup)*bs(hum,df=5)+bs(dsc,df=5)+C(line)+post'
r=smf.glm(f,d,family=sm.families.Binomial()).fit()
print(r.deviance/r.df_resid)
# C1
for s in ['SP-01','SP-02','SP-03']:
    x=d.copy();x['sup']=s;p=r.predict(x);print(s,(p*x.units_produced).sum()/x.units_produced.sum())
print('actual',d.defective_units.sum()/d.units_produced.sum())
# C2
a=d[d.sup=='SP-01'].copy()
for h in np.arange(20,56,1.0):
    x=a.copy();x['hum']=h;p=r.predict(x);print(h,round((p*x.units_produced).sum()/x.units_produced.sum(),5))
# C3
bb=b.copy();bb['hum']=bb.hum.fillna(d.hum.median());bb['mt']=bb.mt.fillna(d.mt.median())
p0=r.predict(bb);x=bb.copy();x['dsc']=x.dsc%14;p1=r.predict(x)
exp=(bb.defective_units*p1/p0).sum()/bb.units_produced.sum();print('C3',exp,(bb.dsc>=14).sum())
x['dsc']=bb.dsc.clip(upper=13);p2=r.predict(x);print('C3 cap',(bb.defective_units*p2/p0).sum()/bb.units_produced.sum())
E
python3 -I $TMPDIR/f.py 2>&1 | grep -v -i warn
