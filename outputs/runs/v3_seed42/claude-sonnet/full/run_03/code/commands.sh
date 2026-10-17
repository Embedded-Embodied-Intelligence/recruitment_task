cd /tmp/edabench_claude_6r2x7p0k; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/a.py <<'E'
import pandas as pd
d=pd.read_csv('batches.csv')
print(d.dtypes);print(d.describe(include='all').T.to_string())
for c in ['shift','line','operator_id','supplier_code']:print(d[c].value_counts(dropna=False))
print(d.batch_id.duplicated().sum(), d.duplicated().sum())
print(d[d.batch_id.duplicated(keep=False)].sort_values('batch_id').head(10).to_string())
print(d.humidity_pct.astype(str).value_counts().head(8))
print(pd.read_csv('maintenance.csv').event.value_counts())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('batches.csv').drop_duplicates()
print(len(d),d.batch_id.nunique())
d['sh']=d['shift'].str.strip().str.upper().str[0]
d['sup']=d.supplier_code.str.strip().str.upper()
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
print('A2',d.hum.isna().sum(), (d.humidity_pct<0).sum(), d.humidity_pct.isna().sum(), d.humidity_pct.max())
print('A3',d.defective_units.sum()/d.units_produced.sum())
print(d.mold_temp.round(-1).value_counts().sort_index().to_string())
print(d.groupby('line').mold_temp.describe())
print(d[d.mold_temp<100].head())
print(pd.read_csv('maintenance.csv').query("event!='mold_cleaning'"))
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_6r2x7p0k; python3 -c "
import pandas as pd
pd.set_option('display.max_colwidth',300,'display.width',300)
print(pd.read_csv('maintenance.csv').query(\"event!='mold_cleaning'\").to_string())"

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('batches.csv').drop_duplicates()
d['date']=pd.to_datetime(d.production_date)
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.mt-32)*5/9
l=d[d.line=='L1'].set_index('date').mt
print(l.resample('2W').median().to_string())
print(d.groupby('line').mt.median())
d['rate']=d.defective_units/d.units_produced
d['m']=d.date.dt.to_period('M')
print(d.pivot_table(index='m',columns='line',values='rate',aggfunc='mean').round(4))
print(d.pivot_table(index='m',columns='line',values='mt',aggfunc='median').round(1))
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_6r2x7p0k; cat >> $TMPDIR/c.py <<'E'
o=d[d.line!='L1'].groupby('date').mt.median()
a=d[d.line=='L1'].groupby('date').mt.median()
x=(a-o.reindex(a.index)).dropna()
print(x['2025-03-25':'2025-05-05'].round(1).to_string())
print(x[:'2025-04-13'].mean(),x['2025-04-14':].mean())
E
python3 -I $TMPDIR/c.py | tail -40

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np
import statsmodels.formula.api as smf
d=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)
d['date']=pd.to_datetime(d.production_date)
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.mt-32)*5/9
d.loc[(d.line=='L1')&(d.date>='2025-04-14'),'mt']-=8
print('A4',d.mt.median())
d['sh']=d['shift'].str.strip().str.upper().str[0]
d['sup']=d.supplier_code.str.strip().str.upper()
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['rate']=d.defective_units/d.units_produced
m=pd.read_csv('maintenance.csv');m=m[m.event=='mold_cleaning'];m['date']=pd.to_datetime(m.date)
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
d['dsc']=d.apply(ds,axis=1)
print(d.dsc.describe(), d.dsc.isna().sum())
d['t']=(d.date-d.date.min()).dt.days
d.to_pickle(__import__('os').environ['TMPDIR']+'/d.pkl')
print(d.groupby(pd.cut(d.dsc,[-1,3,6,9,12,14,17,20,25,30,60])).rate.agg(['mean','count']))
print(m.groupby('line').date.apply(lambda s:s.diff().dt.days.describe()))
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['nd']=d.units_produced-d.defective_units
d['over']=np.maximum(d.dsc-14,0)
d['mtc']=d.mt-211
x=d.dropna(subset=['mt','hum']).copy()
print(len(x))
f='defective_units+nd ~ mtc+I(mtc**2)+hum+I(hum**2)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(operator_id)+C(sh)+C(sup)+dsc+over+C(line)'
r=smf.glm(f,x,family=sm.families.Binomial()).fit(scale='X2')
print(r.summary().tables[1])
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['over']=np.maximum(d.dsc-14,0)
d['mtc']=d.mt-211
x=d.dropna(subset=['mt','hum']).copy()
def fit(f,x=x):
    return smf.glm(f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
f='rate ~ mtc+I(mtc**2)+hum*C(sup)+I(hum**2)*C(sup)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(sh)+dsc+C(line)+C(operator_id)'
r=fit(f);print(r.summary().tables[1])
E
python3 -I $TMPDIR/e.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_6r2x7p0k; cat >> $TMPDIR/e.py <<'E'
f2='rate ~ mtc+hum+I(hum**2)+C(sup)+hum:C(sup)+ambient_temp_c+C(sh)+dsc+C(line)'
r2=fit(f2);x['res']=x.rate-r2.predict(x)
x['w']=(x.date.dt.to_period('W')).astype(str)
x['wk']=x.t//14
print(x.pivot_table(index='wk',columns='line',values='res',aggfunc='mean').round(3).to_string())
print(x.groupby('operator_id').agg(res=('res','mean'),n=('res','size'),tm=('t','mean'),l4=('line',lambda s:(s=='L4').mean())).round(3).to_string())
E
python3 -I $TMPDIR/e.py 2>&1 | grep -v Warn | sed -n '/^wk/,$p'

cd /tmp/edabench_claude_6r2x7p0k; cat >> $TMPDIR/e.py <<'E'
print('----')
y=x[x.line=='L2'].sort_values('date')
best=[]
for dt in sorted(y.date.unique()):
    a=y[y.date<dt].res;b=y[y.date>=dt].res
    if len(a)>30 and len(b)>30:
        best.append((((a-a.mean())**2).sum()+((b-b.mean())**2).sum(),dt))
print(sorted(best)[:3])
print(y[(y.date>='2025-05-25')&(y.date<='2025-06-20')].groupby('date').res.mean().round(3).to_string())
E
python3 -I $TMPDIR/e.py 2>&1 | sed -n '/^----/,$p'

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/f.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/e.py').read().split("r=fit(f)")[0])
f2='rate ~ mtc+hum+I(hum**2)+C(sup)+hum:C(sup)+ambient_temp_c+C(sh)+dsc+C(line)+step'
out=[]
dates=sorted(x[x.line=='L2'].date.unique())
for dt in dates:
    if pd.Timestamp('2025-05-25')<=dt<=pd.Timestamp('2025-07-10'):
        x['step']=((x.line=='L2')&(x.date>=dt)).astype(int)
        r=fit(f2);out.append((r.deviance,str(dt)[:10],r.params['step']))
for o in sorted(out)[:6]:print(o)
E
python3 -I $TMPDIR/f.py 2>&1 | tail -7

cd /tmp/edabench_claude_6r2x7p0k; cat >> $TMPDIR/f.py <<'E'
x['step']=((x.line=='L2')&(x.date>='2025-06-12')).astype(int)
r=fit(f2);x['res']=x.rate-r.predict(x)
y=x[(x.line=='L2')&(x.date>='2025-06-05')&(x.date<='2025-06-20')].sort_values('date')
print(y[['batch_id','date','dsc','rate','res']].round(3).to_string())
print(pd.read_csv('maintenance.csv').query("line=='L2'").tail(12).to_string())
E
python3 -I $TMPDIR/f.py 2>&1 | sed -n '/batch_id/,$p'

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/g.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/e.py').read().split("r=fit(f)")[0])
d['over']=np.maximum(d.dsc-14,0)
z=d.copy(); z['mtc']=z.mtc.fillna(0); z['hum']=z.hum.fillna(30); z['hm']=d.hum.isna().astype(int); z['mm']=d.mt.isna().astype(int)
f2='rate ~ mtc+hum+I(hum**2)+C(sup)+hum:C(sup)+ambient_temp_c+C(sh)+dsc+I(dsc**2)+over+C(line)+hm+mm+step'
out=[]
for dt in sorted(z[z.line=='L2'].date.unique()):
    if pd.Timestamp('2025-05-30')<=dt<=pd.Timestamp('2025-06-25'):
        z['step']=((z.line=='L2')&(z.date>=dt)).astype(int)
        r=fit(f2,z);out.append((round(r.deviance,1),str(dt)[:10]))
print(sorted(out)[:8])
E
python3 -I $TMPDIR/g.py 2>&1 | tail -2

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/h.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/e.py').read().split("r=fit(f)")[0])
x['step']=((x.line=='L2')&(x.date>='2025-06-15')).astype(int)
x['over']=np.maximum(x.dsc-14,0)
f='rate ~ mtc+I(mtc**2)+hum*C(sup)+I(hum**2)*C(sup)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(sh)+dsc+over+C(line)+step+C(operator_id)+t'
r=fit(f);print(r.summary().tables[1])
print(x[['ambient_temp_c','t','mtc','hum','cycle_time_s','machine_age_years','dsc']].corr().round(2))
E
python3 -I $TMPDIR/h.py 2>&1 | grep -v -e 'C(operator' | tail -40

cd /tmp/edabench_claude_6r2x7p0k; cat >> $TMPDIR/h.py <<'E'
print('=====')
f0='rate ~ mtc+C(sh)+dsc+C(line)+step+C(sup)'
r0=fit(f0);x['res']=np.log(x.rate/r0.predict(x))
x['hb']=pd.cut(x.hum,range(0,80,5))
print(x.pivot_table(index='hb',columns='sup',values='res',aggfunc='mean').round(2))
print(x.pivot_table(index='hb',columns='sup',values='res',aggfunc='size'))
print(x.groupby('sup').hum.describe())
E
python3 -I $TMPDIR/h.py 2>&1 | sed -n '/=====/,$p'

cd /tmp/edabench_claude_6r2x7p0k; cat > $TMPDIR/i.py <<'E'
exec(open(__import__('os').environ['TMPDIR']+'/e.py').read().split("r=fit(f)")[0])
x['step']=((x.line=='L2')&(x.date>='2025-06-15')).astype(int)
for f in ['rate ~ mtc+hum*C(sup)+I(hum**2)*C(sup)+C(sh)+dsc+C(line)+step',
          'rate ~ mtc+hum*C(sup)+I(hum**2)*C(sup)+C(sh)+dsc+I(dsc**2)+C(line)+step']:
    r=fit(f);print(r.params.round(4).to_string(),r.deviance)
# full
r=fit('rate ~ mtc+hum*C(sup)+I(hum**2)*C(sup)+C(sh)+dsc+C(line)+step')
for s in ['SP-01','SP-02','SP-03']:
    z=x.copy();z['sup']=s;p=r.predict(z);print(s,(p*z.units_produced).sum()/z.units_produced.sum())
# alpha vertex
a=x[x.sup=='SP-01']
ra=fit('rate ~ mtc+hum+I(hum**2)+C(sh)+dsc+C(line)+step',a);print(ra.params, -ra.params['hum']/(2*ra.params['I(hum ** 2)']))
g=np.arange(12,73,.5);z=a.iloc[:1].copy();z=pd.concat([z]*len(g));z['hum']=g;pp=ra.predict(z);print(g[pp.values.argmin()])
# C3
b=r.params['dsc']
D=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
new=np.where(D.dsc>=14,D.dsc%14,D.dsc)
o=D.rate/(1-D.rate)*np.exp(b*(new-D.dsc));pn=o/(1+o)
print('C3',b,(pn*D.units_produced).sum()/D.units_produced.sum(), 'cap13',)
new=np.minimum(D.dsc,14);o=D.rate/(1-D.rate)*np.exp(b*(new-D.dsc));print((o/(1+o)*D.units_produced).sum()/D.units_produced.sum())
E
python3 -I $TMPDIR/i.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_6r2x7p0k; cat suppliers.csv
