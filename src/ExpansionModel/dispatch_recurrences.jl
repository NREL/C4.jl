struct StorageSiteDispatchRecurrence

    emin_first::JuMP_LessThanConstraintRef
    emax_first::JuMP_LessThanConstraintRef
    emin_last::JuMP_LessThanConstraintRef
    emax_last::JuMP_LessThanConstraintRef

    soc_last::JuMP_ExpressionRef

    function StorageSiteDispatchRecurrence(
        m::JuMP.Model,
        prev_recurrence::Union{StorageSiteDispatchRecurrence,Nothing},
        build::StorageSiteBuild, dispatch::StorageSiteDispatch, repetitions::Int)

        energy = maxenergy(build)

        soc0_first = isnothing(prev_recurrence) ? 0 : prev_recurrence.soc_last
        soc0_last = soc0_first + (repetitions - 1) * dispatch.e_net

        emin_first = @constraint(m, 0 <= soc0_first + dispatch.e_low)
        emax_first = @constraint(m, soc0_first + dispatch.e_high <= energy)
        emin_last = @constraint(m, 0 <= soc0_last + dispatch.e_low)
        emax_last = @constraint(m, soc0_last + dispatch.e_high <= energy)

        soc_last = soc0_first + repetitions * dispatch.e_net

        new(emin_first, emax_first, emin_last, emax_last, soc_last)

    end

end

struct StorageTechDispatchRecurrence

    sites::Vector{StorageSiteDispatchRecurrence}

    function StorageTechDispatchRecurrence(
        m::JuMP.Model,
        prev_recurrence::Union{StorageTechDispatchRecurrence,Nothing},
        build::TechnologyBuild{StorageTechnology,StorageSiteBuild},
        dispatch::StorageTechDispatch, repetitions::Int
    )

        prev_recurrence_sites = isnothing(prev_recurrence) ?
            StorageSiteDispatchRecurrence[] : prev_recurrence.sites

        sites = [
            StorageSiteDispatchRecurrence(
                m, prev_siterecurrence, sitebuild, sitedispatch, repetitions)
            for (prev_siterecurrence, sitebuild, sitedispatch)
            in zip_longest(prev_recurrence_sites, build.sites, dispatch.sites)
        ]

        new(sites)

    end

end

struct RegionDispatchRecurrence

    storagetechs::Vector{StorageTechDispatchRecurrence}

    function RegionDispatchRecurrence(
        m::JuMP.Model,
        prev_recurrence::Union{RegionDispatchRecurrence,Nothing},
        build::RegionBuild, dispatch::D, repetitions::Int
    ) where D <: RegionDispatch

        prev_recurrence_storagetechs = isnothing(prev_recurrence) ?
            StorageTechDispatchRecurrence[] : prev_recurrence.storagetechs

        storagetechs = [
            StorageTechDispatchRecurrence(
                m, prev_techrecurrence, techbuild, techdispatch, repetitions)
            for (prev_techrecurrence, techbuild, techdispatch)
            in zip_longest(prev_recurrence_storagetechs, build.storagetechs, dispatch.storagetechs)
        ]

        new(storagetechs)

    end

end

struct DispatchRecurrence{D <: Dispatch}

    dispatch::D
    repetitions::Int

    regions::Vector{RegionDispatchRecurrence}

    function DispatchRecurrence(
        m::JuMP.Model, prev_recurrence::Union{DispatchRecurrence{D},Nothing},
        build::Builds, dispatch::D, repetitions::Int
    ) where D <: Dispatch

        prev_recurrence_regions = isnothing(prev_recurrence) ?
            RegionDispatchRecurrence[] : prev_recurrence.regions

        regions = [
            RegionDispatchRecurrence(
                m, prev_regionrecurrence, regionbuild, regiondispatch, repetitions)
            for (prev_regionrecurrence, regionbuild, regiondispatch)
            in zip_longest(prev_recurrence_regions, build.regions, dispatch.regions)]

        new{D}(dispatch, repetitions, regions)

    end

end

function sequence_recurrences(
    m::JuMP.Model, builds::Builds, dispatches::Vector{D}, time::TimeProxyAssignment
) where D <: Dispatch

    sequence = deduplicate(time.days)
    recurrences = Vector{DispatchRecurrence}(undef, length(sequence))

    prev_recurrence = nothing

    for (i, (p, repetitions)) in enumerate(sequence)

        recurrence = DispatchRecurrence(m, prev_recurrence, builds, dispatches[p], repetitions)

        recurrences[i]  = recurrence
        prev_recurrence = recurrence

    end

    return recurrences

end

function deduplicate(xs::Vector{Int})

    result = Pair{Int,Int}[]

    iszero(length(xs)) && return result

    x_prev = first(xs)
    repetitions = 1

    for x in xs[2:end]

        if x == x_prev
            repetitions += 1
            continue
        end

        push!(result, x_prev=>repetitions)

        x_prev = x
        repetitions = 1

    end

    push!(result, x_prev=>repetitions)

    return result

end
