total_defective = batches['defective_units'].sum()
total_produced = batches['units_produced'].sum()
a3 = total_defective/total_produced
print(total_defective, total_produced, a3)
