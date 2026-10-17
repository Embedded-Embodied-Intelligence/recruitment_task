import pandas as pd, numpy as np, os, json, sys, matplotlib.pyplot as plt, warnings, textwrap, math, datetime, itertools, re

batches = pd.read_csv('batches.csv')
suppliers = pd.read_csv('suppliers.csv')
maintenance = pd.read_csv('maintenance.csv')
print('batches shape', batches.shape)
print('columns', batches.columns.tolist())
print(batches.head())
print('suppliers shape', suppliers.shape, 'cols', suppliers.columns.tolist())
print(suppliers.head())
print('maintenance shape', maintenance.shape, 'cols', maintenance.columns.tolist())
print(maintenance.head())

