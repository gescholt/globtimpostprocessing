"""
    Refinement Method Types

Modular refinement method system. Each method is a self-contained struct with its
configuration, and a canonical name for dispatch. The `refinement_method` factory
creates methods from symbolic names.

All methods are dispatched through `refine_point` (in `unified_dispatch.jl`), which
always returns `CriticalPointRefinementResult`.

Created: 2026-03-18
"""

# ═══════════════════════════════════════════════════════════════════════════════
# Abstract type + trait interface
# ═══════════════════════════════════════════════════════════════════════════════

"""
    RefinementMethod

Abstract supertype for all refinement methods. Each concrete subtype carries its
own configuration parameters.

Trait queries:
- `needs_gradient(m)` — does this method use gradients during iteration?
- `needs_hessian(m)` — does this method use Hessians during iteration?
- `method_name(m)` — canonical symbol name (e.g. `:newton_cp`, `:lbfgs`)
"""
abstract type RefinementMethod end

"""
    needs_gradient(m::RefinementMethod) -> Bool

Whether this method computes gradients during its iteration (not post-hoc).
"""
needs_gradient(::RefinementMethod) = false

"""
    needs_hessian(m::RefinementMethod) -> Bool

Whether this method computes Hessians during its iteration (not post-hoc).
"""
needs_hessian(::RefinementMethod) = false

"""
    method_name(m::RefinementMethod) -> Symbol

Canonical name for this method (e.g. `:newton_cp`, `:lbfgs`).
"""
method_name(::RefinementMethod) = :unknown

# ═══════════════════════════════════════════════════════════════════════════════
# Newton methods
# ═══════════════════════════════════════════════════════════════════════════════

"""
    NewtonCP <: RefinementMethod

Trust-region Newton on ∇f = 0 — finds critical points of ALL types (min, max, saddle).
Uses the true Hessian eigenvalues in the Newton step.
"""
Base.@kwdef struct NewtonCP <: RefinementMethod
    gradient_method::Symbol = :finitediff
    tol::Float64 = 1e-8
    accept_tol::Float64 = Inf
    f_accept_tol::Union{Nothing,Float64} = nothing
    max_iterations::Int = 100
    hessian_tol::Float64 = 1e-6
    hessian_relative_tol::Float64 = 0.0
    trust_radius_fraction::Float64 = 0.1
    trust_expand::Float64 = 2.0
    trust_shrink::Float64 = 0.25
    max_f_increase_factor::Float64 = 10.0
    patience::Int = 10
    min_improvement_ratio::Float64 = 0.99
end
needs_gradient(::NewtonCP) = true
needs_hessian(::NewtonCP) = true
method_name(::NewtonCP) = :newton_cp

"""
    NewtonMinimize <: RefinementMethod

Modified trust-region Newton — replaces each Hessian eigenvalue λ with |λ|, making
the effective Hessian positive-definite so every step is a descent direction. Only
finds local minima. Avoids convergence to saddle points.
"""
Base.@kwdef struct NewtonMinimize <: RefinementMethod
    gradient_method::Symbol = :finitediff
    tol::Float64 = 1e-8
    accept_tol::Float64 = Inf
    f_accept_tol::Union{Nothing,Float64} = nothing
    max_iterations::Int = 100
    hessian_tol::Float64 = 1e-6
    hessian_relative_tol::Float64 = 0.0
    trust_radius_fraction::Float64 = 0.1
    trust_expand::Float64 = 2.0
    trust_shrink::Float64 = 0.25
    max_f_increase_factor::Float64 = 10.0
    patience::Int = 10
    min_improvement_ratio::Float64 = 0.99
end
needs_gradient(::NewtonMinimize) = true
needs_hessian(::NewtonMinimize) = true
method_name(::NewtonMinimize) = :newton_minimize

# ═══════════════════════════════════════════════════════════════════════════════
# Optim methods
# ═══════════════════════════════════════════════════════════════════════════════

# During iteration, Optim methods handle their own gradient computation internally
# (finite differences when only f is passed). The `gradient_method` field on these
# structs controls only post-hoc Hessian evaluation for CP classification.

"""
    OptimNelderMead <: RefinementMethod

Derivative-free simplex method. Robust for ODE objectives and noisy problems.
"""
Base.@kwdef struct OptimNelderMead <: RefinementMethod
    f_abstol::Float64 = 1e-6
    x_abstol::Float64 = 1e-6
    max_time::Union{Float64,Nothing} = 30.0
    max_iterations::Int = 300
    gradient_method::Symbol = :finitediff   # post-hoc classification only
    hessian_tol::Float64 = 1e-6
    hessian_relative_tol::Float64 = 0.0
end
method_name(::OptimNelderMead) = :neldermead

"""
    OptimLBFGS <: RefinementMethod

Limited-memory BFGS. Uses Optim-internal finite differences for gradient during
iteration (when only f is passed to Fminbox).
"""
Base.@kwdef struct OptimLBFGS <: RefinementMethod
    f_abstol::Float64 = 1e-6
    x_abstol::Float64 = 1e-6
    max_time::Union{Float64,Nothing} = 30.0
    max_iterations::Int = 300
    step_size::Float64 = 1.0
    gradient_method::Symbol = :finitediff   # post-hoc classification only
    hessian_tol::Float64 = 1e-6
    hessian_relative_tol::Float64 = 0.0
end
needs_gradient(::OptimLBFGS) = true
method_name(::OptimLBFGS) = :lbfgs

"""
    OptimBFGS <: RefinementMethod

Full BFGS quasi-Newton method.
"""
Base.@kwdef struct OptimBFGS <: RefinementMethod
    f_abstol::Float64 = 1e-6
    x_abstol::Float64 = 1e-6
    max_time::Union{Float64,Nothing} = 30.0
    max_iterations::Int = 300
    gradient_method::Symbol = :finitediff   # post-hoc classification only
    hessian_tol::Float64 = 1e-6
    hessian_relative_tol::Float64 = 0.0
end
needs_gradient(::OptimBFGS) = true
method_name(::OptimBFGS) = :bfgs

"""
    OptimConjugateGradient <: RefinementMethod

Conjugate gradient method.
"""
Base.@kwdef struct OptimConjugateGradient <: RefinementMethod
    f_abstol::Float64 = 1e-6
    x_abstol::Float64 = 1e-6
    max_time::Union{Float64,Nothing} = 30.0
    max_iterations::Int = 300
    gradient_method::Symbol = :finitediff   # post-hoc classification only
    hessian_tol::Float64 = 1e-6
    hessian_relative_tol::Float64 = 0.0
end
needs_gradient(::OptimConjugateGradient) = true
method_name(::OptimConjugateGradient) = :conjugategradient

"""
    OptimGradientDescent <: RefinementMethod

Steepest descent method.
"""
Base.@kwdef struct OptimGradientDescent <: RefinementMethod
    f_abstol::Float64 = 1e-6
    x_abstol::Float64 = 1e-6
    max_time::Union{Float64,Nothing} = 30.0
    max_iterations::Int = 300
    gradient_method::Symbol = :finitediff   # post-hoc classification only
    hessian_tol::Float64 = 1e-6
    hessian_relative_tol::Float64 = 0.0
end
needs_gradient(::OptimGradientDescent) = true
method_name(::OptimGradientDescent) = :gradientdescent

# ═══════════════════════════════════════════════════════════════════════════════
# Factory
# ═══════════════════════════════════════════════════════════════════════════════

const _VALID_METHOD_NAMES = [
    :newton_cp,
    :newton_minimize,
    :neldermead,
    :lbfgs,
    :bfgs,
    :conjugategradient,
    :gradientdescent,
]

"""
    refinement_method(name; kwargs...) -> RefinementMethod

Construct a `RefinementMethod` by symbolic name. Valid names:
`newton_cp`, `newton_minimize`, `neldermead`, `lbfgs`, `bfgs`,
`conjugategradient`, `gradientdescent`.

Keyword arguments are forwarded to the constructor of the matching type.

# Examples
```julia
m = refinement_method(:newton_cp; tol=1e-10, gradient_method=:forwarddiff)
m = refinement_method(:lbfgs; step_size=0.5)
m = refinement_method("neldermead"; max_iterations=500)
```
"""
function refinement_method(name::Union{Symbol,AbstractString}; kwargs...)
    sym = name isa Symbol ? name : Symbol(lowercase(String(name)))
    sym === :newton_cp ? NewtonCP(; kwargs...) :
    sym === :newton_minimize ? NewtonMinimize(; kwargs...) :
    sym === :neldermead ? OptimNelderMead(; kwargs...) :
    sym === :lbfgs ? OptimLBFGS(; kwargs...) :
    sym === :bfgs ? OptimBFGS(; kwargs...) :
    sym === :conjugategradient ? OptimConjugateGradient(; kwargs...) :
    sym === :gradientdescent ? OptimGradientDescent(; kwargs...) :
    error("Unknown refinement method: $name. Valid: $(join(_VALID_METHOD_NAMES, ", "))")
end
