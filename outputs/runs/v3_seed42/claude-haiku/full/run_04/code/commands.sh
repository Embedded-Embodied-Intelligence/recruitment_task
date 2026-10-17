ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && cat maintenance.csv && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('---',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    if df[c].nunique()<40: print(vc.to_dict())
    else: print(df[c].head(3).tolist(), 'sample odd:', [v for v in df[c].unique()[:0]])
print('dup batch rows', df.duplicated().sum(), 'dup batch_id', df.batch_id.duplicated().sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup groups identical?', (d.groupby('batch_id').nunique()>1).sum().sum())
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x=pd.to_numeric(df[c].str.strip(),errors='coerce')
    bad=df[c][x.isna()].unique()
    print(c,'nonnum:',bad[:10],'n=',x.isna().sum(),'min',x.min(),'max',x.max(),'median',x.median())
print(df.production_date.min(), df.production_date.max())
print(pd.to_datetime(df.production_date,errors='coerce').isna().sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv')
df['shift_n']=df['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
df=df.drop_duplicates()
print(len(df), df.batch_id.nunique())
print('humidity counts <0 or >100:', ((df.humidity_pct<0)|(df.humidity_pct>100)).sum(), df.humidity_pct[df.humidity_pct<0].value_counts().to_dict())
print('humidity hist', np.histogram(df.humidity_pct.dropna(), bins=[-2,0,10,20,30,40,50,60,70,80])[0])
print('mold_temp hist', np.histogram(df.mold_temp, bins=[-1,50,100,150,180,200,220,240,260,300,350,400,460])[0])
print(df[df.mold_temp<100][['batch_id','production_date','line','mold_temp']].to_string())
print('mold>300 count', (df.mold_temp>300).sum())
print('defective>units', (df.defective_units>df.units_produced).sum())
print('shift_n', df.shift_n.value_counts(dropna=False).to_dict())
print(df.groupby('line').mold_temp.describe())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
df['d']=pd.to_datetime(df.production_date)
df['m']=df.d.dt.to_period('M')
nz=df[df.mold_temp>0]
print(nz.groupby(['line','m']).mold_temp.median().unstack(0).round(1).to_string())
print('L3 min nonzero', nz[nz.line=='L3'].mold_temp.min(), 'L3 max', nz[nz.line=='L3'].mold_temp.max())
print('L1 by week around 04-14 and 09-22')
l1=nz[nz.line=='L1'].set_index('d').mold_temp
print(l1['2025-04-01':'2025-04-30'].resample('W').median().round(1).to_string())
print(l1['2025-09-01':'2025-09-30'].resample('W').median().round(1).to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
df['d']=pd.to_datetime(df.production_date)
nz=df[(df.mold_temp>0)].copy()
nz.loc[nz.line=='L3','mold_temp']=(nz.loc[nz.line=='L3','mold_temp']-32)*5/9
w=nz.set_index('d').groupby('line').mold_temp.resample('2W').median().unstack(0)
w['L1-others']=w.L1-w[['L2','L4']].mean(axis=1)
print(w.round(1).to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
df['d']=pd.to_datetime(df.production_date)
nz=df[(df.mold_temp>0)].copy()
nz.loc[nz.line=='L3','mold_temp']=(nz.loc[nz.line=='L3','mold_temp']-32)*5/9
daily=nz.groupby(['d','line']).mold_temp.median().unstack()
others=daily[['L2','L4','L3']].mean(axis=1)
diff=(daily.L1-others).dropna()
r=diff.rolling(7,min_periods=3,center=True).median()
print(r['2025-04-01':'2025-05-31'].round(1).to_string())
print('after 2025-05-10 mean diff', diff['2025-05-10':].mean().round(2), 'before 04-14', diff[:'2025-04-13'].mean().round(2), 'between 04-14 and 05-05', diff['2025-04-14':'2025-05-05'].mean().round(2))
"

mkdir -p $TMPDIR/an && cat > $TMPDIR/an/clean.py <<'EOF'
import pandas as pd, numpy as np
D='/tmp/edabench_claude_qd1w12ft/'
raw=pd.read_csv(D+'batches.csv')
df=raw.drop_duplicates().copy()
df['date']=pd.to_datetime(df.production_date)
df['shift']=df['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
df['supplier_code']=df.supplier_code.str.strip().str.upper()
sup=pd.read_csv(D+'suppliers.csv')
df=df.merge(sup[['supplier_code','supplier_name','resin_grade','pre_dried']],on='supplier_code',how='left')
df['humidity']=df.humidity_pct.where(df.humidity_pct>=0)
df['mold_c']=df.mold_temp.where(df.mold_temp>0)
f=df.line.eq('L3')&df.mold_c.notna()
df.loc[f,'mold_c']=(df.loc[f,'mold_c']-32)*5/9
f=df.line.eq('L1')&(df.date>=pd.Timestamp('2025-04-14'))&df.mold_c.notna()
df.loc[f,'mold_c']=df.loc[f,'mold_c']-8.0
df['rate']=df.defective_units/df.units_produced
df['bad']=df.defective_units
df['good']=df.units_produced-df.defective_units
EOF
cd $TMPDIR/an && python3 -c "
exec(open('clean.py').read())
print(df.supplier_name.isna().sum(), df.shift.isna().sum(), df.humidity.isna().sum(), df.mold_c.isna().sum())
print('overall', df.defective_units.sum()/df.units_produced.sum())
print(df.groupby('supplier_name').apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum(),'hum_mean':g.humidity.mean()})).round(4))
print(df[['rate','qc_inspection_min','rework_cost_eur','cycle_time_s','mold_c','humidity','machine_age_years','ambient_temp_c','units_produced']].corr().round(3).to_string())
print(df.groupby('line').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(df.groupby('shift').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(df.groupby('operator_id').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).sort_values().to_string())
"

cd $TMPDIR/an && python3 -c "
exec(open('clean.py').read())
print(df.supplier_name.isna().sum(), df['shift'].isna().sum(), df.humidity.isna().sum(), df.mold_c.isna().sum())
print('overall', df.defective_units.sum()/df.units_produced.sum())
g=lambda k: df.groupby(k).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum(),'hum_mean':g.humidity.mean()})).round(4)
print(g('supplier_name'))
print(df[['rate','qc_inspection_min','rework_cost_eur','cycle_time_s','mold_c','humidity','machine_age_years','ambient_temp_c','units_produced']].corr().round(3).to_string())
print(g('line')); print(g('shift')); print(g('operator_id').sort_values('rate').to_string())
" 2>&1 | grep -v Warning

cd $TMPDIR/an && python3 -c "
import statsmodels, sklearn; print('ok', statsmodels.__version__)" ; python3 -c "
exec(open('clean.py').read())
import numpy as np
df['rw_per_def']=df.rework_cost_eur/df.defective_units
print(df.rw_per_def.describe().round(3).to_string())
print(np.corrcoef(df.rework_cost_eur, df.defective_units)[0,1], np.corrcoef(df.qc_inspection_min, df.defective_units)[0,1], np.corrcoef(df.qc_inspection_min, df.units_produced)[0,1])
import statsmodels.formula.api as smf
m=smf.ols('qc_inspection_min ~ defective_units + units_produced', df).fit(); print(m.rsquared.round(3))
m=smf.ols('rework_cost_eur ~ defective_units + units_produced', df).fit(); print(m.rsquared.round(3), m.params.round(3).to_dict())
print(pd.crosstab(df.operator_id, df.line).to_string())
print(df.groupby('operator_id').machine_age_years.mean().round(2).to_dict())
" 2>&1 | grep -v Warn

cd $TMPDIR/an && python3 -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
d=df.dropna(subset=['humidity','mold_c']).copy()
d['sup']=d.supplier_name
m=smf.glm('rate ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(sup) + C(line)', d, family=sm.families.Binomial(), var_weights=d.units_produced).fit(scale='X2')
print(m.summary().tables[1])
" 2>&1 | grep -v Warn | head -80

cd $TMPDIR/an && cat > fit.py <<'EOF'
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
mt=pd.read_csv(D+'maintenance.csv',parse_dates=['date'])
cl=mt[mt.event=='mold_cleaning'][['date','line']]
def days_since(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date-pd.Timedelta(days=0))]
    # cleaning before the first shift of the day counts for that day
    c=cl[(cl.line==r.line)&(cl.date<=r.date)]
    return (r.date-c.date.max()).days if len(c) else np.nan
d=df.dropna(subset=['humidity','mold_c']).copy()
d['sup']=d.supplier_name
d['dsc']=d.apply(days_since,axis=1)
d['fam']=sm.families.Binomial()
base='rate ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(sup) + C(line)'
def fit(f,data=d): return smf.glm(f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
full=fit(base)
def lr(f):
    m=fit(f); stat=2*(full.llf-m.llf) if False else 2*(m.llf-full.llf)
    return stat
EOF
python3 -c "
exec(open('fit.py').read())
print('days since cleaning missing', d.dsc.isna().sum(), d.dsc.describe().round(1).to_dict())
full=fit(base); print('full llf',full.llf)
ddf={'mold':'mold_c','humidity':'humidity','cycle':'cycle_time_s','age':'machine_age_years','ambient':'ambient_temp_c','op':'C(operator_id)','shift':'C(shift)','sup':'C(sup)','line':'C(line)'}
for k,t in ddf.items():
    f=base.replace(' + '+t,'').replace(t+' + ','')
    if t in ('C(line)',): pass
    m=fit(f); st=2*(full.llf-m.llf); dfn=full.df_model-m.df_model
    print(k, 'LR',round(st,2),'df',dfn,'p',stats.chi2.sf(st,dfn))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && python3 -c "
exec(open('fit.py').read())
def qfit(f,data=d): return smf.glm(f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
full=qfit(base); sc=full.scale; print('scale',round(sc,3))
def test(f,label):
    m=fit(f); st=2*(full.llf-m.llf)/sc if False else 2*(full.llf-m.llf)/sc; 
    dfn=full.df_model-m.df_model
    print(label,'chi2/scale',round(abs(st),2),'df',dfn,'p',round(stats.chi2.sf(abs(st),dfn),5))
test(base.replace(' + C(shift)',''),'shift')
test(base.replace(' + C(operator_id)',''),'operator(line kept)')
test(base.replace(' + machine_age_years',''),'age')
test(base.replace(' + humidity',''),'humidity')
test(base.replace(' + cycle_time_s',''),'cycle')
test(base.replace(' + ambient_temp_c',''),'ambient')
test(base.replace(' + mold_c',''),'mold')
test(base.replace(' + C(sup)',''),'supplier')
print(qfit(base+' + dsc').summary().tables[1])
print(qfit(base+' + humidity:C(sup)').summary().tables[1])
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('fit.py').read())
def qfit(f,data=d): return smf.glm(f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
core='rate ~ mold_c + cycle_time_s + C(shift) + C(operator_id) + humidity:C(sup) + humidity + C(sup) + dsc + ambient_temp_c'
for lab,sub in [('L2+L4 only',d[d.line.isin(['L2','L4'])]),('L1 pre-Apr14 + L2 + L4',d[(d.line!='L1')|(d.date<'2025-04-14')])]:
    m=qfit(core.replace('+ C(operator_id)','+ C(line)'),sub)
    print(lab, m.params[['mold_c','ambient_temp_c','C(shift)[T.Night]','cycle_time_s','dsc']].round(4).to_dict(), m.pvalues[['ambient_temp_c','C(shift)[T.Night]']].round(5).to_dict())
# dsc shape
m=qfit(base+' + C(pd.cut(dsc,[-1,3,7,10,14,20,40]))'.replace('C(operator_id)','C(operator_id)'),d)
print(m.params.filter(like='pd.cut').round(3).to_dict())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > model.py <<'EOF'
exec(open('fit.py').read())
def qfit(f,data=d): return smf.glm(f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
PRED='rate ~ mold_c + cycle_time_s + C(shift) + ambient_temp_c + dsc + humidity:C(sup) + humidity + C(sup) + C(line)'
EOF
python3 -c "
exec(open('model.py').read())
m=qfit(PRED,d)
print(m.params.round(4).to_dict())
d['pred']=m.predict(d)*d.units_produced
d['res']=d.defective_units-d.pred
d['wk']=d.date.dt.to_period('M')
t=d.groupby(['wk','line']).agg(res=('res','sum'),n=('res','size'),u=('units_produced','sum')).reset_index()
t['z']=t.res/np.sqrt((d.pred.sum()/d.units_produced.sum())*t.u)
print(t.pivot(index='wk',columns='line',values='z').round(2).to_string())
print('total resid', d.res.sum().round(1))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
m=qfit(PRED,d)
d['pred']=m.predict(d)*d.units_produced
d['res']=d.defective_units-d.pred
p=d.pred.sum()/d.units_produced.sum()
for L in ['L1','L2','L3','L4']:
    s=d[d.line==L].sort_values('date').reset_index(drop=True)
    best=None
    for i in range(30,len(s)-30):
        a=s.iloc[:i]; b=s.iloc[i:]
        # standardized mean diff of residual rate
        ra=a.res.sum()/a.pred.sum(); rb=b.res.sum()/b.pred.sum()
        z=(ra-rb)/np.sqrt(p*(1/a.units_produced.sum()+1/b.units_produced.sum())) if False else (b.res.sum()-b.pred.sum()*0)/ (np.sqrt(b.pred.sum())) 
        # simple chi2-like statistic for step in residual sums
        stat=(b.res.sum()/np.sqrt(b.pred.sum())) - (a.res.sum()/np.sqrt(a.pred.sum()))
        st=abs((rb-ra))
        if best is None or st>best[0]: best=(st,s.date[i].date(),ra,rb,i)
    print(L, 'best changepoint', best[1], 'before rate resid', round(best[2],4),'after', round(best[3],4), 'n before',best[4],'after',len(s)-best[4])
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
m=qfit(PRED,d)
d['pred']=m.predict(d)*d.units_produced
d['res']=d.defective_units-d.pred
for L in ['L1','L2','L3','L4']:
    s=d[d.line==L].sort_values('date').reset_index(drop=True)
    best=(0,None)
    for i in range(20,len(s)-20):
        a=s.iloc[:i]; b=s.iloc[i:]
        ra=a.res.sum()/a.pred.sum(); rb=b.res.sum()/b.pred.sum()
        se=np.sqrt(m.scale*(1/a.pred.sum()+1/b.pred.sum()))
        z=(rb-ra)/se
        if abs(z)>abs(best[0]): best=(z,s.date[i].date(),ra,rb)
    print(L,'z',round(best[0],2),'changepoint',best[1],'res before',round(best[2],3),'after',round(best[3],3))
s=d[d.line=='L2'].sort_values('date')
print(s.set_index('date').resample('W')[['res','pred']].sum().assign(r=lambda x:x.res/x.pred).round(2)['2025-04-01':'2025-07-31'].to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
m=qfit(PRED,d)
d['pred']=m.predict(d)*d.units_produced
d['res']=d.defective_units-d.pred
s=d[(d.line=='L2')].sort_values(['date','batch_id'])
x=s[(s.date>='2025-06-08')&(s.date<='2025-06-22')]
print(x.groupby('date').agg(n=('res','size'),res=('res','sum'),pred=('pred','sum'),dsc=('dsc','mean')).assign(r=lambda t:(t.res/t.pred).round(2)).to_string())
# candidate onset: best split on batch index within L2 near that window
s=s.reset_index(drop=True)
best=(0,None)
for i in range(300,len(s)-200):
    a=s.iloc[:i]; b=s.iloc[i:]
    ra=a.res.sum()/a.pred.sum(); rb=b.res.sum()/b.pred.sum()
    z=(rb-ra)/np.sqrt(m.scale*(1/a.pred.sum()+1/b.pred.sum()))
    if abs(z)>abs(best[0]): best=(z,i,s.date[i].date(),s.date[i-1].date())
print('best L2 split z',round(best[0],2),'first batch date after',best[2],'last before',best[3])
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
m=qfit(PRED,d)
d['pred']=m.predict(d)*d.units_produced
d['res']=d.defective_units-d.pred
d['bin']=pd.cut(d.dsc,[-1,2,5,8,11,14,20,40])
d['per']=np.where((d.line=='L2')&(d.date>='2025-06-15'),'L2 after','L2 before/other')
t=d.groupby(['line','bin','per'],observed=True).agg(n=('res','size'),r=('res','sum'),p=('pred','sum'))
t['ratio']=(t.r/t.p).round(3)
print(t.to_string())
print(d.groupby(['line']).apply(lambda g: g.dsc.max()).to_dict())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
F=PRED+' + l2shift'
m=qfit(F,d); print('scale',round(m.scale,3)); print(m.summary().tables[1])
full=m
def test(f,label):
    mm=fit(f) if False else smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
    fu=smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
    st=2*(fu.llf-mm.llf)/m.scale; dfn=fu.df_model-mm.df_model
    print(label,'chi2',round(abs(st),2),'df',dfn,'p',round(stats.chi2.sf(abs(st),dfn),4))
test(F.replace(' + C(shift)',''),'shift')
test(F.replace(' + ambient_temp_c',''),'ambient')
test(F.replace(' + machine_age_years',''),'age') if 'machine_age_years' in F else None
test(F.replace(' + cycle_time_s',''),'cycle')
test(F.replace(' + mold_c',''),'mold')
test(F.replace(' + humidity:C(sup)',''),'hum x sup (keep main)')
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
F=PRED+' + l2shift + machine_age_years + C(operator_id)'
fu=smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
sc=fu.scale; print('scale',round(sc,3))
print(fu.params[['machine_age_years']].round(4).to_dict(), fu.pvalues[['machine_age_years']].round(3).to_dict())
def test(f,label):
    mm=smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
    st=2*(fu.llf-mm.llf)/sc; dfn=fu.df_model-mm.df_model
    print(label,'chi2',round(abs(st),2),'df',dfn,'p',round(stats.chi2.sf(abs(st),dfn),4))
test(F.replace(' + machine_age_years',''),'age')
test(F.replace(' + C(operator_id)',''),'operator (line kept)')
test(F.replace(' + C(operator_id)','').replace(' + C(line)',''),'operator and line together')
test(F.replace(' + C(shift)',''),'shift')
test(F.replace(' + C(sup)',''),'supplier main (interaction kept)')
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
F=PRED+' + l2shift'
base_m=smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
d['res']=d.defective_units-base_m.predict(d)*d.units_produced
g=d.groupby(['line','operator_id']).apply(lambda g: pd.Series({'n':len(g),'res_ratio':g.res.sum()/(g.defective_units.sum()-g.res.sum()) if False else g.res.sum()/(base_m.predict(g)*g.units_produced).sum(), 'first':g.date.min().date(),'last':g.date.max().date()}))
print(g.round(3).to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
F=PRED+' + l2shift'
bm=smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
d['pr']=bm.predict(d)*d.units_produced
d['res']=d.defective_units-d.pr
g=d.groupby(['line','operator_id']).agg(n=('res','size'),res=('res','sum'),pred=('pr','sum'),first=('date','min'),last=('date','max'))
g['ratio']=(g.res/g.pred).round(3)
print(g.round(2).to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && timeout 900 python3 -c "
exec(open('model.py').read())
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
F0=PRED+' + l2shift'
F1=F0+' + C(operator_id)'
m0=smf.glm(F0,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
m1=smf.glm(F1,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
sc=m1.pearson_chi2/m1.df_resid
obs=2*(m1.llf-m0.llf)/sc
print('scale',round(sc,3),'observed stat',round(obs,2))
rng=np.random.default_rng(1)
dd=d.copy(); cnt=0; N=200; stats_=[]
for b in range(N):
    perm=dd.groupby('line').operator_id.transform(lambda s: rng.permutation(s.values))
    dd['operator_id']=perm
    mp=smf.glm(F1,dd,family=sm.families.Binomial(),var_weights=dd.units_produced).fit()
    s=2*(mp.llf-m0.llf)/(mp.pearson_chi2/mp.df_resid)
    stats_.append(s)
stats_=np.array(stats_)
print('perm mean',stats_.mean().round(2),'95th',np.percentile(stats_,95).round(2),'p',(np.sum(stats_>=obs)+1)/(N+1))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && python3 -c "
exec(open('model.py').read())
import statsmodels.formula.api as smf
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
m_proc=smf.ols('qc_inspection_min ~ mold_c + humidity + cycle_time_s + C(shift) + ambient_temp_c + dsc + C(sup) + C(line) + machine_age_years + l2shift',d).fit()
print('qc from process vars R2', round(m_proc.rsquared,3))
m_out=smf.ols('qc_inspection_min ~ defective_units + units_produced',d).fit()
print('qc from defects+units R2', round(m_out.rsquared,3), m_out.params.round(4).to_dict())
m_all=smf.ols('qc_inspection_min ~ defective_units + units_produced + mold_c + humidity + cycle_time_s + C(shift) + ambient_temp_c + dsc + C(sup) + C(line)+ l2shift',d).fit()
print('all R2', round(m_all.rsquared,3), 'defect t', round(m_all.tvalues['defective_units'],1), 'shift t', round(m_all.tvalues.get('C(shift)[T.Night]',np.nan),2))
print('rework from defects R2', round(smf.ols('rework_cost_eur ~ defective_units',d).fit().rsquared,4))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > final.py <<'EOF'
exec(open('model.py').read())
# ---------- A ----------
print('A1 unique batches', df.batch_id.nunique(), len(df))
print('A2 humidity invalid', df.humidity.isna().sum(), 'of which blank', df.humidity_pct.isna().sum() if False else raw.drop_duplicates().humidity_pct.isna().sum(), 'sentinel -1', (raw.drop_duplicates().humidity_pct<0).sum())
print('A3 overall rate', df.defective_units.sum()/df.units_produced.sum(), df.defective_units.sum(), df.units_produced.sum())
mc=df.mold_c.dropna()
print('A4 median mold C', round(mc.median(),4), 'n', len(mc), 'mean', round(mc.mean(),3))
print('A4 median without L1 correction', round(df.assign(x=df.mold_c).x.where(~((df.line=='L1')&(df.date>='2025-04-14')), df.mold_temp.where(df.mold_temp>0)).median(),3))
EOF
python3 final.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > cans.py <<'EOF'
exec(open('model.py').read())
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
F='rate ~ mold_c + cycle_time_s + C(shift) + dsc + humidity:C(sup) + humidity + C(sup) + C(line) + l2shift'
M=smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
print(M.params.round(4).to_dict())
# all-batch frame: humidity missing rows get averaged over observed humidity values
A=df.copy()
A['sup']=A.supplier_name
A['l2shift']=((A.line=='L2')&(A.date>=pd.Timestamp('2025-06-15'))).astype(int)
obsH=A.humidity.dropna().values
def expected_defects(frame):
    tot=0.0
    ok=frame[frame.humidity.notna()]
    p=M.predict(ok)*ok.units_produced
    tot+=p.sum()
    miss=frame[frame.humidity.isna()]
    for _,r in miss.iterrows():
        g=pd.DataFrame([r]*len(obsH))
        g['humidity']=obsH
        tot+=(M.predict(g)*g.units_produced.iloc[0]).mean()
    return tot
base_pred=expected_defects(A.assign(dsc=A.dsc if 'dsc' in A else np.nan) if False else A)
EOF
echo written

cd $TMPDIR/an && cat > cans.py <<'EOF'
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
D='/tmp/edabench_claude_qd1w12ft/'
mt=pd.read_csv(D+'maintenance.csv',parse_dates=['date'])
cl=mt[mt.event=='mold_cleaning']
def dsc_real(line,t):
    c=cl[(cl.line==line)&(cl.date<=t)]
    return (t-c.date.max()).days
A=df.copy()
A['sup']=A.supplier_name
A['l2shift']=((A.line=='L2')&(A.date>=pd.Timestamp('2025-06-15'))).astype(int)
A['dsc']=[dsc_real(l,t) for l,t in zip(A.line,A.date)]
# counterfactual cleaning: real cleanings plus a forced one whenever 14 days have passed
days=pd.date_range('2024-12-01','2025-09-30')
cf={}
for L in ['L1','L2','L3','L4']:
    last=cl[(cl.line==L)&(cl.date<pd.Timestamp('2025-01-06'))].date.max()
    real=set(cl[cl.line==L].date)
    cf_last={}
    for t in days:
        if t in real or (t-last).days>=14: last=t
        cf_last[t]=last
    cf[L]=cf_last
A['dsc_cf']=[(t-cf[l][t]).days for l,t in zip(A.line,A.date)]
print('dsc_cf range',A.dsc_cf.min(),A.dsc_cf.max(),'dsc real max',A.dsc.max())
A['rate_']=A.defective_units/A.units_produced
d=A.dropna(subset=['humidity','mold_c'])
F='rate ~ mold_c + cycle_time_s + C(shift) + dsc + humidity:C(sup) + humidity + C(sup) + C(line) + l2shift'
M=smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
print(M.params.round(4).to_dict())
obsH=d.humidity.values
def pred_defects(frame,dsccol):
    f=frame.copy(); f['dsc']=f[dsccol]
    out=np.zeros(len(f))
    ok=f.humidity.notna().values & f.mold_c.notna().values
    out[ok]=M.predict(f[ok])*f.units_produced[ok]
    for i in np.where(~ok)[0]:
        g=pd.DataFrame([f.iloc[i]]*len(obsH)).reset_index(drop=True)
        g['humidity']=obsH
        out[i]=(M.predict(g)*f.units_produced.iloc[i]).mean()
    return out
A['pd_obs']=pred_defects(A,'dsc')
A['pd_cf']=pred_defects(A,'dsc_cf')
U=A.units_produced.sum()
print('calibration: actual',A.defective_units.sum(),'pred',round(A.pd_obs.sum(),1))
print('C3 rate observed-cleaning baseline',round(A.pd_obs.sum()/U,5),' cleaned every 14 days',round(A.pd_cf.sum()/U,5))
# C1 supplier counterfactual: everything else as observed
res={}
for s in ['Alpha','Beta','Gamma']:
    f=A.copy(); f['sup']=s
    res[s]=pred_defects(f,'dsc').sum()/U
print('C1 counterfactual overall rate by supplier', {k:round(v,5) for k,v in res.items()})
# C2 Alpha humidity curve, others as observed for each batch
alp=A[(A.sup=='Alpha')].dropna(subset=['mold_c'])
print('humidity range valid', A.humidity.min(), A.humidity.max())
grid=np.arange(np.floor(A.humidity.min()*10)/10, A.humidity.max()+0.01, 0.1)
curve=[]
for h in grid:
    g=alp.copy(); g['humidity']=h
    curve.append((M.predict(g)*g.units_produced).sum()/g.units_produced.sum())
curve=np.array(curve)
print('C2 argmin', grid[curve.argmin()].round(2), curve.min().round(5), 'at min', grid[0].round(2), curve[0].round(5), 'at max', grid[-1].round(2), curve[-1].round(5))
EOF
python3 cans.py 2>&1 | grep -v -i warn | grep -v wls

sleep 100; cat /tmp/claude-0/-tmp-edabench-claude-qd1w12ft/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bonjwx1xb.output | grep -v -i warn | grep -v wls

cat /tmp/claude-0/-tmp-edabench-claude-qd1w12ft/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bonjwx1xb.output | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > check_missing.py <<'EOF'
exec(open('clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
D='/tmp/edabench_claude_qd1w12ft/'
mt=pd.read_csv(D+'maintenance.csv',parse_dates=['date']); cl=mt[mt.event=='mold_cleaning']
A=df.copy(); A['sup']=A.supplier_name
A['l2shift']=((A.line=='L2')&(A.date>=pd.Timestamp('2025-06-15'))).astype(int)
A['dsc']=[(t-cl[(cl.line==l)&(cl.date<=t)].date.max()).days for l,t in zip(A.line,A.date)]
A['raw_hum']=raw.drop_duplicates().humidity_pct.values
A['miss']=A.humidity.isna()
d=A.dropna(subset=['humidity','mold_c'])
F='rate ~ mold_c + cycle_time_s + C(shift) + dsc + humidity:C(sup) + humidity + C(sup) + C(line) + l2shift'
M=smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
print('scale', round(M.scale,2))
# predicted for rows with valid humidity only; compare with actual by group
d=d.assign(pr=M.predict(d)*d.units_produced)
print('valid: actual',d.defective_units.sum(),'pred',round(d.pr.sum(),1))
x=A[A.raw_hum<0]; print('sentinel rows',len(x),x.defective_units.sum(),x.units_produced.sum(), 'rate', round(x.defective_units.sum()/x.units_produced.sum(),4))
y=A[A.raw_hum.isna()]; print('blank rows',len(y),y.defective_units.sum(),y.units_produced.sum(), 'rate', round(y.defective_units.sum()/y.units_produced.sum(),4))
print('sentinel by sup', x.supplier_name.value_counts().to_dict(), 'blank by sup', y.supplier_name.value_counts().to_dict())
print('sentinel by line', x.line.value_counts().to_dict(), 'blank by line', y.line.value_counts().to_dict())
print('valid rate', round(d.defective_units.sum()/d.units_produced.sum(),4))
EOF
timeout 110 python3 check_missing.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > cfinal.py <<'EOF'
exec(open('clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
D='/tmp/edabench_claude_qd1w12ft/'
mt=pd.read_csv(D+'maintenance.csv',parse_dates=['date']); cl=mt[mt.event=='mold_cleaning']
A=df.copy(); A['sup']=A.supplier_name
A['l2shift']=((A.line=='L2')&(A.date>=pd.Timestamp('2025-06-15'))).astype(int)
A['dsc']=[(t-cl[(cl.line==l)&(cl.date<=t)].date.max()).days for l,t in zip(A.line,A.date)]
days=pd.date_range('2024-12-01','2025-09-30'); cf={}
for L in ['L1','L2','L3','L4']:
    last=cl[(cl.line==L)&(cl.date<pd.Timestamp('2025-01-06'))].date.max(); real=set(cl[cl.line==L].date); cf_last={}
    for t in days:
        if t in real or (t-last).days>=14: last=t
        cf_last[t]=last
    cf[L]=cf_last
A['dsc_cf']=[(t-cf[l][t]).days for l,t in zip(A.line,A.date)]
# mold temperature imputation model: mold ~ ambient + line, from valid readings
mv=A.dropna(subset=['mold_c'])
mm=smf.ols('mold_c ~ ambient_temp_c + C(line)',mv).fit()
resid_pool=mm.resid.values
d=A.dropna(subset=['humidity','mold_c'])
F='rate ~ mold_c + cycle_time_s + C(shift) + dsc + humidity:C(sup) + humidity + C(sup) + C(line) + l2shift'
M=sm.formula.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2') if False else smf.glm(F,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
rng=np.random.default_rng(0)
K=300
hum_pool=d.humidity.values
def expected(frame,dscc,sup=None):
    f=frame.copy()
    if sup is not None: f['sup']=sup
    f['dsc']=f[dscc]
    out=pd.Series(0.0,index=f.index)
    full=f.dropna(subset=['humidity','mold_c'])
    out[full.index]=M.predict(full)*full.units_produced
    rest=f[f.humidity.isna()|f.mold_c.isna()]
    if len(rest):
        rows=[]
        for idx,r in rest.iterrows():
            base=pd.DataFrame([r]*K).reset_index(drop=True)
            base['humidity']=rng.choice(hum_pool,K) if pd.isna(r.humidity) else r.humidity
            base['mold_c']=(mm.predict(pd.DataFrame({'ambient_temp_c':[r.ambient_temp_c],'line':[r.line]})).values[0]+rng.choice(resid_pool,K)) if pd.isna(r.mold_c) else r.mold_c
            base['idx']=idx
            rows.append(base)
        big=pd.concat(rows,ignore_index=True)
        big['p']=M.predict(big)*big.units_produced
        out[rest.index]=big.groupby('idx').p.mean()
    return out
A['pd_obs']=expected(A,'dsc')
A['pd_cf']=expected(A,'dsc_cf')
U=A.units_produced.sum()
print('calibration actual',A.defective_units.sum(),'pred',round(A.pd_obs.sum(),1))
print('C3 baseline model',round(A.pd_obs.sum()/U,5),'cleaned every 14 days',round(A.pd_cf.sum()/U,5))
for s in ['Alpha','Beta','Gamma']:
    print('C1',s,round(expected(A,'dsc',sup=s).sum()/U,5))
hgrid=np.linspace(A.humidity.min(),A.humidity.max(),600)
alp=d[d.sup=='Alpha']
curve=[]
for h in hgrid:
    g=alp.copy(); g['humidity']=h
    curve.append((M.predict(g)*g.units_produced).sum()/g.units_produced.sum())
curve=np.array(curve)
print('C2 humidity range',A.humidity.min(),A.humidity.max(),'argmin',round(hgrid[curve.argmin()],2),'min',round(curve.min(),5),'at ends',round(curve[0],5),round(curve[-1],5))
print('coef', M.params.round(4).to_dict())
EOF
timeout 115 python3 cfinal.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && timeout 100 python3 -c "
exec(open('clean.py').read())
import statsmodels.formula.api as smf
d=df.dropna(subset=['humidity','mold_c']).copy()
d['l2']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['dsc']=0
a=d[d.supplier_name=='Alpha'].copy()
a['bin']=pd.cut(a.humidity,[10,15,20,25,30,35,40,45,50,55,60,65,75])
t=a.groupby('bin',observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()}))
print(t.round(4).to_string())
b=d[d.supplier_name!='Alpha'].copy(); b['bin']=pd.cut(b.humidity,[10,20,30,40,50,60,75])
print(b.groupby(['supplier_name','bin'],observed=True).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).unstack(0).to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && timeout 110 python3 -c "
exec(open('clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
D='/tmp/edabench_claude_qd1w12ft/'
mt=pd.read_csv(D+'maintenance.csv',parse_dates=['date']); cl=mt[mt.event=='mold_cleaning']
d=df.dropna(subset=['humidity','mold_c']).copy(); d['sup']=d.supplier_name
d['l2shift']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-15'))).astype(int)
d['dsc']=[(t-cl[(cl.line==l)&(cl.date<=t)].date.max()).days for l,t in zip(d.line,d.date)]
d['h2']=(d.humidity-35)**2
base='rate ~ mold_c + cycle_time_s + C(shift) + dsc + C(line) + l2shift + humidity:C(sup) + humidity + C(sup)'
fit=lambda f: smf.glm(f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
m0=fit(base); m1=fit(base+' + h2'); m2=fit(base+' + h2:C(sup)')
sc=m2.pearson_chi2/m2.df_resid
print('scale',round(sc,3))
for nm,mm in [('lin',m0),('quad common',m1),('quad by sup',m2)]:
    print(nm,'llf',round(mm.llf,1),'aic',round(mm.aic,1))
print(m2.params.filter(like='h').round(5).to_dict())
print('LR quad-by-sup vs lin (scaled)', round(2*(m2.llf-m0.llf)/sc,1), 'df', m2.df_model-m0.df_model)
# optimum per supplier of humidity term
for s in ['Alpha','Beta','Gamma']:
    b=m2.params
    h=b['humidity']+(b.get('humidity:C(sup)[T.Beta]',0) if s=='Beta' else b.get('humidity:C(sup)[T.Gamma]',0) if s=='Gamma' else 0)
    q=b['h2']+(b.get('h2:C(sup)[T.Beta]',0) if s=='Beta' else b.get('h2:C(sup)[T.Gamma]',0) if s=='Gamma' else 0)
    print(s,'linear',round(h,5),'quad',round(q,5),'vertex', round(35-h/(2*q),2) if q>0 else 'none')
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > spec.py <<'EOF'
exec(open('clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
D='/tmp/edabench_claude_qd1w12ft/'
mt=pd.read_csv(D+'maintenance.csv',parse_dates=['date']); cl=mt[mt.event=='mold_cleaning']
A=df.copy(); A['sup']=A.supplier_name
A['l2shift']=((A.line=='L2')&(A.date>=pd.Timestamp('2025-06-15'))).astype(int)
A['dsc']=[(t-cl[(cl.line==l)&(cl.date<=t)].date.max()).days for l,t in zip(A.line,A.date)]
A['hsq']=A.humidity**2
d=A.dropna(subset=['humidity','mold_c']).copy()
F='rate ~ mold_c + cycle_time_s + C(shift) + dsc + C(line) + l2shift + humidity + hsq + humidity:C(sup) + C(sup)'
fit=lambda f,data=d: smf.glm(f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
M=fit(F).__class__  # placeholder
M=fit(F); sc=M.pearson_chi2/M.df_resid
print('scale',round(sc,3)); print(M.params.round(5).to_dict())
print('pvals', M.pvalues.round(4).to_dict())
def lrt(f_drop,label):
    mm=fit(f_drop); st=2*(M.llf-mm.llf)/sc; dfn=M.df_model-mm.df_model
    print('drop',label,'chi2',round(st,2),'df',dfn,'p',round(stats.chi2.sf(st,dfn),4))
lrt(F.replace(' + C(shift)',''),'shift')
lrt(F.replace(' + dsc',''),'cleaning age')
lrt(F.replace(' + cycle_time_s',''),'cycle')
lrt(F.replace(' + mold_c',''),'mold')
lrt(F.replace(' + humidity:C(sup)',''),'humidity x supplier')
lrt(F.replace(' + hsq',''),'humidity quadratic')
lrt(F.replace(' + C(line)','')  ,'line')
# extra candidates
G=F+' + ambient_temp_c'
mg=fit(G); print('ambient added: p', round(mg.pvalues['ambient_temp_c'],4), 'coef', round(mg.params['ambient_temp_c'],5))
G=F+' + machine_age_years'
mg=fit(G); print('age added: p', round(mg.pvalues['machine_age_years'],4))
G=F+' + C(operator_id)'
mg=fit(G); st=2*(mg.llf-M.llf)/sc; print('operator added (scaled LR)', round(st,2), 'df', mg.df_model-M.df_model, 'p', round(stats.chi2.sf(st,mg.df_model-M.df_model),4))
EOF
timeout 115 python3 spec.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > age.py <<'EOF'
exec(open('spec.py').read().split("print('scale'")[0])
print(A.groupby('line').machine_age_years.describe().round(2).to_string())
print(A.groupby(['line','operator_id']).machine_age_years.agg(['mean','std']).round(2).head(30).to_string())
EOF
timeout 115 python3 age.py 2>&1 | grep -v -i warn | grep -v wls | head -80

cd $TMPDIR/an && cat > age2.py <<'EOF'
exec(open('spec.py').read().split("print('scale'")[0])
G=F+' + machine_age_years'
mg=fit(G); print('with age: coef', round(mg.params['machine_age_years'],5), 'p', round(mg.pvalues['machine_age_years'],4), 'scale', round(mg.pearson_chi2/mg.df_resid,3))
s=d[d.line!='L4']
F2='rate ~ mold_c + cycle_time_s + C(shift) + dsc + C(line) + l2shift + humidity + hsq + humidity:C(sup) + C(sup)'
m0=fit(F2,s); m1=fit(F2+' + machine_age_years',s)
sc2=m1.pearson_chi2/m1.df_resid
print('L1-L3 only: age coef', round(m1.params['machine_age_years'],5), 'p', round(m1.pvalues['machine_age_years'],4), 'scaled LR p', round(stats.chi2.sf(2*(m1.llf-m0.llf)/sc2,1),4))
m2=fit(F2.replace('C(line) + ','')+' + machine_age_years',d[d.line!='L4'])
EOF
timeout 115 python3 age2.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > cfinal2.py <<'EOF'
exec(open('spec.py').read().split("print('scale'")[0])
D2=D
cl2=cl
days=pd.date_range('2024-12-01','2025-09-30'); cf={}
for L in ['L1','L2','L3','L4']:
    last=cl[(cl.line==L)&(cl.date<pd.Timestamp('2025-01-06'))].date.max(); real=set(cl[cl.line==L].date); cf_last={}
    for t in days:
        if t in real or (t-last).days>=14: last=t
        cf_last[t]=last
    cf[L]=cf_last
A['dsc_cf']=[(t-cf[l][t]).days for l,t in zip(A.line,A.date)]
M=fit(F); 
mv=A.dropna(subset=['mold_c']); mm=smf.ols('mold_c ~ ambient_temp_c + C(line)',mv).fit(); resid_pool=mm.resid.values
rng=np.random.default_rng(0); K=300; hum_pool=d.humidity.values
def expected(frame,dscc,sup=None):
    f=frame.copy()
    if sup is not None: f['sup']=sup
    f['dsc']=f[dscc]; f['hsq']=f.humidity**2
    out=pd.Series(0.0,index=f.index)
    full=f.dropna(subset=['humidity','mold_c'])
    out[full.index]=M.predict(full)*full.units_produced
    rest=f[f.humidity.isna()|f.mold_c.isna()]
    rows=[]
    for idx,r in rest.iterrows():
        b=pd.DataFrame([r]*K).reset_index(drop=True)
        if pd.isna(r.humidity): b['humidity']=rng.choice(hum_pool,K)
        b['hsq']=b.humidity**2
        if pd.isna(r.mold_c): b['mold_c']=mm.predict(pd.DataFrame({'ambient_temp_c':[r.ambient_temp_c],'line':[r.line]})).values[0]+rng.choice(resid_pool,K)
        b['idx']=idx; rows.append(b)
    if rows:
        big=pd.concat(rows,ignore_index=True); big['p']=M.predict(big)*big.units_produced
        out[rest.index]=big.groupby('idx').p.mean()
    return out
A['pd_obs']=expected(A,'dsc'); A['pd_cf']=expected(A,'dsc_cf')
U=A.units_produced.sum()
print('calibration actual',A.defective_units.sum(),'pred',round(A.pd_obs.sum(),1))
print('C3 baseline',round(A.pd_obs.sum()/U,5),'every 14 days',round(A.pd_cf.sum()/U,5))
for s in ['Alpha','Beta','Gamma']:
    print('C1',s,round(expected(A,'dsc',sup=s).sum()/U,5))
alp=d[d.sup=='Alpha']
hg=np.round(np.arange(A.humidity.min(),A.humidity.max()+1e-9,0.1),2)
curve=[]
for h in hg:
    g=alp.copy(); g['humidity']=h; g['hsq']=h*h
    curve.append((M.predict(g)*g.units_produced).sum()/g.units_produced.sum())
curve=np.array(curve)
print('C2 range',A.humidity.min(),A.humidity.max(),'argmin',hg[curve.argmin()],'min',round(curve.min(),5),'ends',round(curve[0],5),round(curve[-1],5))
print('C2 coefficients humidity',M.params['humidity'],'hsq',M.params['hsq'])
EOF
timeout 115 python3 cfinal2.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && cat > bcp.py <<'EOF'
exec(open('spec.py').read().split("print('scale'")[0])
M=fit(F)
d['pr']=M.predict(d)*d.units_produced
d['res']=d.defective_units-d.pr
for L in ['L1','L2','L3','L4']:
    s=d[d.line==L].sort_values('date').reset_index(drop=True)
    best=(0,None)
    for i in range(20,len(s)-20):
        a=s.iloc[:i]; b=s.iloc[i:]
        ra=a.res.sum()/a.pr.sum(); rb=b.res.sum()/b.pr.sum()
        z=(rb-ra)/np.sqrt(sc*(1/a.pr.sum()+1/b.pr.sum()))
        if abs(z)>abs(best[0]): best=(z,s.date[i].date(),round(ra,3),round(rb,3))
    print(L,'max |z|',round(best[0],2),'at',best[1],'resid before',best[2],'after',best[3])
EOF
timeout 115 python3 bcp.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && timeout 115 python3 -c "
exec(open('spec.py').read().split(\"print('scale'\")[0])
G=F+' + machine_age_years'
mg=fit(G); st=2*(mg.llf-M.llf)/sc
print('age scaled LR', round(st,2), 'p', round(stats.chi2.sf(st,1),4), 'coef', round(mg.params['machine_age_years'],5))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/an && timeout 500 python3 -c "
exec(open('spec.py').read().split(\"print('scale'\")[0])
F1=F+' + C(operator_id)'
m1=fit(F1); obs=2*(m1.llf-M.llf)/sc
print('obs scaled LR', round(obs,2), 'p', round(stats.chi2.sf(obs,m1.df_model-M.df_model),4))
rng=np.random.default_rng(7); dd=d.copy(); S=[]
for b in range(150):
    dd['operator_id']=dd.groupby('line').operator_id.transform(lambda s: rng.permutation(s.values))
    mp=fit(F1,dd); S.append(2*(mp.llf-M.llf)/sc)
S=np.array(S); print('perm p', round((np.sum(S>=obs)+1)/(len(S)+1),4), 'perm mean', round(S.mean(),2))
" 2>&1 | grep -v -i warn | grep -v wls
