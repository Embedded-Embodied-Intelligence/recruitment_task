# Overall defect rate
total_defective = batches['defective_units'].sum()
total_produced = batches['units_produced'].sum()
a3 = total_defective / total_produced
print('overall defect rate', a3)
# median mold temp where valid (non-null, numeric)
valid_mold = pd.to_numeric(batches['mold_temp'], errors='coerce')
valid_mold = valid_mold.dropna()
a4 = valid_mold.median()
print('median mold temp', a4)

