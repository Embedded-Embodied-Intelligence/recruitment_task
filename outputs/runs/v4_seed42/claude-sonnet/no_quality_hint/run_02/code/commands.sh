cd /tmp/edabench_claude_qjq54r8i; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.describe().T)
for c in ['line','shift','operator_id','supplier_code']: print(b[c].value_counts(dropna=False))
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
for c in ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','units_produced','defective_units']:
    x=pd.to_numeric(b[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(b[c][x.isna()].value_counts(dropna=False).head())
print(b.production_date.str.len().value_counts()); print(b.production_date.sample(10).tolist())
E
python3 -I $TMPDIR/a.py; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_qjq54r8i; grep sensor maintenance.csv; cat > $TMPDIR/b.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b), b.batch_id.duplicated().sum())
d=b.production_date
b['date']=pd.to_datetime(np.where(d.str.contains('/'),pd.to_datetime(d,format='%m/%d/%Y',errors='coerce'),pd.to_datetime(d,errors='coerce')))
print(b.date.min(),b.date.max())
print(np.histogram(b.mold_temp,bins=[-1,0.01,50,100,150,180,200,220,240,260,300,350,400,500]))
print(b.groupby('line').mold_temp.describe())
print((b.humidity_pct<0).sum(), b.humidity_pct.isna().sum(), b.humidity_pct.max())
print(b.humidity_pct.value_counts().head(3))
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/c.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
d=b.production_date
b['date']=pd.to_datetime(d.where(~d.str.contains('/'),None),errors='coerce').fillna(pd.to_datetime(d,format='%m/%d/%Y',errors='coerce'))
print(b.date.min(),b.date.max(),b.date.isna().sum())
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
print('A2',b.hum.isna().sum())
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
print(b.mt.isna().sum(), b.mt.median())
b['rate']=b.defective_units/b.units_produced
print('A3',b.defective_units.sum()/b.units_produced.sum())
print(b.groupby('line').mt.describe())
l1=b[b.line=='L1'].sort_values('date'); print(l1.groupby(l1.date.dt.to_period('M')).mt.agg(['mean','std','min']))
print(b.groupby('sup')[['mt']].mean())
print(b[b.mt.notna()].groupby(['line',pd.cut(b.mt,[0,190,200,205,210,215,220,230,250])]).size().unstack())
print(b.corr(numeric_only=True)['rate'])
b.to_pickle('/tmp/edabench_claude_qjq54r8i/../b.pkl') if False else b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/d.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
d=b.production_date
print(d[d.str.contains('/')].str[:2].astype(int).max(), d[d.str.contains('/')].str[3:5].astype(int).max())
print(d[~d.str.contains('/')].head())
print(b.head(40)[['production_date','line']].T)
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/d.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
d=b.production_date
iso=pd.to_datetime(d.where(~d.str.contains('/')),errors='coerce')
print(iso.is_monotonic_increasing, iso.dropna().is_monotonic_increasing)
ref=iso.ffill().bfill()
s=d.str.contains('/')
a=pd.to_datetime(d[s],format='%m/%d/%Y',errors='coerce'); c=pd.to_datetime(d[s],format='%d/%m/%Y',errors='coerce')
# nearest by position
ra=(a-ref[s]).abs().dt.days; rc=(c-ref[s]).abs().dt.days
print((ra<=7).sum(),(rc<=7).sum(),((ra>7)&(rc>7)).sum(), s.sum())
print(pd.DataFrame({'d':d[s],'ref':ref[s],'ra':ra,'rc':rc})[ra>7].head(20))
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/d.py <<'E'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
d=b.production_date
s=d.str.contains('/')
iso=pd.to_datetime(d.where(~s),errors='coerce')
a=pd.to_datetime(d.where(s),format='%m/%d/%Y',errors='coerce'); c=pd.to_datetime(d.where(s),format='%d/%m/%Y',errors='coerce')
known=iso.copy()
known=known.fillna(a.where(c.isna())).fillna(c.where(a.isna()))
ref=known.astype('int64').where(known.notna()).rolling(41,center=True,min_periods=1).median()
ref=pd.to_datetime(ref)
amb=a.notna()&c.notna()&s&(a!=c)
pick=np.where((a-ref).abs()<=(c-ref).abs(),a,c)
out=known.copy()
out[amb]=pd.to_datetime(pick)[amb]
out[s&a.notna()&c.notna()&(a==c)]=a
print(out.isna().sum(),out.min(),out.max(),amb.sum())
print(((out-ref).abs().dt.days>10).sum())
print((out.diff().dt.days<-3).sum())
b['date']=out
b.to_pickle(__import__('os').environ['TMPDIR']+'/raw.pkl')
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/e.py <<'E'
import pandas as pd, numpy as np, os
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/raw.pkl').drop_duplicates('batch_id')
print(b[b.date<'2025-01-06'][['production_date','date','line']].head())
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
b['rate']=b.defective_units/b.units_produced
for l in ['L1','L2','L3','L4']:
    x=b[b.line==l].set_index('date').sort_index()
    print(l, x.mt.resample('MS').mean().round(1).tolist())
x=b[b.line=='L1'].set_index('date').sort_index()
print(x.loc['2025-04-01':'2025-04-30'].groupby(level=0).mt.mean().round(1).to_string())
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/f.py <<'E'
import pandas as pd, numpy as np, os
T=os.environ['TMPDIR']
b=pd.read_csv('batches.csv')
print(b.iloc[300:335][['batch_id','production_date','line']].to_string())
print(b.iloc[-5:][['batch_id','production_date','line']])
E
python3 -I $TMPDIR/f.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/d.py <<'E'
import pandas as pd, numpy as np, os
b=pd.read_csv('batches.csv')
d=b.production_date
s=d.str.contains('/')
iso=pd.to_datetime(d.where(~s),errors='coerce')
a=pd.to_datetime(d.where(s),format='%m/%d/%Y',errors='coerce'); c=pd.to_datetime(d.where(s),format='%d/%m/%Y',errors='coerce')
known=iso.fillna(a.where(c.isna())).fillna(c.where(a.isna()))
ref=known.ffill().bfill()   # chronological file: nearest earlier unambiguous date
# use mean of prev & next known for robustness
r=known.ffill(); n=known.bfill()
da=np.minimum((a-r).abs().dt.days,(a-n).abs().dt.days); dc=np.minimum((c-r).abs().dt.days,(c-n).abs().dt.days)
out=known.copy()
m=known.isna()&s
out[m]=a.where(da<=dc,c)[m]
print(out.isna().sum(),out.min(),out.max())
print(out.diff().dt.days.describe(), (out.diff().dt.days<0).sum(), (out.diff().dt.days<-1).sum())
print(out.iloc[316:330].tolist()[:14])
b['date']=out
b.to_pickle(os.environ['TMPDIR']+'/raw.pkl')
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/g.py <<'E'
import pandas as pd, os
b=pd.read_pickle(os.environ['TMPDIR']+'/raw.pkl')
x=b[(b.date>'2025-09-30')]; print(x[['batch_id','production_date','line','date']].to_string()); 
print(b.iloc[2995:3002][['production_date','date']])
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/g.py <<'E'
import pandas as pd, os
b=pd.read_pickle(os.environ['TMPDIR']+'/raw.pkl')
print(b[b.batch_id=='B-213906'].T)
print(b.iloc[2390:2398][['production_date','date','line']])
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/h.py <<'E'
import pandas as pd, numpy as np, os
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/raw.pkl').drop_duplicates('batch_id')
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['mt']=b.mold_temp.where(b.mold_temp>0)
b.loc[b.line=='L3','mt']=(b.mt-32)*5/9
b['rate']=b.defective_units/b.units_produced
b.to_pickle(T+'/c.pkl')
b['m']=b.date.dt.to_period('M')
print(b.pivot_table(index='m',columns='line',values='ambient_temp_c').round(1))
print(b.pivot_table(index='m',columns='line',values='mt').round(1))
print(b.pivot_table(index='m',columns='line',values='rate').round(4))
print(b.pivot_table(index='m',columns='line',values='cycle_time_s').round(1))
print(b.groupby('line').date.agg(['min','max','count']))
E
python3 -I $TMPDIR/h.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/i.py <<'E'
import pandas as pd, numpy as np, os
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/c.pkl').dropna(subset=['mt'])
import numpy.linalg as la
ref=b[b.line.isin(['L2','L4'])]
X=np.c_[np.ones(len(ref)),ref.ambient_temp_c,ref.cycle_time_s]
co=la.lstsq(X,ref.mt,rcond=None)[0];print(co)
b['res']=b.mt-np.c_[np.ones(len(b)),b.ambient_temp_c,b.cycle_time_s]@co
b['w']=b.date.dt.to_period('2W')
print(b.pivot_table(index='w',columns='line',values='res').round(1).to_string())
E
python3 -I $TMPDIR/i.py

cd /tmp/edabench_claude_qjq54r8i; cat maintenance.csv | awk -F, '{print $2}' | sort | uniq -c; grep -c . maintenance.csv; awk -F, '$2=="L2"' maintenance.csv | tr '\n' ' '; echo; awk -F, '$2=="L4"' maintenance.csv | tr '\n' ' ';echo; awk -F, '$2=="L1"' maintenance.csv | tr '\n' ' ';echo; awk -F, '$2=="L3"' maintenance.csv | tr '\n' ' '

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/j.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/c.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']); m=m[m.event=='mold_cleaning']
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days
b['ds']=b.apply(ds,axis=1)
b['y']=b.defective_units/b.units_produced
print(b.groupby(pd.cut(b.ds,[-1,0,2,4,6,8,10,12,14,17,20,25,40,100])).agg(r=('y','mean'),n=('y','size')))
print(b.groupby('line').ds.describe())
b.to_pickle(T+'/d.pkl')
E
python3 -I $TMPDIR/j.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/k.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/d.pkl')
s=pd.read_csv('suppliers.csv'); print(s)
b=b.merge(s,left_on='sup',right_on='supplier_code',suffixes=('','_s'))
b['ct_dev']=b.cycle_time_s-b.recipe_cycle_time_s
print(b.groupby('sup').cycle_time_s.describe())
b['fail']=b.units_produced-b.defective_units
b['mt2']=b.mt-b.mt.mean()
b.to_pickle(T+'/e.pkl')
bb=b.dropna(subset=['mt','hum']).copy()
f='y~mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+C(line)+ds'
r=smf.glm('I(defective_units/units_produced)~mt+hum+I(hum**2)+cycle_time_s+ct_dev+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)+ds',data=bb,family=sm.families.Binomial(),var_weights=bb.units_produced).fit()
print(r.summary().tables[1])
E
python3 -I $TMPDIR/k.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/l.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/e.pkl')
bb=b.dropna(subset=['mt','hum']).copy()
bb['y']=bb.defective_units/bb.units_produced
bb['hum_c']=bb.hum-30; bb['mt_c']=bb.mt-212; bb['dsc']=np.minimum(bb.ds,40)
bb['over']=np.maximum(bb.ds-14,0)
base='y~mt_c+I(mt_c**2)+hum_c+I(hum_c**2)+ct_dev+I(ct_dev**2)+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)+ds+over'
def fit(f,d=bb):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
r=fit(base); print(r.summary().tables[1]); print(r.scale)
r2=fit(base+'+C(operator_id)')
print('operator LR-ish F', ((r.deviance-r2.deviance)/23)/r2.scale, r2.scale)
bb.to_pickle(T+'/f.pkl')
E
python3 -I $TMPDIR/l.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/m.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
bb['alpha']=(bb.sup=='SP-01').astype(int)
bb['l1post']=((bb.line=='L1')&(bb.date>='2025-04-14')).astype(int)
bb['l3post']=((bb.line=='L3')&(bb.date>='2025-05-19')).astype(int)
def fit(f,d=bb):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
f='y~mt_c+hum_c*C(sup)+I(hum_c**2):C(sup)+ct_dev+I(ct_dev**2)+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)+ds+l1post+l3post'
r=fit(f);print(r.summary().tables[1],r.scale)
bb['res']=r.resid_pearson
bb['w']=bb.date.dt.to_period('M')
print(bb.pivot_table(index='w',columns='line',values='res').round(2))
E
python3 -I $TMPDIR/m.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/n.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
def fit(f,d):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
h='+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+ds+C(line)'
for lines in [['L2','L4'],['L1'],['L3'],['L1','L2','L3','L4']]:
  d=bb[bb.line.isin(lines)]
  for extra in ['mt_c','mt_c+ambient_temp_c','mt_c+ambient_temp_c+machine_age_years']:
    r=fit('y~'+extra+h,d); print(lines,extra,r.params.filter(regex='^(mt_c|amb|mach)').round(4).to_dict(), round(r.scale,2))
E
python3 -I $TMPDIR/n.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/o.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
def fit(f,d):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
bb['dsb']=pd.cut(bb.ds,[-1,2,5,8,11,14,17,21,28,50]).astype(str)
bb['wk']=bb.date.dt.to_period('2W').astype(str)
h='y~mt_c+ambient_temp_c+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)+l1+l3'
bb['l1']=((bb.line=='L1')&(bb.date>='2025-04-14')).astype(int)
bb['l3']=((bb.line=='L3')&(bb.date>='2025-05-19')).astype(int)
r=fit(h,bb);print(r.params.filter(regex='dsb|l1|l3|mt|amb').round(3),r.scale)
bb['res']=r.resid_pearson
print(bb.pivot_table(index='wk',columns='line',values='res').round(1).to_string())
E
python3 -I $TMPDIR/o.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/p.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
def fit(f,d):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
bb['dsb']=pd.cut(bb.ds,[-1,2,5,8,11,14,17,21,28,50]).astype(str)
bb['l1']=((bb.line=='L1')&(bb.date>='2025-04-14')).astype(int)
bb['wk']=bb.date.dt.to_period('2W').astype(str)
h='y~mt_c+ambient_temp_c+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)'
for extra in ['','+l1']:
    r=fit(h+extra,bb);print(extra,r.params.filter(regex='l1|mt|amb').round(3).to_dict(),r.scale)
bb['res']=r.resid_pearson
print(bb.pivot_table(index='wk',columns='line',values='res').round(1).iloc[8:30].to_string())
# scan L-line breaks
for l in ['L1','L2','L3','L4']:
    d=bb[bb.line==l]; best=[]
    for t in pd.date_range('2025-02-01','2025-09-01',freq='D'):
        d2=d.assign(post=(d.date>=t).astype(int))
        rr=fit(h.replace('+C(line)','')+'+post',d2); best.append((rr.deviance,t,rr.params['post']))
    m=min(best); print(l,m[1].date(),round(m[2],3),round(m[0],1))
E
python3 -I $TMPDIR/p.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/q.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
def fit(f,d):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
bb['dsb']=pd.cut(bb.ds,[-1,2,5,8,11,14,17,21,28,50]).astype(str)
bb['mtb']=pd.cut(bb.mt,[0,200,205,208,211,214,217,220,224,228,260]).astype(str)
d=bb[bb.line.isin(['L2','L4'])&(bb.date<'2025-06-16')]
h='y~hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)'
r=fit(h+'+C(mtb)',d); print(r.params.filter(regex='mtb').round(3), r.scale)
r=fit(h+'+C(mtb)+ambient_temp_c',d); print(r.params.filter(regex='mtb|amb').round(3), r.scale)
r=fit(h+'+mt_c+ambient_temp_c+I(ambient_temp_c**2)',d); print(r.params.filter(regex='mt|amb').round(4), r.scale)
E
python3 -I $TMPDIR/q.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/r.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
def fit(f,d):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
bb['dsb']=pd.cut(bb.ds,[-1,2,5,8,11,14,17,21,28,50]).astype(str)
bb['l1']=((bb.line=='L1')&(bb.date>='2025-04-14')).astype(int)
bb['l3']=((bb.line=='L3')&(bb.date>='2025-05-19')).astype(int)
bb['l2']=((bb.line=='L2')&(bb.date>='2025-06-16')).astype(int)
bb['l3b']=((bb.line=='L3')&(bb.date>='2025-07-21')).astype(int)
h='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)+l2+l3b'
for d1 in [0,3,5,7,9]:
  for d3 in [0,3,6]:
    bb['mt_a']=bb.mt_c-d1*bb.l1-d3*bb.l3
    r=fit(h,bb); print(d1,d3,round(r.deviance,1),round(r.params['mt_a'],4),round(r.params['l2'],3),round(r.params['l3b'],3))
E
python3 -I $TMPDIR/r.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/s.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
def fit(f,d):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
bb['dsb']=pd.cut(bb.ds,[-1,2,5,8,11,14,17,21,28,50]).astype(str)
bb['l1']=((bb.line=='L1')&(bb.date>='2025-04-14')).astype(int)
bb['mt_a']=bb.mt_c-7.5*bb.l1
h='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)'
r=fit(h,bb); bb['res']=r.resid_pearson; print(r.scale)
for l in ['L1','L2','L3','L4']:
    d=bb[bb.line==l]; res=[]
    for t in pd.date_range('2025-02-01','2025-09-01',freq='D'):
        rr=fit(h.replace('+C(line)','')+'+post',d.assign(post=(d.date>=t).astype(int))); res.append((rr.deviance,t,rr.params['post'],rr.bse['post']))
    m=min(res); print(l,m[1].date(),round(m[2],3),round(m[3],3),round(m[0],1), 'null',round(fit(h.replace('+C(line)',''),d).deviance,1))
x=bb[(bb.line=='L3')&(bb.date>='2025-07-10')&(bb.date<='2025-08-05')].groupby('date').agg(res=('res','mean'),ds=('ds','mean'),n=('y','size'),y=('y','mean'))
print(x.round(2).to_string())
E
python3 -I $TMPDIR/s.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/t.py <<'E'
import pandas as pd, numpy as np, os
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
for l,a,b_ in [('L2','2025-06-01','2025-07-05'),('L3','2025-05-05','2025-08-10')]:
    x=bb[(bb.line==l)&(bb.date>=a)&(bb.date<=b_)]
    g=x.groupby(x.date.dt.to_period('W')).agg(d=('defective_units','sum'),u=('units_produced','sum'),mt=('mt','mean'),ds=('ds','mean'),hum=('hum','mean'),sup=('sup',lambda s:(s=='SP-01').mean()),ct=('ct_dev','mean'))
    g['r']=g.d/g.u; print(l);print(g.round(3))
E
python3 -I $TMPDIR/t.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/u.py <<'E'
import pandas as pd, numpy as np, os
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
bb['m']=bb.date.dt.to_period('M')
print(bb.pivot_table(index='m',columns='line',values='machine_age_years').round(2))
x=bb[bb.line=='L3']; x=x.assign(post=x.date>='2025-07-21')
print(x.groupby('post')[['machine_age_years','hum','ct_dev','units_produced','ambient_temp_c','mt']].mean())
print(x.groupby('post')['shift'].value_counts(normalize=True))
print(bb.groupby('line').machine_age_years.agg(['mean','std','min','max']))
x=bb[bb.line=='L2']; x=x.assign(post=x.date>='2025-06-16')
print(x.groupby('post')[['machine_age_years','hum','ct_dev','units_produced','ambient_temp_c','mt']].mean())
E
python3 -I $TMPDIR/u.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/v.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/f.pkl')
def fit(f,d=bb):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
bb['dsb']=pd.cut(bb.ds,[-1,2,5,8,11,14,17,21,28,50]).astype(str)
bb['l1']=((bb.line=='L1')&(bb.date>='2025-04-14')).astype(int)
bb['mt_a']=bb.mt_c-7.5*bb.l1
bb['l2']=((bb.line=='L2')&(bb.date>='2025-06-16')).astype(int)
bb['l3b']=((bb.line=='L3')&(bb.date>='2025-07-21')).astype(int)
h='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)+l2+l3b'
r=fit(h);print(r.summary().tables[1],r.scale)
for add in ['+ambient_temp_c','+machine_age_years','+C(operator_id)','+I(ct_dev**2)','+I(mt_a**2)','+cycle_time_s','+units_produced']:
    r2=fit(h+add); k=r2.df_model-r.df_model
    print(add,'F',round((r.deviance-r2.deviance)/k/r2.scale,2),k, r2.params.filter(regex='amb|mach|cycle|units').round(4).to_dict())
# L4 only age
d=bb[bb.line=='L4']; print(fit(h.replace('+C(line)','').replace('+l2+l3b','')+'+machine_age_years',d).params['machine_age_years'])
bb.to_pickle(T+'/g.pkl')
E
python3 -I $TMPDIR/v.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/w.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/g.pkl')
def fit(f,d=bb):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
h='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)+l2+l3b'
r=fit(h); r2=fit(h+'+C(operator_id)')
print(r2.params.filter(regex='oper').round(3).describe())
print('opF',(r.deviance-r2.deviance)/ (r2.df_model-r.df_model)/r2.scale,r2.df_model-r.df_model)
# shift confounding?
print(bb.groupby('shift')[['mt','hum','ct_dev','ds','ambient_temp_c']].mean())
# C1
names={'SP-01':'Alpha','SP-02':'Beta','SP-03':'Gamma'}
for s in names:
    d=bb.copy(); d['sup']=s; d['ct_dev']=0
    p=r.predict(d); print(names[s], (p*d.units_produced).sum()/d.units_produced.sum())
d=bb.copy(); print('actual-model', (r.predict(d)*d.units_produced).sum()/d.units_produced.sum(), bb.defective_units.sum()/bb.units_produced.sum())
# C2: Alpha
a=bb[bb.sup=='SP-01']
ra=fit('y~mt_a+hum_c+I(hum_c**2)+ct_dev+C(shift)+C(dsb)+C(line)+l2+l3b',a); print(ra.params[['hum_c','I(hum_c ** 2)']], 30-ra.params['hum_c']/(2*ra.params['I(hum_c ** 2)']))
ra=fit('y~mt_a+hum_c+I(hum_c**2)+I(hum_c**3)+ct_dev+C(shift)+C(dsb)+C(line)+l2+l3b',a)
g=np.linspace(a.hum.min(),a.hum.max(),200); dd=a.iloc[[0]].copy()
pr=[ra.predict(pd.concat([dd]*1).assign(hum_c=x-30))[a.index[0]] for x in g]; print(g[np.argmin(pr)])
a['hb']=pd.cut(a.hum,[0,10,15,20,25,28,31,34,38,42,50,80]).astype(str)
rb=fit('y~mt_a+C(hb)+ct_dev+C(shift)+C(dsb)+C(line)+l2+l3b',a); print(rb.params.filter(regex='hb').round(3))
print(a.hum.describe())
E
python3 -I $TMPDIR/w.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/x.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/g.pkl')
print(pd.crosstab(bb.operator_id,bb['shift']).T.to_string())
print(pd.crosstab(bb.operator_id,bb.line).T.to_string())
h='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)+l2+l3b-1'
r=smf.glm(h+'+C(operator_id)',data=bb,family=sm.families.Binomial(),var_weights=bb.units_produced).fit(scale='X2')
print(r.params.filter(regex='oper').round(2).to_string(), r.bse.filter(regex='oper').mean())
E
python3 -I $TMPDIR/x.py

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/y.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/g.pkl')
def fit(f,d=bb):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
h='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)+C(line)'
for line,t in [('L2','2025-06-16'),('L3','2025-07-21')]:
    d=bb[bb.line==line].copy(); d['post']=(d.date>=t).astype(int)
    for by in ['sup','shift','dsb']:
        r=fit(h.replace('+C(line)','')+f'+post:C({by})',d); print(line,by,r.params.filter(regex='post').round(2).to_dict())
    # slope of ds pre/post
    d['dsn']=d.ds
    r=fit(h.replace('+C(line)','').replace('+C(dsb)','')+'+post+dsn+dsn:post',d); print(r.params.filter(regex='post|dsn').round(3).to_dict())
    print(d.groupby('post').apply(lambda x: x.defective_units.sum()/x.units_produced.sum()))
# other lines at the same date
for line in ['L1','L4']:
  for t in ['2025-06-16','2025-07-21']:
    d=bb[bb.line==line].copy(); d['post']=(d.date>=t).astype(int)
    r=fit(h.replace('+C(line)','')+'+post',d); print(line,t,round(r.params['post'],3))
E
python3 -I $TMPDIR/y.py 2>&1 | grep -v Warn | grep -v wls

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/z.py <<'E'
import pandas as pd, numpy as np, os
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/e.pkl')
b['hm']=b.hum.isna(); b['mm']=b.mt.isna()
print(b.groupby('line')[['hm','mm']].mean())
print(b.groupby('hm').apply(lambda x:x.defective_units.sum()/x.units_produced.sum()))
print(b.groupby('mm').apply(lambda x:x.defective_units.sum()/x.units_produced.sum()))
b['m']=b.date.dt.to_period('M')
print(b.pivot_table(index='m',columns='line',values='hm').round(2))
print(b.pivot_table(index='m',columns='line',values='units_produced').round(0))
print(b.pivot_table(index='m',columns='line',values='y',aggfunc='size'))
E
python3 -I $TMPDIR/z.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/aa.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/g.pkl')
def fit(f,d):
    return smf.glm(f,data=d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
h='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(dsb)'
d=bb[bb.line=='L3'].copy()
d['post']=(d.date>='2025-07-21').astype(int); d['ep']=((d.date>='2025-05-19')&(d.date<'2025-07-21')).astype(int); d['after519']=(d.date>='2025-05-19').astype(int)
for nm,ex in [('null',''),('post',"+post"),('ep','+ep'),('after519','+after519'),('both','+post+after519')]:
    r=fit(h+ex,d); print(nm,round(r.deviance,1),r.params.filter(regex='post|ep|after|mt_a').round(3).to_dict())
d['mt_a']=d.mt_c-6*d.after519
for nm,ex in [('post',"+post"),('ep','+ep'),('both','+post+after519')]:
    r=fit(h+ex,d); print('offset6',nm,round(r.deviance,1),r.params.filter(regex='post|ep|after|mt_a').round(3).to_dict())
E
python3 -I $TMPDIR/aa.py 2>&1 | grep -v Warn|grep -v wls

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/bc.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/g.pkl')
bb['rc']=bb.rework_cost_eur/bb.defective_units
bb['qcu']=bb.qc_inspection_min/bb.units_produced
for l,t in [('L2','2025-06-16'),('L3','2025-07-21'),('L1','2025-04-14')]:
    d=bb[bb.line==l]; d=d.assign(post=d.date>=t)
    print(l,d.groupby('post')[['qc_inspection_min','rework_cost_eur','rc','qcu','y','units_produced']].mean().round(3))
import statsmodels.formula.api as smf
print(smf.ols('qc_inspection_min~y+units_produced+C(line)',bb).fit().params, smf.ols('rework_cost_eur~defective_units+C(line)',bb).fit().rsquared)
E
python3 -I $TMPDIR/bc.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/cc.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
bb=pd.read_pickle(T+'/g.pkl')
bb['dsl']=np.log1p(bb.ds); bb['ds2']=bb.ds**2
base='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(line)+l2+l3b'
def fit(f,link=sm.families.links.Logit()):
    return smf.glm(f,data=bb,family=sm.families.Binomial(link=link),var_weights=bb.units_produced).fit(scale='X2')
for nm,ex in [('bins','+C(dsb)'),('lin','+ds'),('quad','+ds+ds2'),('log','+dsl'),('lin+log','+ds+dsl')]:
    r=fit(base+ex); print(nm,round(r.deviance,1),r.params.filter(regex='^ds|dsl').round(4).to_dict())
r=fit(base+'+ds',sm.families.links.Log()) if False else None
# multiplicative: ratio to cleaning day by exact ds for 0..14,
bb['over14']=np.maximum(bb.ds-14,0)
r=fit(base+'+ds+over14'); print(r.deviance, r.params[['ds','over14']])
E
python3 -I $TMPDIR/cc.py 2>&1 | grep -v Warn|grep -v wls

cd /tmp/edabench_claude_qjq54r8i; cat > $TMPDIR/dd.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
T=os.environ['TMPDIR']
b=pd.read_pickle(T+'/e.pkl')
# offset estimate
d=b.dropna(subset=['mt']).copy()
d['l1']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int); d['l3']=((d.line=='L3')&(d.date>='2025-05-19')).astype(int)
r=smf.ols('mt~ambient_temp_c+C(line)+l1+l3+cycle_time_s',d).fit(); print(r.params[['l1','l3']],r.bse[['l1','l3']])
OFF=r.params['l1']
b['mt_true']=b.mt-OFF*((b.line=='L1')&(b.date>='2025-04-14'))
print('A4',b.mt_true.median(), b.mt.median(), b.mt.notna().sum())
b['l1']=0
b['mt_a']=b.mt_true-212
b['l2']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['l3b']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['hum_c']=b.hum-30
f='y~mt_a+hum_c*C(sup)+I(hum_c**2)*C(sup)+ct_dev+C(shift)+C(sup)+C(line)+l2+l3b+ds'
cc=b.dropna(subset=['mt','hum'])
r=smf.glm(f,data=cc,family=sm.families.Binomial(),var_weights=cc.units_produced).fit(scale='X2')
print(r.params.round(4).to_string())
# imputed full
full=b.copy(); full['mt_a']=full.mt_a.fillna(full.groupby('line').mt_a.transform('mean')); full['hum_c']=full.hum_c.fillna(full.groupby('sup').hum_c.transform('mean'))
u=full.units_produced
p0=r.predict(full); print('pred overall',(p0*u).sum()/u.sum(), full.defective_units.sum()/u.sum())
f2=full.copy(); f2['ds']=f2.ds%14; p1=r.predict(f2)
print('C3 model-based',(p1*u).sum()/u.sum())
ratio=(p1*u).sum()/(p0*u).sum(); print('C3 scaled',ratio*full.defective_units.sum()/u.sum())
# row-wise odds scaling
act=full.defective_units
print('rowwise', (act*p1/p0).sum()/u.sum())
f3=full.copy(); f3['ds']=np.minimum(f3.ds,14); print('cap14',(r.predict(f3)*u).sum()/u.sum())
for s in ['SP-01','SP-02','SP-03']:
    g=full.copy(); g['sup']=s; g['ct_dev']=0; print(s,(r.predict(g)*u).sum()/u.sum())
a=cc[cc.sup=='SP-01']
ra=smf.glm('y~mt_a+hum_c+I(hum_c**2)+ct_dev+C(shift)+C(line)+l2+l3b+ds',data=a,family=sm.families.Binomial(),var_weights=a.units_produced).fit(scale='X2')
b1,b2=ra.params['hum_c'],ra.params['I(hum_c ** 2)']; print('C2',30-b1/(2*b2), 'se', )
E
python3 -I $TMPDIR/dd.py 2>&1 | grep -v Warn|grep -v wls
