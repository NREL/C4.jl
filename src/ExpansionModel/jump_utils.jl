const JuMP_ExpressionRef = JuMP.GenericAffExpr{Float64,JuMP.VariableRef}

const JuMP_ConstrRef{T} = JuMP.ConstraintRef{JuMP.Model,MOI.ConstraintIndex{
     MOI.ScalarAffineFunction{Float64},T},JuMP.ScalarShape}

const JuMP_LessThanConstraintRef    = JuMP_ConstrRef{MOI.LessThan{Float64}}
const JuMP_GreaterThanConstraintRef = JuMP_ConstrRef{MOI.GreaterThan{Float64}}
const JuMP_EqualToConstraintRef     = JuMP_ConstrRef{MOI.EqualTo{Float64}}

function varnames!(vars::Array{JuMP.VariableRef},
                   basename::String, labels::AbstractVector...)

    dims = size(vars)
    dims == length.(labels) || error("Provided labels do not match array size")

    for idxs in Iterators.product(Base.OneTo.(dims)...)
        idx_labels = getindex.(labels, idxs)
        JuMP.set_name(vars[idxs...], basename * "[" * join(idx_labels, ",") * "]")
    end

end
