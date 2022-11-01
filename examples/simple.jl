using Factorio
using GraphPlot, Compose
using Graphs, MetaGraphsNext

function test()
    @show sizeof(m)
    @show typeof(a)
    @show sizeof(a)
    @show consumption(Electricity, a)
    @show consumption(Fuel, a)
    @show tier(a)
    @show typeof(a)
end

g = Factorio.recipes()
@show typeof(g)
@show typeof(g.graph)
@show nv(g)
@show ne(g)

function print_recipes(items...)
    println("Ingredients : ", join(items, ' '))
    println("Consumes Any : ", Factorio.consumes_any(items...) |> Factorio.labels)
    println("Consumes All : ", Factorio.consumes_all(items...) |> Factorio.labels)
    println("Consumes Only : ", Factorio.consumes_only(items...) |> Factorio.labels)
end

f = Factorio.consumes_all("iron-plate", "copper-cable") |> Factorio.with_ingredients |> Factorio.related_graph
Compose.draw(SVG("factorio.svg", 100cm, 100cm), Factorio.rplot(f))
#Graphs.savegraph("factorio.dot", f, MetaGraphsNext.DOTFormat())
#@show Graphs.simplecycles(f)

f1 = consumes_all("iron-plate", "copper-cable") |> Factorio.with_ingredients |> Factorio.related_graph
f2 = consumes_only("iron-gear-wheel", "iron-plate", "electronic-circuit") |> Factorio.with_ingredients |> Factorio.related_graph
Graphs.edit_distance(f1.graph, f2.graph)