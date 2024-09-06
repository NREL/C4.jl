struct InterfaceParams <: Interface

    name::String

    region_from::Int
    region_to::Int

    cost_capital::Float64 # $/MW

    capacity_existing::Float64 # MW
    capacity_new_max::Float64 # MW

end

name(iface::InterfaceParams) = iface.name
availablecapacity(iface::InterfaceParams) = iface.capacity_existing

struct RegionParams <: Region{
    ThermalParams, VariableParams,
    StorageParams, StorageSiteParams, InterfaceParams
}

    name::String

    demand::Vector{Float64}

    thermaltechs::Vector{ThermalParams}
    variabletechs::Vector{VariableParams}
    storagetechs::Vector{StorageParams}

    export_interfaces::Vector{Int}
    import_interfaces::Vector{Int}

end

name(region::RegionParams) = region.name
demand(region::RegionParams, t::Int) = region.demand[t]

techs(region::RegionParams, ::Type{<:ThermalTechnology}) = region.thermaltechs
techs(region::RegionParams, ::Type{<:VariableTechnology}) = region.variabletechs
techs(region::RegionParams, ::Type{<:StorageTechnology}) = region.storagetechs

importinginterfaces(region::RegionParams) = region.import_interfaces
exportinginterfaces(region::RegionParams) = region.export_interfaces

struct SystemParams <: System{RegionParams,InterfaceParams}

    name::String

    timesteps::StepRange{DateTime,Hour}

    regions::Vector{RegionParams}
    interfaces::Vector{InterfaceParams}

end

get_region(system::SystemParams, regionname::String) =
    last(getbyname(system.regions, regionname))

regionset(system::SystemParams) = Set(r.name for r in system.regions)

function get_tech(
    system::SystemParams,
    techtype::Type{<:Technology},
    regionname::String,
    techname::String
)

    _, region = getbyname(system.regions, regionname)
    return last(getbyname(techs(region, techtype), techname))

end

function regiontechset(system::SystemParams, techtype::Type{<:Technology})
    result = Set{Tuple{String,String}}()
    for region in system.regions
        for tech in techs(region, techtype)
            push!(result, (region.name, tech.name))
        end
    end
    return result
end

function get_site(
    system::SystemParams,
    techtype::Type{<:Technology},
    regionname::String,
    techname::String,
    sitename::String
)

    _, region = getbyname(system.regions, regionname)
    _, tech = getbyname(techs(region, techtype), techname)
    return last(getbyname(tech.sites, sitename))

end

function regiontechsiteset(system::SystemParams, techtype::Type{<:Technology})
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
    i = findfirst(x -> x.name == name, vals)
    isnothing(i) && error("Could not find entity with name $name")
    return i, vals[i]
end

function daycount(sys::SystemParams, daylength::Int)
    n_periods = length(sys.timesteps)
    n_days, remainder = divrem(n_periods, daylength)
    iszero(remainder) ||
        error("SystemParams timesteps ($(n_periods)) should be a multiple of daylength ($(daylength))")
    return n_days
end

function Base.show(io::IO, ::MIME"text/plain", sys::SystemParams)

    r = length(sys.regions)
    i = length(sys.interfaces)

    println(io, "System with $r regions connected by $i interfaces")
    println(io, "spanning ", first(sys.timesteps), " to ", last(sys.timesteps))

    length(sys.regions) > 0 && println(io, "\nSummary\n")

    println(io, "Region\tThermal\tVRE\tStorage\tNeighbours")

    for region in sys.regions

        neighbours = String[]

        for i in region.import_interfaces
            iface = sys.interfaces[i]
            push!(neighbours, sys.regions[iface.region_from].name)
        end

        for i in region.export_interfaces
            iface = sys.interfaces[i]
            push!(neighbours, sys.regions[iface.region_to].name)
        end

        println(io, region.name, "\t",
                    length(region.thermaltechs), "\t",
                    length(region.variabletechs), "\t",
                    length(region.storagetechs), "\t",
                    join(sort(neighbours), ", "))

    end

    length(sys.regions) > 0 && println(io, "\nRegions\n")

    for region in sys.regions

        has_thermal = any(tech -> nameplatecapacity(tech) > 0, region.thermaltechs)
        has_variable = any(tech -> nameplatecapacity(tech) > 0, region.variabletechs)
        has_storage = any(tech -> powerrating(tech) > 0, region.storagetechs)

        println(io, region.name, " (Peak Load: ", maximum(region.demand), " MW)")

        has_thermal || has_variable || has_storage ||
            println(io, "\t(No resources)")

        has_thermal && for thermaltech in region.thermaltechs
            n_units = num_units(thermaltech)
            iszero(n_units) && continue
            println(io, "\t", thermaltech.name, ": ",
                    n_units, " x ", thermaltech.unit_size, " MW")
        end

        has_variable && for variabletech in region.variabletechs
            capacity = nameplatecapacity(variabletech)
            iszero(capacity) && continue
            println(io, "\t", variabletech.name, ": ", capacity, " MW")
        end

        has_storage && for storagetech in region.storagetechs
            power, energy = powerrating(storagetech), energyrating(storagetech)
            iszero(power) && continue
            println(io, "\t", storagetech.name, ": ",
                    power, " MW (", energy / power, " h)")
        end

    end

    length(sys.interfaces) > 0 && println(io, "\nInterfaces\n")

    for interface in sys.interfaces
        println(io, interface.name, ": ", interface.capacity_existing, " MW")
    end

end
