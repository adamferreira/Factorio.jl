using DataFrames
using JSON

DATA_DIR = joinpath(@__DIR__, "..", "..", "data")

function load_items()::DataFrame
    d = JSON.parsefile(joinpath(DATA_DIR, "item.json"))
    cols = ["name", "type", "stack_size", "fuel_value"]
    df = DataFrame([(c => []) for c in cols]...)
    for (name, desc) in d
        push!(df, [desc[c] for c in cols])
    end
    return df
end

function load_fluids()::DataFrame
    d = JSON.parsefile(joinpath(DATA_DIR, "fluid.json"))
    df = DataFrame()
    map(x -> append!(df, d[x]), [name for (name, desc) in d])
    return df
end

items = load_items()
#print(load_fluids())
#d = load_fluids()
#@show d[1, :]
fuel = filter(row -> row.fuel_value > 0, items)