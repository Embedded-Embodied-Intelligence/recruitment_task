print("Values < 100:", batches_unique[batches_unique['mold_temp'] < 100]['mold_temp'].tolist())
print("Values between 100 and 300:", len(batches_unique[(batches_unique['mold_temp'] >= 100) & (batches_unique['mold_temp'] < 300)]))
print("Values between 300 and 500:", len(batches_unique[batches_unique['mold_temp'] >= 300]))

