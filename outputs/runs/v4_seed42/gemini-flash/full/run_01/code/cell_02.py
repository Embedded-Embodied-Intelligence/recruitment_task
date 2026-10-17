print("Batches head:")
print(batches.head())
print("\nBatches info:")
print(batches.info())
print("\nUnique batch_id count:", batches['batch_id'].nunique())
print("Total rows:", len(batches))

