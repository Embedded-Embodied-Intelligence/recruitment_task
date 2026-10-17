from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=d.dropna(subset=['mt_c','hum']).copy()
f='defective_units + ok ~ mt_c + I(mt_c**2) + hum*C(pre_dried) + I(hum**2)*C(pre_dried) + cycle_time_s + C(resin_grade) + machine_age_years + ambient_temp_c + C(shift) + C(line) + dsc + I(dsc**2)+ C(supplier_name)'
m=smf.glm(f,dd,family=sm.families.Binomial()).fit()
import warnings; warnings.filterwarnings('ignore')
dd['s2']=((dd.line=='L2')&(dd.date>='2025-06-16')).astype(int)
dd['s3']=((dd.line=='L3')&(dd.date>='2025-07-21')).astype(int)
