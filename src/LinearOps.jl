module LinearOps
import FFTW
import Luna: Modes, Grid, PhysData
import Luna.PhysData: wlfreq

# limit α so that we do not get overflow in exp(α*dz)
function αlim!(α)
    # magic number: this is 1300 dB/m it could probably be bigger
    α[α .> 300] .= 300
    α[α .< 0] .= 0
end

function make_const_linop(grid::Grid.RealGrid, βfun!, αfun!, frame_vel)
    β = similar(grid.ω)
    βfun!(β, grid.ω, 0)
    α = similar(grid.ω)
    αfun!(α, grid.ω, 0)
    αlim!(α)
    β1 = 1/frame_vel(0)
    linop = @. -im*(β-β1*grid.ω) - α/2
    linop[1] = 0
    return linop
end

function make_const_linop(grid::Grid.EnvGrid, βfun!, αfun!, frame_vel, β0ref)
    β = similar(grid.ω)
    βfun!(β, grid.ω, 0)
    α = similar(grid.ω)
    αfun!(α, grid.ω, 0)
    αlim!(α)
    β1 = 1/frame_vel(0)
    linop = -im.*(β .- β1.*(grid.ω .- grid.ω0) .- β0ref) .- α./2
    linop[.!grid.sidx] .= 1
    return linop
end

function make_const_linop(grid::Grid.EnvGrid, mode::Modes.AbstractMode, λ0; thg=false)
    β1const = Modes.dispersion(mode, 1, wlfreq(λ0))
    if thg
        β0const = 0.0
    else
        β0const = Modes.β(mode, wlfreq(λ0))
    end
    βconst = zero(grid.ω)
    βconst[grid.sidx] = Modes.β.(mode, grid.ω[grid.sidx])
    βconst[.!grid.sidx] .= 1
    function βfun!(out, ω, z)
        out .= βconst
    end
    αconst = zero(grid.ω)
    αconst[grid.sidx] = Modes.α.(mode, grid.ω[grid.sidx])
    function αfun!(out, ω, z)
        out .= αconst
    end
    frame_vel(z) = 1/β1const
    make_const_linop(grid, βfun!, αfun!, frame_vel, β0const), βfun!, frame_vel, αfun!
end

function make_const_linop(grid::Grid.RealGrid, mode::Modes.AbstractMode, λ0)
    β1const = Modes.dispersion(mode, 1, wlfreq(λ0))
    βconst = zero(grid.ω)
    βconst[2:end] = Modes.β.(mode, grid.ω[2:end])
    βconst[1] = 1
    function βfun!(out, ω, z)
        out .= βconst
    end
    αconst = zero(grid.ω)
    αconst[2:end] = Modes.α.(mode, grid.ω[2:end])
    function αfun!(out, ω, z)
        out .= αconst
    end
    frame_vel(z) = 1/β1const
    make_const_linop(grid, βfun!, αfun!, frame_vel), βfun!, frame_vel, αfun!
end

function make_const_linop(grid::Grid.RealGrid, modes, λ0; ref_mode=1)
    vel = 1/Modes.dispersion(modes[ref_mode], 1, wlfreq(λ0))
    nmodes = length(modes)
    linops = zeros(ComplexF64, length(grid.ω), nmodes)
    for i = 1:nmodes
        βconst = zero(grid.ω)
        βconst[2:end] = Modes.β.(modes[i], grid.ω[2:end])
        βconst[1] = 1
        α = Modes.α.(modes[i], grid.ω)
        linops[:,i] = im.*(-βconst .+ grid.ω./vel) .- α./2
    end
    linops
end

function make_const_linop(grid::Grid.EnvGrid, modes, λ0; ref_mode=1, thg=false)
    vel = 1/Modes.dispersion(modes[ref_mode], 1, wlfreq(λ0))
    if thg
        βref = 0.0
    else
        βref = Modes.β(modes[ref_mode], wlfreq(λ0))
    end
    nmodes = length(modes)
    linops = zeros(ComplexF64, length(grid.ω), nmodes)
    for i = 1:nmodes
        βconst = zero(grid.ω)
        βconst[grid.sidx] = Modes.β.(modes[i], grid.ω[grid.sidx])
        βconst[.!grid.sidx] .= 1
        α = Modes.α.(modes[i], grid.ω)
        linops[:,i] = -im.*(βconst .- (grid.ω .- grid.ω0)./vel .- βref) .- α./2
    end
    linops
end

function make_linop(grid::Grid.RealGrid, mode::Modes.AbstractMode, λ0)
    function linop!(out, z)
        out[2:end] .= -im.*grid.ω[2:end]./PhysData.c.*conj.(Modes.neff.(mode, grid.ω[2:end], z=z))
        out .-= -im.*grid.ω.*Modes.dispersion(mode, 1, wlfreq(λ0), z=z)
        out[1] = 1
    end
    function βfun!(out, ω, z)
        out[2:end] .= Modes.β.(mode, ω[2:end], z=z)
        out[1] = 1
    end
    return linop!, βfun!
end

function make_linop(grid::Grid.EnvGrid, mode::Modes.AbstractMode, λ0; thg=false)
    function linop!(out, z)
        fill!(out, 1.0)
        out[grid.sidx] .= -im.*(
            grid.ω[grid.sidx]./PhysData.c.*conj.(Modes.neff.(mode, grid.ω[grid.sidx], z=z))
            )
        out[grid.sidx] .-= -im.*(
            (grid.ω[grid.sidx] .- grid.ω0).*Modes.dispersion(mode, 1, wlfreq(λ0), z=z)
            )
        if !thg
            out[grid.sidx] .-= -im.*Modes.β(mode, wlfreq(λ0))
        end
    end
    function βfun!(out, ω, z)
        fill!(out, 1.0)
        out[grid.sidx] .= Modes.β.(mode, ω[grid.sidx], z=z)
    end
    return linop!, βfun!
end

function make_linop(grid::Grid.RealGrid, modes, λ0; ref_mode=1)
    function linop!(out, z)
        β1 = Modes.dispersion(modes[ref_mode], 1, wlfreq(λ0), z=z)
        nmodes = length(modes)
        for i = 1:nmodes
            out[2:end, i] .= -im.*(
                grid.ω[2:end]./PhysData.c.*conj.(Modes.neff.(modes[i], grid.ω[2:end], z=z))
                .- grid.ω[2:end] .* β1
                )
            out[1, i] = 1
        end
    end
end

function make_linop(grid::Grid.EnvGrid, modes, λ0; ref_mode=1, thg=false)
    function linop!(out, z)
        β1 = Modes.dispersion(modes[ref_mode], 1, wlfreq(λ0), z=z)
        βref = Modes.β(modes[ref_mode], wlfreq(λ0))
        nmodes = length(modes)
        fill!(out, 1.0)
        for i = 1:nmodes
            out[grid.sidx, i] .= -im.*(
                grid.ω[grid.sidx]./PhysData.c.*conj.(Modes.neff.(modes[i], grid.ω[grid.sidx], z=z))
                .- (grid.ω[grid.sidx] .- grid.ω0) .* β1
                )
            if !thg
                out[grid.sidx, i] .-= -im.*βref
            end
        end
    end
end


end