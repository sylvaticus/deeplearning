"Part of [BetaML](https://github.com/sylvaticus/BetaML.jl). Licence is MIT."

# MLJ interface for imputers models

import MLJModelInterface       # It seems that having done this in the top module is not enought
const MMI = MLJModelInterface  # We need to repeat it here

export SimpleImputer,GaussianMixtureImputer, RandomForestImputer, GeneralImputer

"""
$(TYPEDEF)

Impute missing values using feature (column) mean, with optional record normalisation (using l-`norm` norms), from the Beta Machine Learning Toolkit (BetaML).

## Hyperparameters:
$(TYPEDFIELDS)
"""
mutable struct SimpleImputer <: MMI.Unsupervised
    statistic::Function
    norm::Int64
end

SimpleImputer(;
    statistic::Function              = mean,
    norm::Union{Nothing,Int64}       = nothing,
) = SimpleImputer(statistic,norm)

"""
$(TYPEDEF)

Impute missing values using a probabilistic approach (Gaussian Mixture Models) fitted using the Expectation-Maximisation algorithm, from the Beta Machine Learning Toolkit (BetaML).

## Hyperparameters:
$(TYPEDFIELDS)
"""
mutable struct GaussianMixtureImputer <: MMI.Unsupervised
    n_classes::Int64
    initial_probmixtures::Vector{Float64}
    mixtures::Union{Type,Vector{<: AbstractMixture}}
    tol::Float64
    minimum_variance::Float64
    minimum_covariance::Float64
    initialisation_strategy::String
    verbosity::Verbosity
    rng::AbstractRNG
end
function GaussianMixtureImputer(;
    n_classes      = 3,
    initial_probmixtures  = Float64[],
    mixtures      = [DiagonalGaussian() for i in 1:n_classes],
    tol           = 10^(-6),
    minimum_variance   = 0.05,
    minimum_covariance = 0.0,
    initialisation_strategy  = "kmeans",
    verbosity     = STD,
    rng           = Random.GLOBAL_RNG,
)
    if typeof(mixtures) <: UnionAll
        mixtures = [mixtures() for i in 1:n_classes]
    end
    return GaussianMixtureImputer(n_classes,initial_probmixtures,mixtures, tol, minimum_variance, minimum_covariance,initialisation_strategy,verbosity,rng)
end

"""
$(TYPEDEF)

Impute missing values using Random Forests, from the Beta Machine Learning Toolkit (BetaML).

## Hyperparameters:
$(TYPEDFIELDS)
"""
mutable struct RandomForestImputer <: MMI.Unsupervised
    n_trees::Int64
    max_depth::Union{Nothing,Int64}
    min_gain::Float64
    min_records::Int64
    max_features::Union{Nothing,Int64}
    forced_categorical_cols::Vector{Int64}
    splitting_criterion::Union{Nothing,Function}
    recursive_passages::Int64                  
    #multiple_imputations::Int64 
    verbosity::Verbosity
    rng::AbstractRNG
end
RandomForestImputer(;
    n_trees                 = 30, 
    max_depth               = nothing,
    min_gain                = 0.0,
    min_records             = 2,
    max_features            = nothing,
    forced_categorical_cols  = Int64[],
    splitting_criterion     = nothing,
    recursive_passages      = 1,
    #multiple_imputations    = 1,
    verbosity              = STD,
    rng                    = Random.GLOBAL_RNG,
) = RandomForestImputer(n_trees, max_depth, min_gain, min_records, max_features, forced_categorical_cols, splitting_criterion, recursive_passages, verbosity, rng)

"""
$(TYPEDEF)

Impute missing values using a vector (one per column) of arbitrary learning models (classifiers/regressors) that implement `m = Model([options])`, `train!(m,X,Y)` and `predict(m,X)` (default to Random Forests), from the Beta Machine Learning Toolkit (BetaML).

## Hyperparameters:
$(TYPEDFIELDS)
"""
mutable struct GeneralImputer <: MMI.Unsupervised
    estimators::Union{Vector,Nothing}
    recursive_passages::Int64     
    #multiple_imputations::Int64
    verbosity::Verbosity 
    rng::AbstractRNG
end
GeneralImputer(;
    estimators               = nothing,
    recursive_passages    = 1,
    #multiple_imputations  = 1,
    verbosity            = STD,
    rng                  = Random.GLOBAL_RNG,
) = GeneralImputer(estimators, recursive_passages, verbosity, rng)


# ------------------------------------------------------------------------------
# Fit functions...

function MMI.fit(m::SimpleImputer, verbosity, X)
    x          = MMI.matrix(X) # convert table to matrix
    mod = FeatureBasedImputer(
        statistic = m.statistic,
        norm      = m.norm,
    )
    fit!(mod,x)
    #fitResults = MMI.table(predict(mod))
    fitResults = mod
    cache      = nothing
    report     = info(mod)
    return (fitResults, cache, report)
end

function MMI.fit(m::GaussianMixtureImputer, verbosity, X)
    x          = MMI.matrix(X) # convert table to matrix
    #=if m.mixtures == :diag_gaussian
        mixtures = [DiagonalGaussian() for i in 1:m.n_classes]
    elseif m.mixtures == :full_gaussian
        mixtures = [FullGaussian() for i in 1:m.n_classes]
    elseif m.mixtures == :spherical_gaussian
        mixtures = [SphericalGaussian() for i in 1:m.n_classes]
    else
        error("Usupported mixture. Supported mixtures are either `:diag_gaussian`, `:full_gaussian` or `:spherical_gaussian`.")
    end
    =#

    mod = GMMImputer(
        n_classes      = m.n_classes,
        initial_probmixtures  = m.initial_probmixtures,
        mixtures      = m.mixtures,
        tol           = m.tol,
        minimum_variance   = m.minimum_variance,
        minimum_covariance = m.minimum_covariance,
        initialisation_strategy  = m.initialisation_strategy,
        verbosity     = m.verbosity,
        rng           = m.rng
    )
    fit!(mod,x)
    #fitResults = MMI.table(predict(mod))
    fitResults = mod
    cache      = nothing
    report     = info(mod)

    return (fitResults, cache, report)  
end

function MMI.fit(m::RandomForestImputer, verbosity, X)
    x          = MMI.matrix(X) # convert table to matrix

    mod = RFImputer(
        n_trees                 = m.n_trees, 
        max_depth               = m.max_depth,
        min_gain                = m.min_gain,
        min_records             = m.min_records,
        max_features            = m.max_features,
        forced_categorical_cols  = m.forced_categorical_cols,
        splitting_criterion     = m.splitting_criterion,
        verbosity              = m.verbosity,
        recursive_passages      = m.recursive_passages,
        #multiple_imputations    = m.multiple_imputations,
        rng                    = m.rng,
    )
    fit!(mod,x)
    #if m.multiple_imputations == 1
    #    fitResults = MMI.table(predict(mod))
    #else
    #    fitResults = MMI.table.(predict(mod))
    #end
    fitResults = mod
    cache      = nothing
    report     = info(mod)
    return (fitResults, cache, report)
end

function MMI.fit(m::GeneralImputer, verbosity, X)
    x          = MMI.matrix(X) # convert table to matrix

    mod =  UniversalImputer(
        estimators                 = m.estimators,
        verbosity              = m.verbosity,
        recursive_passages      = m.recursive_passages,
        #multiple_imputations    = m.multiple_imputations,
        rng                    = m.rng,
    )
    fit!(mod,x)
    #if m.multiple_imputations == 1
    #    fitResults = MMI.table(predict(mod))
    #else
    #    fitResults = MMI.table.(predict(mod))
    #end
    fitResults = mod
    cache      = nothing
    report     = info(mod)
    return (fitResults, cache, report)
end

# ------------------------------------------------------------------------------
# Transform functions...

""" transform(m, fitResults, X) - Given a trained imputator model fill the missing data of some new observations"""
function MMI.transform(m::Union{SimpleImputer,GaussianMixtureImputer,RandomForestImputer,GeneralImputer}, fitResults, X)
    x   = MMI.matrix(X) # convert table to matrix
    mod = fitResults
    return MMI.table(predict(mod,x))
end


# ------------------------------------------------------------------------------
# Model metadata for registration in MLJ...

MMI.metadata_model(SimpleImputer,
    input_scitype    = MMI.Table(Union{MMI.Continuous,MMI.Missing}),
    output_scitype   = MMI.Table(MMI.Continuous),     # for an unsupervised, what output?
    supports_weights = false,                         # does the model support sample weights?
	load_path        = "BetaML.Imputation.SimpleImputer"
)

MMI.metadata_model(GaussianMixtureImputer,
    input_scitype    = MMI.Table(Union{MMI.Continuous,MMI.Missing}),
    output_scitype   = MMI.Table(MMI.Continuous),     # for an unsupervised, what output?
    supports_weights = false,                         # does the model support sample weights?
	load_path        = "BetaML.Imputation.GaussianMixtureImputer"
)

MMI.metadata_model(RandomForestImputer,
    input_scitype    = MMI.Table(Union{MMI.Missing, MMI.Known}),
    output_scitype   = MMI.Table(MMI.Known),          # for an unsupervised, what output?
    supports_weights = false,                         # does the model support sample weights?
	load_path        = "BetaML.Imputation.RandomForestImputer"
)
MMI.metadata_model(GeneralImputer,
    input_scitype    = MMI.Table(Union{MMI.Missing, MMI.Known}),
    output_scitype   = MMI.Table(MMI.Known),          # for an unsupervised, what output?
    supports_weights = false,                         # does the model support sample weights?
	load_path        = "BetaML.Imputation.GeneralImputer"
)
