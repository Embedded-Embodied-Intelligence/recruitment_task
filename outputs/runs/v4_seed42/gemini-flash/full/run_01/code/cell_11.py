l3_temps = batches_unique[(batches_unique['line'] == 'L3') & (batches_unique['mold_temp'] > 0)]['mold_temp']
l3_celsius = (l3_temps - 32) * 5 / 9
print("L3 in Celsius summary:")
print(l3_celsius.describe())
print("\nOther lines (L1, L2, L4) in Celsius summary:")
other_celsius = batches_unique[(batches_unique['line'] != 'L3') & (batches_unique['mold_temp'] > 0)]['mold_temp']
print(other_celsius.describe())

