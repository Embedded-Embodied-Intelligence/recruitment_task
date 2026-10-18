exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
d['l1new']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['l3qc']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['h']=d.hum-35
d['m']=d.mold_c-212
d['ok']=d.defective_units; d['bad']=d.units_produced-d.defective_units
x=d.dropna(subset=['hum','mold_c']).copy()
def fit(f,data=x):
    return smf.glm(f+'',data,family=sm.families.Binomial(),var_weights=None,freq_weights=None).fit() if False else smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
d['m']=d.mold_c-212-7.7*d.l1new
d['mc']=d.mold_c-7.7*d.l1new
d['s2']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
c=d.dropna(subset=['hum','mold_c'])
c=c[c.l3qc==0].copy()
def fitq(f,data=c):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
d['l4gap']=((d.line=='L4')&(d.date>='2025-02-01')&(d.date<'2025-04-11')).astype(int)
c=c.merge(d[['l4gap']],left_index=True,right_index=True) if 'l4gap' not in c else c
