# this file defines a piecewise-uniform distribution, and defines the cdf
# function for the SkewNormal.

using Distributions, StatsAPI

# representation of two-part uniform distribution used for priors in spend-down model
struct PiecewiseUniform{T<:Real} <: ContinuousUnivariateDistribution
  x::Vector{T}; Fx::Vector{T}
  iter::Base.Iterators.Zip{Tuple{Vector{T}, Vector{T}, Vector{T}}}  # holds x[2:end] and corresponding percentiles and densities

  function PiecewiseUniform{T}(x, Fx) where {T<:Real}  # constructor
    length(x)==length(Fx) || throw(ArgumentError("`x` and `Fx` must have the same length."))
    issorted(Fx)          || throw(ArgumentError("`Fx` must be sorted."))
    iszero(Fx[1])         || throw(ArgumentError("The first value for `Fx` must be 0."))
    isone(Fx[end])        || throw(ArgumentError("The last value for `Fx` must be 1."))

    return new{T}(x, Fx, zip(x[2:end], Fx[2:end], (Fx[2:end] - Fx[1:end-1]) ./ (x[2:end] - x[1:end-1])))
  end
end
PiecewiseUniform(x::Vector{T}, Fx::Vector{T}) where {T<:Real} = PiecewiseUniform{T}(x,Fx)

StatsAPI.params(d::PiecewiseUniform) = d.x, d.Fx

function Distributions.pdf(d::PiecewiseUniform{T}, y::Real) where {T}
  (y≤d.x[1] || y>d.x[end]) && return zero(T)
  for (x,_,density) ∈ d.iter
    y ≤ x && return density
  end
end

Base.show(io::IO, o::PiecewiseUniform{T}) where {T} = print(io, "PiecewiseUniform($(o.x), $(o.Fx))")

# quantile function for this distribution--given p ∈ [0,1], return quantile
# all that's needed for rand() to work with the distribution
function Statistics.quantile(d::PiecewiseUniform, q::Real)
  for (x,Fx,density) ∈ d.iter
    q ≤ Fx && return x - (Fx - q) / density
  end
end

# define + and * to shift and scale this distribution by a scalar 
import Base.+, Base.*, Base./
+(a::Real, b::PiecewiseUniform{T}) where {T} = PiecewiseUniform{T}(a.+b.x,b.Fx)
+(b::PiecewiseUniform{T}, a::Real) where {T} = PiecewiseUniform{T}(a.+b.x,b.Fx)
*(a::Real, b::PiecewiseUniform{T}) where {T} = PiecewiseUniform{T}(a.*b.x,b.Fx)
*(b::PiecewiseUniform{T}, a::Real) where {T} = PiecewiseUniform{T}(a.*b.x,b.Fx)
/(b::PiecewiseUniform{T}, a::Real) where {T} = PiecewiseUniform{T}(b.x/a,b.Fx)

TwoPieceUniform(x) = PiecewiseUniform(x, eltype(x)[0, .5, 1])

# quasi-triangular distribution, in general with discontintuity in pdf at central quantile
# https://www.mhnederlof.nl/doubletriangular.html
struct Bitriangular{T<:Real} <: ContinuousUnivariateDistribution
  x::Vector{T}; Fx::Vector{T}
  C₁::T; C₂::T

  function Bitriangular{T}(x, Fx) where {T<:Real}  # constructor
    length(x)==length(Fx) || throw(ArgumentError("`x` and `Fx` must have the same length."))
    issorted(Fx)          || throw(ArgumentError("`Fx` must be sorted."))
    iszero(Fx[1])         || throw(ArgumentError("The first value for `Fx` must be 0."))
    isone(Fx[end])        || throw(ArgumentError("The last value for `Fx` must be 1."))

    return new{T}(x, Fx, (x[2]-x[1])/√Fx[2], (x[2]-x[3])/√(1-Fx[2]))
  end
end
Bitriangular(x::Vector{T}, Fx::Vector{T}=T[0,.5,1]) where {T<:Real} = Bitriangular{T}(x,Fx)

StatsAPI.params(d::Bitriangular) = d.x, d.Fx

Base.show(io::IO, o::Bitriangular{T}) where {T} = print(io, "Bitriangular($(o.x), $(o.Fx))")

# quantile function for this distribution--given p ∈ [0,1], return quantile
# all that's needed for rand() to work with the distribution
Statistics.quantile(d::Bitriangular, q::Real) = q ≤ d.Fx[2] ? d.x[1] + d.C₁ * √q : d.x[3] + d.C₂ * √(1-q)

Distributions.pdf(d::Bitriangular{T}, y::Real) where {T} =
  y ≤ d.x[1] ? zero(T) :
  y ≤ d.x[2] ? 2 * (y - d.x[1]) / (d.x[2] - d.x[1])^2 * d.Fx[2] :
  y < d.x[3] ? 2 * (d.x[3] - y) / (d.x[2] - d.x[3])^2 * (1 - d.Fx[2]) :
               zero(T)

# define + and * to shift and scale this distribution by a scalar 
import Base.+, Base.*, Base./
+(a::Real, b::Bitriangular{T}) where {T} = Bitriangular{T}(a.+b.x,b.Fx)
+(b::Bitriangular{T}, a::Real) where {T} = Bitriangular{T}(a.+b.x,b.Fx)
*(a::Real, b::Bitriangular{T}) where {T} = Bitriangular{T}(a.*b.x,b.Fx)
*(b::Bitriangular{T}, a::Real) where {T} = Bitriangular{T}(a.*b.x,b.Fx)
/(b::Bitriangular{T}, a::Real) where {T} = Bitriangular{T}(b.x/a,b.Fx)

