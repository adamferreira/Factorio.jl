
function load_items()
    d = JSON.parsefile(joinpath(DATA_DIR, "items.json"))
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
        [],
        [],
        []
    )
end