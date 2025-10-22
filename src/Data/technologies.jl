const TechnologyParams = Union{
    ThermalExistingParams, ThermalCandidateParams,
    VariableExistingParams, VariableCandidateParams,
    StorageExistingParams, StorageCandidateParams
}

name(tech::TechnologyParams) = tech.name
