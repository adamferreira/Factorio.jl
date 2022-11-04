
abstract type AbstractElement end
abstract type AbstractDataModel end

abstract type AbstractItem <: AbstractElement end
abstract type Fluid <: AbstractItem end
abstract type Item <: AbstractItem end

abstract type Energy end
abstract type Fuel <: Energy end
abstract type Electricity <: Energy end


# Type Logic
#EnergyConsumer = Union{Asset, Item}


# DataModel Holding Everything Needed
abstract type FactorioDataBase end

const Tier = UInt16
# An Asset is an object that can be defined by different tiers and can be placed down in the game
# Example: AssemblingMachine1, AssemblingMachine2, etc...
# Or: Stone Furnace, Electric Furnace
# The tier of an asset can be retrived from the template value of the 'Asset' struct
abstract type Asset{T} <: AbstractElement end
# An AssetDataModel is an AbstractDataModel that stores tiers information with vectors
# Each indexes of the vectors represents a Tier
#abstract type AssetDataModel <: AbstractDataModel end
Asset(x) = Asset{x}()
tier(::Asset{T}) where T = T

# Macro to easily define new assets
macro asset(AssetType)
    return quote
        struct $AssetType{T} <: Asset{T}
            database::FactorioDataBase
        end
        #$AssetType(x) = $AssetType{x}()
        $AssetType(x,m) = $AssetType{x}(m)
    end |> esc
end

# --------------
# Data Models
# --------------
database(x::Asset) = x.database # defaultdb
# Every DataModel should have the files ::names
name(x::Asset) = database(x).names[tier(x)]

# DataModel for AssemblingMachines 
@asset AssemblingMachine
struct AssemblingMachines <: AbstractDataModel # -> Object Model ?
    # Mapping names to asset types
    #mapping::Dict{String, AssemblingMachine}
    # Names
    names::Vector{String}
    # Electric consumption
    elec_consumptions::Vector{Float64}
    # Fuel consumption
    fuel_consumptions::Vector{Float64}
    # Pollution Generation
    pollution::Vector{Float64}
end


# DataModel Holding Everything Needed
struct DefaultFactorioDataBase <: FactorioDataBase
    recgraph
end

# Define mapping between elements (asset, items, ...) and their data model
@inline model(m::DefaultFactorioDataBase, x::AssemblingMachine)::AbstractDataModel = m.assembling_machines


# Default consumption for any DataModel and Any Asset
consumption(::Type{<:Energy}, x::Asset) = 0.0

consumption(::Type{Electricity}, x::AssemblingMachine) =  model(database(x), x).elec_consumptions[tier(x)]
consumption(::Type{Fuel}, x::AssemblingMachine) = model(database(x), x).fuel_consumptions[tier(x)]


####### ----- New implem
"""
    A Factorio element is a UniqueElement.
    It has a unique identifider (Interger) that encodes:
    - The index of its model
    - Its index in the global DataModel Array (given the type)
"""
const ElementHash = UInt16
struct UniqueElement{T<:Unsigned}
    # TODO: have model_id in UInt16 and uid as UInt16 ?
    uid::T
end

"""
    Concatenates the two hashes `a` and `b` into `T`.
    Let's sya T = UInt8 and:
    - a = 10 = 00001010
    - b = 12 = 00001100
    This function returns the new hash 10100000 | 00001100 = 10101100
"""
function combine(a::T, b::T) where {T<:Unsigned}
    return (a << (4*sizeof(T))) | (b & mask(T))
end

UniqueElement(mid::T, id::T) where {T<:Unsigned} = UniqueElement{T}(combine(mid,id))
@inline uid(x::UniqueElement{T}) where {T<:Unsigned} = x.uid

"""
    The mask for an Integer type `T` stored in n bits is
    n/2 `0` bits followed by n/2 `1` bits
    The mask for UInt8 is `00001111`
"""
@inline mask(::Type{T}) where {T<:Unsigned} = T((1 << (4*sizeof(T))) - 1)
"""
    Get the last |`T`|/2 bits of the uid
"""
@inline index(x::UniqueElement{T}) where {T<:Unsigned} = uid(x) & mask(T)
"""
    Get the first |`T`|/2 bits of the uid
"""
@inline model(x::UniqueElement{T}) where {T<:Unsigned} = (uid(x) << (4*sizeof(T))) & mask(T)


MODELS = [
    :Recipe
]

for p in enumerate(MODELS)
    @eval const $(p[2]){T} = UniqueElement{p[1],T} where {T<:Unsigned}
end

a = UniqueElement(UInt8(10), UInt8(12))
@show bitstring(uid(a))
@show bitstring(model(a))
@show bitstring(index(a))