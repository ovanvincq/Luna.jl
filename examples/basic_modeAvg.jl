using Luna
import Logging
import FFTW
Logging.disable_logging(Logging.BelowMinLevel)

a = 13e-6
gas = :Ar
pres = 5

τ = 30e-15
λ0 = 800e-9

grid = Grid.RealGrid(15e-2, 800e-9, (160e-9, 3000e-9), 1e-12)

m = Capillary.MarcatilliMode(a, gas, pres, loss=false)
aeff = let m=m
    z -> Modes.Aeff(m, z=z)
end

energyfun, energyfunω = NonlinearRHS.energy_modal(grid)

function gausspulse(t)
    It = Maths.gauss(t, fwhm=τ)
    ω0 = 2π*PhysData.c/λ0
    Et = @. sqrt(It)*cos(ω0*t)
end

dens0 = PhysData.density(gas, pres)
densityfun(z) = dens0

ionpot = PhysData.ionisation_potential(gas)
ionrate = Ionisation.ionrate_fun!_ADK(ionpot)

plasma = Nonlinear.PlasmaCumtrapz(grid.to, grid.to, ionrate, ionpot)
responses = (Nonlinear.Kerr_field(PhysData.γ3_gas(gas)),
             plasma)

linop, βfun, β1, αfun = LinearOps.make_const_linop(grid, m, λ0)

normfun = NonlinearRHS.norm_mode_average(grid.ω, βfun, aeff)

in1 = (func=gausspulse, energy=1e-6)
inputs = (in1, )

Eω, transform, FT = Luna.setup(
    grid, energyfun, densityfun, normfun, responses, inputs, aeff)

statsfun = Stats.collect_stats(grid, Eω,
                               Stats.ω0(grid),
                               Stats.energy(grid, energyfunω),
                               Stats.energy_λ(grid, energyfunω, (150e-9, 300e-9), label="RDW"),
                               Stats.peakpower(grid),
                               Stats.peakintensity(grid, aeff),
                               Stats.fwhm_t(grid),
                               Stats.electrondensity(grid, ionrate, densityfun, aeff),
                               Stats.density(densityfun))
output = Output.MemoryOutput(0, grid.zmax, 201, (length(grid.ω),), statsfun)

Luna.run(Eω, grid, linop, transform, FT, output)

import PyPlot:pygui, plt

ω = grid.ω
t = grid.t

zout = output["z"]
Eout = output["Eω"]

Etout = FFTW.irfft(Eout, length(grid.t), 1)

Ilog = log10.(Maths.normbymax(abs2.(Eout)))

idcs = @. (t < 30e-15) & (t >-30e-15)
to, Eto = Maths.oversample(t[idcs], Etout[idcs, :], factor=16)
It = abs2.(Maths.hilbert(Eto))
Itlog = log10.(Maths.normbymax(It))
zpeak = argmax(dropdims(maximum(It, dims=1), dims=1))

Et = Maths.hilbert(Etout)
energy = [energyfun(t, Etout[:, ii]) for ii=1:size(Etout, 2)]
energyω = [energyfunω(ω, Eout[:, ii]) for ii=1:size(Eout, 2)]

pygui(true)
##
plt.figure()
plt.pcolormesh(ω./2π.*1e-15, zout, transpose(Ilog))
plt.clim(-6, 0)
plt.colorbar()

##
plt.figure()
plt.pcolormesh(to*1e15, zout, transpose(It))
plt.colorbar()
plt.xlim(-30, 30)

##
plt.figure()
plt.plot(zout.*1e2, energy.*1e6)
plt.plot(zout.*1e2, energyω.*1e6)
plt.plot(output["stats"]["z"].*1e2, output["stats"]["energy"].*1e6)
plt.xlabel("Distance (cm)")
plt.ylabel("Energy (μJ)")

##
plt.figure()
plt.plot(output["stats"]["z"].*1e2, output["stats"]["energy_RDW"].*1e6)
plt.xlabel("Distance (cm)")
plt.ylabel("RDW Energy (μJ)")

##
plt.figure()
plt.plot(output["stats"]["z"].*1e2, output["stats"]["peakpower"].*1e-9)
plt.xlabel("Distance (cm)")
plt.ylabel("Peak power (GW)")

##
plt.figure()
plt.plot(output["stats"]["z"].*1e2, output["stats"]["peakintensity"].*1e-4.*1e-12)
plt.xlabel("Distance (cm)")
plt.ylabel("Peak intensity (TW/cm\$^2\$)")

##
plt.figure()
plt.plot(output["stats"]["z"].*1e2, output["stats"]["fwhm_t_min"].*1e15)
plt.plot(output["stats"]["z"].*1e2, output["stats"]["fwhm_t_max"].*1e15)
plt.xlabel("Distance (cm)")
plt.ylabel("FWHM (fs)")

##
plt.figure()
plt.plot(output["stats"]["z"].*1e2, output["stats"]["density"]*1e-6)
plt.xlabel("Distance (cm)")
plt.ylabel("Density (cm\$^{-3}\$)")

##
plt.figure()
plt.plot(output["stats"]["z"].*1e2, output["stats"]["electrondensity"]*1e-6)
plt.xlabel("Distance (cm)")
plt.ylabel("Electron Density (cm\$^{-3}\$)")