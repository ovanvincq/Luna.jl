module Fields
import Luna
import Luna: Grid, Maths, PhysData
import NumericalIntegration: integrate, SimpsonEven
import Random: MersenneTwister
import Hankel

abstract type AbstractField end

"""
    TimeField(λ0, energy, ϕ, τ0, Itshape)

Represents a temporal pulse with shape defined by `Itshape`.

# Fields
- `λ0::Float64`: the central field wavelength
- `energy::Float64`: the pulse energy
- `ϕ::Float64`: the CEO phase
- `τ0::Float64`: the temproal shift from grid time 0
- `Itshape`: a callable `f(t)` to get the shape of the intensity/power in the time domain
"""
struct TimeField{iT} <: AbstractField
    λ0::Float64
    energy::Float64
    ϕ::Float64
    τ0::Float64
    Itshape::iT
end

"""
    GaussField(;λ0, τfwhm, energy, ϕ=0.0, τ0=0.0, m=1)

Construct a (super)Gaussian shaped pulse with intensity/power FWHM `τfwhm`,
superGaussian parameter `m=1` and other parameters as defined for [`TimeField`](@ref).
"""
function GaussField(;λ0, τfwhm, energy, ϕ=0.0, τ0=0.0, m=1)
    TimeField(λ0, energy, ϕ, τ0, t -> Maths.gauss(t, fwhm=τfwhm, power=2*m))
end

"""
    SechField(;λ0, τw, energy, ϕ=0.0, τ0=0.0)

Construct a Sech^2(t/τw) shaped pulse with natural width `τw`,
and other parameters as defined for [`TimeField`](@ref).
"""
function SechField(;λ0, τw, energy, ϕ=0.0, τ0=0.0)
    TimeField(λ0, energy, ϕ, τ0, t -> sech(t/τw)^2)
end

"""
    SechField(;λ0, τfwhm, energy, ϕ=0.0, τ0=0.0)

Construct a Sech^2 shaped pulse with intensity/power FWHM `τfwhm`,
and other parameters as defined for [`TimeField`](@ref).
"""
#function SechField(;λ0, τfwhm, energy, ϕ=0.0, τ0=0.0)
#    τw = τfwhm/(2*log(1 + sqrt(2)))
#    SechField(λ0=λ0, τw=τw, energy=energy, ϕ=ϕ, τ0=τ0)
#end

function make_Et(p::TimeField, grid::Grid.RealGrid)
    t = grid.t .- p.τ0
    ω0 = PhysData.wlfreq(p.λ0)
    @. sqrt(p.Itshape(t))*cos(ω0*t + p.ϕ)
end

function make_Et(p::TimeField, grid::Grid.EnvGrid)
    t = grid.t .- p.τ0
    Δω = PhysData.wlfreq(p.λ0) - grid.ω0
    @. sqrt(p.Itshape(t))*exp(im*(p.ϕ + Δω*t))
end

"Add the field to `Eω` for the provided `grid`, `energy_t` function and Fourier transform `FT`"
function (p::TimeField)(Eω, grid, energy_t, FT)
    Eω .+= FT * (sqrt(p.energy)/sqrt(energy_t(Et)) .* make_Et(p, grid))
end

"Add shotnoise to `Eω` for the provided `grid`. The random `seed` can optionally be provided.
The optional parameters `energy_t` and `FT` are unused and are present for interface
compatibility with [`TimeField`](@ref)."
function shotnoise!(Eω, grid::Grid.RealGrid, energy_t=nothing, FT=nothing; seed=nothing)
    rng = MersenneTwister(seed)
    δω = grid.ω[2] - grid.ω[1]
    δt = grid.t[2] - grid.t[1]
    amp = @. sqrt(PhysData.ħ*grid.ω/δω)
    rFFTamp = sqrt(2π)/2δt*amp
    φ = 2π*rand(rng, size(Eω)...)
    @. Eω += rFFTamp * exp(1im*φ)
end

function shotnoise!(Eω, grid::Grid.EnvGrid, energy_t=nothing, FT=nothing; seed=nothing)
    rng = MersenneTwister(seed)
    δω = grid.ω[2] - grid.ω[1]
    δt = grid.t[2] - grid.t[1]
    amp = zero(grid.ω)
    amp[grid.sidx] = @. sqrt(PhysData.ħ*grid.ω[grid.sidx]/δω)
    FFTamp = sqrt(2π)/δt*amp
    φ = 2π*rand(rng, size(Eω)...)
    @. Eω += FFTamp * exp(1im*φ)
end

"""
    SpatioTemporalField(timefield, Isshape)

Represents a spatiotemporal pulse with temporal shape defined by `timefield`,
and spatial intensity defined by `Isshape`.
"""
struct SpatioTemporalField{tT,sT} <: AbstractField
    timefield::tT
    Isshape::sT
    propz::Float64
end

"""
    GaussGaussField(;λ0, τfwhm, energy, w0, ϕ=0.0, τ0=0.0, m=1)

Construct a (super)Gaussian shaped pulse with intensity/power FWHM `τfwhm`,
uperGaussian parameter `m=1` and Gaussian shaped spatial profile with waist `w0`,
propagation distance from the waist of `propz`,
and other parameters as defined for [`TimeField`](@ref).
"""
function GaussGaussField(;λ0, τfwhm, energy, w0, ϕ=0.0, τ0=0.0, m=1, propz=0.0)
    SpatioTemporalField(TimeField(λ0, energy, ϕ, τ0, t -> Maths.gauss(t, fwhm=τfwhm, power=2*m)),
                        r -> Maths.gauss(r, w0/2), propz)
end

"Add the field to `Eωk` for the provided `grid`, `spacegrid` `energy_t` function
and Fourier transform `FT`"
function (s::SpatioTemporalField)(Eωk, grid, spacegrid::Hankel.QDH, energy_t, FT)
    Et = make_Et(s.timefield, grid) .* sqrt.(Isshape.(spacegrid.r)')
    lEωk = spacegrid * (FT * (sqrt(s.timefield.energy)/sqrt(energy_t(Et)) .* Et))
    prop!(lEωk, z, grid, spacegrid)
    Eωk .+= lEωk
end

# TODO propagation of this field
function (s::SpatioTemporalField)(Eωk, grid, spacegrid::Grid.FreeGrid, energy_t, FT)
    Et = make_Et(s.timefield, grid) .* sqrt.(Isshape.(spacegrid.r))
    Eωk .+= spacegrid * (FT * (sqrt(s.timefield.energy)/sqrt(energy_t(Et)) .* Et))
end

function prop!(Eωk, z, grid, q)
    kzsq = @. (grid.ω/PhysData.c)^2 - (q.k^2)'
    kzsq[kzsq .< 0] .= 0
    kz = sqrt.(kzsq)
    @. Eωk *= exp(-1im * z * (kz - grid.ω/PhysData.c))
end

"Calculate energy from modal field E(t)"
function energyfuncs(grid::Grid.RealGrid)
    function energy_t(Et)
        Eta = Maths.hilbert(Et)
        return integrate(grid.t, abs2.(Eta), SimpsonEven())
    end

    prefac = 2π/(grid.ω[end]^2)
    function energy_ω(Eω)
        prefac*integrate(grid.ω, abs2.(Eω), SimpsonEven())
    end
    return energy_t, energy_ω
end

function energyfuncs(grid::Grid.EnvGrid)
    function energy_t(Et)
        return integrate(grid.t, abs2.(Et), SimpsonEven())
    end

    δω = grid.ω[2] - grid.ω[1]
    Δω = length(grid.ω)*δω
    prefac = 2π*δω/(Δω^2)
    function energy_ω(Eω)
        prefac*sum(abs2.(Eω))
    end
    return energy_t, energy_ω
end

function energyfuncs(grid::Grid.RealGrid, q::Hankel.QDHT)
    function energy_t(Et)
        Eta = Maths.hilbert(Et)
        tintg = integrate(grid.t, abs2.(Eta), SimpsonEven())
        return 2π*PhysData.c*PhysData.ε_0/2 * Hankel.integrateR(tintg, q)
    end

    prefac = 2π*PhysData.c*PhysData.ε_0/2 * 2π/(grid.ω[end]^2)
    function energy_ω(Eω)
        ωintg = integrate(grid.ω, abs2.(Eω), SimpsonEven())
        return prefac*Hankel.integrateK(ωintg, q)
    end
    return energy_t, energy_ω
end

function energyfuncs(grid::Grid.EnvGrid, q::Hankel.QDHT)
    function energy_t(Et)
        tintg = integrate(grid.t, abs2.(Et), SimpsonEven())
        return 2π*PhysData.c*PhysData.ε_0/2 * Hankel.integrateR(tintg, q)
    end

    δω = grid.ω[2] - grid.ω[1]
    Δω = length(grid.ω)*δω
    prefac = 2π*PhysData.c*PhysData.ε_0/2 * 2π*δω/(Δω^2)
    function energy_ω(Eω)
        ωintg = dropdims(sum(abs2.(Eω); dims=1), dims=1)
        return prefac*Hankel.integrateK(ωintg, q)
    end
    return energy_t, energy_ω
end

function energyfuncs(grid::Grid.RealGrid, xygrid::Grid.FreeGrid)
    δx = xygrid.x[2] - xygrid.x[1]
    δy = xygrid.y[2] - xygrid.y[1]
    δt = grid.t[2] - grid.t[1]
    prefac_t = PhysData.c*PhysData.ε_0/2 * δx * δy * δt
    function energy_t(Et)
        Eta = Maths.hilbert(Et)
        return  prefac_t * sum(abs2.(Eta)) 
    end

    δω = grid.ω[2] - grid.ω[1]
    Δω = grid.ω[end]
    δkx = xygrid.kx[2] - xygrid.kx[1]
    Δkx = length(xygrid.kx)*δkx
    δky = xygrid.ky[2] - xygrid.ky[1]
    Δky = length(xygrid.ky)*δky
    prefac = PhysData.c*PhysData.ε_0/2 * 2π*δω/(Δω^2) * 2π*δkx/(Δkx^2) * 2π*δky/(Δky^2)
    energy_ω(Eω) = prefac * sum(abs2.(Eω))

    return energy_t, energy_ω
end

function energyfuncs(grid::Grid.EnvGrid, xygrid::Grid.FreeGrid)
    δx = xygrid.x[2] - xygrid.x[1]
    δy = xygrid.y[2] - xygrid.y[1]
    δt = grid.t[2] - grid.t[1]
    prefac_t = PhysData.c*PhysData.ε_0/2 * δx * δy * δt
    function energy_t(Et)
        return  prefac_t * sum(abs2.(Et)) 
    end

    δω = grid.ω[2] - grid.ω[1]
    Δω = length(grid.ω)*δω
    δkx = xygrid.kx[2] - xygrid.kx[1]
    Δkx = length(xygrid.kx)*δkx
    δky = xygrid.ky[2] - xygrid.ky[1]
    Δky = length(xygrid.ky)*δky
    prefac = PhysData.c*PhysData.ε_0/2 * 2π*δω/(Δω^2) * 2π*δkx/(Δkx^2) * 2π*δky/(Δky^2)
    energy_ω(Eω) = prefac * sum(abs2.(Eω))

    return energy_t, energy_ω
end

end
