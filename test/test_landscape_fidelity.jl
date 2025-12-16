"""
Standalone test for Landscape Fidelity features (bypassing package compilation issue)
"""

# Load dependencies directly
using LinearAlgebra
using Statistics
using DataFrames
using Printf

# Global flag for ForwardDiff availability
global HAS_FORWARDDIFF = false

println("Checking for ForwardDiff...")
try
    using ForwardDiff
    global HAS_FORWARDDIFF = true
    println("✓ ForwardDiff available - can compute Hessians automatically")
catch
    global HAS_FORWARDDIFF = false
    println("✗ ForwardDiff not available - install with: using Pkg; Pkg.add(\"ForwardDiff\")")
end

# Load LandscapeFidelity module
println("\nLoading LandscapeFidelity module...")
include("src/LandscapeFidelity.jl")
println("✅ Landscape fidelity functions loaded")

# Load demo functions
println("Loading demo functions...")
include("examples/landscape_fidelity_demo.jl")
println("✅ Demo functions loaded")

println("\n" * "="^70)
println("Running Landscape Fidelity Tests")
println("="^70)

# Run demos
println("\n### Demo 1: Simple Quadratic ###")
demo_1_simple_quadratic()

println("\n### Demo 2: Multiple Minima ###")
demo_2_multiple_minima()

println("\n### Demo 4: Batch Processing ###")
demo_4_batch_processing()

println("\n" * "="^70)
println("All demos completed successfully!")
println("="^70)
