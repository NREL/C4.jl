struct ThermalSiteBuild

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

struct ThermalTechnologyBuild

    params::ThermalTechnology
    sites::Vector{ThermalSiteBuild}

    function ThermalTechnologyBuild(
        m::JuMP.Model, techparams::ThermalTechnology, regionparams::Region
    )

        sites = [ThermalSiteBuild(m, siteparams, techparams, regionparams)
                 for siteparams in techparams.sites]
        new(techparams, sites)

    end

end

struct VariableSiteBuild

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

struct VariableTechnologyBuild

    params::VariableTechnology
    sites::Vector{VariableSiteBuild}

    function VariableTechnologyBuild(
        m::JuMP.Model, techparams::VariableTechnology, regionparams::Region
    )

        sites = [VariableSiteBuild(m, siteparams, techparams, regionparams)
                 for siteparams in techparams.sites]
        new(techparams, sites)

    end

end

struct RegionBuild

    params::Region

    thermaltechs::Vector{ThermalTechnologyBuild}
    variabletechs::Vector{VariableTechnologyBuild}

    function RegionBuild(m::JuMP.Model, regionparams::Region)

        thermaltechs = [ThermalTechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.thermaltechs]

        variabletechs = [VariableTechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.variabletechs]

        new(regionparams, thermaltechs, variabletechs)

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
