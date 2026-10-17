print("Unique supplier_code:", batches_unique['supplier_code'].unique())
print("Unique shift:", batches_unique['shift'].unique())
print("Unique operator_id:", batches_unique['operator_id'].unique())
print("Unique line:", batches_unique['line'].unique())
print("Unique production_date formats:", batches_unique['production_date'].head(10).tolist())

