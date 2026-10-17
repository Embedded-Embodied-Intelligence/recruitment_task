print("mold_temp summary:")
print(batches_unique['mold_temp'].describe())
print("\nmold_temp histogram / quantiles:")
print(batches_unique['mold_temp'].quantile(np.linspace(0, 1, 11)))

