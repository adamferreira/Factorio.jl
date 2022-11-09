
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
    # Empty recipe graph
    g = RecipeGraph()
    # Empty (default) database
    database = DefaultFactorioDataBase(g)
   
    # All items and ressource are recipes with 0s craftime and produce one unit of themselves
    items_to_recipes = Dict()
    resources_to_recipes = Dict()
    items = JSON.parsefile(joinpath(DATA_DIR, "item.json"))
    ressources = JSON.parsefile(joinpath(DATA_DIR, "resource.json"))
    fluids = JSON.parsefile(joinpath(DATA_DIR, "fluid.json"))


    for (name, desc) in ressources
        
    end

    # Add names as item recipe nodes
    for name in Set(vcat(collect(keys(items)), collect(keys(ressources)), collect(keys(fluids))))
        add_recipe_node!(g, RecipeNode(name, 0.0, ITEM))
    end
    # Flag fluids and ressources and ressources
    for name in Set(vcat(collect(keys(ressources)), collect(keys(fluids))))
        MetaGraphsNext.set_data!(g, name, RecipeNode(name, 0.0, RESSOURCE))
    end

    # Register recipes
    for (name, desc) in JSON.parsefile(joinpath(DATA_DIR, "recipe.json"))
        # Register the recipe as a node
        recipe_name = "recipe-"*name
        recipe = RecipeNode(recipe_name, convert(Float64, desc["energy"]), RECIPE)
        add_recipe_node!(g, recipe)
        # Add ingredients and products as edges of the graph
        for ingredient in desc["ingredients"]
            add_recipe_edge!(g, ingredient["name"], recipe_name, RecipeEdge(ingredient["amount"], 1.))
        end
        # Add ingredients and products as edges of the graph
        for product in desc["products"]
            add_recipe_edge!(g, recipe_name, product["name"], RecipeEdge(product["amount"], product["probability"]))
        end
    end
    # Some recipe node are not attached to any recipe (i.e steam, etc)
    # We remove those nodes from the graph
    to_remove = [v for v in Graphs.vertices(g) if Graphs.degree(g,v) == 0]
    # Also remove Barrel recipes as they introduces cycles
    # Water produces water-barel that produces water
    # This hides the fact that 'water' is a ressource (no inbound edge)
    to_remove = vcat(to_remove, [v for v in Graphs.vertices(g) if occursin("-barrel", MetaGraphsNext.label_for(g,v))])
    Graphs.rem_vertices!(g, to_remove)
    
    return database
end