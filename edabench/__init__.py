"""edabench: an end-to-end pipeline for benchmarking LLMs on a hard EDA task.

Pipeline stages (one module each):
    generate  -> synthetic dataset + ground truth from a seeded DGP
    prompt    -> render the task prompt from a template
    sandbox   -> execute model-written Python in an isolated subprocess
    runners   -> model adapters (OpenAI-compatible endpoints, `claude -p`)
    scorer    -> partial-credit score in [0, 1] against the ground truth
    report    -> aggregate runs into tables and an error heatmap
"""

__version__ = "0.1.0"
