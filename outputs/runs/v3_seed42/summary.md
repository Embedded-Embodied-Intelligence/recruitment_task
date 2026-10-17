# Benchmark results

1 scored runs. Scores are in [0, 1]; sd is the run-to-run standard deviation.

## Total score

| model | variant | count | mean | std | min | max | equal_weights_mean | format_ok | tool_calls_mean | turn_limit_runs |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 1 | 0.940 | nan | 0.940 | 0.940 | 0.957 | 1.000 | 35.000 | 0 |

## Mean score per question

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 1.00 | 1.00 | 1.00 | 1.00 | 0.60 | 1.00 | 1.00 | 1.00 | 1.00 | 0.97 |

Run-to-run sd per question:

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | nan | nan | nan | nan | nan | nan | nan | nan | nan | nan |

## How often the trap answer was given

Share of runs whose answer was closer to the naive (trap) answer than to the truth.

| model | variant | A1 | A2 | A3 | A4 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |

## Wrong items in set answers

`+x` = listed but wrong, `-x` = missed; counts over runs.

- claude-haiku / full / B1: `+operator_id` x1, `+machine_age_years` x1, `+mold_temp_c` x1, `-mold_temp` x1

## Robustness of the ranking to the weights

The ranking of models by mean total is the same with equal question weights (variant `full`).
