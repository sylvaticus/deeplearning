
"""
    kernelPerceptron(x,y;K,T,α,nMsgs,shuffle)

Train a multiclass kernel classifier "perceptron" algorithm based on x and y.

!!! warning
    This function is deprecated and will possibly be removed in BetaML 0.9.
    Use the model KernelPerceptron() instead. 

`kernelPerceptron` is a (potentially) non-linear perceptron-style classifier employing user-defined kernel funcions. Multiclass is supported using a one-vs-one approach.

# Parameters:
* `x`:        Feature matrix of the training data (n × d)
* `y`:        Associated labels of the training data
* `K`:        Kernel function to employ. See `?radialKernel` or `?polynomialKernel`for details or check `?BetaML.Utils` to verify if other kernels are defined (you can alsways define your own kernel) [def: [`radialKernel`](@ref)]
* `T`:        Maximum number of iterations (aka "epochs") across the whole set (if the set is not fully classified earlier) [def: 100]
* `α`:        Initial distribution of the number of errors errors [def: `nothing`, i.e. zeros]. If provided, this should be a nModels-lenght vector of nRecords integer values vectors , where nModels is computed as `(nClasses  * (nClasses - 1)) / 2`
* `nMsg`:     Maximum number of messages to show if all iterations are done [def: `0`]
* `shuffle`:  Whether to randomly shuffle the data at each iteration [def: `false`]
* `rng`:      Random Number Generator (see [`FIXEDSEED`](@ref)) [deafult: `Random.GLOBAL_RNG`]

# Return a named tuple with:
* `x`: The x data (eventually shuffled if `shuffle=true`)
* `y`: The label
* `α`: The errors associated to each record
* `classes`: The labels classes encountered in the training

# Notes:
* The trained model can then be used to make predictions using the function `predict()`.
* This model is available in the MLJ framework as the `KernelPerceptronClassifier`

# Example:
```jldoctest
julia> model = kernelPerceptron([1.1 1.1; 5.3 4.2; 1.8 1.7; 7.5 5.2;], ["a","c","b","c"])
julia> ŷtest = Perceptron.predict([10 10; 2.2 2.5; 1 1],model.x,model.y,model.α, model.classes,K=model.K)
```
"""
function kernelPerceptron(x, y; K=radialKernel, T=100, α=nothing, nMsgs=0, shuffle=false, rng = Random.GLOBAL_RNG)
 x         = makeMatrix(x)
 yclasses  = unique(y)
 nCl       = length(yclasses)
 nModels   = Int((nCl  * (nCl - 1)) / 2)
 (n,d) = size(x)
 outX = Array{typeof(x),1}(undef,nModels)
 outY = Array{Array{Int64,1},1}(undef,nModels)
 outα = Array{Array{Int64,1},1}(undef,nModels)
 α = (α == nothing) ? [zeros(Int64,length(y)) for i in 1:nModels] : α

 modelCounter = 1
 for (i,c) in enumerate(yclasses)
     for (i2,c2) in enumerate(yclasses)
         if i2 <= i continue end # never false with a single class (always "continue")
         ids = ( (y .== c) .| (y .== c2) )
         thisx = x[ids,:]
         thisy = y[ids]
         thisα = α[modelCounter][ids]
         ybin = ((thisy .== c) .*2 .-1)  # conversion to +1 (if c) or -1 (if c2)
         outBinary = kernelPerceptronBinary(thisx, ybin; K=K, T=T, α=thisα, nMsgs=nMsgs, shuffle=shuffle, rng = rng)
         outX[modelCounter] = outBinary.x
         outY[modelCounter] = outBinary.y
         outα[modelCounter] = outBinary.α
         modelCounter += 1
     end
 end
 return (x=outX,y=outY,α=outα,classes=yclasses,K=K)
end

"""
    kernelPerceptronBinary(x,y;K,T,α,nMsgs,shuffle)

Train a binary kernel classifier "perceptron" algorithm based on x and y

!!! warning
    This function is deprecated and will possibly be removed in BetaML 0.9.
    Use the model KernelPerceptron() instead. 

# Parameters:
* `x`:        Feature matrix of the training data (n × d)
* `y`:        Associated labels of the training data, in the format of ⨦ 1
* `K`:        Kernel function to employ. See `?radialKernel` or `?polynomialKernel`for details or check `?BetaML.Utils` to verify if other kernels are defined (you can alsways define your own kernel) [def: [`radialKernel`](@ref)]
* `T`:        Maximum number of iterations across the whole set (if the set is not fully classified earlier) [def: 1000]
* `α`:        Initial distribution of the errors [def: `zeros(length(y))`]
* `nMsg`:     Maximum number of messages to show if all iterations are done
* `shuffle`:  Whether to randomly shuffle the data at each iteration [def: `false`]
* `rng`:      Random Number Generator (see [`FIXEDSEED`](@ref)) [deafult: `Random.GLOBAL_RNG`]

# Return a named tuple with:
* `x`: the x data (eventually shuffled if `shuffle=true`)
* `y`: the label
* `α`: the errors associated to each record
* `errors`: the number of errors in the last iteration
* `besterrors`: the minimum number of errors in classifying the data ever reached
* `iterations`: the actual number of iterations performed
* `separated`: a flag if the data has been successfully separated

# Notes:
* The trained data can then be used to make predictions using the function `predict()`. **If the option `shuffle` has been used, it is important to use there the returned (x,y,α) as these would have been shuffled compared with the original (x,y)**.
* Please see @kernelPerceptron for a multi-class version
# Example:
```jldoctest
julia> model = kernelPerceptronBinary([1.1 2.1; 5.3 4.2; 1.8 1.7], [-1,1,-1])
```
"""
function kernelPerceptronBinary(x, y; K=radialKernel, T=1000, α=zeros(Int64,length(y)), nMsgs=10, shuffle=false, rng = Random.GLOBAL_RNG)
 if nMsgs != 0
     @codeLocation
     println("***\n*** Training kernel perceptron for maximum $T iterations. Random shuffle: $shuffle")
 end
 x = makeMatrix(x)
 α = deepcopy(α) # let's not modify the argument !
 (n,d) = size(x)
 bestϵ = Inf
 lastϵ = Inf
 
  if nMsgs == 0
    showTime = typemax(Float64)
  elseif nMsgs < 5
    showTime = 50
  elseif nMsgs < 10
    showTime = 1
  elseif nMsgs < 100
    showTime = 0.5
  else
    showTime = 0.2
  end

 @showprogress showTime "Training Kernel Perceptron..." for t in 1:T
     ϵ = 0
     if shuffle
        # random shuffle x, y and alpha
        ridx = Random.shuffle(rng, 1:size(x)[1])
        x = x[ridx, :]
        y = y[ridx]
        α = α[ridx]
     end
     for i in 1:n
         if y[i]*sum([α[j]*y[j]*K(x[j,:],x[i,:]) for j in 1:n]) <= 0 + eps()
             α[i] += 1
             ϵ += 1
         end
     end
     if (ϵ == 0)
         if nMsgs != 0
             println("*** Avg. error after epoch $t : $(ϵ/size(x)[1]) (all elements of the set has been correctly classified")
         end
         return (x=x,y=y,α=α,errors=0,besterrors=0,iterations=t,separated=true,K=K)
     elseif ϵ < bestϵ
         bestϵ = ϵ
     end
     lastϵ = ϵ
     if nMsgs != 0 && (t % ceil(T/nMsgs) == 0 || t == 1 || t == T)
       println("Avg. error after iteration $t : $(ϵ/size(x)[1])")
     end
 end
 return  (x=x,y=y,α=α,errors=lastϵ,besterrors=bestϵ,iterations=T,separated=false)
end

"""
    predict(x,xtrain,ytrain,α;K)

Predict a binary label {-1,1} given the feature vector and the training data together with their errors (as trained by a kernel perceptron algorithm)

!!! warning
    This function is deprecated and will possibly be removed in BetaML 0.9.
    Use the `predict` function with your desired model instead. 

# Parameters:
* `x`:      Feature matrix of the data to predict (n × d)
* `xtrain`: The feature vectors used for the training
* `ytrain`: The labels of the training set
* `α`:      The errors associated to each record
* `K`:      The kernel function used for the training and to be used for the prediction [def: [`radialKernel`](@ref)]

# Return :
* `y`: Vector of the predicted labels

# Example:
```julia
julia> predict([1.1 2.1; 5.3 4.2; 1.8 1.7], [3.2,1.2])
```
"""
function predict(x,xtrain,ytrain,α;K=radialKernel)
    x = makeMatrix(x)
    xtrain = makeMatrix(xtrain)
    (n,d) = size(x)
    (ntrain,d2) = size(xtrain)
    if (d2 != d) error("xtrain and x must have the same dimensions."); end
    # corner case all one category
    if length(unique(ytrain)) == 1
        return fill(unique(ytrain)[1],n)
    end
    if ( length(ytrain) != ntrain || length(α) != ntrain) error("xtrain, ytrain and α must all have the same length."); end
    y = zeros(Int64,n)
    for i in 1:n
        y[i] = sum([ α[j] * ytrain[j] * K(x[i,:],xtrain[j,:]) for j in 1:ntrain]) > eps() ? 1 : -1
    end
    return y
 end


 """
     predict(x,xtrain,ytrain,α,classes;K)

 Predict a multiclass label given the new feature vector and a trained kernel perceptron model.

 !!! warning
    This function is deprecated and will possibly be removed in BetaML 0.9.
    Use the `predict` function with your desired model instead. 

 # Parameters:
 * `x`:      Feature matrix of the data to predict (n × d)
 * `xtrain`: A vector of the feature matrix used for training each of the one-vs-one class matches (i.e. `model.x`)
 * `ytrain`: A vector of the label vector used for training each of the one-vs-one class matches (i.e. `model.y`)
 * `α`:      A vector of the errors associated to each record (i.e. `model.α`)
 * `classes`: The overal classes encountered in training (i.e. `model.classes`)
 * `K`:      The kernel function used for the training and to be used for the prediction [def: [`radialKernel`](@ref)]

 # Return :
 * `ŷ`: Vector of dictionaries `label=>probability` (warning: it isn't really a probability, it is just the standardized number of matches "won" by this class compared with the other classes)

  # Notes:
  * Use `mode(ŷ)` if you want a single predicted label per record

 # Example:
 ```julia
 julia> model  = kernelPerceptron([1.1 2.1; 5.3 4.2; 1.8 1.7], [-1,1,-1])
 julia> ŷtrain = Perceptron.predict([10 10; 2.2 2.5],model.x,model.y,model.α, model.classes,K=model.K)
 ```
 """
 function predict(x,xtrain,ytrain,α,classes::AbstractVector{Tcl};K=radialKernel) where {Tcl}
     (n,d)   = size(x)
     nCl     = length(classes)
     y       = Array{Dict{Tcl,Float64},1}(undef,n)
     # corner case single class in training
     if nCl == 1
        return fill(Dict(classes[1] => 100.0),n)
     end
     nModels = Int((nCl  * (nCl - 1)) / 2)
     if !(nModels == length(xtrain) == length(ytrain) == length(α)) error("xtrain, ytrain or α have a length not compatible with the number of classes in this model."); end
     x = makeMatrix(x)
     d2 = size(xtrain[1],2)
     if (d2 != d) error("xtrain and x must have the same dimensions."); end
     for i in 1:n
         #countByClass = zeros(Float64,nCl)
         countByClass = zeros(Int64,nCl)
         mCounter = 1
          for (ic,c) in enumerate(classes)
             for (ic2,c2) in enumerate(classes)
                 if ic2 <= ic
                     continue
                 end
                 nThisModel = size(xtrain[mCounter],1)
                 if ( length(ytrain[mCounter]) != nThisModel || length(α[mCounter]) != nThisModel) error("xtrain, ytrain and α must all have the same length."); end
                 # note that we assign "winning" scores between pair of classes matches only based on who win, not by how much he did
                 # todo check
                 #if sum([ α[mCounter][j] * ((ytrain[mCounter][j] .== c) .*2 .-1) * K(x[i,:],xtrain[mCounter][j,:]) for j in 1:nThisModel]) > eps()
                 score = sum([ α[mCounter][j] * (ytrain[mCounter][j]) * K(x[i,:],xtrain[mCounter][j,:]) for j in 1:nThisModel])
                 #println(score)
                 if score > eps()
                     countByClass[ic] += 1
                     #countByClass[ic] += score
                 else
                     countByClass[ic2] += 1
                     #countByClass[ic2] += -score
                 end
                 mCounter += 1
             end
         end
         #println(countByClass)
         prob = softmax(countByClass)
         y[i] = Dict(zip(classes,prob))
    end
    return y
end

# ----------------------------------------------
# API V2...

"""
$(TYPEDEF)

Hyperparameters for the `Pegasos` model

# Parameters:
$(FIELDS)
"""
Base.@kwdef mutable struct KernelPerceptronHyperParametersSet <: BetaMLHyperParametersSet
    "Kernel function to employ. See `?radialKernel` or `?polynomialKernel` for details or check `?BetaML.Utils` to verify if other kernels are defined (you can alsways define your own kernel) [def: [`radialKernel`](@ref)]"
    kernel::Function = radialKernel       
    "Initial distribution of the number of errors errors [def: `nothing`, i.e. zeros]. If provided, this should be a nModels-lenght vector of nRecords integer values vectors , where nModels is computed as `(nClasses  * (nClasses - 1)) / 2`"
    initErrors::Union{Nothing,Vector{Vector{Int64}}} = nothing
    "Maximum number of epochs, i.e. passages trough the whole training sample [def: `100`]"
    epochs::Int64 = 100
    "Whether to randomly shuffle the data at each iteration (epoch) [def: `false`]"
    shuffle::Bool = false
end

Base.@kwdef mutable struct KernelPerceptronLearnableParameters <: BetaMLLearnableParametersSet
    xtrain::Union{Nothing,Vector{Matrix{Float64}}} = nothing
    ytrain::Union{Nothing,Vector{Vector{Int64}}} = nothing
    errors::Union{Nothing,Vector{Vector{Int64}}} = nothing
    classes::Vector  = []
end

"""
$(TYPEDEF)

A "kernel" version of the `Pegasos` model (supervised) with user configurable kernel function.

For the parameters see [`KernelPerceptronHyperParametersSet`](@ref) and [`BetaMLDefaultOptionsSet`](@ref)

## Limitations:
- data must be numerical
- online training (retraining) is not supported

"""
mutable struct KernelPerceptron <: BetaMLSupervisedModel
    hpar::KernelPerceptronHyperParametersSet
    opt::BetaMLDefaultOptionsSet
    par::Union{Nothing,KernelPerceptronLearnableParameters}
    cres::Union{Nothing,Vector}
    fitted::Bool
    info::Dict{Symbol,Any}
end

function KernelPerceptron(;kwargs...)
    m              = KernelPerceptron(KernelPerceptronHyperParametersSet(),BetaMLDefaultOptionsSet(),KernelPerceptronLearnableParameters(),nothing,false,Dict{Symbol,Any}())
    thisobjfields  = fieldnames(nonmissingtype(typeof(m)))
    for (kw,kwv) in kwargs
       found = false
       for f in thisobjfields
          fobj = getproperty(m,f)
          if kw in fieldnames(typeof(fobj))
              setproperty!(fobj,kw,kwv)
              found = true
          end
        end
        found || error("Keyword \"$kw\" is not part of this model.")
    end
    return m
end

"""
$(TYPEDFIELDS)

Fit a KernelPerceptron model.

"""
function fit!(m::KernelPerceptron,X,Y)
    

    # Parameter alias..
    kernel          = m.hpar.kernel
    initErrors      = m.hpar.initErrors
    epochs          = m.hpar.epochs
    shuffle         = m.hpar.shuffle

    cache           = m.opt.cache
    verbosity       = m.opt.verbosity
    rng             = m.opt.rng

    nR,nD    = size(X)
    yclasses = unique(Y)
    nCl      = length(yclasses)
    nModels   = Int((nCl  * (nCl - 1)) / 2)
    initErrors =  (initErrors == nothing) ? [zeros(nR) for i in 1:nCl] : initErrors 
    
    if verbosity == NONE
        nMsgs = 0
    elseif verbosity <= LOW
        nMsgs = 5
    elseif verbosity <= STD
        nMsgs = 10
    elseif verbosity <= HIGH
        nMsgs = 100
    else
        nMsgs = 100000
    end

    out = kernelPerceptron(X, Y; K=kernel, T=epochs, α=initErrors, nMsgs=nMsgs, shuffle=shuffle, rng = rng)

    m.par = KernelPerceptronLearnableParameters(out.x,out.y,out.α,out.classes)

  
    if cache
       out    = predict(X,m.par.xtrain,m.par.ytrain,m.par.errors,m.par.classes;K=kernel)
       m.cres = cache ? out : nothing
    end

    m.info[:fitted_records] = nR
    m.info[:dimensions]    = nD
    m.info[:nClasses]      = nCl
    m.info[:nModels]       = nModels
    
    m.fitted = true
    
    return cache ? m.cres : nothing
end

"""
$(TYPEDFIELDS)

Predict labels using a fitted KernelPerceptron model.

"""
function predict(m::KernelPerceptron,X)
    return predict(X,m.par.xtrain,m.par.ytrain,m.par.errors,m.par.classes;K=m.hpar.kernel)
end

function show(io::IO, ::MIME"text/plain", m::KernelPerceptron)
    if m.fitted == false
        print(io,"KernelPerceptron - A \"kernelised\" version of the perceptron classifier (unfitted)")
    else
        print(io,"KernelPerceptron - A \"kernelised\" version of the perceptron classifier (fitted on $(m.info[:fitted_records]) records)")
    end
end

function show(io::IO, m::KernelPerceptron)
    m.opt.descr != "" && println(io,m.opt.descr)
    if m.fitted == false
        println(io,"KernelPerceptron - A $(m.info[:dimensions])-dimensions $(m.info[:nClasses])-classes \"kernelised\" version of the perceptron classifier (unfitted)")
    else
        println(io,"KernelPerceptron - A $(m.info[:dimensions])-dimensions $(m.info[:nClasses])-classes \"kernelised\" version of the perceptron classifier (fitted on $(m.info[:fitted_records]) records)")
        print(io,"Kernel: ")
        print(io,m.hpar.kernel)
    end
end
