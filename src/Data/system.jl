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
region_from(iface::InterfaceParams) = iface.region_from
region_to(iface::InterfaceParams) = iface.region_to

struct RegionParams <: Region{InterfaceParams}

    name::String

    demand::Vector{Float64}

    thermaltechs_existing::Vector{ThermalExistingParams}
    thermaltechs_candidate::Vector{ThermalCandidateParams}

    variabletechs_existing::Vector{VariableExistingParams}
    variabletechs_candidate::Vector{VariableCandidateParams}

    storagetechs_existing::Vector{StorageExistingParams}
    storagetechs_candidate::Vector{StorageCandidateParams}

    export_interfaces::Vector{Int}
    import_interfaces::Vector{Int}

end

name(region::RegionParams) = region.name
demand(region::RegionParams, t::Int) = region.demand[t]

thermaltechs(region::RegionParams) = region.thermaltechs_existing
variabletechs(region::RegionParams) = region.variabletechs_existing
storagetechs(region::RegionParams) = region.storagetechs_existing

techs(region::RegionParams, ::Type{ThermalExistingParams}) =
    region.thermaltechs_existing

techs(region::RegionParams, ::Type{ThermalCandidateParams}) =
    region.thermaltechs_candidate

techs(region::RegionParams, ::Type{VariableCandidateParams}) =
    region.variabletechs_candidate

techs(region::RegionParams, ::Type{VariableExistingParams}) =
    region.variabletechs_existing

techs(region::RegionParams, ::Type{StorageExistingParams}) =
    region.storagetechs_existing

techs(region::RegionParams, ::Type{StorageCandidateParams}) =
    region.storagetechs_candidate

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
    techtype::Type{<:TechnologyParams},
    regionname::String,
    techname::String
)

    _, region = getbyname(system.regions, regionname)
    return last(getbyname(techs(region, techtype), techname))

end

function regiontechset(system::SystemParams, techtype::Type{<:TechnologyParams})
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
    techtype::Type{<:TechnologyParams},
    regionname::String,
    techname::String,
    sitename::String
)

    _, region = getbyname(system.regions, regionname)
    _, tech = getbyname(techs(region, techtype), techname)
    return last(getbyname(tech.sites, sitename))

end

total_demand(sys::SystemParams) =
    sum(sum(region.demand) for region in sys.regions)

function regiontechsiteset(system::SystemParams, techtype::Type{<:TechnologyParams})
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
                    length(region.thermaltechs_existing), "\t",
                    length(region.variabletechs_existing), "\t",
                    length(region.storagetechs_existing), "\t",
                    join(sort(neighbours), ", "))

    end

    length(sys.regions) > 0 && println(io, "\nRegions\n")

    for region in sys.regions

        has_thermal = length(region.thermaltechs_existing) > 0
        has_variable = length(region.variabletechs_existing) > 0
        has_storage = length(region.storagetechs_existing) > 0

        println(io, region.name, " (Peak Load: ", maximum(region.demand) * powerunits_MW, " MW)")

        has_thermal || has_variable || has_storage ||
            println(io, "\t(No resources)")

        for thermaltech in region.thermaltechs_existing
            println(io, "\t", thermaltech.name, ":")
            for site in thermaltech.sites
                println(io, "\t\t", site.name, ": ",
                        site.units, " x ", site.unit_size * powerunits_MW, " MW")
            end
        end

        for variabletech in region.variabletechs_existing
            capacity = nameplatecapacity(variabletech)
            iszero(capacity) && continue
            println(io, "\t", variabletech.name, ": ", capacity * powerunits_MW, " MW")
        end

        for storagetech in region.storagetechs_existing
            power, energy = maxpower(storagetech), maxenergy(storagetech)
            iszero(power) && continue
            println(io, "\t", storagetech.name, ": ",
                    power * powerunits_MW, " MW (", energy / power, " h)")
        end

    end

    length(sys.interfaces) > 0 && println(io, "\nInterfaces\n")

    for interface in sys.interfaces
        println(io, interface.name, ": ", interface.capacity_existing * powerunits_MW, " MW")
    end

end
