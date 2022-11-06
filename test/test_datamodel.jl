using Factorio
using Test

@testset "Test Index hash" begin
    @test bitstring(mask(UInt8)) == "00001111"
    @test bitstring(~mask(UInt8)) == "11110000"

    a = UniqueElement(UInt8(10), UInt8(12))
    #@assert bitstring(uid(a)) == bitstring(model(a)) * bitstring(index(a))
    @test bitstring(uid(a)) == "10101100"
    @test bitstring(model(a)) == "00001010"
    @test bitstring(index(a)) == "00001100"
end