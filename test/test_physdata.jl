import Test: @test, @test_throws, @testset
import Luna: PhysData

@testset "All" begin
@testset "Exceptions" begin
    @test_throws DomainError PhysData.ref_index(:Hello, 800e-9)
end

@testset "refractive indices" begin
    @test PhysData.ref_index(:He, 800e-9) ≈ 1.000031838924767
    @test PhysData.ref_index(:He, 800e-9, 10) ≈ 1.000316956731852
    @test PhysData.ref_index(:SiO2, 800e-9) ≈ 1.4533172548587419
    @test PhysData.ref_index(:SiO2, 400e-9) ≈ 1.4701161185594052
end

@testset "Function equivalence" begin
    @test PhysData.ref_index_fun(:SiO2)(800e-9) == PhysData.ref_index(:SiO2, 800e-9)
    @test PhysData.ref_index_fun(:He)(800e-9) == PhysData.ref_index(:He, 800e-9)
end

@testset "Dispersion" begin
    @test PhysData.dispersion(2, :SiO2, 800e-9) ≈ 3.61619983e-26
    @test isapprox(PhysData.dispersion(2, :He, 800e-9), 9.341731241826773e-31, rtol=1e-5)
    @test isapprox(PhysData.dispersion(2, :He, 800e-9, 10), 9.29798136665208e-30, rtol=1e-5)
end

@testset "glasses" begin
    for g in PhysData.glass
        @test isreal(PhysData.ref_index(g, 800e-9))
    end
end

@testset "gases" begin
    for g in PhysData.gas
        @test isreal(PhysData.ref_index(g, 800e-9))
        @test isreal(PhysData.ref_index(g, 200e-9))
        @test isreal(PhysData.ref_index(g, 800e-9, 10))
        @test isreal(PhysData.ref_index(g, 200e-9, 10))
    end
end

@testset "Nonlinear coefficients" begin
    # @test PhysData.χ3_gas(:He)*PhysData.std_dens ≈ 1.2820625447291168e-27
    @test PhysData.χ3_gas(:He, 1) ≈ 1.2747527567432276e-27
    @test PhysData.χ3_gas(:Ar, 1) ≈ 2.99474912011304e-26
    @test PhysData.n2_gas(:He, 1) ≈ 3.6015556897183797e-25
    @test PhysData.n2_gas(:He, 2) ≈ 7.199115643112888e-25
    @test PhysData.n2_gas.(:He, [1, 2]) ≈ [3.6015556897183797e-25, 7.199115643112888e-25]
    @test PhysData.n2_gas.([:He, :Ne], 1) ≈ [3.6015556897183797e-25, 6.482245292051824e-25]
    for gas in PhysData.gas[2:end] # Don't have γ3 for Air
        @test isreal(PhysData.n2_gas(gas, 1))
    end
end

@testset "Density spline" begin
    P = range(0, 10, length=10)
    Plow = range(0, 0.1, length=10)
    for g in PhysData.gas
        dens = PhysData.densityspline(g, Pmax=maximum(P))
        @test all(dens.(P) .≈ PhysData.density.(g, P))
        dens = PhysData.densityspline(g, Pmax=maximum(Plow))
        @test all(dens.(Plow) .≈ PhysData.density.(g, Plow))
    end
end
end