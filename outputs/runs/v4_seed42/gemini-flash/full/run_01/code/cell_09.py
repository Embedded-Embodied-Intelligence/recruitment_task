print("Line distribution of mold_temp >= 300:")
print(batches_unique[batches_unique['mold_temp'] >= 300]['line'].value_counts())
print("Line distribution of mold_temp < 100:")
print(batches_unique[batches_unique['mold_temp'] < 100]['line'].value_counts())
print("Line distribution of 100 <= mold_temp < 300:")
print(batches_unique[(batches_unique['mold_temp'] >= 100) & (batches_unique['mold_temp'] < 300)]['line'].value_counts())

