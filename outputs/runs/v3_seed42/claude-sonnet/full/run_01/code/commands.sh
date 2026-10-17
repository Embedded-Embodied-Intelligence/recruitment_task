cd /tmp/edabench_claude_egqz7huo; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv');print(b.dtypes);print(b.describe(include='all').T.to_string())
for c in ['line','shift','operator_id','supplier_code']:print(b[c].value_counts(dropna=False))
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
print(pd.read_csv('maintenance.csv').event.value_counts(), pd.read_csv('suppliers.csv'))
for c in ['humidity_pct','mold_temp','cycle_time_s','units_produced','defective_units']:
    print(c,b[c].sort_values().unique()[:8],b[c].sort_values().unique()[-8:])
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
pd.set_option('display.width',200)
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning']);print(m.groupby('line').date.apply(list).to_string())
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.duplicated().sum())
print(np.histogram(b.mold_temp,bins=[-1,1,150,180,190,250,300,350,400,500]))
print(b[b.mold_temp>300].groupby('line').size(), b[b.mold_temp<1].groupby('line').size())
print(b[b.humidity_pct<=0].shape, b.humidity_pct.isna().sum(), (b.humidity_pct==-1).sum())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
pd.set_option('display.width',250);pd.set_option('display.max_colwidth',200)
m=pd.read_csv('maintenance.csv');print(m[m.event!='mold_cleaning'].to_string())
b=pd.read_csv('batches.csv').drop_duplicates()
l3=b[b.line=='L3'].sort_values('production_date')
print(l3[l3.mold_temp>300].production_date.agg(['min','max']), l3[(l3.mold_temp<300)&(l3.mold_temp>1)].production_date.agg(['min','max']))
print(l3.groupby(l3.mold_temp>300).mold_temp.describe())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
pd.set_option('display.width',250)
b=pd.read_csv('batches.csv').drop_duplicates()
b['d']=pd.to_datetime(b.production_date)
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp);b.loc[b.mold_temp==0,'mt']=np.nan
b['mo']=b.d.dt.to_period('M')
print(b.pivot_table(index='mo',columns='line',values='mt',aggfunc='median'))
x=b[b.line=='L1'].set_index('d').mt.resample('W').median();print(x.loc['2025-03-25':'2025-05-10'])
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np
pd.set_option('display.width',250)
b=pd.read_csv('batches.csv').drop_duplicates()
b['d']=pd.to_datetime(b.production_date)
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp);b.loc[b.mold_temp==0,'mt']=np.nan
b.loc[(b.line=='L1')&(b.d>='2025-04-14'),'mt']-=8
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['sc']=b.supplier_code.str.strip().str.upper()
b['sup']=b.sc.map({'SP-01':'Alpha','SP-02':'Beta','SP-03':'Gamma'})
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['y']=b.defective_units/b.units_produced
m=pd.read_csv('maintenance.csv');m=m[m.event=='mold_cleaning'];m['date']=pd.to_datetime(m.date)
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.d)].date
    return (r.d-c.max()).days
b['since']=b.apply(ds,axis=1)
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
E
python3 -I $TMPDIR/p.py
cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
print(len(b),b.hum.isna().sum(),b.defective_units.sum()/b.units_produced.sum(),b.mt.median())
print(b.since.describe())
print(b.groupby('since').y.mean().round(4).to_string())
print(b[['y','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur','since']].corr().y)
print(b.groupby('sup').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
print(b.groupby('line').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
b['mo']=b.d.dt.to_period('M');print(b.pivot_table(index='mo',columns='line',values='y'))
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210
b['hc']=b.hum-30
b['over']=np.maximum(b.since-14,0)
f='defective_units+good~mtc+I(mtc**2)+hc+I(hc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+C(line)+since+over'
d=b.dropna(subset=['mt','hum'])
r=smf.glm(f,d,family=sm.families.Binomial()).fit()
print(r.summary().tables[1])
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
print(pd.crosstab(b.operator_id,b.line).T.to_string())
print(pd.crosstab(b.sup,b.line))
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210;b['hc']=b.hum-30
d=b.dropna(subset=['mt','hum']).copy()
base='defective_units+good~mtc+hc+I(hc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(sup)*(hc+I(hc**2))+C(line)+since'
terms={'mtc':'mtc+','hc':None,'cycle':'cycle_time_s+','age':'machine_age_years+','amb':'ambient_temp_c+','shift':'C(shift)+'}
def fit(f):return smf.glm(f,d,family=sm.families.Binomial()).fit(scale='X2')
r=fit(base);print(r.summary().tables[1]);print(r.scale)
for name,extra in [('operator','+C(operator_id)')]:
    r2=fit(base+extra);print(name,'dev diff',r.deviance-r2.deviance,'df',r.df_resid-r2.df_resid,'scale',r2.scale)
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210;b['hc']=b.hum-30
d=b.dropna(subset=['mt','hum']).copy()
d['hb']=pd.cut(d.hum,[0,10,15,20,25,30,35,40,45,50,60,80])
f='defective_units+good~C(hb)+mtc+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+since'
for s,g in d.groupby('sup'):
    r=smf.glm(f,g,family=sm.families.Binomial()).fit()
    print(s,len(g));print(r.params.filter(like='hb').round(3).to_string())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210;b['hc']=b.hum-30
d=b.dropna(subset=['mt','hum']).copy()
f='defective_units+good~hc+I(hc**2)+mtc+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+since'
for s,g in d.groupby('sup'):
    r=smf.glm(f,g,family=sm.families.Binomial()).fit()
    a,c=r.params['hc'],r.params['I(hc ** 2)'];print(s,a,c,30-a/(2*c), r.bse[['hc','I(hc ** 2)']].values)
g=d[d.sup=='Alpha']
for deg in (2,3):
    ff=f.replace('I(hc**2)','+'.join(f'I(hc**{k})' for k in range(2,deg+1)))
    r=smf.glm(ff,g,family=sm.families.Binomial()).fit()
    x=np.linspace(g.hum.min(),g.hum.max(),500);X=pd.DataFrame({'hc':x-30})
    p=r.params;eta=sum(p[('hc' if k==1 else f'I(hc ** {k})')]*X.hc**k for k in range(1,deg+1))
    print(deg,x[eta.argmin()],r.aic)
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210;b['hc']=b.hum-30
d=b.dropna(subset=['mt','hum']).copy()
f='defective_units+good~(hc+I(hc**2))*C(sup)+mtc+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+since'
r=smf.glm(f,d,family=sm.families.Binomial()).fit()
d['pred']=r.predict(d)*d.units_produced
d['res']=d.defective_units/d.pred
d['wk']=d.d.dt.to_period('W').dt.start_time
for l,g in d.groupby('line'):
    x=g.groupby(g.d.dt.to_period('M')).apply(lambda t:t.defective_units.sum()/t.pred.sum())
    print(l,x.round(2).to_dict())
    # best single changepoint on log ratio
    g=g.sort_values('d');dates=sorted(g.d.unique())
    best=None
    for dt in dates[10:-10]:
        a=g[g.d<dt];c=g[g.d>=dt]
        ra=a.defective_units.sum()/a.pred.sum();rc=c.defective_units.sum()/c.pred.sum()
        ll=lambda t,k:(t.defective_units.sum()*np.log(k)-k*t.pred.sum())
        s=ll(a,ra)+ll(c,rc)
        if best is None or s>best[0]:best=(s,dt,ra,rc)
    print(best)
for s in ['Alpha','Beta','Gamma']:
    x=d.copy();x['sup']=s;p=r.predict(x)*x.units_produced;print(s,p.sum()/x.units_produced.sum())
x=d.copy();print(r.predict(x).mul(x.units_produced).sum()/x.units_produced.sum(), d.defective_units.sum()/d.units_produced.sum())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210;b['hc']=b.hum-30
d=b.dropna(subset=['mt','hum']).copy()
f='defective_units+good~(hc+I(hc**2))*C(sup)+mtc+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+since'
best=[]
for dt in pd.date_range('2025-05-15','2025-06-30'):
    d['reg']=((d.line=='L2')&(d.d>=dt)).astype(int)
    r=smf.glm(f+'+reg',d,family=sm.families.Binomial()).fit()
    best.append((r.llf,dt.date(),r.params['reg']))
best.sort(reverse=True);print(best[:6])
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_egqz7huo; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
print(sorted(b[b.line=='L2'].production_date.unique())[-100:][30:50] if False else b[(b.line=='L2')&(b.d>='2025-06-10')&(b.d<='2025-06-18')].production_date.value_counts().sort_index())
b['good']=b.units_produced-b.defective_units
b['mtc']=b.mt-210;b['hc']=b.hum-30
b['reg']=((b.line=='L2')&(b.d>='2025-06-16')).astype(int)
b['over']=np.maximum(b.since-14,0)
d=b.dropna(subset=['mt','hum']).copy()
f='defective_units+good~(hc+I(hc**2))*C(sup)+mtc+I(mtc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(line)+since+reg'
r=smf.glm(f,d,family=sm.families.Binomial()).fit();print(r.summary().tables[1])
ph=r.pearson_chi2/r.df_resid;print('disp',ph)
for t in ['mtc+I(mtc**2)','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)','C(operator_id)']:
    if t=='C(operator_id)': r2=smf.glm(f+'+'+t,d,family=sm.families.Binomial()).fit();dev=r.deviance-r2.deviance;df=r.df_resid-r2.df_resid
    else:
        g=f.replace('+'+t,'',1) if '+'+t in f else f
        r2=smf.glm(g,d,family=sm.families.Binomial()).fit();dev=r2.deviance-r.deviance;df=r2.df_resid-r.df_resid
    print(t,dev,df,stats.chi2.sf(dev/ph,df))
r3=smf.glm(f+'+over',d,family=sm.families.Binomial()).fit();print('over',r3.params['over'],r3.bse['over'])
# counterfactual
x=d.copy();x['since']=x.since%14
p0=r.predict(d)*d.units_produced;p1=r.predict(x)*x.units_produced
print(p0.sum()/d.units_produced.sum(),p1.sum()/d.units_produced.sum(), 'ratio',p1.sum()/p0.sum())
for s in ['Alpha','Beta','Gamma']:
    z=d.copy();z['sup']=s;print(s,(r.predict(z)*z.units_produced).sum()/z.units_produced.sum())
E
python3 -I $TMPDIR/a.py
