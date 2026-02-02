using Aqua
using GlobtimPostProcessing

@testset "Aqua.jl Quality Assurance" begin
    Aqua.test_all(GlobtimPostProcessing;
        ambiguities=true,
        unbound_args=true,
        undefined_exports=true,
        stale_deps=(; ignore=[:Tidier]),  # Tidier may show as stale
        deps_compat=true,
        persistent_tasks=false  # Skip for Julia version compatibility
    )
end
