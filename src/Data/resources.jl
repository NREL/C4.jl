abstract type ResourceTechnology end
abstract type ResourceSite end

struct ThermalSite <: ResourceSite

    name::String

    units_existing::Int
    units_new_max::Int

    λ::Vector{Float64}
    μ::Vector{Float64}

end

struct ThermalTechnology <: ResourceTechnology

    name::String

    cost_capital::Float64 # $/MW
    cost_generation::Float64 # $/MWh

    size::Int # MW/unit

    sites::Vector{ThermalSite}

end

struct VariableSite <: ResourceSite

    name::String

    capacity_existing::Float64
    capacity_new_max::Float64

    availability::Vector{Float64}

end

struct VariableTechnology <: ResourceTechnology

    name::String

    cost_capital::Float64 # $/MW
    cost_generation::Float64 # $/MWh

    sites::Vector{VariableSite}

end

struct StorageSite <: ResourceSite

    name::String

    power_existing::Float64
    power_new_max::Float64

    energy_existing::Float64
    energy_new_max::Float64

end

struct StorageTechnology <: ResourceTechnology

    name::String

    cost_capital_power::Float64 # $/MW
    cost_capital_energy::Float64 # $/MWh

    sites::Vector{StorageSite}

end

abstract type AbstractRegion end

struct Interface{R<:AbstractRegion}

    name::String

    region_from::R
    region_to::R

    cost_capital::Float64 # $/MW

    capacity_existing::Float64 # MW
    capacity_new_max::Float64 # MW

end

struct Region <: AbstractRegion

    name::String

    demand::Vector{Float64}

    thermaltechs::Vector{ThermalTechnology}
    variabletechs::Vector{VariableTechnology}
    storagetechs::Vector{StorageTechnology}

    export_interfaces::Vector{Interface}
    import_interfaces::Vector{Interface}

end

techs(region::Region, ::Type{ThermalTechnology}) = region.thermaltechs
techs(region::Region, ::Type{VariableTechnology}) = region.variabletechs
techs(region::Region, ::Type{StorageTechnology}) = region.storagetechs

struct System

    name::String

    timesteps::StepRange{DateTime,Hour}

    regions::Vector{Region}
    interfaces::Vector{Interface{Region}}

end

get_region(system::System, regionname::String) =
    getbyname(system.regions, regionname)

regionset(system::System) = Set(r.name for r in system.regions)

function get_tech(
    system::System,
    techtype::Type{<:ResourceTechnology},
    regionname::String,
    techname::String
)

    region = getbyname(system.regions, regionname)
    return getbyname(techs(region, techtype), techname)

end

function regiontechset(system::System, techtype::Type{<:ResourceTechnology})
    result = Set{Tuple{String,String}}()
    for region in system.regions
        for tech in techs(region, techtype)
            push!(result, (region.name, tech.name))
        end
    end
    return result
end

function get_site(
    system::System,
    techtype::Type{<:ResourceTechnology},
    regionname::String,
    techname::String,
    sitename::String
)

    region = getbyname(system.regions, regionname)
    tech = getbyname(techs(region, techtype), techname)
    return getbyname(tech.sites, sitename)

end

function regiontechsiteset(system::System, techtype::Type{<:ResourceTechnology})
    result = Set{Tuple{String,String,String}}()
    for region in system.regions
        for tech in techs(region, techtype)
            for site in tech.sites
                push!(result, (region.name, tech.name, site.name))
            end
        end
    end
    return result
end

function getbyname(vals::Vector{T}, name::String) where T
    val = findfirst(x -> x.name == name, vals)
    isnothing(val) && error("Could not find entity with name $name")
    return vals[val]
end

function Base.show(io::IO, ::MIME"text/plain", sys::System)

    r = length(sys.regions)
    i = length(sys.interfaces)

    println(io, "System with $r regions connected by $i interfaces")
    println(io, "spanning ", first(sys.timesteps), " to ", last(sys.timesteps))

    println(io, "\nRegion\tThermal\tVRE\tStorage\tNeighbours")

    for region in sys.regions

        neighbours = String[]

        for i in region.import_interfaces
            push!(neighbours, i.region_from.name)
        end

        for i in region.export_interfaces
            push!(neighbours, i.region_to.name)
        end

        println(io, region.name, "\t",
                    length(region.thermaltechs), "\t",
                    length(region.variabletechs), "\t",
                    length(region.storagetechs), "\t",
                    join(sort(neighbours), ", "))

    end

    # for regionname in sort!(collect(keys(sys.regions)))

    #     region = sys.regions[regionname]

    #     has_gens = any(!iszero(gen.units_existing)
    #                    for gen in values(region.generators))

    #     has_stors = any(!iszero(stor.capacity_existing)
    #                     for stor in values(region.storages))

    #     has_gens || has_stors || continue

    #     println(io, "\n", regionname)

    #     for genname in sort!(collect(keys(region.generators)))

    #         gen = region.generators[genname]
    #         iszero(gen.units_existing) && continue

    #         println(io, "\t", genname, ": ",
    #                 gen.units_existing * maximum(gen.maxgen), " MW")

    #     end

    #     for storname in sort!(collect(keys(region.storages)))

    #         stor = region.storages[storname]
    #         iszero(stor.capacity_existing) && continue

    #         println(io, "\t", storname, ": ",
    #                 stor.capacity_existing, " MW (",
    #                 stor.energy_existing / stor.capacity_existing, " h)")

    #     end

    # end

end
