unique_ids = batches['batch_id'].nunique()
print('unique batch_id count', unique_ids)
# check duplicates
print('duplicate count', len(batches)-unique_ids)

