import pandas as pd
import numpy as np

batches = pd.read_csv('batches.csv')
suppliers = pd.read_csv('suppliers.csv')
maintenance = pd.read_csv('maintenance.csv')

print("Batches shape:", batches.shape)
print("Batches columns:", batches.columns.tolist())
print("Suppliers shape:", suppliers.shape)
print("Suppliers columns:", suppliers.columns.tolist())
print("Maintenance shape:", maintenance.shape)
print("Maintenance columns:", maintenance.columns.tolist())

