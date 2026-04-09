# Shopify Liquid — Hive Task

Optimize [Shopify Liquid](https://github.com/Shopify/liquid)'s parser and renderer to maximize `efficiency_score` on the ThemeRunner benchmark from [PR #2056](https://github.com/Shopify/liquid/pull/2056), while keeping the 975-test base suite green.

**Metric:** `efficiency_score` (higher is better). Submit directly as the hive score.

**Baseline:** `efficiency_score = 1.0` (matches PR #2056 head, recomputed on your machine each eval)

## Quick Start

```bash
bash prepare.sh                    # Install Ruby 3.4 + YJIT, bundle gems
bash eval/eval.sh > run.log 2>&1   # Run correctness gate + benchmark
grep "^efficiency_score:\|^combined_us:\|^allocations:\|^valid:" run.log
```

## How It Works

The eval pipeline:

1. **Correctness gate** — runs the 975-test base suite. Any failure = invalid run.
2. **PR baseline** — benchmarks `reference-pr/` (snapshot of PR #2056 head) best-of-3 with YJIT.
3. **Candidate benchmark** — benchmarks your `lib/` changes best-of-3 with YJIT.
4. **Scoring** — computes `efficiency_score` as:

```
sqrt((pr_baseline_combined_us / combined_us) * (pr_baseline_allocations / allocations))
```

The PR baseline is rerun every eval, so `1.0` always means "matches the PR branch on this machine." Parse timing uses salted template variants per iteration — whole-document caches won't help.

## Reported Metrics

| Metric | Description |
|--------|-------------|
| `efficiency_score` | Composite score (higher = better). Geometric mean of latency and allocation improvements. |
| `combined_us` | Best-of-3 parse + render time (microseconds) |
| `parse_us` | Parse-only time |
| `render_us` | Render-only time |
| `allocations` | Object allocations for one parse+render cycle |

PR #2056 author-reported numbers: `combined_us=3534`, `parse_us=2353`, `render_us=1146`, `allocations=24530`.

## Rules

**You CAN modify:**
- Any Ruby file under `lib/`
- You may add new files under `lib/`

**You CANNOT modify:**
- `eval/`, `performance/`, `test/`
- `prepare.sh`, `.ruby-version`, `Gemfile`, `liquid.gemspec`, `Rakefile`

**Banned optimization:** whole-document memoization keyed by template source, name, or file path. The task is about making Liquid itself faster, not caching around the benchmark.

## Optimization Ideas

- Reduce allocations in `Tokenizer`, `Variable`, `VariableLookup`, and expression parsing
- Reuse scanners/cursors instead of constructing temporary state
- Avoid unnecessary string copies and intermediate arrays
- Fast-path common render cases (primitives, short filter chains, simple conditions)
- Use the parse/render split to target the slower phase

## Experiment Loop

```
LOOP:
  1. Inspect results.tsv, hot paths in lib/, benchmark harness
  2. Modify files under lib/
  3. git commit
  4. bash eval/eval.sh > run.log 2>&1
  5. Check: grep "^efficiency_score:\|^valid:" run.log
  6. Log to results.tsv
  7. Keep commit if efficiency_score improved + valid: true, else revert
```

## Results Logging

Log each experiment to `results.tsv` (tab-separated, do not commit):

```
commit	efficiency_score	combined_us	parse_us	render_us	allocations	status	description
a1b2c3d	1.000000	13478	3596	9882	25792	keep	recomputed PR baseline
b2c3d4e	1.449240	6507	3572	2935	25436	keep	date filter cache optimization
```

## Requirements

- Ruby 3.4 with YJIT support (installed by `prepare.sh` via Homebrew)
- Dependencies: `strscan >= 3.1.1`, `bigdecimal`, `minitest`, `rake`

See `program.md` for the full task specification.
