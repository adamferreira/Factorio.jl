using Factorio
using GraphPlot, Compose
using Graphs, MetaGraphsNext
using DataFrames

Factorio.get("assembling-machine-1", Recipe)

db = Factorio.default_database()
g = Factorio.default_database().recgraph
println(Graphs.nv(g))
println(Graphs.ne(g))
#println(Graphs.inneighbors(g, 10))


#println(Factorio.get(MetaGraphsNext.label_for(g, 10)))
#println(Factorio.get(MetaGraphsNext.label_for(g, MetaGraphsNext.inneighbors(g, 10)[1])))


#println([Factorio.get(MetaGraphsNext.label_for(g, MetaGraphsNext.inneighbors(g, 341)[i])) for i = 1:length(MetaGraphsNext.inneighbors(g, 341))])

#Factorio.ingredients("stack-inserter")

#a = filter(row -> row.tier == 0, Factorio.data(Item); view=true)

circuit = 1157
MetaGraphsNext.code_for(g, 1157)

#items = sort(filter(row -> row.tier >= 0 && (row.type == "item" || row.type == "fluid" || row.type == "fuel"), Factorio.data(Item)), :tier, rev=true)

G = Factorio.similarity_graph(; dist = 0.0)

#for r in Graphs.vertices(G)
#    println(Factorio.data(Recipe)[r, :].name, " -> ", [Factorio.data(Recipe)[r2, :].name for r2 in Graphs.neighbors(G, r)])
#end

groups = filter(g -> length(g) >= 2,  Graphs.connected_components(G))
for (i,g) in enumerate(groups)
    println("Group ", i, " = ", [Factorio.data(Recipe)[j, :].name for j in g])
end


machines = Factorio.data(Factorio.AssemblingMachine)
modules = Factorio.data(Factorio.Module)



#transform!(machines_extended, )

# 
"""
This creates a machine entry for each machine and each module combination that can be filled in.
Example for one machine:

Row │ name            modules                            crafting_speed  energy_usage  pollution  module_inventory_size  crafting_categories 
    │ String          Array…                             Float64         Float64       Float64    Int64                  Array…
────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
1 │ chemical-plant  ["effectivity-module"]                       1.0       147000.0       4.0                       3  ["chemistry"]
2 │ chemical-plant  ["effectivity-module-3"]                     1.0       105000.0       4.0                       3  ["chemistry"]
3 │ chemical-plant  ["effectivity-module-2"]                     1.0       126000.0       4.0                       3  ["chemistry"]
4 │ chemical-plant  ["speed-module-2"]                           1.3       336000.0       4.0                       3  ["chemistry"]
5 │ chemical-plant  ["speed-module"]                             1.2       315000.0       4.0                       3  ["chemistry"]
6 │ chemical-plant  ["productivity-module-2"]                    0.9       336000.0       4.28                      3  ["chemistry"]
7 │ chemical-plant  ["productivity-module-3"]                    0.85      378000.0       4.4                       3  ["chemistry"]
8 │ chemical-plant  ["productivity-module"]                      0.95      294000.0       4.2                       3  ["chemistry"]
9 │ chemical-plant  ["speed-module-3"]                           1.5       357000.0       4.0                       3  ["chemistry"]
10 │ chemical-plant  ["effectivity-module", "effectiv…            1.0       102900.0       4.0                       3  ["chemistry"]
11 │ chemical-plant  ["effectivity-module", "effectiv…            1.0        73500.0       4.0                       3  ["chemistry"]
12 │ chemical-plant  ["effectivity-module", "effectiv…            1.0        88200.0       4.0                       3  ["chemistry"]
13 │ chemical-plant  ["effectivity-module", "speed-mo…            1.3       235200.0       4.0                       3  ["chemistry"]
14 │ chemical-plant  ["effectivity-module", "speed-mo…            1.2       220500.0       4.0                       3  ["chemistry"]
15 │ chemical-plant  ["effectivity-module", "producti…            0.9       235200.0       4.28                      3  ["chemistry"]
16 │ chemical-plant  ["effectivity-module", "producti…            0.85      264600.0       4.4                       3  ["chemistry"]
17 │ chemical-plant  ["effectivity-module", "producti…            0.95      205800.0       4.2                       3  ["chemistry"]
18 │ chemical-plant  ["effectivity-module", "speed-mo…            1.5       249900.0       4.0                       3  ["chemistry"]
19 │ chemical-plant  ["effectivity-module-3", "effect…            1.0        73500.0       4.0                       3  ["chemistry"]
20 │ chemical-plant  ["effectivity-module-3", "effect…            1.0        52500.0       4.0                       3  ["chemistry"]
...
819 │ chemical-plant  ["speed-module-3", "speed-module…          3.375        1.03173e6    4.0                       3  ["chemistry"]
...
"""
function extended_machines()::DataFrame
    # Get machine and module data from db
    machines = Factorio.data(Factorio.AssemblingMachine)
    modules = Factorio.data(Factorio.Module)
    # Add module list columns to machines as it will be filled during the crossjoin
    machines[!, "modules"] = [String[] for i = 1:size(machines)[1]]
    # Add default productivity (1.0)
    machines[!, "productivity"] = ones(size(machines)[1])
    # remove uid colmuns for append later
    select!(machines, Not([:uid]))

    # Perform the cartesian product of a single machine (as DataFrame) with all modules combination
    # (depending on how many modules a machine can support) and their effect
    function cartesian_product(i)
        # machines[[1], :] is the ith row AS a Dataframe (and not DataFrameRow)
        single_machine = copy(machines[[i], :])
        for nbm in 1:machines[i,:].module_inventory_size
            # This will add the module in the module list
            single_machine = select(
                # Dataframe :Cols = uid, name, crafting_speed, energy_usage, pollution, module_inventory_size, crafting_categories, uid_1, name_1, consumption, speed, productivity, pollution_1
                crossjoin(single_machine, modules, makeunique = true),
                # Columns
                :name,
                # Add current module (name_1) to the module list
                [:modules, :name_1] => ((a, b) -> vcat.(a, b)) => :modules,
                # crafting_speed = crafting_speed * module_speed_bonus
                [:crafting_speed, :speed] => ((a, b) -> a .* b) => :crafting_speed,
                # energy_usage = energy_usage * module_consumption_bonus
                [:energy_usage, :consumption] => ((a, b) -> a .* b) => :energy_usage,
                # pollution = pollution * module_pollution_bonus
                [:pollution, :pollution_1] => ((a, b) -> a .* b) => :pollution,
                # productivity = productivity * module_productivity_bonus
                [:productivity, :productivity_1] => ((a, b) -> a .* b) => :productivity,
                :module_inventory_size,
                :crafting_categories
            )
        end
        return single_machine
    end

    # Perform the cartesian product of all combination of modules for each types of machines
    df = DataFrame()
    # Also add machines with no modules to the overall data
    append!(df, machines)
    for i = 1:size(machines)[1]
        append!(df, cartesian_product(i))
    end
    return df
end


"""
belt = MetaGraphsNext.code_for(g, Factorio.get("transport-belt", Item).uid)
plate = MetaGraphsNext.code_for(g, Factorio.get("iron-plate", Item).uid)
gear = MetaGraphsNext.code_for(g, Factorio.get("iron-gear-wheel", Item).uid)
circuit = MetaGraphsNext.code_for(g, Factorio.get("electronic-circuit", Item).uid)
G = g#Graphs.SimpleGraph(g.graph)
N = Graphs.nv(G)
distmx = ones(N, N) * Inf
map(v -> distmx[v,:] = Graphs.dijkstra_shortest_paths(G, v).dists, 1:N)
map(v -> distmx[:,v] = distmx[v,:], 1:N)

@show Graphs.dijkstra_shortest_paths(G, plate).dists
@show distmx[gear, gear]
@show distmx[gear, belt]
@show distmx[gear, circuit]
@show distmx[gear, plate]
"""