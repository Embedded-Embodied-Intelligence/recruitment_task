batches_unique['supplier_code'] = batches_unique['supplier_code'].str.strip().str.upper()
batches_unique['shift'] = batches_unique['shift'].str.strip().str.upper().map(lambda s: 'Day' if s.startswith('D') else 'Night')
print("Supplier codes:", batches_unique['supplier_code'].value_counts())
print("Shifts:", batches_unique['shift'].value_counts())

