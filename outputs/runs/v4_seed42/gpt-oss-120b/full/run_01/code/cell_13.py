import pandas as pd, numpy as np
batches = pd.read_csv('batches.csv')
# A1 unique batches
A1 = batches['batch_id'].nunique()
# A2 missing humidity (invalid measurement)
# treat non-numeric or missing as invalid
batches['humidity_num'] = pd.to_numeric(batches['humidity_pct'], errors='coerce')
A2 = batches['humidity_num'].isna().sum()
# A3 overall defect rate
def_valid = batches['defective_units'].sum()
prod_valid = batches['units_produced'].sum()
A3 = def_valid / prod_valid
# A4 median mold temp numeric
batches['mold_temp_num'] = pd.to_numeric(batches['mold_temp'], errors='coerce')
A4 = batches['mold_temp_num'].median()
print('A1', A1, 'A2', A2, 'A3', A3, 'A4', A4)

