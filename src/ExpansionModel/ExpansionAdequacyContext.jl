struct ThermalSiteUnitCount
    units::Int
end

ThermalSiteUnitCount(site::ThermalSiteParams) =
    ThermalSiteUnitCount(site.units_existing)

ThermalSiteUnitCount(site::ThermalSiteExpansion) =
    ThermalSiteUnitCount(site.params.units_existing + round(Int, value(site.units_new)))

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

struct ExpansionAdequacyContext
    nonthermal_availability::Matrix{Float64} # RxT
    thermal_units::Vector{ThermalRegionUnitCount} # per region
    adequacy::AdequacyResult
end

function ExpansionAdequacyContext(
    cem::ExpansionProblem, adequacy::AdequacyResult
)

    R, T = size(adequacy.shortfalls.regions.load)
    daylength = cem.reliabilitydispatch.time.daylength

    nonthermal_availability = zeros(R, T)

    for (r, region) in enumerate(cem.builds.regions)
        for tech in region.variabletechs
            for site in tech.sites
                nameplate = value(site.capacity_new) + site.params.capacity_existing
                nonthermal_availability[r,:] .+= nameplate .* site.params.availability
            end
        end
    end

    for (p, rep_idx) in enumerate(cem.reliabilitydispatch.time.days)

        t_start = (p - 1) * daylength + 1
        t_end = p * daylength

        dispatch = cem.reliabilitydispatch.dispatches[rep_idx]

        for (r, region) in enumerate(dispatch.regions)
            for stor in region.storagetechs
                nonthermal_availability[r, t_start:t_end] .+= value.(stor.dispatch)
            end
        end

        nonthermal_availability[:, t_start:t_end] .+= value.(dispatch.netimports)

    end

    thermal_units = [ThermalRegionUnitCount(region) for region in cem.builds.regions]

    return ExpansionAdequacyContext(
        nonthermal_availability, thermal_units, adequacy)

end
