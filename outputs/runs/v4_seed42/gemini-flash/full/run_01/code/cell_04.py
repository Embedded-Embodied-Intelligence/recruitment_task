print("Exact row duplicates:", batches.duplicated().sum())
print("Duplicates on batch_id:", batches.duplicated(subset=['batch_id']).sum())

