using Factorio
using Test

@testset "Test UniqueID bit-packing" begin
    @test bitstring(mask(UInt8)) == "00001111"
    @test bitstring(~mask(UInt8)) == "11110000"

    a = combine(UInt8(10), UInt8(12))
    @test bitstring(a) == "10101100"
    @test bitstring(model(a)) == "00001010"
    @test bitstring(index(a)) == "00001100"
end
