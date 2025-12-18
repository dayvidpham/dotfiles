# Refactoring Plan: Tabbed Data Explorer with Grid View

> **Scope:** Add tabbed navigation, parameter grid view, and streaming data preview to `data_explorer.py`  
> **Affected Files:** @src/vis/data_explorer.py  
> **Estimated Complexity:** Medium

---

## 1. Motivation

### Problem Statement

The current `data_explorer.py` provides a single-view density heatmap with parameter filtering. This limits exploratory analysis in two key ways:

- **No overview of parameter space:** Users must manually iterate through filter combinations to understand how parameters affect outcomes. There's no grid view showing multiple parameter configurations simultaneously.
- **No raw data inspection:** Users cannot verify what the underlying data looks like or spot anomalies without external tools.

### Impact of Inaction

- Slower iteration when exploring grid search results (~32K parameter combinations)
- No quick sanity checks on data quality without leaving the app
- Cognitive overhead of mentally tracking which parameter combinations have been explored

### Success Criteria

- [ ] Tabbed interface with ≥3 views (Explorer, Grid Overview, Data Preview)
- [ ] Grid view renders parameter facets without loading all data into memory
- [ ] Data preview loads ≤10 rows using streaming (no full file scan)
- [ ] Existing density heatmap functionality preserved

---

## 2. Code Quality Standards

### Rules

**NEVER:**
- Load full datasets into memory for preview operations
- Use `pl.read_parquet()` when `pl.scan_parquet()` suffices
- Block the UI thread during data operations (use `pn.state.onload` for initial loads)

**ALWAYS:**
- Use Polars lazy API (`scan_parquet`) for streaming operations
- Wrap expensive computations in `@pn.cache` decorators
- Pass `dynamic=True` to `pn.Tabs` to defer inactive tab rendering
- Constrain Bokeh pan/zoom bounds to data extents via `Range1d(bounds=...)`

### Bad → Good Examples

**BAD - Eager full load for preview:**

```python
# Problem: Loads 165M rows just to show 10
def preview_data():
    df = pl.read_parquet("results/*.parquet")
    return df.head(10)
```

**GOOD - Lazy streaming preview:**

```python
# Solution: Only reads necessary rows from disk
def preview_data():
    return pl.scan_parquet("results/*.parquet").head(10).collect()
```

---

**BAD - Render all tabs immediately:**

```python
# Problem: All tabs compute on load, blocking UI
tabs = pn.Tabs(
    ("Explorer", expensive_explorer_view()),
    ("Grid", expensive_grid_view()),
)
```

**GOOD - Deferred tab rendering:**

```python
# Solution: Only active tab renders; others wait until selected
tabs = pn.Tabs(
    ("Explorer", expensive_explorer_view),  # Pass callable, not result
    ("Grid", expensive_grid_view),
    dynamic=True
)
```

---

**BAD - Unbounded pan/zoom:**

```python
# Problem: User can pan into empty void outside data region
shaded = dynspread(datashade(path)).opts(
    width=600,
    height=450,
)
```

**GOOD - Data-constrained pan/zoom:**

```python
# Solution: Restrict pan/zoom to data extents (O(1) metadata lookup)
from bokeh.models import Range1d

def apply_data_bounds(plot, element):
    x_min, x_max = element.range('turn')
    y_min, y_max = element.range('n')
    plot.state.x_range = Range1d(start=x_min, end=x_max, bounds=(x_min, x_max))
    plot.state.y_range = Range1d(start=y_min, end=y_max, bounds=(y_min, y_max))

shaded = dynspread(datashade(path)).opts(
    width=600,
    height=450,
    hooks=[apply_data_bounds],
)
```

### Pattern Recognition Guide

When you see this pattern:
```python
data = pl.read_parquet(path)  # or .collect() without .head()
```

**STOP.** Ask: "Do I need all rows?" If showing a preview or computing aggregates, use:
1. `scan_parquet(...).head(n).collect()` for previews
2. `scan_parquet(...).select([cols]).collect()` for metadata
3. `scan_parquet(...).group_by(...).agg(...).collect()` for summaries

---

## 3. Architectural Design

### Current State

```
┌─────────────────────────────────────────────────────────┐
│                    FastListTemplate                      │
├─────────────┬───────────────────────────────────────────┤
│  Sidebar    │              Main Content                  │
│  (Filters)  │     ┌─────────────────────────────┐       │
│             │     │    Datashader Heatmap       │       │
│  - Policy   │     │    (Single View)            │       │
│  - UtilDist │     │                             │       │
│  - RepChange│     └─────────────────────────────┘       │
│  - ...      │                                           │
└─────────────┴───────────────────────────────────────────┘
```

**Problem:** Single view requires manual parameter iteration.

### Proposed State

```
┌─────────────────────────────────────────────────────────┐
│                    FastListTemplate                      │
├─────────────┬───────────────────────────────────────────┤
│  Sidebar    │  ┌─────────────────────────────────────┐  │
│  (Filters)  │  │ [Explorer] [Grid] [Data] [Params]  │  │
│             │  └─────────────────────────────────────┘  │
│  - Policy   │  ┌─────────────────────────────────────┐  │
│  - UtilDist │  │                                     │  │
│  - ...      │  │   Tab Content (dynamic render)      │  │
│             │  │                                     │  │
│             │  └─────────────────────────────────────┘  │
└─────────────┴───────────────────────────────────────────┘
```

### Design Decisions

| Decision | Rationale | Alternatives Considered |
| :--- | :--- | :--- |
| Use `pn.Tabs(dynamic=True)` | Defers rendering of inactive tabs | Eager rendering (rejected: blocks UI) |
| Polars lazy scan for preview | O(n) rows read, not O(N) | Pandas (rejected: no lazy eval) |
| HoloViews `gridspace` for grid | Native datashader support | Matplotlib subplots (rejected: no interactivity) |
| Separate params loading | Params are small (~32K rows) | Lazy scan (overkill for small data) |

### Invariants to Preserve

- Existing density heatmap functionality unchanged
- Filter widgets remain in sidebar
- Dark background + fire colormap styling preserved
- Turn 0 synthetic data injection logic retained

---

## 4. Summary of Changes

| Component | Change Description | Impact |
| :--- | :--- | :--- |
| **`create_app`** | **Restructure to tabbed layout** | Main entry point now returns `pn.Tabs` |
| **`create_explorer_tab`** | **Extract existing view** | No logic change, just reorganization |
| **`apply_data_bounds`** | **New: Bokeh hook for pan/zoom bounds** | Prevents panning outside data region |
| **`create_grid_tab`** | **New: Parameter grid visualization** | Faceted heatmaps by 2 parameters |
| **`create_data_tab`** | **New: Streaming data preview** | Shows first 10 rows of results + params |
| **`create_params_tab`** | **New: Full params table** | Searchable/sortable params view |
| **`load_data`** | **Split into results + params loaders** | Better separation of concerns |

---

## 5. Implementation Tasks

### Task A: Split Data Loading

**File:** @src/vis/data_explorer.py

**Current Problem:** Single `load_data()` function loads and joins everything eagerly.

**Fix:** Separate loaders for different use cases.

```python
@pn.cache
def load_params() -> pl.DataFrame:
    """Load params (small, can be eager)."""
    return pl.scan_parquet(DATA_DIR / "flat_params" / "**/*.parquet").collect()

@pn.cache  
def load_results_lazy() -> pl.LazyFrame:
    """Return lazy frame for streaming operations."""
    return pl.scan_parquet(DATA_DIR / "results" / "*.parquet")
```

**Checklist:**
- [ ] `load_params()` returns eager DataFrame (small data)
- [ ] `load_results_lazy()` returns LazyFrame (large data)
- [ ] Existing `load_data()` refactored to use these primitives
- [ ] `@pn.cache` applied to both

---

### Task B: Create Tabbed Layout Structure

**File:** @src/vis/data_explorer.py

**Current Problem:** `create_app()` builds a single-view layout.

**Fix:** Wrap content in `pn.Tabs` with `dynamic=True`.

```python
def create_app():
    # ... existing setup ...
    
    tabs = pn.Tabs(
        ("Explorer", create_explorer_tab(data, widgets)),
        ("Grid Overview", create_grid_tab),      # Callable for deferred
        ("Data Preview", create_data_tab),
        ("Parameters", create_params_tab),
        dynamic=True,
    )
    
    template.main.append(tabs)
    return template
```

**Checklist:**
- [ ] `pn.Tabs` created with `dynamic=True`
- [ ] Explorer tab contains existing heatmap logic
- [ ] Other tabs are callables (deferred rendering)
- [ ] Sidebar filters still update Explorer tab reactively

---

### Task C: Extract Explorer Tab

**File:** @src/vis/data_explorer.py

**Current Problem:** Heatmap logic is inline in `create_app()`.

**Fix:** Extract to dedicated function.

```python
def create_explorer_tab(data: pd.DataFrame, widgets: dict) -> pn.Column:
    """Existing density heatmap view, extracted."""
    # Move existing plot_container, update logic here
    # Return pn.Column with stats_pane + plot_container
    return pn.Column(stats_pane, plot_container)
```

**Checklist:**
- [ ] All existing heatmap logic moved to `create_explorer_tab`
- [ ] `@pn.depends` decorators preserved
- [ ] Widget references passed via `widgets` dict
- [ ] Return type is `pn.Column`

---

### Task C.1: Constrain Pan/Zoom to Data Bounds

**File:** @src/vis/data_explorer.py

**Current Problem:** Users can pan/zoom into empty regions outside the data extent, which is disorienting.

**Fix:** Add a Bokeh hook that constrains `x_range` and `y_range` to data bounds. The bounds are extracted via `element.range()`, which is O(1)—it reads pre-computed metadata from datashader, not raw data.

```python
from bokeh.models import Range1d

def apply_data_bounds(plot, element):
    """Constrain pan/zoom to data extents. O(1) metadata lookup."""
    x_min, x_max = element.range('turn')
    y_min, y_max = element.range('n')
    plot.state.x_range = Range1d(start=x_min, end=x_max, bounds=(x_min, x_max))
    plot.state.y_range = Range1d(start=y_min, end=y_max, bounds=(y_min, y_max))
```

Apply in `create_datashader_plot()`:

```python
shaded = dynspread(
    datashade(path, aggregator=ds.count(), cmap=fire), max_px=5
).opts(
    # ... existing opts ...
    hooks=[apply_data_bounds],
)
```

**Checklist:**
- [ ] `apply_data_bounds` function defined at module level
- [ ] Hook added to `.opts()` call in `create_datashader_plot()`
- [ ] Pan constrained to data x-range (turns)
- [ ] Zoom constrained to data y-range (n)
- [ ] Verified: cannot pan into empty regions

---

### Task D: Implement Grid Overview Tab

**File:** @src/vis/data_explorer.py

**Current Problem:** No way to see multiple parameter combinations at once.

**Fix:** Use HoloViews `GridSpace` or `NdLayout` with datashader.

```python
def create_grid_tab() -> pn.Column:
    """Faceted grid of heatmaps by two parameters."""
    # Use hv.DynamicMap + datashade for each cell
    # Facet by (e.g.) reputation_change × perf_scaling
    
    grid = hv.GridSpace(kdims=["reputation_change", "perf_scaling"])
    for rep in rep_values:
        for perf in perf_values:
            grid[rep, perf] = create_single_heatmap(rep, perf)
    
    return pn.Column(pn.pane.HoloViews(grid))
```

**Checklist:**
- [ ] Grid renders without blocking (use `DynamicMap` if needed)
- [ ] Each cell uses datashader for density
- [ ] Faceting parameters configurable via widgets
- [ ] Memory usage stays bounded (don't materialize all cells)

---

### Task E: Implement Data Preview Tab

**File:** @src/vis/data_explorer.py

**Current Problem:** No way to inspect raw data.

**Fix:** Streaming preview using Polars lazy + Tabulator widget.

```python
def create_data_tab() -> pn.Column:
    """Streaming preview of first N rows."""
    n_rows = pn.widgets.IntSlider(name="Rows", value=10, start=5, end=100)
    
    @pn.depends(n_rows)
    def get_preview(n):
        # Streaming: only reads n rows from disk
        preview = load_results_lazy().head(n).collect()
        return pn.widgets.Tabulator(preview.to_pandas(), height=400)
    
    return pn.Column(
        "### Results Preview (streaming)",
        n_rows,
        get_preview,
    )
```

**Checklist:**
- [ ] Uses `scan_parquet().head(n).collect()` pattern
- [ ] `Tabulator` widget for sortable/searchable table
- [ ] Row count adjustable via slider
- [ ] Params preview in separate section (can be eager)

---

### Task F: Implement Parameters Tab

**File:** @src/vis/data_explorer.py

**Current Problem:** No visibility into the full parameter grid.

**Fix:** Searchable table of all parameter combinations.

```python
def create_params_tab() -> pn.Column:
    """Full params table with search/filter."""
    params_df = load_params()
    
    tabulator = pn.widgets.Tabulator(
        params_df.to_pandas(),
        pagination="remote",
        page_size=50,
        height=600,
    )
    
    return pn.Column("### Parameter Grid (32K combinations)", tabulator)
```

**Checklist:**
- [ ] Uses `load_params()` (eager, small data)
- [ ] Pagination enabled for performance
- [ ] Columns sortable and filterable
- [ ] Search box functional

---

## 6. Testing Strategy

### Unit Tests
- [ ] `load_results_lazy()` returns `pl.LazyFrame` (not DataFrame)
- [ ] `load_params()` returns expected columns
- [ ] Preview with `n=10` reads ≤1000 rows from disk (verify with `explain()`)

### Integration Tests
- [ ] All four tabs render without errors
- [ ] Switching tabs does not reload already-rendered content
- [ ] Filter widgets in sidebar affect Explorer tab only

### Manual Verification
- [ ] Run `panel serve src/vis/data_explorer.py --show`
- [ ] Click through all tabs; verify no UI freezes
- [ ] Adjust preview row count; verify streaming behavior
- [ ] Apply filters; verify heatmap updates

---

## 7. Migration Notes

### Breaking Changes
- None—internal refactor only

### Rollback Plan
- Revert to previous `data_explorer.py` commit

---

## 8. Implementation Checklist (Master)

- [ ] **Phase 1: Data Loading Refactor**
  - [ ] Create `load_params()` function
  - [ ] Create `load_results_lazy()` function
  - [ ] Update existing `load_data()` to use new primitives
- [ ] **Phase 2: Tab Structure**
  - [ ] Add `pn.Tabs` to `create_app()`
  - [ ] Extract `create_explorer_tab()`
  - [ ] Add `apply_data_bounds` hook for pan/zoom constraints
  - [ ] Verify existing functionality preserved
- [ ] **Phase 3: New Tabs**
  - [ ] Implement `create_grid_tab()`
  - [ ] Implement `create_data_tab()`
  - [ ] Implement `create_params_tab()`
- [ ] **Phase 4: Polish**
  - [ ] Add loading indicators to each tab
  - [ ] Test memory usage with large data
  - [ ] Update docstrings
- [ ] **Phase 5: Validation**
  - [ ] Manual testing complete
  - [ ] No regressions in Explorer view
  - [ ] Pan/zoom constrained to data bounds in all views
