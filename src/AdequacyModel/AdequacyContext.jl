struct ThermalSiteUnitCount
    units::Int
end

ThermalSiteUnitCount(site::ThermalSiteParams) =
    ThermalSiteUnitCount(site.units_existing)

struct ThermalTechUnitCount
    sites::Vector{ThermalSiteUnitCount}
end

ThermalTechUnitCount(tech::ThermalTechnology) =
    ThermalTechUnitCount([ThermalSiteUnitCount(site) for site in tech.sites])

struct ThermalRegionUnitCount
    techs::Vector{ThermalTechUnitCount}
end

ThermalRegionUnitCount(region::Region) =
    ThermalRegionUnitCount([ThermalTechUnitCount(tech) for tech in region.thermaltechs])

struct AdequacyContext
    variable_availability::Matrix{Float64} # RxT
    thermal_units::Vector{ThermalRegionUnitCount} # per region
    adequacy::AdequacyResult
end

function AdequacyContext(sys::SystemParams, adequacy::AdequacyResult)

    R, T = size(adequacy.load)
    variable_availability = zeros(Float64, R, T)

    for (r, region) in enumerate(sys.regions)
        for tech in region.variabletechs
            for site in tech.sites
                variable_availability[r,:] .+= site.capacity_existing .* site.availability
            end
        end
    end

    thermal_units = [ThermalRegionUnitCount(region) for region in sys.regions]

    return AdequacyContext(
        variable_availability, thermal_units, adequacy)

end

