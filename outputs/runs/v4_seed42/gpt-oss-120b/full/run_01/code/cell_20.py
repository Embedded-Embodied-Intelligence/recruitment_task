import pandas as pd, statsmodels.api as sm, patsy
batches = pd.read_csv('batches.csv')
# numeric conversion
for col in ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']:
    batches[col] = pd.to_numeric(batches[col], errors='coerce')
# compute defect_rate
batches['defect_rate'] = batches['defective_units'] / batches['units_produced']
# drop rows with missing essential vars
cols_needed = ['defect_rate','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']
df = batches.dropna(subset=cols_needed)
# formula
formula = 'defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)'
y, X = patsy.dmatrices(formula, data=df, return_type='dataframe')
model = sm.OLS(y, X).fit(cov_type='HC3')
print(model.pvalues[['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']])
# significance for categorical
op_sig = model.pvalues.filter(like('C(operator_id)')).lt(0.05).any()
sh_sig = model.pvalues.filter(like('C(shift)')).lt(0.05).any()
print('operator any sig', op_sig)
print('shift any sig', sh_sig)

