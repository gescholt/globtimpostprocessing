"""
    CriticalPointClassification.jl

Classification of critical points based on Hessian matrix eigenvalues.

This module analyzes the polynomial approximant's critical points by examining
the eigenvalues of the Hessian matrix at each critical point. Classification
is performed BEFORE evaluating the objective function at these points.

# Classification Categories

- **Minimum**: All eigenvalues > 0 (positive definite Hessian)
- **Maximum**: All eigenvalues < 0 (negative definite Hessian)
- **Saddle**: Mixed eigenvalue signs (indefinite Hessian)
- **Degenerate**: One or more eigenvalues ≈ 0 (singular/near-singular Hessian)

# Usage

```julia
# Classify a single point given eigenvalues
classification = classify_critical_point([2.5, 1.3, 0.8])  # "minimum"

# Add classification column to critical points DataFrame
classify_all_critical_points!(df)

# Count each classification type
counts = count_classifications(df)
# Returns: Dict("minimum" => 5, "saddle" => 12, "maximum" => 2, "degenerate" => 1)
```
"""

"""
    classify_critical_point(eigenvalues::Vector{Float64}; tol::Float64=1e-6) -> String

Classify a single critical point based on its Hessian eigenvalues.

# Arguments
- `eigenvalues::Vector{Float64}`: Eigenvalues of the Hessian matrix at the critical point
- `tol::Float64`: Tolerance for considering an eigenvalue as zero (default: 1e-6)

# Returns
- `String`: One of "minimum", "maximum", "saddle", "degenerate"

# Algorithm
1. Check for near-zero eigenvalues (|λ| < tol) → "degenerate"
2. All eigenvalues > tol → "minimum" (positive definite)
3. All eigenvalues < -tol → "maximum" (negative definite)
4. Mixed signs → "saddle" (indefinite)

# Examples
```julia
classify_critical_point([2.5, 1.3, 0.8])        # "minimum"
classify_critical_point([-3.2, -1.5, -0.9])     # "maximum"
classify_critical_point([2.1, -1.8, 0.5])       # "saddle"
classify_critical_point([1.2, 0.00001, 0.9])    # "degenerate"
```
"""
function classify_critical_point(eigenvalues::Vector{Float64}; tol::Float64=1e-6)
    # Check for degenerate case first
    if any(abs.(eigenvalues) .< tol)
        return "degenerate"
    end

    # Count positive and negative eigenvalues
    num_positive = count(λ -> λ > tol, eigenvalues)
    num_negative = count(λ -> λ < -tol, eigenvalues)

    # Classify based on eigenvalue signs
    if num_positive == length(eigenvalues)
        return "minimum"
    elseif num_negative == length(eigenvalues)
        return "maximum"
    else
        return "saddle"
    end
end

"""
    extract_eigenvalues_from_row(row::DataFrameRow) -> Union{Vector{Float64}, Nothing}

Extract Hessian eigenvalues from a DataFrame row.

# Arguments
- `row::DataFrameRow`: A row from the critical points DataFrame

# Returns
- `Vector{Float64}`: Eigenvalues if columns exist, or `Nothing` if not found

# Details
Searches for columns matching the pattern "hessian_eigenvalue_N" where N is a digit.
Returns eigenvalues sorted by column name to ensure consistent ordering.
"""
function extract_eigenvalues_from_row(row::DataFrameRow)
    # Get column names
    col_names = propertynames(row)

    # Find eigenvalue columns
    eigenvalue_cols = filter(n -> occursin(r"hessian_eigenvalue_\d+", string(n)), col_names)

    if isempty(eigenvalue_cols)
        return nothing
    end

    # Sort columns to ensure consistent ordering (eigenvalue_1, eigenvalue_2, ...)
    sorted_cols = sort(eigenvalue_cols, by=x -> parse(Int, match(r"\d+", string(x)).match))

    # Extract values
    eigenvalues = [Float64(row[col]) for col in sorted_cols]

    return eigenvalues
end

"""
    classify_all_critical_points!(df::DataFrame; tol::Float64=1e-6,
                                   classification_col::Symbol=:point_classification) -> DataFrame

Add classification column to critical points DataFrame (in-place).

# Arguments
- `df::DataFrame`: Critical points DataFrame with Hessian eigenvalue columns
- `tol::Float64`: Tolerance for zero eigenvalues (default: 1e-6)
- `classification_col::Symbol`: Name for the new classification column (default: :point_classification)

# Returns
- `DataFrame`: The modified DataFrame (same as input, modified in-place)

# Side Effects
Adds a new column with classifications: "minimum", "maximum", "saddle", "degenerate"

# Examples
```julia
df = load_critical_points("path/to/experiment")
classify_all_critical_points!(df)
println(df.point_classification)  # ["minimum", "saddle", "minimum", ...]
```

# Errors
Throws an error if no Hessian eigenvalue columns are found in the DataFrame.
"""
function classify_all_critical_points!(df::DataFrame; tol::Float64=1e-6,
                                       classification_col::Symbol=:point_classification)
    # Check if DataFrame is empty
    if nrow(df) == 0
        # Add empty classification column
        df[!, classification_col] = String[]
        return df
    end

    # Check for eigenvalue columns
    eigenvalue_cols = filter(n -> occursin(r"hessian_eigenvalue_\d+", string(n)), names(df))

    if isempty(eigenvalue_cols)
        error("No Hessian eigenvalue columns found in DataFrame. " *
              "Expected columns matching pattern 'hessian_eigenvalue_N'.")
    end

    # Classify each row
    classifications = String[]

    for row in eachrow(df)
        eigenvalues = extract_eigenvalues_from_row(row)

        if eigenvalues === nothing
            push!(classifications, "unknown")
        else
            classification = classify_critical_point(eigenvalues, tol=tol)
            push!(classifications, classification)
        end
    end

    # Add classification column
    df[!, classification_col] = classifications

    return df
end

"""
    count_classifications(df::DataFrame; classification_col::Symbol=:point_classification) -> Dict{String, Int}

Count the number of critical points in each classification category.

# Arguments
- `df::DataFrame`: Critical points DataFrame with classification column
- `classification_col::Symbol`: Name of the classification column (default: :point_classification)

# Returns
- `Dict{String, Int}`: Counts for each classification type

# Examples
```julia
counts = count_classifications(df)
# Returns: Dict("minimum" => 5, "saddle" => 12, "maximum" => 2, "degenerate" => 1)
```

# Errors
Throws an error if the classification column doesn't exist in the DataFrame.
"""
function count_classifications(df::DataFrame; classification_col::Symbol=:point_classification)
    if !(classification_col in propertynames(df))
        error("Classification column '$classification_col' not found in DataFrame. " *
              "Run classify_all_critical_points! first.")
    end

    # Initialize counts
    counts = Dict{String, Int}(
        "minimum" => 0,
        "maximum" => 0,
        "saddle" => 0,
        "degenerate" => 0
    )

    # Count each classification
    for classification in df[!, classification_col]
        if haskey(counts, classification)
            counts[classification] += 1
        else
            # Handle unexpected classifications
            counts[classification] = get(counts, classification, 0) + 1
        end
    end

    return counts
end

"""
    find_distinct_local_minima(df::DataFrame;
                                classification_col::Symbol=:point_classification,
                                distance_threshold::Float64=1e-3) -> Vector{Int}

Find indices of distinct local minima, removing duplicates within distance threshold.

# Arguments
- `df::DataFrame`: Critical points DataFrame with classification column
- `classification_col::Symbol`: Name of the classification column (default: :point_classification)
- `distance_threshold::Float64`: Minimum Euclidean distance to consider points distinct (default: 1e-3)

# Returns
- `Vector{Int}`: Row indices of distinct local minima

# Algorithm
1. Filter for points classified as "minimum"
2. Cluster points within distance_threshold
3. Return representative points from each cluster

# Examples
```julia
distinct_minima_indices = find_distinct_local_minima(df)
distinct_minima = df[distinct_minima_indices, :]
println("Found $(length(distinct_minima_indices)) distinct local minima")
```
"""
function find_distinct_local_minima(df::DataFrame;
                                    classification_col::Symbol=:point_classification,
                                    distance_threshold::Float64=1e-3)
    # Filter for minima
    if !(classification_col in propertynames(df))
        error("Classification column '$classification_col' not found in DataFrame.")
    end

    minima_mask = df[!, classification_col] .== "minimum"
    minima_indices = findall(minima_mask)

    if isempty(minima_indices)
        return Int[]
    end

    # Extract parameter columns (x1, x2, ..., xN)
    param_cols = filter(n -> occursin(r"^x\d+$", string(n)), names(df))

    if isempty(param_cols)
        # If no parameter columns, can't compute distances - return all minima
        @warn "No parameter columns (x1, x2, ...) found. Returning all minima without clustering."
        return minima_indices
    end

    # Sort param columns by number
    sorted_param_cols = sort(param_cols, by=x -> parse(Int, match(r"\d+", string(x)).match))

    # Extract coordinates of minima
    minima_coords = Matrix(df[minima_indices, sorted_param_cols])

    # Simple clustering: greedy removal of nearby duplicates
    distinct_indices = Int[]
    used = falses(length(minima_indices))

    for i in 1:length(minima_indices)
        if used[i]
            continue
        end

        # Mark this point as a representative
        push!(distinct_indices, minima_indices[i])
        used[i] = true

        # Mark nearby points as duplicates
        for j in (i+1):length(minima_indices)
            if used[j]
                continue
            end

            # Compute Euclidean distance
            dist = norm(minima_coords[i, :] - minima_coords[j, :])

            if dist < distance_threshold
                used[j] = true
            end
        end
    end

    return distinct_indices
end

"""
    get_classification_summary(df::DataFrame;
                                classification_col::Symbol=:point_classification) -> Dict{String, Any}

Get a comprehensive summary of critical point classifications.

# Arguments
- `df::DataFrame`: Critical points DataFrame with classification column
- `classification_col::Symbol`: Name of the classification column (default: :point_classification)

# Returns
- `Dict{String, Any}`: Summary statistics including counts, percentages, and distinct minima count

# Examples
```julia
summary = get_classification_summary(df)
println("Total critical points: ", summary["total"])
println("Minima: ", summary["counts"]["minimum"], " (", summary["percentages"]["minimum"], "%)")
println("Distinct local minima: ", summary["distinct_local_minima"])
```
"""
function get_classification_summary(df::DataFrame;
                                    classification_col::Symbol=:point_classification)
    total = nrow(df)

    if total == 0
        return Dict{String, Any}(
            "total" => 0,
            "counts" => Dict{String, Int}(),
            "percentages" => Dict{String, Float64}(),
            "distinct_local_minima" => 0
        )
    end

    counts = count_classifications(df, classification_col=classification_col)

    # Compute percentages
    percentages = Dict{String, Float64}()
    for (class, count) in counts
        percentages[class] = round(100.0 * count / total, digits=2)
    end

    # Find distinct local minima
    distinct_minima_indices = find_distinct_local_minima(df, classification_col=classification_col)

    return Dict{String, Any}(
        "total" => total,
        "counts" => counts,
        "percentages" => percentages,
        "distinct_local_minima" => length(distinct_minima_indices)
    )
end
