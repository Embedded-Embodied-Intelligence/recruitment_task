import pandas as pd, numpy as np, statsmodels.api as sm
batches = pd.read_csv('batches.csv')
# convert numeric columns
for col in ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']:
    batches[col] = pd.to_numeric(batches[col], errors='coerce')
# defect_rate
batches['defect_rate'] = batches['defective_units'] / batches['units_produced']
# drop rows with missing essential vars
cols_needed = ['defect_rate','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']
df = batches.dropna(subset=cols_needed)
# formula
import patsy
y, X = patsy.dmatrices('defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)', data=df, return_type='dataframe')
model = sm.OLS(y, X).fit(cov_type='HC3')
# extract p-values for numeric vars
pvals = model.pvalues
numeric_vars = ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']
print('p-values:')
for var in numeric_vars:
    print(var, pvals[var])
# For operator_id and shift, they are categorical; we need to see if any levels significant? But direct effect definition: if changing operator while others fixed changes expected defect rate => yes if operator appears in model with any significant coefficient.
# Let's check if any operator_id level p < 0.05
operator_ps = pvals.filter(like('C(operator_id)') )
shift_ps = pvals.filter(like('C(shift)') )
print('operator significant any?', (operator_ps < 0.05).any())
print('shift significant any?', (shift_ps < 0.05).any())

