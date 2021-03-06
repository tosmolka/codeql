/**
 * @name Open descriptor may not be closed
 * @description A function may return before closing a socket or file that was opened in the function. Closing resources in the same function that opened them ties the lifetime of the resource to that of the function call, making it easier to avoid and detect resource leaks.
 * @kind problem
 * @id cpp/descriptor-may-not-be-closed
 * @problem.severity warning
 * @tags efficiency
 *       security
 *       external/cwe/cwe-775
 */
import semmle.code.cpp.pointsto.PointsTo
import Negativity

predicate closeCall(FunctionCall fc, Variable v)
{
  (fc.getTarget().hasQualifiedName("close") and v.getAnAccess() = fc.getArgument(0))
  or
  exists(FunctionCall midcall, Function mid, int arg |
    fc.getArgument(arg) = v.getAnAccess() and
    fc.getTarget() = mid and
    midcall.getEnclosingFunction() = mid and
    closeCall(midcall, mid.getParameter(arg)))
}

predicate openDefinition(LocalScopeVariable v, ControlFlowNode def)
{
  exists(Expr expr |
      exprDefinition(v, def, expr) and allocateDescriptorCall(expr))
}

predicate openReaches(ControlFlowNode def, ControlFlowNode node)
{
  exists(LocalScopeVariable v |
    openDefinition(v, def) and node = def.getASuccessor())
  or
  exists(LocalScopeVariable v, ControlFlowNode mid |
    openDefinition(v, def) and
    openReaches(def, mid) and
    not(errorSuccessor(v, mid)) and
    not(closeCall(mid, v)) and
    not(assignedToFieldOrGlobal(v, mid)) and
    node = mid.getASuccessor())
}

predicate assignedToFieldOrGlobal(LocalScopeVariable v, Assignment assign)
{
  exists(Variable external |
    assign.getRValue() = v.getAnAccess() and
    assign.getLValue().(VariableAccess).getTarget() = external and
    (external instanceof Field or external instanceof GlobalVariable))
}

from LocalScopeVariable v, ControlFlowNode def, ReturnStmt ret
where openDefinition(v, def)
  and openReaches(def, ret)
  and checkedSuccess(v, ret)
  and not(ret.getExpr().getAChild*() = v.getAnAccess())
  and exists(ReturnStmt other | other.getExpr() = v.getAnAccess())
select ret,
  "Descriptor assigned to '" + v.getName().toString() + "' (line " +
  def.getLocation().getStartLine().toString() + ") may not be closed."
