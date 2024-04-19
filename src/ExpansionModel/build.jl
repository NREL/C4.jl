struct RegionBuild

    params::Region

    function RegionBuild(m::JuMP.Model, params::Region)
        new(params)
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
