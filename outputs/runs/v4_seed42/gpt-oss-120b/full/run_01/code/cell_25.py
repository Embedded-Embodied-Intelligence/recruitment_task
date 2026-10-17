import pandas as pd, statsmodels.api as sm, patsy
batches = pd.read_csv('batches.csv')
for col in ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']:
    batches[col] = pd.to_numeric(batches[col], errors='coerce')
# defect_rate
def compute_defect_rate(row):
    if row['units_produced']>0:
        return row['defective_units']/row['units_produced']
    else:
        return None
batches['defect_rate'] = batches.apply(lambda r: compute_defect_rate(r), axis=1)
cols_needed = ['defect_rate','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']
df = batches.dropna(subset=cols_needed)
formula = 'defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)'
y, X = patsy.dmatrices(formula, data=df, return_type='dataframe')
model = sm.OLS(y, X).fit(cov_type='HC3')
print(model.pvalues[['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']])
# show few categorical p-values
print('operator coefficients p-values (first 5):')
print(model.pvalues.filter(like('C(operator_id)')).head())
print('shift coefficients p-values (first 5):')
print(model.pvalues.filter(like('C(shift)')).head())

