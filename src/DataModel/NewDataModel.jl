using DataFrames
using JSON

DATA_DIR = joinpath(@__DIR__, "..", "..", "data")

function load_items()
    d = JSON.parsefile(joinpath(DATA_DIR, "item.json"))
    for (name, desc) in d

        println(name)
    end
end

function load_items2()
    d = JSON.parsefile(joinpath(DATA_DIR, "recipe.json"))
    df = DataFrame()
    map(x -> append!(df, d[x]), [name for (name, desc) in d])
    return df
end

#load_items()
print(load_items2())