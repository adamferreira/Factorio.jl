using Factorio
using GraphPlot, Compose
using Graphs, MetaGraphsNext

Factorio.get("assembling-machine-1", Recipe)

fuels = filter(row -> row.type == "fuel", Factorio.data(Item))

for f in eachrow(fuels)
    @show f.name
end