using Factorio
using Test

@testset "Test consumes only" begin
    g = Factorio.recipes()
    # Recipes that ONLY uses iron-gear-wheel, iron-plate and electronic-circuit
    expected = Set(["recipe-radar", "recipe-assembling-machine-1", "recipe-electric-mining-drill", "recipe-rocket-launcher", "recipe-inserter"])
    @test Set(consumes_only(g, "iron-gear-wheel", "iron-plate", "electronic-circuit") |> Factorio.labels) == expected
    @test Set(consumes_only("iron-gear-wheel", "iron-plate", "electronic-circuit") |> Factorio.labels) == expected
end

@testset "Test consumes any" begin
    # Recipes that uses iron-ore and concrete
    expected = Set(["recipe-concrete", "recipe-refined-concrete", "recipe-hazard-concrete", "recipe-nuclear-reactor", "recipe-artillery-turret", "recipe-iron-plate", "recipe-rocket-silo", "recipe-centrifuge"])
    @test Set(consumes_any("iron-ore", "concrete") |> Factorio.labels) == expected
end

@testset "Test consumes all" begin
    # Recipes that uses AT LEAST iron-plate and copper-cable, may use other ingredients
    expected = Set(["recipe-programmable-speaker", "recipe-power-switch", "recipe-electronic-circuit", "recipe-small-lamp"])
    @test Set(consumes_all("iron-plate", "copper-cable") |> Factorio.labels) == expected
end