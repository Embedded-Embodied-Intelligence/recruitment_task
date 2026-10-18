cd /tmp/edabench_claude_8s4ymmi_; ls; for f in *.csv; do echo $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_8s4ymmi_; cat suppliers.csv; cat maintenance.csv | head -80; python3 -I - <<'E'
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.describe().T)
for c in ['line','shift','operator_id','supplier_code']: print(d[c].value_counts(dropna=False))
print(d.production_date.str.len().value_counts())
print(d[d.batch_id.duplicated(keep=False)].sort_values('batch_id').head(20).to_string())
for c in ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','units_produced','defective_units']:
    x=pd.to_numeric(d[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(d[c][x.isna()].value_counts().head())
E

cd /tmp/edabench_claude_8s4ymmi_; python3 -I - <<'E'
import pandas as pd,re
d=pd.read_csv('batches.csv',dtype=str)
d['fmt']=d.production_date.str.replace(r'\d','9',regex=True)
print(d.groupby(['line','fmt']).size())
print(d[d.fmt=='99/99/9999'].groupby('line').apply(lambda g:(g.production_date.str[:2].astype(int).max(),g.production_date.str[3:5].astype(int).max())))
print(d.duplicated().sum(), d.duplicated(['batch_id','line']).sum(), d.duplicated(['batch_id','line','production_date']).sum())
d['mt']=d.mold_temp.astype(float)
print(d.groupby('line').mt.describe())
print((d.mt==0).groupby(d.line).sum())
E

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates()
def pdt(r):
    s=r.production_date
    if r.line=='L1': return pd.to_datetime(s,format='%m/%d/%Y')
    if r.line=='L4': return pd.to_datetime(s,format='%d/%m/%Y')
    return pd.to_datetime(s,format='%Y-%m-%d')
d['date']=d.apply(pdt,axis=1)
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']: d[c]=d[c].astype(float)
d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
d['sup']=d.supplier_code.str.strip().str.upper()
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.mt-32)*5/9
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['rate']=d.defective_units/d.units_produced
print(len(d),d.hum.isna().sum(),d.defective_units.sum()/d.units_produced.sum(),d.mt.median())
print(d.groupby('line').mt.describe())
d.to_pickle('/tmp/edabench_claude_8s4ymmi_/../claude-0/clean.pkl') if False else d.to_pickle('clean.pkl')
print(d.date.min(),d.date.max(), d.rate.describe())
print(d[['rate','qc_inspection_min','rework_cost_eur']].corr())
print(d.groupby('line').date.agg(['min','max']))
E
python3 -I $TMPDIR/p.py

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/q.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
d=pd.read_pickle('clean.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
l1=d[d.line=='L1']
print(l1.groupby(l1.date<'2025-04-14')[['mt','rate']].mean())
print(l1.set_index('date').mt.resample('M').agg(['mean','std','count']))
# days since cleaning
cl=m[m.event=='mold_cleaning']
def ds(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date
    return (r.date-c.max()).days
d['ds']=d.apply(ds,axis=1)
d.to_pickle('clean2.pkl')
print(d.groupby(pd.cut(d.ds,[-1,3,6,9,12,14,17,20,25,30,60,100])).rate.agg(['mean','count']))
d['mo']=d.date.dt.to_period('M')
print(d.pivot_table(index='mo',columns='line',values='rate',aggfunc='mean'))
E
python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_8s4ymmi_; sed -i "s/'M')/'ME')/" $TMPDIR/q.py; python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/r.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
d=pd.read_pickle('clean2.pkl')
l1=d[d.line=='L1']
print(l1[(l1.date>='2025-03-25')&(l1.date<='2025-05-05')].groupby(l1.date.dt.to_period('W'))[['mt','rate']].mean())
d['mo']=d.date.dt.to_period('M')
print(d.pivot_table(index='mo',columns='line',values='rate',aggfunc='mean'))
print(d.pivot_table(index='mo',columns='line',values='mt',aggfunc='mean'))
print(d.groupby('sup').rate.mean(), d.groupby('shift').rate.mean())
E
python3 -I $TMPDIR/r.py

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/s.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
d=pd.read_pickle('clean2.pkl')
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
m=smf.ols('mt~ambient_temp_c+C(line)+post',d).fit();print(m.params,m.bse['post'])
d['pre']=((d.line=='L1')&(d.date<'2025-04-14')).astype(int)
m=smf.ols('mt~ambient_temp_c+C(line)+post',d[(d.line!='L1')|(d.date>='2025-03-01')]).fit();print(m.params['post'])
# rate model
d['lr']=np.log(d.rate)
f='rate~mt+hum+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(sup)+ds+C(line)'
x=d.dropna(subset=['hum','mt'])
print(smf.ols(f,x).fit().summary().tables[1])
E
python3 -I $TMPDIR/s.py

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/t.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf
d=pd.read_pickle('clean2.pkl')
d['mt2']=d.mt.where(~((d.line=='L1')&(d.date>='2025-04-14')),d.mt-6.5)
sup=pd.read_csv('suppliers.csv');d=d.merge(sup,left_on='sup',right_on='supplier_code',suffixes=('','_s'))
d['dct']=d.cycle_time_s-d.recipe_cycle_time_s
print(d.groupby('line').machine_age_years.describe())
print(d.groupby('sup')[['cycle_time_s','hum','mt2']].mean())
print(d.groupby('sup').cycle_time_s.describe())
print(d.groupby(['line','sup']).size().unstack())
d['hb']=pd.cut(d.hum,[0,10,20,30,40,50,60,80])
print(d.pivot_table(index='hb',columns='sup',values='rate',aggfunc='mean'))
d['db']=pd.cut(d.dct,[-20,-6,-4,-2,-1,0,1,2,4,6,20])
print(d.pivot_table(index='db',columns='sup',values='rate',aggfunc='mean'))
d['tb']=pd.cut(d.mt2,[0,200,205,210,215,220,225,230,250])
print(d.pivot_table(index='tb',columns='sup',values='rate',aggfunc='mean'))
d.to_pickle('clean3.pkl')
E
python3 -I $TMPDIR/t.py

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/u.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle('clean3.pkl')
d['t']=(d.date-d.date.min()).dt.days
print(d.groupby('line').apply(lambda g:np.corrcoef(g.t,g.machine_age_years)[0,1]))
print(d.groupby(['line','op:=' if False else 'operator_id']).size().unstack(0).head(30))
d['y']=d.defective_units/d.units_produced
def fit(f,x=d):
    return smf.glm(f,x,family=sm.families.Binomial(),freq_weights=x.units_produced).fit(cov_type='HC1')
x=d.dropna(subset=['hum','mt2']).copy()
x['h']=x.hum;x['h2']=(x.hum-35)**2
x['pd']=x.pre_dried=='yes'
f='y~mt2+h+h2+dct+machine_age_years+ambient_temp_c+C(shift)+C(sup)+ds'
r=fit(f,x);print(r.summary().tables[1])
r=fit(f+'+C(line)',x);print(r.summary().tables[1])
E
python3 -I $TMPDIR/u.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/v.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle('clean3.pkl')
d['h2']=(d.hum-35)**2
d['nd']=d.units_produced-d.defective_units
x=d.dropna(subset=['hum','mt2']).copy()
f='defective_units+nd~mt2+hum+h2+dct+ambient_temp_c+C(shift)+C(sup)+ds+C(line)+machine_age_years'
r=smf.glm(f,x,family=sm.families.Binomial()).fit(scale='X2')
print(r.summary().tables[1], r.scale)
x['res']=x.defective_units/x.units_produced-r.predict(x)
x['wk']=x.date.dt.to_period('W')
for L in ['L1','L2','L3','L4']:
    g=x[x.line==L]
    print(L, g.groupby(g.date.dt.to_period('M')).apply(lambda q:(q.defective_units.sum()-(r.predict(q)*q.units_produced).sum())/q.units_produced.sum()).round(4).tolist())
E
python3 -I $TMPDIR/v.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/v.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle('clean3.pkl')
d['h2']=(d.hum-35)**2
d['nd']=d.units_produced-d.defective_units
x=d.dropna(subset=['hum','mt2']).copy()
def fit(f,x):
    import patsy
    y,X=patsy.dmatrices(f,x,return_type='dataframe')
    return sm.GLM(x[['defective_units','nd']],X,family=sm.families.Binomial()).fit(scale='X2')
f='x~mt2+hum+h2+dct+ambient_temp_c+C(shift)+C(sup)+ds+C(line)+machine_age_years'
x['x']=0
r=fit(f,x)
print(r.summary().tables[1], r.scale)
import patsy
X=patsy.dmatrix(f.split('~')[1],x,return_type='dataframe')
x['p']=r.predict(X)
for L in ['L1','L2','L3','L4']:
    g=x[x.line==L]
    print(L, g.groupby(g.date.dt.to_period('M')).apply(lambda q:(q.defective_units.sum()-(q.p*q.units_produced).sum())/q.units_produced.sum()).round(4).tolist())
x.to_pickle('x.pkl')
E
python3 -I $TMPDIR/v.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/w.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
f='mt2+hum+h2+dct+ambient_temp_c+C(shift)+C(sup)+ds+C(line)+machine_age_years'
X=patsy.dmatrix(f,x,return_type='dataframe')
Y=x[['defective_units','nd']]
r=sm.GLM(Y,X,family=sm.families.Binomial()).fit(); print(r.pearson_chi2/r.df_resid)
for L in ['L1','L2','L3','L4']:
    best=[]
    for dt in pd.date_range('2025-02-01','2025-09-10',freq='D'):
        X2=X.copy();X2['s']=((x.line==L)&(x.date>=dt)).astype(float)
        m=sm.GLM(Y,X2,family=sm.families.Binomial()).fit()
        best.append((m.deviance,dt,m.params['s']))
    b=sorted(best)[:3];print(L,r.deviance,[(round(a,1),str(c.date()),round(e,3)) for a,c,e in b])
E
python3 -I $TMPDIR/w.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/y.py <<'E'
import pandas as pd,numpy as np
x=pd.read_pickle('clean3.pkl')
for L,a,b in [('L2','2025-05-20','2025-07-15'),('L3','2025-06-25','2025-08-15')]:
    g=x[(x.line==L)&(x.date>=a)&(x.date<=b)].sort_values('date')
    g['wk']=g.date.dt.to_period('W')
    print(g.groupby('wk').agg(n=('rate','size'),rate=('rate','mean'),mt=('mt2','mean'),amb=('ambient_temp_c','mean'),hum=('hum','mean'),ct=('dct','mean'),ds=('ds','mean'),u=('units_produced','mean'),qc=('qc_inspection_min','mean')))
g=x[(x.line=='L2')].sort_values('date')
print(g[(g.date>='2025-06-10')&(g.date<='2025-06-22')][['batch_id','date','rate','mt2','ds','sup']].to_string())
E
python3 -I $TMPDIR/y.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/z.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
Y=x[['defective_units','nd']]
def run(f,extra=None,disp=True):
    X=patsy.dmatrix(f,x,return_type='dataframe')
    if extra is not None: X['s']=extra
    return sm.GLM(Y,X,family=sm.families.Binomial()).fit()
f='mt2+hum+h2+dct+ambient_temp_c+C(shift)+C(sup)+ds+C(line)+machine_age_years+l3p'
res=[]
for dt in pd.date_range('2025-05-25','2025-07-10'):
    m=run(f,((x.line=='L2')&(x.date>=dt)).astype(float));res.append((m.deviance,dt))
print(sorted(res)[:4])
m=run(f,((x.line=='L2')&(x.date>='2025-06-16')).astype(float));print(m.pearson_chi2/m.df_resid);print(m.summary().tables[1])
x['res']=(x.defective_units-m.predict()*x.units_produced)/np.sqrt(m.predict()*x.units_produced)
print(x.groupby('operator_id').res.mean().round(2).tolist())
E
python3 -I $TMPDIR/z.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
x['l2p']=((x.line=='L2')&(x.date>='2025-06-16')).astype(float)
base='mt2+hum+h2+dct+ambient_temp_c+C(shift)+C(sup)+ds+machine_age_years+l3p+l2p'
def run(f,d,extra=''):
    X=patsy.dmatrix(f+extra,d,return_type='dataframe')
    m=sm.GLM(d[['defective_units','nd']],X,family=sm.families.Binomial()).fit(scale='X2')
    return m
for name,d,ex in [('all+line',x,'+C(line)'),('L4',x[x.line=='L4'],''),('L123+line',x[x.line!='L4'],'+C(line)'),('all+op',x,'+C(operator_id)')]:
    m=run(base,d,ex);print(name,round(m.scale,2));print(pd.DataFrame({'b':m.params,'p':m.pvalues})[lambda t:~t.index.str.contains('operator')].round(4).T.to_string())
    if name=='all+op':
        print(pd.DataFrame({'b':m.params,'p':m.pvalues})[lambda t:t.index.str.contains('operator')].round(3).T.to_string())
E
python3 -I $TMPDIR/a.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
x['l2p']=((x.line=='L2')&(x.date>='2025-06-16')).astype(float)
base='mt2+hum+h2+dct+C(shift)+ds+C(line)+l3p+l2p'
for s,g in x.groupby('sup'):
    X=patsy.dmatrix(base,g,return_type='dataframe')
    m=sm.GLM(g[['defective_units','nd']],X,family=sm.families.Binomial()).fit()
    sc=m.pearson_chi2/m.df_resid
    print(s,len(g),round(sc,2));print(pd.DataFrame({'b':m.params,'se':m.bse*np.sqrt(sc)}).round(4).T.to_string())
    print('opt hum',35-m.params['hum']/(2*m.params['h2']))
E
python3 -I $TMPDIR/b.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
x['l2p']=((x.line=='L2')&(x.date>='2025-06-16')).astype(float)
x['dsb']=pd.cut(x.ds,[-1,0,2,4,6,8,10,12,14,16,18,20,25,30,40,100]).astype(str)
base='mt2+hum+h2+dct+C(shift)+C(sup)+C(line)+l3p+l2p+C(dsb,Treatment("(-1, 0]"))'
X=patsy.dmatrix(base,x,return_type='dataframe')
m=sm.GLM(x[['defective_units','nd']],X,family=sm.families.Binomial()).fit()
print(m.params.filter(like='dsb').round(3).to_string())
print(x.groupby('dsb').size())
print(x.ds.max(), (x.ds>14).sum())
E
python3 -I $TMPDIR/c.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np
x=pd.read_pickle('clean3.pkl')
print(x[x.ds>40].groupby('line').date.agg(['min','max','count']))
g=x[(x.line=='L4')&(x.date>='2025-02-01')&(x.date<='2025-04-12')]
print(g.groupby('ds').agg(n=('rate','size'),r=('rate','mean'),mt=('mt2','mean')).round(3).to_string())
E
python3 -I $TMPDIR/e.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
x['l2p']=((x.line=='L2')&(x.date>='2025-06-16')).astype(float)
f='mt2+hum+h2+dct+C(shift)+C(sup)+C(line)+l3p+l2p+cr(ds,df=5)'
X=patsy.dmatrix(f,x,return_type='dataframe')
Y=x[['defective_units','nd']]
for nm,l in [('logit',sm.families.links.Logit()),('log',sm.families.links.Log())]:
    try:
        m=sm.GLM(Y,X,family=sm.families.Binomial(link=l)).fit(start_params=None)
        print(nm,m.deviance,m.pearson_chi2/m.df_resid)
    except Exception as e: print(nm,e)
# interactions with sup for ds and mt, hum, dct, shift
g='mt2+hum+h2+dct+C(shift)+C(sup)+C(line)+l3p+l2p+cr(ds,df=5)'
for term in ['mt2:C(sup)','dct:C(sup)','C(shift):C(sup)','cr(ds,df=5):C(sup)','hum:C(sup)+h2:C(sup)','mt2:C(shift)','mt2:dct','ambient_temp_c','machine_age_years','mt2:hum','C(shift):hum','dct:hum']:
    X=patsy.dmatrix(g+'+'+term,x,return_type='dataframe')
    m=sm.GLM(Y,X,family=sm.families.Binomial()).fit();print(term,round(m.deviance,1),X.shape[1])
E
python3 -I $TMPDIR/f.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
x['l2p']=((x.line=='L2')&(x.date>='2025-06-16')).astype(float)
x['hb']=pd.cut(x.hum,list(range(0,80,5))).astype(str)
for s,g in x.groupby('sup'):
    f='mt2+dct+C(shift)+C(line)+l3p+l2p+cr(ds,df=5)+C(hb)-1'
    X=patsy.dmatrix(f,g,return_type='dataframe')
    m=sm.GLM(g[['defective_units','nd']],X,family=sm.families.Binomial()).fit()
    h=m.params.filter(like='hb');h.index=[i[-12:] for i in h.index]
    n=g.groupby('hb').size()
    print(s,round(m.deviance,1));print(pd.DataFrame({'b':h,}).assign(n=[n.get(i.split('[')[-1].strip(']')) for i in m.params.filter(like='hb').index]).round(2).T.to_string())
E
python3 -I $TMPDIR/g.py 2>&1 | grep -v -i Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
x['l2p']=((x.line=='L2')&(x.date>='2025-06-16')).astype(float)
g=x[x.sup=='SP-01'];print(g.hum.describe())
grid=np.arange(g.hum.min(),g.hum.max(),0.1)
for f in ['mt2+dct+C(shift)+C(line)+l3p+l2p+cr(ds,df=5)+cr(hum,df=%d)'%k for k in (4,5,6,8)]+['mt2+dct+C(shift)+C(line)+l3p+l2p+cr(ds,df=5)+hum+I(hum**2)','mt2+dct+C(shift)+C(line)+l3p+l2p+cr(ds,df=5)+hum+I(hum**2)+I(hum**3)']:
    X=patsy.dmatrix(f,g,return_type='dataframe')
    m=sm.GLM(g[['defective_units','nd']],X,family=sm.families.Binomial()).fit()
    d=g.iloc[[0]*len(grid)].copy();d['hum']=grid
    Xn=patsy.build_design_matrices([X.design_info],d,return_type='dataframe')[0]
    p=m.predict(Xn);print(f[-22:],round(m.deviance,1),grid[p.values.argmin()].round(1))
E
python3 -I $TMPDIR/h.py 2>&1 | grep -v -i Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
x=pd.read_pickle('x.pkl')
x['l3p']=((x.line=='L3')&(x.date>='2025-07-21')).astype(float)
x['l2p']=((x.line=='L2')&(x.date>='2025-06-16')).astype(float)
g=x[x.sup=='SP-01'].copy()
base='mt2+dct+C(shift)+C(line)+l3p+l2p+cr(ds,df=5)'
grid=np.arange(13,72,0.1)
for nm,extra in [('q','hum+I(hum**2)'),('q+h50',"hum+I(hum**2)+I(np.maximum(hum-50,0)**2)"),('q+h50lin',"hum+I(hum**2)+I(np.maximum(hum-50,0))"),('hinge',"I(np.maximum(hum-30,0))+I(np.maximum(30-hum,0))"),('q+h45', "hum+I(hum**2)+I(np.maximum(hum-45,0)**2)"),('q+h40',"hum+I(hum**2)+I(np.maximum(hum-40,0)**2)"),('exp','hum+I(hum**2)+I(np.exp((hum-50)/10))'),('quart','hum+I(hum**2)+I(hum**3)+I(hum**4)')]:
    X=patsy.dmatrix(base+'+'+extra,g,return_type='dataframe')
    m=sm.GLM(g[['defective_units','nd']],X,family=sm.families.Binomial()).fit()
    d=g.iloc[[0]*len(grid)].copy();d['hum']=grid
    Xn=patsy.build_design_matrices([X.design_info],d,return_type='dataframe')[0]
    p=m.predict(Xn);print(nm,round(m.deviance,1),grid[p.values.argmin()].round(1))
E
python3 -I $TMPDIR/i.py 2>&1 | grep -v -i Warn

cd /tmp/edabench_claude_8s4ymmi_; cat > $TMPDIR/j.py <<'E'
import pandas as pd,numpy as np,statsmodels.api as sm,patsy
a=pd.read_pickle('clean3.pkl')
a['l3p']=((a.line=='L3')&(a.date>='2025-07-21')).astype(float)
a['l2p']=((a.line=='L2')&(a.date>='2025-06-16')).astype(float)
a['nd']=a.units_produced-a.defective_units
a['h2']=a.hum**2
x=a.dropna(subset=['hum','mt2']).copy()
f='(hum+h2+mt2+dct)*C(sup)+C(shift)*C(sup)+C(line)+l3p+l2p+cr(ds,df=5)'
X=patsy.dmatrix(f,x,return_type='dataframe')
m=sm.GLM(x[['defective_units','nd']],X,family=sm.families.Binomial()).fit();print(m.deviance,m.pearson_chi2/m.df_resid)
def tot(df,s,dct0):
    d=df.copy();d['sup']=s
    d['dct']=0.0 if dct0 else df.dct
    d['h2']=d.hum**2
    p=m.predict(patsy.build_design_matrices([X.design_info],d,return_type='dataframe')[0])
    # remove l3p/l2p artefact? keep as is
    return (p*d.units_produced).sum()/d.units_produced.sum()
for nm,df in [('complete',x)]:
  for dct0 in (True,False):
    print(nm,dct0,{s:round(tot(df,s,dct0),5) for s in ['SP-01','SP-02','SP-03']})
# also excluding artefact: set l3p=0,l2p=0
x2=x.copy();x2['l3p']=0.;x2['l2p']=0.
print({s:round(tot(x2,s,True),5) for s in ['SP-01','SP-02','SP-03']})
print('actual',x.defective_units.sum()/x.units_produced.sum())
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v -i Warn

cd /tmp/edabench_claude_8s4ymmi_; cat >> $TMPDIR/j.py <<'E'
print('---C3')
for shape in ['cr5','cr4','cr6','lin','bins']:
    fs={'cr5':'cr(ds,df=5)','cr4':'cr(ds,df=4)','cr6':'cr(ds,df=6)','lin':'ds','bins':'C(dsb)'}[shape]
    a['dsb']=pd.cut(a.ds,[-1,1,3,5,7,9,11,13,15,18,22,30,200]).astype(str)
    x=a.dropna(subset=['hum','mt2']).copy()
    f2='(hum+h2+mt2+dct)*C(sup)+C(shift)*C(sup)+C(line)+l3p+l2p+'+fs
    X2=patsy.dmatrix(f2,x,return_type='dataframe')
    m2=sm.GLM(x[['defective_units','nd']],X2,family=sm.families.Binomial()).fit()
    d=a.copy()
    d['hum']=d.hum.fillna(x.hum.median()); d['mt2']=d.mt2.fillna(x.mt2.median()); d['h2']=d.hum**2
    def pr(dd): return m2.predict(patsy.build_design_matrices([X2.design_info],dd,return_type='dataframe')[0])
    p0=pr(d); d2=d.copy(); d2['ds']=d2.ds%14
    d2['dsb']=pd.cut(d2.ds,[-1,1,3,5,7,9,11,13,15,18,22,30,200]).astype(str)
    p1=pr(d2)
    cf=(d.defective_units*p1/p0).sum()/d.units_produced.sum()
    cf2=(d.units_produced*p1).sum()/d.units_produced.sum(); base=(d.units_produced*p0).sum()/d.units_produced.sum()
    print(shape,round(m2.deviance,1),round(cf,5),'model-level',round(cf2,5),round(base,5), 'min14', round(((d.defective_units*np.minimum(1,pr(d2.assign(ds=d.ds.clip(upper=14)%14))/p0))).sum()/d.units_produced.sum(),5))
E
python3 -I $TMPDIR/j.py 2>&1 | grep -v -i Warn | sed -n '/C3/,$p'

cd /tmp/edabench_claude_8s4ymmi_; python3 -I -c "
import pandas as pd
d=pd.read_pickle('clean3.pkl');print(d.mt.median(),d.mt2.median(),d.mt2.notna().sum())"
