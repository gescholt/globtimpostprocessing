# Tests for the consolidated critical point and config loaders (bead tibf).
#
# Verifies that:
#   - UnifiedPipeline._load_critical_points handles both _raw_ and non-raw naming
#   - load_critical_points_from_csvs delegates to _load_critical_points
#   - LV4DAnalysis.load_critical_points_csv delegates to _load_critical_points
#   - load_experiment_config_json delegates to load_experiment_config
#   - print_parameter_recovery_table uses p$i columns (not x$i)

using Test
using GlobtimPostProcessing
using GlobtimPostProcessing.UnifiedPipeline
using GlobtimPostProcessing.LV4DAnalysis
using DataFrames
using CSV
using Dates

fixtures_dir = joinpath(@__DIR__, "fixtures")

# ---------------------------------------------------------------------------
# Helpers: build minimal temp experiment directories
# ---------------------------------------------------------------------------

function write_raw_csv(dir, degree, n_params, n_rows)
    path = joinpath(dir, "critical_points_raw_deg_$(degree).csv")
    header = join(["index"; ["p$i" for i in 1:n_params]; "objective"], ",")
    rows = [join([j; [0.1 * i * j for i in 1:n_params]; 0.5 * j], ",") for j in 1:n_rows]
    write(path, join([header; rows], "\n"))
    return path
end

function write_nonraw_csv(dir, degree, n_rows)
    path = joinpath(dir, "critical_points_deg_$(degree).csv")
    header = "x1,x2,z,gradient_norm"
    rows = [join([0.1j, 0.2j, 0.01j, 1e-5], ",") for j in 1:n_rows]
    write(path, join([header; rows], "\n"))
    return path
end

function write_config(dir; p_true=[1.0, 1.5])
    path = joinpath(dir, "experiment_config.json")
    write(path, """{"p_true": $(p_true), "dimension": $(length(p_true)), "function_name": "test"}""")
    return path
end

# ---------------------------------------------------------------------------
# _load_critical_points
# ---------------------------------------------------------------------------

@testset "Loader consolidation" begin

@testset "_load_critical_points: raw naming only" begin
    mktempdir() do dir
        write_raw_csv(dir, 4, 2, 7)
        result = UnifiedPipeline._load_critical_points(dir)
        @test result !== nothing
        @test nrow(result) == 7
        @test hasproperty(result, :degree)
        @test unique(result.degree) == [4]
        @test hasproperty(result, :p1)
        @test hasproperty(result, :objective)
    end
end

@testset "_load_critical_points: non-raw naming only" begin
    mktempdir() do dir
        write_nonraw_csv(dir, 6, 5)
        result = UnifiedPipeline._load_critical_points(dir)
        @test result !== nothing
        @test nrow(result) == 5
        @test hasproperty(result, :degree)
        @test unique(result.degree) == [6]
        @test hasproperty(result, :x1)
    end
end

@testset "_load_critical_points: both naming patterns, different degrees" begin
    mktempdir() do dir
        write_raw_csv(dir, 4, 2, 7)    # critical_points_raw_deg_4.csv
        write_nonraw_csv(dir, 6, 5)    # critical_points_deg_6.csv
        result = UnifiedPipeline._load_critical_points(dir)
        @test result !== nothing
        # Columns differ between the two files — vcat with cols=:union fills missing with missing
        @test nrow(result) == 12
        @test sort(unique(result.degree)) == [4, 6]
        # Both raw and non-raw columns present (missing where not applicable)
        @test hasproperty(result, :p1)
        @test hasproperty(result, :x1)
    end
end

@testset "_load_critical_points: empty directory returns nothing" begin
    mktempdir() do dir
        result = UnifiedPipeline._load_critical_points(dir)
        @test result === nothing
    end
end

# ---------------------------------------------------------------------------
# load_critical_points_from_csvs
# ---------------------------------------------------------------------------

@testset "load_critical_points_from_csvs: delegates to _load_critical_points" begin
    mktempdir() do dir
        write_raw_csv(dir, 4, 2, 9)
        write_raw_csv(dir, 6, 2, 3)
        # data argument is ignored — pass empty dict
        result = GlobtimPostProcessing.load_critical_points_from_csvs(dir, Dict{String,Any}())
        @test result !== nothing
        @test nrow(result) == 12
        @test sort(unique(result.degree)) == [4, 6]
    end
end

@testset "load_critical_points_from_csvs: picks up non-raw files too" begin
    mktempdir() do dir
        write_nonraw_csv(dir, 8, 4)
        result = GlobtimPostProcessing.load_critical_points_from_csvs(dir, Dict{String,Any}())
        @test result !== nothing
        @test nrow(result) == 4
        @test unique(result.degree) == [8]
    end
end

@testset "load_critical_points_from_csvs: empty dir returns nothing" begin
    mktempdir() do dir
        result = GlobtimPostProcessing.load_critical_points_from_csvs(dir, Dict{String,Any}())
        @test result === nothing
    end
end

# ---------------------------------------------------------------------------
# LV4DAnalysis.load_critical_points_csv
# ---------------------------------------------------------------------------

@testset "load_critical_points_csv: loads non-raw files (original behaviour)" begin
    mktempdir() do dir
        write_nonraw_csv(dir, 4, 5)
        result = LV4DAnalysis.load_critical_points_csv(dir)
        @test result isa DataFrame
        @test nrow(result) == 5
        @test hasproperty(result, :degree)
        @test unique(result.degree) == [4]
    end
end

@testset "load_critical_points_csv: now also loads _raw_ files (new unified behaviour)" begin
    mktempdir() do dir
        write_raw_csv(dir, 4, 2, 6)
        result = LV4DAnalysis.load_critical_points_csv(dir)
        @test result isa DataFrame
        @test nrow(result) == 6
        @test unique(result.degree) == [4]
    end
end

@testset "load_critical_points_csv: empty dir returns empty DataFrame" begin
    mktempdir() do dir
        result = LV4DAnalysis.load_critical_points_csv(dir)
        @test result isa DataFrame
        @test nrow(result) == 0
    end
end

# ---------------------------------------------------------------------------
# load_experiment_config_json delegates to load_experiment_config
# ---------------------------------------------------------------------------

@testset "load_experiment_config_json: same result as load_experiment_config" begin
    # Both should return the same config from the fixtures dir
    config_canonical = load_experiment_config(fixtures_dir)
    config_json = LV4DAnalysis.load_experiment_config_json(fixtures_dir)

    @test config_json["function_name"] == config_canonical["function_name"]
    @test config_json["dimension"]     == config_canonical["dimension"]
    @test config_json["p_true"]        == config_canonical["p_true"]
end

@testset "load_experiment_config_json: throws on missing file" begin
    mktempdir() do dir
        @test_throws Exception LV4DAnalysis.load_experiment_config_json(dir)
    end
end

# ---------------------------------------------------------------------------
# print_parameter_recovery_table: p$i columns, no crash
# ---------------------------------------------------------------------------

@testset "print_parameter_recovery_table: runs without error on _raw_ fixture" begin
    mktempdir() do dir
        # Copy the _raw_ CSV and a config with p_true into a temp experiment dir
        cp(joinpath(fixtures_dir, "critical_points_raw_deg_4.csv"),
           joinpath(dir, "critical_points_raw_deg_4.csv"))
        write_config(dir; p_true=[0.2, 0.3, 0.5, 0.6])

        exp = ExperimentResult("test_exp", Dict{String,Any}(), String[], String[],
                               nothing, nothing, nothing, dir)
        campaign = CampaignResults("test_campaign", [exp],
                                   Dict{String,Any}(), now())

        # Should not throw; output goes to stdout
        @test_nowarn print_parameter_recovery_table(campaign)
    end
end

@testset "print_parameter_recovery_table: skips experiment without p_true" begin
    mktempdir() do dir
        write_raw_csv(dir, 4, 2, 3)
        # Config without p_true
        write(joinpath(dir, "experiment_config.json"),
              """{"function_name": "test", "dimension": 2}""")

        exp = ExperimentResult("no_ptrue", Dict{String,Any}(), String[], String[],
                               nothing, nothing, nothing, dir)
        campaign = CampaignResults("c", [exp], Dict{String,Any}(), now())

        @test_nowarn print_parameter_recovery_table(campaign)
    end
end

@testset "print_parameter_recovery_table: skips experiment without config file" begin
    mktempdir() do dir
        write_raw_csv(dir, 4, 2, 3)
        # No experiment_config.json written

        exp = ExperimentResult("no_config", Dict{String,Any}(), String[], String[],
                               nothing, nothing, nothing, dir)
        campaign = CampaignResults("c", [exp], Dict{String,Any}(), now())

        @test_nowarn print_parameter_recovery_table(campaign)
    end
end

end # @testset "Loader consolidation"
