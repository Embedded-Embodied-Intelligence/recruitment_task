# Convert dates
batches['production_date'] = pd.to_datetime(batches['production_date'], errors='coerce')
print('date parse errors', batches['production_date'].isna().sum())
# check unique batch ids
print('unique batch ids', batches['batch_id'].nunique())
# missing humidity
print('humidity missing or non-numeric?')
# convert humidity to numeric
batches['humidity_pct_num'] = pd.to_numeric(batches['humidity_pct'], errors='coerce')
missing_humidity = batches['humidity_pct_num'].isna().sum()
print('missing humidity count', missing_humidity)
# overall defect rate
valid = batches['units_produced']>0
overall_defect = batches.loc[valid, 'defective_units'].sum() / batches.loc[valid, 'units_produced'].sum()
print('overall defect rate', overall_defect)
# median mold temp valid numeric
batches['mold_temp_num'] = pd.to_numeric(batches['mold_temp'], errors='coerce')
median_mold = batches['mold_temp_num'].median()
print('median mold temp', median_mold)
# summary of candidate variables
candidates = ['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','operator_id','shift']
print(batches[candidates].head())

