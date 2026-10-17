cd /tmp/edabench_claude_xm180yp6; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv');print(b.dtypes);print(len(b),b.batch_id.nunique())
for c in ['shift','operator_id','supplier_code','line']:print(b[c].value_counts(dropna=False))
print(b.describe().T)
print(b.production_date.min(),b.production_date.max())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id');print(d.head(10).to_string())
print(b.humidity_pct.astype(str).value_counts().head(8))
print(pd.read_csv('maintenance.csv').event.value_counts())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.nunique())
b=b.drop_duplicates('batch_id')
print(b.mold_temp.describe(), (b.mold_temp<=0).sum())
print(np.histogram(b.mold_temp,bins=20))
print(b.groupby('line').mold_temp.describe())
print(b[b.humidity_pct<=0].humidity_pct.value_counts(), b.humidity_pct.isna().sum())
print(b.humidity_pct.describe())
for c in b.columns[6:]:print(c,(b[c]==-1).sum(),(b[c]<0).sum(),b[c].isna().sum())
print((b.defective_units>b.units_produced).sum())
print(b.units_produced.sort_values().tail(8).values, b.units_produced.min())
print(pd.read_csv('maintenance.csv').query("event!='mold_cleaning'"))
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_xm180yp6; python3 -c "
import pandas as pd
pd.set_option('display.max_colwidth',300)
m=pd.read_csv('maintenance.csv');print(m.query(\"event!='mold_cleaning'\").to_string())
b=pd.read_csv('batches.csv').drop_duplicates('batch_id')
print(b[b.mold_temp==0].line.value_counts())
print(b[b.units_produced>1700][['line','production_date','units_produced','defective_units']])
"

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates('batch_id')
b['date']=pd.to_datetime(b.production_date)
b['dr']=b.defective_units/b.units_produced
b['sup']=b.supplier_code.str.strip().str.upper()
b['sh']=b['shift'].str.strip().str.upper().str[0]
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
print(b.hum.isna().sum(), b.mt.median())
print(b.defective_units.sum()/b.units_produced.sum())
b['m']=b.date.dt.to_period('M')
print(b.pivot_table(index='m',columns='line',values='mt',aggfunc='median'))
print(b.pivot_table(index='m',columns='line',values='dr',aggfunc='mean'))
l1=b[b.line=='L1'].set_index('date').mt.resample('W').median();print(l1.to_string())
b.to_pickle('b.pkl')
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b.pkl')
b.loc[(b.line=='L1')&(b.date>='2025-04-14'),'mt']-=8
print('A4',b.mt.median())
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def since(r):
    d=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-d.max()).days if len(d) else np.nan
b['ds']=b.apply(since,axis=1)
print(b.ds.describe(), b.ds.isna().sum())
print(m.groupby('line').date.apply(lambda s:s.diff().dt.days.describe()))
b.to_pickle('b2.pkl')
b['dsb']=pd.cut(b.ds,[-1,2,5,8,11,14,17,20,25,40,100])
print(b.groupby('dsb').apply(lambda g:pd.Series({'n':len(g),'r':g.defective_units.sum()/g.units_produced.sum()})))
print(b.groupby('line').apply(lambda g:g.groupby(pd.cut(g.ds,[-1,7,14,21,100])).apply(lambda h:h.defective_units.sum()/h.units_produced.sum())))
print(b.groupby('sup').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
E
python3 -I $TMPDIR/c.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['ok']=b.units_produced-b.defective_units
b['h']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna().astype(int)
b['dsx']=np.maximum(b.ds-14,0)
f='ok+defective_units~C(line)+C(sup)+h+I(h**2)+hm+mt+I(mt**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(sh)+C(operator_id)+ds+dsx'
r=smf.glm(f.replace('ok+defective_units','I(defective_units/units_produced)'),b,family=sm.families.Binomial(),freq_weights=b.units_produced).fit()
# use proper binomial
y=np.column_stack([b.defective_units,b.ok])
r=smf.glm('y~C(line)+C(sup)+h+I(h**2)+hm+mt+I(mt**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(sh)+ds+dsx',b.assign(y=list(y)),family=sm.families.Binomial()).fit(scale='X2')
print(r.summary().tables[1]); print(r.scale)
b['res']=r.resid_pearson
b['w']=b.date.dt.to_period('W')
print(b.pivot_table(index=b.date.dt.to_period('M'),columns='line',values='res'))
E
python3 -I $TMPDIR/d.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['ok']=b.units_produced-b.defective_units
b['h']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna().astype(int)
b['dsx']=np.maximum(b.ds-14,0)
d=b.dropna(subset=['mt']).copy()
f='defective_units+ok~C(line)+C(sup)+h+I(h**2)+hm+mt+I(mt**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(sh)+ds+dsx'
r=smf.glm(f,d,family=sm.families.Binomial()).fit(scale='X2')
print(r.summary().tables[1]); print(r.scale)
d['res']=r.resid_pearson
print(d.pivot_table(index=d.date.dt.to_period('M'),columns='line',values='res'))
E
python3 -I $TMPDIR/d.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['ok']=b.units_produced-b.defective_units
b['h']=b.hum.fillna(b.hum.median()); b['hm']=b.hum.isna().astype(int)
b['dsx']=np.maximum(b.ds-14,0)
d=b.dropna(subset=['mt']).copy()
f='defective_units+ok~C(line)+C(sup)+h+I(h**2)+hm+mt+I(mt**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(sh)+ds+dsx'
best=[]
for dt in pd.date_range('2025-05-01','2025-07-15'):
    d['st']=((d.line=='L2')&(d.date>=dt)).astype(int)
    r=smf.glm(f+'+st',d,family=sm.families.Binomial()).fit()
    best.append((r.llf,dt))
best.sort(reverse=True);print(best[:5])
dt=best[0][1]
d['st']=((d.line=='L2')&(d.date>=dt)).astype(int)
r=smf.glm(f+'+st',d,family=sm.families.Binomial()).fit(scale='X2')
print(r.summary().tables[1],r.scale)
print(d[d.line=='L2'].groupby('date').apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).loc['2025-05-10':'2025-06-20'].round(3).to_string())
E
python3 -I $TMPDIR/e.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['ok']=b.units_produced-b.defective_units
b['st']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['dsx']=np.maximum(b.ds-14,0)
d=b.dropna(subset=['mt','hum']).copy()
d['cyc']=d.cycle_time_s
print(d.groupby('sup').apply(lambda g:g.groupby(pd.cut(g.hum,[0,10,15,20,25,30,35,40,50,80])).apply(lambda h:h.defective_units.sum()/h.units_produced.sum())).round(4))
f='defective_units+ok~C(line)+C(sup)*(hum+I(hum**2))+mt+I(mt**2)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(sh)+C(operator_id)+ds+dsx+st'
r=smf.glm(f,d,family=sm.families.Binomial()).fit(scale='X2')
print(r.summary().tables[1],r.scale)
E
python3 -I $TMPDIR/f.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['ok']=b.units_produced-b.defective_units
b['st']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['dsx']=np.maximum(b.ds-14,0)
d=b.dropna(subset=['mt','hum']).copy()
d['r']=d.defective_units/d.units_produced
base='C(line)+C(sup)*(hum+I(hum**2))+mt+cycle_time_s+machine_age_years+ambient_temp_c+C(sh)+C(operator_id)+ds+dsx+st'
r=smf.glm('r~'+base,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
phi=r.pearson_chi2/r.df_resid;print('phi',phi)
terms=['C(operator_id)','mt','cycle_time_s','machine_age_years','ambient_temp_c','C(sh)','hum+C(sup):hum']
for t in ['C(operator_id)','mt','cycle_time_s','machine_age_years','ambient_temp_c','C(sh)','C(line)']:
    f=base.replace(t+'+','',1) if t+'+' in base else base
    r2=smf.glm('r~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
    print(t,'F',(r2.deviance-r.deviance)/phi/(r2.df_resid-r.df_resid), 'df',r2.df_resid-r.df_resid)
print(r.summary().tables[1])
E
python3 -I $TMPDIR/g.py 2>&1|grep -v Warn|grep -v operator_id\\\]

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['st']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['dsx']=np.maximum(b.ds-14,0)
b['r']=b.defective_units/b.units_produced
d=b.dropna(subset=['mt','hum']).copy()
def fit(f,dd=d):return smf.glm('r~'+f,dd,family=sm.families.Binomial(),var_weights=dd.units_produced).fit()
common='C(line)+mt+cycle_time_s+C(sh)+st'
A=d[d.sup=='SP-01']
for hf in ['hum+I(hum**2)','hum+I(hum**2)+I(hum**3)','bs(hum,df=5)']:
    r=fit(common+'+'+hf+'+ds+dsx',A)
    g=pd.DataFrame({'hum':np.arange(A.hum.min(),A.hum.max(),0.1)})
    p=A.iloc[[0]].drop(columns='hum').merge(g,how='cross')
    p['ds']=A.ds.mean();p['dsx']=A.dsx.mean()
    pr=r.predict(p);print(hf,p.hum[pr.argmin()],A.hum.min(),A.hum.max(), r.aic if hasattr(r,'aic') else '')
# ds shape
r=fit('C(line)+C(sup)*(hum+I(hum**2))+mt+cycle_time_s+C(sh)+st+C(pd.cut(ds,[-1,2,4,6,8,10,12,14,16,20,25,40]))')
print(r.params.filter(like='cut'))
# mt
r=fit('C(line)+C(sup)*(hum+I(hum**2))+C(pd.cut(mt,[0,200,205,208,211,214,218,222,230,260]))+cycle_time_s+C(sh)+st+ds+dsx')
print(r.params.filter(like='mt'))
r=fit('C(line)+C(sup)*(hum+I(hum**2))+mt+C(pd.cut(cycle_time_s,[0,24,26,28,30,32,34,36,60]))+C(sh)+st+ds+dsx')
print(r.params.filter(like='cycle'))
E
python3 -I $TMPDIR/h.py 2>&1|grep -v Warn|grep -v wls_

cd /tmp/edabench_claude_xm180yp6; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf,statsmodels.api as sm
b=pd.read_pickle('b2.pkl')
b['st']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['r']=b.defective_units/b.units_produced
d=b.dropna(subset=['mt','hum']).copy()
f='r~C(line)+C(sup)*(hum+I(hum**2))+mt+cycle_time_s+C(sh)+st+ds'
r=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
for name,dd in [('complete',d),('imputed',b.assign(hum=b.hum.fillna(b.hum.median()),mt=b.mt.fillna(b.groupby('line').mt.transform('median'))))]:
    w=dd.units_produced
    print(name,'actual',dd.defective_units.sum()/w.sum(),'pred',(r.predict(dd)*w).sum()/w.sum())
    for s in ['SP-01','SP-02','SP-03']:
        print(s,(r.predict(dd.assign(sup=s))*w).sum()/w.sum())
    p0=r.predict(dd);p1=r.predict(dd.assign(ds=dd.ds%14))
    print('C3 pred',(p1*w).sum()/w.sum(),'ratio-adj',(dd.r*p1/p0*w).sum()/w.sum())
E
python3 -I $TMPDIR/i.py 2>&1|grep -v Warn|grep -v wls_
