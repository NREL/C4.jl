struct RegionBuild

    params::Region

    function RegionBuild(m::JuMP.Model, params::Region)
        new(params)
    end

end

struct InterfaceBuild

    params::Interface

    function InterfaceBuild(m::JuMP.Model, params::Interface)
        new(params)
    end

end
