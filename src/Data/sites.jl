const SiteParams = Union{
    ThermalExistingSiteParams,
    VariableExistingSiteParams,VariableCandidateSiteParams,
    StorageExistingSiteParams
}

name(site::SiteParams) = site.name
