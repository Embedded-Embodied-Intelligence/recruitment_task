"""edabench: an end-to-end pipeline for benchmarking LLMs on a hard EDA task.

Pipeline stages (one module each):
    generate  -> synthetic dataset + ground truth from a seeded DGP
    prompt    -> render the task prompt from a template
    sandbox   -> execute model-written Python in a Jupyter kernel without network
    backends  -> model adapters (OpenAI-compatible endpoints, `claude -p`)
    runner    -> repeated runs per model and prompt variant, isolation preflight
    answer    -> parse the JSON answer from a model reply
    scorer    -> partial-credit score in [0, 1] against the ground truth
    report    -> aggregate runs into tables and an error heatmap
    profile   -> group question scores by the kind of skill they test
    explorer  -> self-contained HTML page of all runs
"""

__version__ = "0.1.0"
