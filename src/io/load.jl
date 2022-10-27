
function load_items()
    d = JSON.parsefile(joinpath(DATA_DIR, "item.json"))
    for (name, desc) in d

        println(name)
    end
end


function load_assembling_machines()::AssemblingMachines
    d = JSON.parsefile(joinpath(DATA_DIR, "assembling-machine.json"))
    names = Vector()
    e_cons = Vector()
    for machine in d
        push!(names, machine.first)
    end
    return AssemblingMachines(
        names,
        [1.,1.,1.],
        [2.,2.,2.],
        [3.,3.,3.]
    )
end


function load_default()::DefaultFactorioDataBase
    # Empty (default) database
    database = DefaultFactorioDataBase()
    # Load all item names
    items_mapping = Dict()
    for (name, desc) in JSON.parsefile(joinpath(DATA_DIR, "item.json"))
        new_name = ""#replace()
        items_mapping[name] = (replace(name, r"\+(\p{Lu})" => lowercase), nothing, nothing, nothing)
    end
    println(length(items_mapping))
    return database
end