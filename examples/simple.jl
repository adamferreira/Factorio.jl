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

f = Factorio.consumes_only("iron-gear-wheel", "iron-plate", "electronic-circuit") |> Factorio.with_ingredients |> Factorio.related_graph
Compose.draw(SVG("factorio.svg", 100cm, 100cm), Factorio.rplot(f))
#Graphs.savegraph("factorio.dot", f, MetaGraphsNext.DOTFormat())

#print_recipes("iron-gear-wheel", "iron-plate")
print_recipes("iron-gear-wheel", "iron-plate", "electronic-circuit")
@show Graphs.simplecycles(f)

Graphs.edit_distance(f.graph, f.graph)