
abstract type AbstractElement end

abstract type AbstractDataModel end

abstract type AbstractItem <: AbstractElement end

struct Fluid <: AbstractItem end

struct Item <: AbstractItem end


struct AssemblingMachine{T} end
AssemblingMachine(x) = AssemblingMachine{x}()
tier(::AssemblingMachine{T}) where T = T

struct AssemblingMachines <: AbstractDataModel 
    energy_usage::Vector{Float64}
    AssemblingMachines() = new([1.,2.,3.,4.,5.])
end

electricity_usage(x::AbstractElement) = 0.0
electricity_usage(m::AssemblingMachines, x::AssemblingMachine) = m.energy_usage[tier(x)]