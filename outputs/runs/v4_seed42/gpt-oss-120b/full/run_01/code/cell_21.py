# Compute A1, A2, A3, A4 with proper handling
import pandas as pd, numpy as np
batches = pd.read_csv('batches.csv')
# parse dates robustly
batches['prod_date'] = pd.to_datetime(batches['production_date'], errors='coerce')
# A1 unique batches
A1 = batches['batch_id'].nunique()
# A2 missing or invalid humidity
humidity = pd.to_numeric(batches['humidity_pct'], errors='coerce')
A2_missing = humidity.isna().sum()
A2_invalid = ((humidity <= 0) | (humidity > 100)).sum()
A2 = A2_missing + A2_invalid
# A3 overall defect rate
A3 = batches['defective_units'].sum() / batches['units_produced'].sum()
# A4 median mold temp (valid numeric)
mold_temp = pd.to_numeric(batches['mold_temp'], errors='coerce')
A4 = mold_temp.dropna().median()
print('A1', A1)
print('A2_missing', A2_missing, 'invalid', A2_invalid, 'total', A2)
print('A3', A3)
print('A4', A4)

