abstract type ResourceSiteBuild end

struct ThermalSiteBuild <: ResourceSiteBuild

    params::ThermalSite
    units_new::JuMP.VariableRef

    function ThermalSiteBuild(
        m::JuMP.Model, siteparams::ThermalSite,
        techparams::ThermalTechnology, regionparams::Region
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")
        units_new = @variable(m, integer=true, lower_bound=0, upper_bound=siteparams.units_new_max)
        JuMP.set_name(units_new, "thermal_new_units[$fullname]")
        new(siteparams, units_new)

    end

end

sitebuildtype(::Type{ThermalTechnology}) = ThermalSiteBuild

struct VariableSiteBuild <: ResourceSiteBuild

    params::VariableSite
    capacity_new::JuMP.VariableRef

    function VariableSiteBuild(
        m::JuMP.Model, siteparams::VariableSite,
        techparams::VariableTechnology, regionparams::Region
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")
        capacity_new = @variable(m, lower_bound=0, upper_bound=siteparams.capacity_new_max)
        JuMP.set_name(capacity_new, "variable_new_capacity[$fullname]")
        new(siteparams, capacity_new)

    end

end

sitebuildtype(::Type{VariableTechnology}) = VariableSiteBuild

struct StorageSiteBuild <: ResourceSiteBuild

    params::StorageSite
    power_new::JuMP.VariableRef
    energy_new::JuMP.VariableRef

    function StorageSiteBuild(
        m::JuMP.Model, siteparams::StorageSite,
        techparams::StorageTechnology, regionparams::Region
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")

        power_new = @variable(m, lower_bound=0, upper_bound=siteparams.power_new_max)
        JuMP.set_name(power_new, "storage_new_power[$fullname]")

        energy_new = @variable(m, lower_bound=0, upper_bound=siteparams.energy_new_max)
        JuMP.set_name(energy_new, "storage_new_energy[$fullname]")

        new(siteparams, power_new, energy_new)

    end

end

sitebuildtype(::Type{StorageTechnology}) = StorageSiteBuild

struct TechnologyBuild{T<:ResourceTechnology,B<:ResourceSiteBuild}

    params::T
    sites::Vector{B}

    function TechnologyBuild(
        m::JuMP.Model, techparams::T, regionparams::Region
    ) where T <: ResourceTechnology

        B = sitebuildtype(T)

        sites = [B(m, siteparams, techparams, regionparams)
                 for siteparams in techparams.sites]

        new{T,B}(techparams, sites)

    end

end

struct RegionBuild

    params::Region

    thermaltechs::Vector{TechnologyBuild{ThermalTechnology}}
    variabletechs::Vector{TechnologyBuild{VariableTechnology}}
    storagetechs::Vector{TechnologyBuild{StorageTechnology}}

    function RegionBuild(m::JuMP.Model, regionparams::Region)

        thermaltechs = [TechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.thermaltechs]

        variabletechs = [TechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.variabletechs]

        storagetechs = [TechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.storagetechs]

        new(regionparams, thermaltechs, variabletechs, storagetechs)

    end

end

struct InterfaceBuild

    params::Interface
    capacity_new::JuMP.VariableRef

    function InterfaceBuild(m::JuMP.Model, params::Interface)

        capacity_new = @variable(m, lower_bound=0,
                                    upper_bound=params.capacity_new_max)
        JuMP.set_name(capacity_new, "iface_capacity_new[$(params.name)]")

        return new(params, capacity_new)

    end

end
