
function load_items()
    d = JSON.parsefile(joinpath(DATA_DIR, "items.json"))
end

function load_assembling_machines()
    d = JSON.parsefile(joinpath(DATA_DIR, "assembling-machine.json"))
    i = 0
    for machine in d
        #@show toto(Tier(i))
        i+=1
    end
end