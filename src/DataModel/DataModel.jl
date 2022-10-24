
abstract type AbstractElement end

abstract type AssetDataModel end
abstract type Asset end

abstract type AbstractItem <: AbstractElement end
abstract type Fluid <: AbstractItem end
abstract type Item <: AbstractItem end

abstract type Energy end
abstract type Fuel <: Energy end
abstract type Electricity <: Energy end


struct AssemblingMachine{T} <: Asset end
AssemblingMachine(x) = AssemblingMachine{x}()
tier(::AssemblingMachine{T}) where T = T

struct AssemblingMachines <: AssetDataModel 
    elec_consumptions::Vector{Float64}
    fuel_consumptions::Vector{Float64}
    AssemblingMachines() = new([1.,2.,3.,4.,5.], [0.,0.,0.,0.,0.])
end

consumption(::Type{<:Energy}, m::AssetDataModel, x::Asset) = 0.0
consumption(::Type{Electricity}, m::AssemblingMachines, x::AssemblingMachine) = m.elec_consumptions[tier(x)]