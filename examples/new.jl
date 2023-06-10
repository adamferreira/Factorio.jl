using Factorio
using GraphPlot, Compose
using Graphs, MetaGraphsNext

Factorio.get("assembling-machine-1", Recipe)

g = Factorio.default_database().recgraph
println(Graphs.nv(g))
println(Graphs.ne(g))
println(Graphs.inneighbors(g, 10))


println(Factorio.get(MetaGraphsNext.label_for(g, 10)))
println(Factorio.get(MetaGraphsNext.label_for(g, MetaGraphsNext.inneighbors(g, 10)[1])))