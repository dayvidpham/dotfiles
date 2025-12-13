# Refactoring Plan: Explicit Split Plotting with PlotTask

## 1. The Core Abstraction: `PlotTask`

We will introduce a `dataclass` to encapsulate "what to plot". This separates the decision of *which data to show* from the *logic of drawing it*.

**Location:** `engine/plotting.py` (near top)

```python
from dataclasses import dataclass

@dataclass
class PlotTask:
    """
    Defines a specific plotting job. 
    Can represent a single split (e.g., Train Loss) or a mixed split (e.g., Combined Loss).
    """
    metric: Metric
    keys: List[MetricKey]
    filename_prefix: str    # e.g., "train_loss" or "loss"
    display_title: str      # e.g., "Train Loss" or "Loss"
```

## 2. Refactor `plot_all` (The Driver)

The `plot_all` function changes its iteration strategy. It will no longer iterate by string names or rely on hardcoded split logic inside sub-functions. Instead, it generates concrete tasks and dispatches them.

```python
def plot_all(results: ResultsType, ...):
    # ... setup ...

    # 1. Group keys by Metric Enum
    metric_groups: Dict[Metric, List[MetricKey]] = {}
    for key in metric_keys:
        if key.metric not in metric_groups:
            metric_groups[key.metric] = []
        metric_groups[key.metric].append(key)

    # 2. Iterate Metrics and Generate Tasks
    for metric, keys in metric_groups.items():
        tasks: List[PlotTask] = []

        # --- Task A: Combined / Mixed Split ---
        # Contains ALL keys for this metric. Existing styling logic handles differentiation.
        tasks.append(PlotTask(
            metric=metric,
            keys=keys,
            filename_prefix=metric.name.lower(), # e.g. "loss"
            display_title=metric.display_name    # e.g. "Loss"
        ))

        # --- Task B & C: Specific Splits ---
        # Group keys by DatasetSplit Enum
        keys_by_split: Dict[DatasetSplit, List[MetricKey]] = {}
        for key in keys:
            if key.split: # Handle keys that have a valid split
                if key.split not in keys_by_split:
                    keys_by_split[key.split] = []
                keys_by_split[key.split].append(key)

        # Create distinct tasks for each split found (Train, Test)
        for split, split_keys in keys_by_split.items():
            tasks.append(PlotTask(
                metric=metric,
                keys=split_keys,
                filename_prefix=f"{split.name.lower()}_{metric.name.lower()}", # e.g. "train_loss"
                display_title=f"{split.name} {metric.display_name}"            # e.g. "Train Loss"
            ))

        # 3. Dispatch Tasks to Plotters
        for task in tasks:
            # Helper to build consistent paths
            def get_path(folder: str, suffix: str = "") -> Path:
                return base_dir / folder / f"{task.filename_prefix}{suffix}.png"

            if save_combined:
                plot_combined(
                    results, configs_by_lr, learning_rates, 
                    task, get_path("combined")
                )

            if save_separate:
                for config in all_configs:
                    plot_separate(
                        results, config, 
                        task, base_dir / "separate" / config.dir_name / f"{task.filename_prefix}.png"
                    )

            if save_aggregated:
                plot_aggregated(
                    results, configs_by_lr, learning_rates, 
                    task, get_path("aggregated", "_comparison")
                )
            
            if has_rho_sweeps:
                 plot_hyperparam_grid(
                    results, learning_rates_for_grid, rho_values,
                    task, get_path("hyperparam_grid", "_grid")
                 )
            
            if optimizer_pairs:
                 plot_sam_comparison(
                    results,
                    task, get_path("sam_comparison", "_sam_comparison")
                 )
```

## 3. Refactor Plotting Functions

All plotting functions need to update their signature to accept `task: PlotTask` instead of `metric_keys`.

### A. `plot_sam_comparison`

**Current Problem:** Hardcoded to filter `DatasetSplit.Test`.
**Fix:** Iterate `task.keys`. If the task is "Train Loss", `task.keys` only contains train keys, so it plots the train loss.

```python
def plot_sam_comparison(
    results: ResultsType,
    task: PlotTask,  # <-- Updated Signature
    filepath: Path,
) -> None:
    # ... setup ...

    # Use task.keys. 
    # Logic for styling (light/dark) remains, but applies to whatever keys are present.
    # If task is "Train Only", only the "Lighter" style logic will execute.
    has_splits = any(key.split is not None for key in task.keys)
    
    # ... logic ...

    # Update Labels
    # Use task.display_title for the explicit split name
    ax.set_ylabel(task.display_title)
    fig.suptitle(f"{task.display_title}: Base vs SAM Variants")
```

### B. `plot_hyperparam_grid`

**Current Problem:** Generic Y-labels.
**Fix:** Use `task.display_title` for the row labels.

```python
def plot_hyperparam_grid(
    results: ResultsType,
    # ... other args ...
    task: PlotTask, # <-- Updated Signature
    filepath: Path,
) -> None:
    # ...
    
    # Internal loop splits task.keys into train/test for styling purposes.
    # If task is "Train Only", test_keys will be empty, and that logic simply won't run.
    train_keys = [k for k in task.keys if k.split == DatasetSplit.Train]
    test_keys = [k for k in task.keys if k.split == DatasetSplit.Test]
    
    # ... plotting logic ...

    # Labeling
    if col_idx == 0:
        # Explicitly says "Train Loss" or "Test Loss"
        ax.set_ylabel(f"rho={rho}\n{task.display_title}", fontsize=9)
```

### C. `plot_combined`

**Current Problem:** Axis label assumes generic name.
**Fix:** Use `task.display_title` in `configure_axis`.

```python
def plot_combined(
    # ...
    task: PlotTask,
    filepath: Path,
) -> None:
    # ...
    # Set axis label
    strategy.configure_axis(ax, base_label=task.display_title)
    
    # Logic handles mixed splits automatically by iterating task.keys
    # ...
```

### D. `plot_aggregated`

**Current Problem:** Prioritizes Test split if available.
**Fix:** Simply use the keys provided in the task.

```python
def plot_aggregated(
    # ...
    task: PlotTask,
    filepath: Path,
) -> None:
    # ...
    # No need to search for "Test" keys. The driver already decided what keys we have.
    selected_keys = task.keys
    
    # ... plotting logic ...
    
    ax.set_title(f"{task.display_title} of {opt_name}")
```

## 4. Summary of Changes

| Component | Change Description | Impact |
| :--- | :--- | :--- |
| **`PlotTask`** | **New Dataclass** | Decouples data selection from rendering logic. |
| **`plot_all`** | **Logic Overhaul** | Iterates by `Metric` Enum; generates distinct tasks for Combined, Train-only, and Test-only views. |
| **`plot_sam_comparison`** | **Remove Filtering** | Now supports plotting Train loss (showing $10^{-16}$ convergence) by respecting the input task keys. |
| **`plot_hyperparam_grid`** | **Dynamic Labeling** | Y-axis labels now accurately reflect the split (e.g., "Train Loss"). |
| **All Functions** | **Signature Update** | Replaced `metric_keys: List[MetricKey]` with `task: PlotTask`. |
| **File Structure** | **Granularity** | Output folders now contain specific files like `train_loss_grid.png` and `test_loss_grid.png`. |

## 5. Implementation Checklist

- [ ] **Define `PlotTask`**: Add the dataclass definition to `engine/plotting.py`.
- [ ] **Refactor `plot_all`**:
    - [ ] Remove string-based `metric_types` grouping.
    - [ ] Implement `Metric` Enum grouping.
    - [ ] Implement loop to generate `PlotTask` objects (Combined + Split-specific).
    - [ ] Update calls to plotting functions to pass `task` and dynamic file paths.
- [ ] **Update `plot_sam_comparison`**:
    - [ ] Change signature to accept `task: PlotTask`.
    - [ ] **CRITICAL:** Remove `if k.split == DatasetSplit.Test` filter.
    - [ ] Update title and Y-label to use `task.display_title`.
- [ ] **Update `plot_hyperparam_grid`**:
    - [ ] Change signature to accept `task: PlotTask`.
    - [ ] Update row Y-labels to use `task.display_title`.
- [ ] **Update `plot_combined`**:
    - [ ] Change signature to accept `task: PlotTask`.
    - [ ] Update axis configuration to use `task.display_title`.
- [ ] **Update `plot_separate`**:
    - [ ] Change signature to accept `task: PlotTask`.
    - [ ] Update figure title to use `task.display_title`.
- [ ] **Update `plot_aggregated`**:
    - [ ] Change signature to accept `task: PlotTask`.
    - [ ] Remove logic that defaults to Test split; use `task.keys`.
    - [ ] Update title to use `task.display_title`.
