import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
batches = pd.read_csv('batches.csv')
# parse dates not needed
# Clean numeric columns
batches['humidity_pct'] = pd.to_numeric(batches['humidity_pct'], errors='coerce')
batches['mold_temp'] = pd.to_numeric(batches['mold_temp'], errors='coerce')
batches['cycle_time_s'] = pd.to_numeric(batches['cycle_time_s'], errors='coerce')
batches['machine_age_years'] = pd.to_numeric(batches['machine_age_years'], errors='coerce')
batches['ambient_temp_c'] = pd.to_numeric(batches['ambient_temp_c'], errors='coerce')
# drop rows with missing defect_rate components? We'll keep rows with non-missing defect_rate and predictor values.
batches['defect_rate'] = batches['defective_units'] / batches['units_produced']
# filter rows with all needed predictors present
cols = ['defect_rate','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']
model_df = batches[cols].dropna()
print('rows used', model_df.shape)
# Fit weighted linear regression using units_produced as weight
weights = batches.loc[model_df.index, 'units_produced']
# Use formula
formula = 'defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)'
model = smf.wls(formula=formula, data=model_df, weights=weights).fit()
print(model.summary().tables[1])

