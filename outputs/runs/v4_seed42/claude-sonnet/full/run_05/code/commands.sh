cd /tmp/edabench_claude_jzy6bhxx; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_jzy6bhxx; cat suppliers.csv; cat maintenance.csv | awk -F, '{print $2,$3,$4}' | sort | uniq -c | sort -rn | head -20
python3 -I -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.batch_id.nunique(), d.duplicated().sum())
for c in ['shift','line','operator_id','supplier_code']: print(d[c].value_counts(dropna=False).to_dict())
for c in ['production_date','machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    n=pd.to_numeric(d[c],errors='coerce'); print(c,n.isna().sum(),n.describe().round(2).to_dict()); print(d[c][n.isna()].value_counts(dropna=False).head(8).to_dict())
"

cd /tmp/edabench_claude_jzy6bhxx; python3 -I -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.drop_duplicates().batch_id.duplicated().sum())
d=d.drop_duplicates('batch_id')
print(d.production_date.str.replace(r'\d','9',regex=True).value_counts())
print(d[d.production_date.str.contains('/')].production_date.head(20).tolist())
m=pd.to_numeric(d.mold_temp)
print(m.round(-1).value_counts().sort_index())
print(d[m<50].head(), (m==0).sum())
h=pd.to_numeric(d.humidity_pct);print(h[h<=0].value_counts(), h.isna().sum(), (h>100).sum())
print(d.groupby('line').mold_temp.apply(lambda s:pd.to_numeric(s).describe()))
"; grep -n sensor maintenance.csv

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/p.py <<'E'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates('batch_id')
d['date']=pd.to_datetime(d.production_date.where(d.production_date.str.contains('-'),None),format='%Y-%m-%d',errors='coerce').fillna(pd.to_datetime(d.production_date.where(d.production_date.str.contains('/'),None),format='%m/%d/%Y',errors='coerce'))
for c in d.columns[6:]: 
    if c not in('date',): d[c]=pd.to_numeric(d[c])
d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
d['sc']=d.supplier_code.str.strip().str.upper()
d['mt']=np.where(d.line=='L3',(d.mold_temp-32)/1.8,d.mold_temp); d.loc[d.mold_temp==0,'mt']=np.nan
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['rate']=d.defective_units/d.units_produced
print(d.date.isna().sum(),d.date.min(),d.date.max())
print('A',len(d),d.hum.isna().sum(),d.defective_units.sum()/d.units_produced.sum(),d.mt.median())
d.to_pickle('/tmp/edabench_claude_jzy6bhxx/../claude-0/c.pkl') if False else d.to_pickle(__import__('os').environ['TMPDIR']+'/c.pkl')
print(d.groupby('line').mt.describe())
l1=d[d.line=='L1'].sort_values('date');print(l1.groupby(l1.date>='2025-04-14').mt.describe())
print(d.groupby('sc')[['rate','cycle_time_s','hum']].mean(), d.groupby('shift').rate.mean())
print(d[['rate','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur','units_produced']].corr().round(2)['rate'])
E
python3 -I $TMPDIR/p.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/q.py <<'E'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv',dtype=str)
iso=pd.to_datetime(d.production_date,format='%Y-%m-%d',errors='coerce')
print(iso.notna().sum(), iso.dropna().is_monotonic_increasing)
print(d.production_date.iloc[:40].tolist())
print(d.groupby('line').head(3)[['production_date','line']].T)
# by line order monotone?
E
python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/p2.py <<'E'
import pandas as pd, numpy as np, os
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates('batch_id').reset_index(drop=True)
iso=pd.to_datetime(d.production_date,format='%Y-%m-%d',errors='coerce')
ref=iso.ffill().combine(iso.bfill(),lambda a,b:a if pd.isna(b) else (b if pd.isna(a) else a+(b-a)/2))
a=pd.to_datetime(d.production_date,format='%m/%d/%Y',errors='coerce')
b=pd.to_datetime(d.production_date,format='%d/%m/%Y',errors='coerce')
da=(a-ref).abs();db=(b-ref).abs()
pick=np.where(da.isna(),b,np.where(db.isna(),a,np.where(da<=db,a,b)))
dt=pd.Series(pd.to_datetime(pick),index=d.index).where(iso.isna(),iso)
print(dt.isna().sum(),dt.min(),dt.max(),(dt-ref).abs().describe(), dt.diff().dt.days.lt(0).sum(), dt.diff().dt.days.min())
amb=a.notna()&b.notna()&(a!=b)&iso.isna();print(amb.sum())
d['date']=dt
for c in d.columns[6:-1]: d[c]=pd.to_numeric(d[c])
d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
d['sc']=d.supplier_code.str.strip().str.upper()
d['mt']=np.where(d.line=='L3',(d.mold_temp-32)/1.8,d.mold_temp); d.loc[d.mold_temp==0,'mt']=np.nan
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['rate']=d.defective_units/d.units_produced
d.to_pickle(os.environ['TMPDIR']+'/c.pkl')
print(len(d),d.hum.isna().sum(),d.defective_units.sum()/d.units_produced.sum(),d.mt.median(),d.mt.notna().sum())
E
python3 -I $TMPDIR/p2.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/q.py <<'E'
import pandas as pd, os
d=pd.read_pickle(os.environ['TMPDIR']+'/c.pkl')
x=d.date.diff().dt.days
i=x[x<0].index[:8]
for k in i: print(d.loc[k-2:k+2,['production_date','date','line']])
E
python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/q.py <<'E'
import pandas as pd, numpy as np, os
exec(open(os.environ['TMPDIR']+'/p2.py').read().split("iso=")[0])
iso=pd.to_datetime(d.production_date,format='%Y-%m-%d',errors='coerce')
n=iso.astype('int64').where(iso.notna()); 
ref=pd.to_datetime(n.rolling(15,center=True,min_periods=3).median().ffill().bfill())
a=pd.to_datetime(d.production_date,format='%m/%d/%Y',errors='coerce')
b=pd.to_datetime(d.production_date,format='%d/%m/%Y',errors='coerce')
da=(a-ref).abs();db=(b-ref).abs()
pick=np.where(a.isna(),b,np.where(b.isna(),a,np.where(da<=db,a,b)))
dt=pd.Series(pd.to_datetime(pick),index=d.index).where(iso.isna(),iso)
old=pd.read_pickle(os.environ['TMPDIR']+'/c.pkl').date
print((dt!=old).sum(), dt.diff().dt.days.lt(-1).sum(), (dt-ref).abs().gt(pd.Timedelta(days=3)).sum())
amb=(a.notna()&b.notna()&(a!=b)&iso.isna());print(amb.sum(), ((dt-ref).abs()[amb]>pd.Timedelta(days=3)).sum())
o=pd.read_pickle(os.environ['TMPDIR']+'/c.pkl'); o['date']=dt; o.to_pickle(os.environ['TMPDIR']+'/c.pkl')
E
python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_jzy6bhxx; cat >> $TMPDIR/q.py <<'E'
print(ref.head(), iso.head(), n.head())
E
python3 -I $TMPDIR/q.py | tail -20

cd /tmp/edabench_claude_jzy6bhxx; python3 - <<'E'
import re,os
p=os.environ['TMPDIR']+'/q.py'
s=open(p).read()
s=s.replace("n=iso.astype('int64').where(iso.notna()); ","n=(iso-pd.Timestamp('2025-01-01')).dt.days.astype(float)")
s=s.replace("ref=pd.to_datetime(n.rolling(15,center=True,min_periods=3).median().ffill().bfill())","ref=pd.Timestamp('2025-01-01')+pd.to_timedelta(n.rolling(15,center=True,min_periods=3).median().ffill().bfill(),unit='D')")
s=s.split("print(ref.head()")[0]
s=s.replace("(dt-ref).abs().gt(pd.Timedelta(days=3)).sum()","(dt-ref).abs().gt(pd.Timedelta(days=3)).sum(), dt.min(), dt.max()")
open(p,'w').write(s)
E
python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/m.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/c.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def dsc(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
d['dsc']=d.apply(dsc,axis=1)
print(d.dsc.describe(), d.dsc.isna().sum())
d['rec']=d.sc.map({'SP-01':30,'SP-02':30,'SP-03':36}); d['ctd']=d.cycle_time_s-d.rec
d.to_pickle(os.environ['TMPDIR']+'/c2.pkl')
print(d.groupby(pd.cut(d.dsc,[-1,2,5,8,11,14,17,20,30,60])).rate.agg(['mean','count']))
print(d.groupby(pd.cut(d.hum,range(0,80,8))).rate.agg(['mean','count']))
print(d.groupby([d.sc,pd.cut(d.hum,range(0,80,10))]).rate.mean().unstack(0))
print(d.groupby(['line',d.date.dt.to_period('M')]).rate.mean().unstack(0))
E
python3 -I $TMPDIR/m.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/c2.pkl')
print(d.groupby('line').machine_age_years.describe())
print(d.groupby(['line',d.date.dt.month]).machine_age_years.mean().unstack(0).round(1))
print(d.groupby('operator_id').rate.mean().round(3).values)
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['mtc']=d.mt-212; d['y']=d.defective_units/d.units_produced
d['fail']=d.units_produced-d.defective_units
D=d.dropna(subset=['mt','hum']).copy()
D['h']=(D.hum-35)/10
f="y ~ mtc + I(mtc**2) + h + I(h**2)+C(sc)+ctd+I(ctd**2)+machine_age_years+ambient_temp_c+C(shift)+C(operator_id)+C(line)+dsc"
r=smf.glm(f,D,family=sm.families.Binomial(),freq_weights=D.units_produced).fit(scale='X2')
print(r.summary().tables[1])
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g2.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle(os.environ['TMPDIR']+'/c2.pkl')
print(pd.crosstab(d.operator_id,d.line).T.to_string()); print(pd.crosstab(d.operator_id,d['shift']).T.to_string())
d['mtc']=d.mt-212;d['fail']=d.units_produced-d.defective_units
D=d.dropna(subset=['mt','hum']).copy(); D['h']=(D.hum-35)/10
def fit(f):
    r=smf.glm("I(cbind) ~ 1",D,family=sm.families.Binomial()) if False else smf.glm("defective_units + fail ~ "+f,D,family=sm.families.Binomial()).fit(scale='X2'); return r
base="mtc+I(mtc**2)+h+I(h**2)+C(sc)+ctd+I(ctd**2)+dsc+ambient_temp_c+machine_age_years+C(shift)"
for extra in ["","+C(line)","+C(line)+C(operator_id)"]:
    r=fit(base+extra); print(extra, r.deviance, r.scale); print(pd.DataFrame({'b':r.params,'p':r.pvalues}).round(4).loc[lambda x:~x.index.str.contains('operator')].to_string())
E
python3 -I $TMPDIR/g2.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g3.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.formula.api as smf, statsmodels.api as sm, warnings
warnings.filterwarnings('ignore')
d=pd.read_pickle(os.environ['TMPDIR']+'/c2.pkl')
d['mtc']=d.mt-212;d['fail']=d.units_produced-d.defective_units
D=d.dropna(subset=['mt','hum']).copy(); D['h']=(D.hum-35)/10
def fit(f,D=D):
    import patsy
    y,X=patsy.dmatrices("I(defective_units*1.0) ~ "+f,D,return_type='dataframe')
    yy=np.column_stack([D.loc[X.index,'defective_units'],D.loc[X.index,'fail']])
    return sm.GLM(yy,X,family=sm.families.Binomial()).fit(scale='X2')
base="mtc+I(mtc**2)+h+I(h**2)+C(sc)+ctd+I(ctd**2)+dsc+ambient_temp_c+machine_age_years+C(shift)+C(line)"
r=fit(base);print(r.scale);print(pd.DataFrame({'b':r.params,'p':r.pvalues}).round(4).to_string())
D['res']=D.defective_units-r.fittedvalues*D.units_produced
D['pr']=D.res/D.units_produced
print(D.groupby(['line',D.date.dt.to_period('M')]).pr.mean().unstack(0).round(3))
D.to_pickle(os.environ['TMPDIR']+'/D.pkl')
E
python3 -I $TMPDIR/g3.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/r.py <<'E'
import pandas as pd, numpy as np, os
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
for l,a,b in [('L2','2025-05-10','2025-06-30'),('L3','2025-06-20','2025-08-31'),('L1','2025-03-25','2025-04-30')]:
    x=D[(D.line==l)&(D.date>=a)&(D.date<=b)]
    print(l);print(x.groupby('date').pr.mean().round(3).to_string())
E
python3 -I $TMPDIR/r.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g4.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
D['t']=(D.date-pd.Timestamp('2025-01-01')).dt.days/100
D['l1p']=((D.line=='L1')&(D.date>='2025-04-14')).astype(int)
D['fail']=D.units_produced-D.defective_units
def fit(f):
    X=patsy.dmatrix(f,D,return_type='dataframe')
    yy=np.column_stack([D.loc[X.index,'defective_units'],D.loc[X.index,'fail']])
    r=sm.GLM(yy,X,family=sm.families.Binomial()).fit(scale='X2'); return r,X
base="mtc+I(mtc**2)+h+I(h**2)+C(sc)+ctd+I(ctd**2)+dsc+ambient_temp_c+machine_age_years+C(shift)+C(line)"
for ex in ["","+l1p","+l1p+h:C(sc)+I(h**2):C(sc)","+l1p+h:C(sc)+I(h**2):C(sc)+C(line):t","+l1p+C(line):t+C(line):I(t**2)"]:
    r,X=fit(base+ex);print(ex,r.deviance,r.scale)
r,X=fit(base+"+l1p+h:C(sc)+I(h**2):C(sc)"); print(pd.DataFrame({'b':r.params,'p':r.pvalues}).round(4).to_string())
E
python3 -I $TMPDIR/g4.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g5.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
D['t']=(D.date-pd.Timestamp('2025-01-01')).dt.days/100
D['l1p']=((D.line=='L1')&(D.date>='2025-04-14')).astype(int)
D['fail']=D.units_produced-D.defective_units
D['hb']=pd.cut(D.hum,[0,12,16,20,24,28,32,36,40,44,48,52,56,60,65,75]).astype(str)
D['mb']=pd.cut(D.mt,[180,195,200,205,210,215,220,225,230,245]).astype(str)
D['db']=pd.cut(D.dsc,[-1,3,6,9,12,14,16,18,21,25,40]).astype(str)
D['cb']=pd.cut(D.ctd,[-20,-8,-5,-3,-1,1,3,5,8,20]).astype(str)
D['ab']=pd.cut(D.ambient_temp_c,[0,12,16,20,24,28,40]).astype(str)
D['gb']=pd.cut(D.machine_age_years,[0,3,4,5,6,7,9,12,15,17,19,30]).astype(str)
def fit(f):
    X=patsy.dmatrix(f,D,return_type='dataframe')
    yy=np.column_stack([D.loc[X.index,'defective_units'],D.loc[X.index,'fail']])
    return sm.GLM(yy,X,family=sm.families.Binomial()).fit(scale='X2')
r=fit("C(sc):C(hb)+C(mb)+C(db)+C(cb)+C(ab)+C(gb)+C(shift)+C(line)+C(line):t+l1p-1")
print(r.deviance,r.scale)
for k in ['hb','mb','db','cb','ab','gb']:
    print(k);print(r.params[[i for i in r.params.index if f'{k})' in i or f'[{k}' in i or f'C({k})' in i]].round(3).to_string())
print(r.params[~r.params.index.str.contains('hb|mb|db|cb|ab|gb')])
E
python3 -I $TMPDIR/g5.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g6.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
D['l1p']=((D.line=='L1')&(D.date>='2025-04-14')).astype(int)
D['fail']=D.units_produced-D.defective_units
D['d14']=np.minimum(D.dsc,14); D['dx']=np.maximum(D.dsc-14,0)
def fit(f,D=D):
    X=patsy.dmatrix(f,D,return_type='dataframe')
    yy=np.column_stack([D.loc[X.index,'defective_units'],D.loc[X.index,'fail']])
    r=sm.GLM(yy,X,family=sm.families.Binomial()).fit()
    ph=r.deviance/r.df_resid
    return r,ph
f="mtc+h+I(h**2)+C(sc)+ctd+d14+dx+C(shift)+C(line)+l1p+C(sc):h+C(sc):I(h**2)"
r,ph=fit(f);print(ph)
D['pr']=(D.defective_units-r.fittedvalues*D.units_produced)/D.units_produced
D['wk']=D.date.dt.to_period('W').dt.start_time
print(D.groupby(['wk','line']).pr.mean().unstack().round(3).to_string())
E
python3 -I $TMPDIR/g6.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g7.py <<'E'
import pandas as pd, numpy as np, os
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
for l,a,b in [('L2','2025-06-02','2025-06-30'),('L3','2025-07-10','2025-08-05')]:
    x=D[(D.line==l)&(D.date>=a)&(D.date<=b)]
    print(l);print(x.groupby('date')[['pr','mt','hum','ctd','dsc','units_produced','qc_inspection_min']].mean().round(3).to_string())
    print(x.groupby('date').sc.agg(lambda s:''.join(s.str[-1])).to_string())
E
python3 -I $TMPDIR/g7.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g8.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
D['l1p']=((D.line=='L1')&(D.date>='2025-04-14')).astype(int)
D['l3p']=((D.line=='L3')&(D.date>='2025-07-21')).astype(int)
D['fail']=D.units_produced-D.defective_units
D['d14']=np.minimum(D.dsc,14); D['dx']=np.maximum(D.dsc-14,0)
def fit(f,D=D):
    X=patsy.dmatrix(f,D,return_type='dataframe')
    yy=np.column_stack([D.loc[X.index,'defective_units'],D.loc[X.index,'fail']])
    r=sm.GLM(yy,X,family=sm.families.Binomial()).fit(); return r
f="mtc+h+I(h**2)+C(sc)+ctd+d14+dx+C(shift)+C(line)+l1p+l3p+C(sc):h+C(sc):I(h**2)"
for s in pd.date_range('2025-06-08','2025-06-24'):
    D['l2p']=((D.line=='L2')&(D.date>=s)).astype(int)
    print(s.date(),round(fit(f+"+l2p").deviance,1))
D['l2p']=((D.line=='L2')&(D.date>='2025-06-16')).astype(int)
r=fit(f+"+l2p");print(r.deviance/r.df_resid);print(r.summary().tables[1])
print(D[(D.line=='L2')&(D.date.between('2025-06-12','2025-06-20'))][['date','rate','mt']].sort_values('date').to_string())
E
python3 -I $TMPDIR/g8.py

cd /tmp/edabench_claude_jzy6bhxx; grep -E "L2" maintenance.csv | sed -n 1,40p | tr '\n' ' '; python3 -I - <<'E'
import pandas as pd
d=pd.read_csv('maintenance.csv');print(d.note.value_counts(),d.event.value_counts())
E

cd /tmp/edabench_claude_jzy6bhxx; cat >> $TMPDIR/g8.py <<'E'
D['l2p']=((D.line=='L2')&(D.date>='2025-06-16')).astype(int)
r=fit(f+"+l2p");D['fit']=r.fittedvalues
x=D[(D.line=='L2')&(D.date.between('2025-06-11','2025-06-19'))].sort_values('date')
x['pear']=(x.defective_units-x.fit*x.units_produced)/np.sqrt(x.fit*(1-x.fit)*x.units_produced)
print(x[['date','shift','units_produced','defective_units','rate','fit','pear','dsc','hum']].round(3).to_string())
E
python3 -I $TMPDIR/g8.py | tail -30

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g9.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
D['l1p']=((D.line=='L1')&(D.date>='2025-04-14')).astype(int)
D['l3p']=((D.line=='L3')&(D.date>='2025-07-21')).astype(int)
D['l2p']=((D.line=='L2')&(D.date>='2025-06-16')).astype(int)
D['fail']=D.units_produced-D.defective_units
D['d14']=np.minimum(D.dsc,14); D['dx']=np.maximum(D.dsc-14,0)
D['hb']=pd.cut(D.hum,[0,10,14,18,22,26,30,34,38,42,46,50,54,58,62,66,75]).astype(str)
def fit(f,D=D):
    X=patsy.dmatrix(f,D,return_type='dataframe')
    yy=np.column_stack([D.loc[X.index,'defective_units'],D.loc[X.index,'fail']])
    return sm.GLM(yy,X,family=sm.families.Binomial()).fit()
f="mtc+C(shift)+C(line)+l1p+l3p+l2p+ctd+d14+dx"
for s in ['SP-01','SP-02','SP-03']:
    E=D[D.sc==s]
    r=fit(f+"+C(hb)-1",E); p=r.params[[i for i in r.params.index if 'hb' in i]]
    print(s,r.deviance/r.df_resid); print(pd.DataFrame({'b':p.round(2),'se':r.bse[p.index].round(2)}).to_string())
E
python3 -I $TMPDIR/g9.py

cd /tmp/edabench_claude_jzy6bhxx; cat >> $TMPDIR/g9.py <<'E'
print('----')
E=D[D.sc=='SP-01']
g=pd.DataFrame({'hum':np.arange(12,70,0.5)})
for name,term in [('quad',"hum+I(hum**2)"),('cubic',"hum+I(hum**2)+I(hum**3)"),('quart',"hum+I(hum**2)+I(hum**3)+I(hum**4)"),('cr4',"cr(hum,df=4)"),('cr6',"cr(hum,df=6)"),('cr8',"cr(hum,df=8)")]:
    X=patsy.dmatrix(f+"+"+term,E,return_type='dataframe')
    yy=np.column_stack([E.defective_units,E.fail])
    r=sm.GLM(yy,X,family=sm.families.Binomial()).fit()
    G=pd.DataFrame({'hum':g.hum}); 
    for c in ['mtc','ctd','d14','dx','l1p','l3p','l2p']: G[c]=0
    G['shift']='Day';G['line']='L1'
    Xg=patsy.build_design_matrices([X.design_info],G)[0]
    pr=np.asarray(Xg)@r.params.values
    print(name,round(r.deviance,1),g.hum[np.argmin(pr)])
# alternative: pooled model with common curve? hinge model on alpha
for k in [40,44,48]:
    E=E.copy();E['hk']=np.maximum(E.hum-k,0)
    for lo in [20,24,28]:
        E['hl']=np.maximum(lo-E.hum,0)
        X=patsy.dmatrix(f+"+hk+hl",E,return_type='dataframe')
        r=sm.GLM(np.column_stack([E.defective_units,E.fail]),X,family=sm.families.Binomial()).fit(); print(k,lo,round(r.deviance,1))
E
python3 -I $TMPDIR/g9.py | sed -n '/----/,$p'

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g10.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
from scipy import stats
warnings.filterwarnings('ignore')
exec(open(os.environ['TMPDIR']+'/g9.py').read().split("f=\"mtc")[0])
base="mtc+C(shift)+C(line)+l1p+l3p+l2p+ctd+d14+dx+C(sc)*(hum+I(hum**2))"
r0=fit(base);phi=r0.deviance/r0.df_resid;print('phi',phi)
for name,ex in [('ambient',"+ambient_temp_c"),('age',"+machine_age_years"),('operator',"+C(operator_id)"),('shift_drop',None),('mold',None)]:
    if ex is None: continue
    r=fit(base+ex);dd=(r0.deviance-r.deviance);df=r0.df_resid-r.df_resid
    print(name,round(dd,1),df,'p=',stats.f.sf(dd/df/phi,df,r.df_resid))
for name,b in [('shift',base.replace("+C(shift)","")),('mold',base.replace("mtc+","")),('ctd',base.replace("+ctd","")),('hum',base.replace("+C(sc)*(hum+I(hum**2))","+C(sc)")),('dsc',base.replace("+d14+dx",""))]:
    r=fit(b);dd=r.deviance-r0.deviance;df=r.df_resid-r0.df_resid
    print('drop',name,round(dd,1),df,'p=',stats.f.sf(dd/df/phi,df,r0.df_resid))
r=fit(base+"+ambient_temp_c+machine_age_years");print(r.params[['ambient_temp_c','machine_age_years']],r.bse[['ambient_temp_c','machine_age_years']])
r=fit(base);print(r.params.round(3).to_string())
# ambient vs humidity relation
print(D[['ambient_temp_c','hum','mt']].corr())
E
python3 -I $TMPDIR/g10.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g11.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.formula.api as smf
D=pd.read_pickle(os.environ['TMPDIR']+'/D.pkl')
D['t']=(D.date-pd.Timestamp('2025-01-01')).dt.days
D['grp']=np.where((D.line=='L1')&(D.date<'2025-04-14'),'L1pre',D.line)
print(smf.ols('mt~ambient_temp_c+C(grp)+C(shift)',D).fit().params.round(2))
x=D[D.line=='L1']
x=x.assign(w=x.date.dt.to_period('2W').astype(str))
print(smf.ols('mt~ambient_temp_c',x).fit().resid.groupby(x.w).mean().round(1).to_string())
print(D.groupby('grp').mt.agg(['mean','std']))
E
python3 -I $TMPDIR/g11.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g12.py <<'E'
import pandas as pd, numpy as np, os
D=pd.read_pickle(os.environ['TMPDIR']+'/c2.pkl')
for dl in [0,5,6.3,7,8,8.3]:
    m=D.mt-dl*((D.line=='L1')&(D.date>='2025-04-14')); print(dl,m.median(),m.notna().sum())
print(D.mold_temp.eq(0).sum())
E
python3 -I $TMPDIR/g12.py

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g13.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
exec(open(os.environ['TMPDIR']+'/g9.py').read().split("f=\"mtc")[0])
base="mtc+C(shift)+C(line)+l1p+l3p+l2p+ctd+I(ctd**2)+d14+dx+C(sc)*(hum+I(hum**2)+I(hum**3))"
X=patsy.dmatrix(base,D,return_type='dataframe')
r=sm.GLM(np.column_stack([D.defective_units,D.fail]),X,family=sm.families.Binomial()).fit(); print(r.deviance)
def pred(E):
    Xe=patsy.build_design_matrices([X.design_info],E)[0]; return r.predict(np.asarray(Xe))
for mode in ['ctd0','keep']:
    for s in ['SP-01','SP-02','SP-03']:
        E=D.copy();E['sc']=s
        if mode=='ctd0':E['ctd']=0
        p=pred(E);print(mode,s,(p*E.units_produced).sum()/E.units_produced.sum())
print(D.defective_units.sum()/D.units_produced.sum(), (pred(D)*D.units_produced).sum()/D.units_produced.sum())
# C3
E=D.copy();E['dsc']=D.dsc%14;E['d14']=np.minimum(E.dsc,14);E['dx']=np.maximum(E.dsc-14,0)
p0=pred(D);p1=pred(E)
print('C3 model-delta',(D.defective_units.sum()+((p1-p0)*D.units_produced).sum())/D.units_produced.sum(), 'ratio',(p1*D.units_produced).sum()/(p0*D.units_produced).sum())
tot=pd.read_pickle(os.environ['TMPDIR']+'/c2.pkl'); print(tot.units_produced.sum(),D.units_produced.sum(),tot.defective_units.sum(),D.defective_units.sum())
E=D[D.sc=='SP-01']
g=np.arange(15,60,0.5);
for s in ['SP-01']:
    G=D.iloc[:len(g)].copy();G['sc']=s;G['hum']=g
    for c in ['mtc','ctd','d14','dx','l1p','l3p','l2p']:G[c]=0
    G['shift']='Day';G['line']='L1';pr=pred(G);print(g[np.argmin(pr)])
E
python3 -I $TMPDIR/g13.py

cd /tmp/edabench_claude_jzy6bhxx; cat >> $TMPDIR/g13.py <<'E'
A=pd.read_pickle(os.environ['TMPDIR']+'/c2.pkl')
A['h']=0
A['mtc']=A.mt.fillna(A.groupby('line').mt.transform('median'))-212
A['hum']=A.hum.fillna(30)
A['l1p']=((A.line=='L1')&(A.date>='2025-04-14')).astype(int);A['l3p']=((A.line=='L3')&(A.date>='2025-07-21')).astype(int);A['l2p']=((A.line=='L2')&(A.date>='2025-06-16')).astype(int)
A['d14']=np.minimum(A.dsc,14);A['dx']=np.maximum(A.dsc-14,0)
B=A.copy();B['dsc']=A.dsc%14;B['d14']=np.minimum(B.dsc,14);B['dx']=np.maximum(B.dsc-14,0)
p0=pred(A);p1=pred(B);u=A.units_produced
print('full ratio',(p1*u).sum()/(p0*u).sum(),'delta',(A.defective_units.sum()+((p1-p0)*u).sum())/u.sum(), 'ratio*obs',A.defective_units.sum()/u.sum()*(p1*u).sum()/(p0*u).sum())
# variant: dsc cap at 13 or reset at 14 -> dsc>=14 => dsc-14k
B['dsc']=np.where(A.dsc>=14,A.dsc%14,A.dsc);
E
python3 -I $TMPDIR/g13.py | tail -2

cd /tmp/edabench_claude_jzy6bhxx; cat > $TMPDIR/g14.py <<'E'
import pandas as pd, numpy as np, os, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
exec(open(os.environ['TMPDIR']+'/g9.py').read().split("f=\"mtc")[0])
base="mtc+C(shift)+C(line)+l1p+l3p+l2p+ctd+I(ctd**2)+d14+dx+C(sc)*(hum+I(hum**2)+I(hum**3))"
for drop in [False,True]:
  for s in ['2025-06-14','2025-06-15','2025-06-16','2025-06-17']:
    Dd=D.copy();Dd['l2p']=((Dd.line=='L2')&(Dd.date>=s)).astype(int)
    if drop: Dd=Dd[~((Dd.line=='L2')&(Dd.date=='2025-06-15')&(Dd.defective_units==141))]
    r=fit(base,Dd);print(drop,s,round(r.deviance,1))
E
python3 -I $TMPDIR/g14.py
