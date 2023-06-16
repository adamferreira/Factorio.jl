using Factorio
using GraphPlot, Compose
using Graphs, MetaGraphsNext

Factorio.get("assembling-machine-1", Recipe)

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