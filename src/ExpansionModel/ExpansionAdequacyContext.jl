struct ExpansionAdequacyContext
    available_capacity::Matrix{Float64} # RxT
    adequacy::AdequacyResult
end

# This creates a full-chronology available capacity dataset to match the
# full-chronology LOLP/EUE data.
# CEM/PCM dispatch.available_capacity only matches this on representative days.
# On other days, the CEM/PCM results give available capacity for the
# representative day while we want the "real" day.
# We only have storage / transmission dispatch for representative days, so we
# just use that

function ExpansionAdequacyContext(
    cem::ExpansionProblem, adequacy::AdequacyResult
)

    R, T = size(adequacy.shortfalls.regions.load)
    daylength = cem.reliabilitydispatch.time.daylength

    available_capacity = zeros(R, T)

    for (r, region) in enumerate(cem.builds.regions)

        for tech in region.params.variabletechs_existing
            for site in tech.sites
                available_capacity[r, :] .+= site.capacity .* site.availability
            end
        end

        for tech in region.variabletechs
            for site in tech.sites
                available_capacity[r, :] .+= value(site.capacity_new) .* site.params.availability
            end
        end

        for tech in region.thermaltechs
            for site in tech.sites
                site_units = site.params.units_existing + value(site.units_new)
                site_capacity = site_units * tech.params.unit_size
                available_capacity[r, :] .+= site_capacity .* availability.(Ref(site.params), 1:T)
            end
        end

    end

    for (p, rep_idx) in enumerate(cem.reliabilitydispatch.time.days)

        t_start = (p - 1) * daylength + 1
        t_end = p * daylength

        dispatch = cem.reliabilitydispatch.dispatches[rep_idx]

        for (r, region) in enumerate(dispatch.regions)
            for stor in region.storagetechs
                available_capacity[r, t_start:t_end] .+= value.(stor.dispatch)
            end
        end

        available_capacity[:, t_start:t_end] .+= value.(dispatch.netimports)

    end

    return ExpansionAdequacyContext(available_capacity, adequacy)

end
