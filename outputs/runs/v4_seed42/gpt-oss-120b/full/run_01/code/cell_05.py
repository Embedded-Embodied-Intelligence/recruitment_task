import statsmodels.api as sm
from patsy import dmatrices
# drop rows with missing essential variables
cols_needed = ['defect_rate','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']
df = batches.copy()
# convert numeric columns
numeric_cols = ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','defect_rate']
for c in numeric_cols:
    df[c] = pd.to_numeric(df[c], errors='coerce')
# drop rows with any missing among needed
df_model = df.dropna(subset=cols_needed)
# Build formula
formula = 'defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)'
# Use OLS
y, X = dmatrices(formula, data=df_model, return_type='dataframe')
model = sm.OLS(y, X).fit(cov_type='HC3')
print(model.summary())

