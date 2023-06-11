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

print(sort(Factorio.data(Recipe), :tier, rev=true))
print(sort(Factorio.data(Item), :tier, rev=true))

items = sort(filter(row -> row.tier >= 0 && (row.type == "item" || row.type == "fluid" || row.type == "fuel"), Factorio.data(Item)), :tier, rev=true)

# Graphs.dijkstra_shortest_paths(g, 268).dists