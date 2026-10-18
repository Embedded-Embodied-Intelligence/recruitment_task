exec(open('an/clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['ctd']=d.cycle_time_s-d.recipe_cycle_time_s
d['l1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['l3qc']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['ok']=d.units_produced-d.defective_units
def fit(f,x):
    return smf.glm(f,x,family=sm.families.Binomial(),freq_weights=None,var_weights=None).fit() if False else smf.glm('defective_units + ok ~ '+f,x,family=sm.families.Binomial()).fit()
d['l2s']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['mtc']=d.mt-215
d['l4gap']=((d.line=='L4')&(d.date>'2025-02-14')&(d.date<'2025-04-11')).astype(int)
d['hb']=pd.cut(d.hum,[0,15,20,25,30,35,40,45,50,55,60,80])
d['mtA']=d.mt-8*d.l1post
d['mtc']=d.mtA-215
