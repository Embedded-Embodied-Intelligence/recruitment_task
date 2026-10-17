dup_batches = batches[batches.duplicated(subset=['batch_id'], keep=False)].sort_values('batch_id')
print("Number of duplicate rows:", len(batches[batches.duplicated()]))
print("Number of rows with duplicated batch_id:", len(dup_batches))
print(dup_batches.head(10))

