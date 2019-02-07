import csharp

/**
 * Provides classes representing the control flow graph within callables.
 */
module ControlFlow {
  private import semmle.code.csharp.controlflow.BasicBlocks as BBs
  private import semmle.code.csharp.controlflow.internal.Completion
  import semmle.code.csharp.controlflow.internal.SuccessorType
  private import SuccessorTypes

  /**
   * A control flow node.
   *
   * Either a callable entry node (`EntryNode`), a callable exit node (`ExitNode`),
   * or a control flow node for a control flow element, that is, an expression or a
   * statement (`ElementNode`).
   *
   * A control flow node is a node in the control flow graph (CFG). There is a
   * many-to-one relationship between `ElementNode`s and `ControlFlowElement`s.
   * This allows control flow splitting, for example modeling the control flow
   * through `finally` blocks.
   *
   * Only nodes that can be reached from the callable entry point are included in
   * the CFG.
   */
  class Node extends TNode {
    /** Gets a textual representation of this control flow node. */
    string toString() { none() }

    /** Gets the control flow element that this node corresponds to, if any. */
    ControlFlowElement getElement() { none() }

    /** Gets the location of this control flow node. */
    Location getLocation() { result = getElement().getLocation() }

    /** Holds if this control flow node has conditional successors. */
    predicate isCondition() { exists(getASuccessorByType(any(ConditionalSuccessor e))) }

    /** Gets the basic block that this control flow node belongs to. */
    BasicBlock getBasicBlock() { result.getANode() = this }

    /**
     * Holds if this node dominates `that` node.
     *
     * That is, all paths reaching `that` node from some callable entry
     * node (`EntryNode`) must go through this node.
     *
     * Example:
     *
     * ```
     * int M(string s)
     * {
     *     if (s == null)
     *         throw new ArgumentNullException(nameof(s));
     *     return s.Length;
     * }
     * ```
     *
     * The node on line 3 dominates the node on line 5 (all paths from the
     * entry point of `M` to `return s.Length;` must go through the null check).
     *
     * This predicate is *reflexive*, so for example `if (s == null)` dominates
     * itself.
     */
    // potentially very large predicate, so must be inlined
    pragma[inline]
    predicate dominates(Node that) {
      strictlyDominates(that)
      or
      this = that
    }

    /**
     * Holds if this node strictly dominates `that` node.
     *
     * That is, all paths reaching `that` node from some callable entry
     * node (`EntryNode`) must go through this node (which must
     * be different from `that` node).
     *
     * Example:
     *
     * ```
     * int M(string s)
     * {
     *     if (s == null)
     *         throw new ArgumentNullException(nameof(s));
     *     return s.Length;
     * }
     * ```
     *
     * The node on line 3 strictly dominates the node on line 5
     * (all paths from the entry point of `M` to `return s.Length;` must go
     * through the null check).
     */
    // potentially very large predicate, so must be inlined
    pragma[inline]
    predicate strictlyDominates(Node that) {
      this.getBasicBlock().strictlyDominates(that.getBasicBlock())
      or
      exists(BasicBlock bb, int i, int j |
        bb.getNode(i) = this and
        bb.getNode(j) = that and
        i < j
      )
    }

    /**
     * Holds if this node post-dominates `that` node.
     *
     * That is, all paths reaching a callable exit node (`ExitNode`)
     * from `that` node must go through this node.
     *
     * Example:
     *
     * ```
     * int M(string s)
     * {
     *     try
     *     {
     *         return s.Length;
     *     }
     *     finally
     *     {
     *         Console.WriteLine("M");
     *     }
     * }
     * ```
     *
     * The node on line 9 post-dominates the node on line 5 (all paths to the
     * exit point of `M` from `return s.Length;` must go through the `WriteLine`
     * call).
     *
     * This predicate is *reflexive*, so for example `Console.WriteLine("M");`
     * post-dominates itself.
     */
    // potentially very large predicate, so must be inlined
    pragma[inline]
    predicate postDominates(Node that) {
      strictlyPostDominates(that)
      or
      this = that
    }

    /**
     * Holds if this node strictly post-dominates `that` node.
     *
     * That is, all paths reaching a callable exit node (`ExitNode`)
     * from `that` node must go through this node (which must be different
     * from `that` node).
     *
     * Example:
     *
     * ```
     * int M(string s)
     * {
     *     try
     *     {
     *         return s.Length;
     *     }
     *     finally
     *     {
     *          Console.WriteLine("M");
     *     }
     * }
     * ```
     *
     * The node on line 9 strictly post-dominates the node on line 5 (all
     * paths to the exit point of `M` from `return s.Length;` must go through
     * the `WriteLine` call).
     */
    // potentially very large predicate, so must be inlined
    pragma[inline]
    predicate strictlyPostDominates(Node that) {
      this.getBasicBlock().strictlyPostDominates(that.getBasicBlock())
      or
      exists(BasicBlock bb, int i, int j |
        bb.getNode(i) = this and
        bb.getNode(j) = that and
        i > j
      )
    }

    /** Gets a successor node of a given type, if any. */
    Node getASuccessorByType(SuccessorType t) { result = getASuccessorByType(this, t) }

    /** Gets an immediate successor, if any. */
    Node getASuccessor() { result = getASuccessorByType(_) }

    /** Gets an immediate predecessor node of a given flow type, if any. */
    Node getAPredecessorByType(SuccessorType t) { result.getASuccessorByType(t) = this }

    /** Gets an immediate predecessor, if any. */
    Node getAPredecessor() { result = getAPredecessorByType(_) }

    /**
     * Gets an immediate `true` successor, if any.
     *
     * An immediate `true` successor is a successor that is reached when
     * this condition evaluates to `true`.
     *
     * Example:
     *
     * ```
     * if (x < 0)
     *     x = -x;
     * ```
     *
     * The node on line 2 is an immediate `true` successor of the node
     * on line 1.
     */
    Node getATrueSuccessor() {
      result = getASuccessorByType(any(BooleanSuccessor t | t.getValue() = true))
    }

    /**
     * Gets an immediate `false` successor, if any.
     *
     * An immediate `false` successor is a successor that is reached when
     * this condition evaluates to `false`.
     *
     * Example:
     *
     * ```
     * if (!(x >= 0))
     *     x = -x;
     * ```
     *
     * The node on line 2 is an immediate `false` successor of the node
     * on line 1.
     */
    Node getAFalseSuccessor() {
      result = getASuccessorByType(any(BooleanSuccessor t | t.getValue() = false))
    }

    /**
     * Gets an immediate `null` successor, if any.
     *
     * An immediate `null` successor is a successor that is reached when
     * this expression evaluates to `null`.
     *
     * Example:
     *
     * ```
     * x?.M();
     * return;
     * ```
     *
     * The node on line 2 is an immediate `null` successor of the node
     * `x` on line 1.
     */
    deprecated Node getANullSuccessor() {
      result = getASuccessorByType(any(NullnessSuccessor t | t.isNull()))
    }

    /**
     * Gets an immediate non-`null` successor, if any.
     *
     * An immediate non-`null` successor is a successor that is reached when
     * this expressions evaluates to a non-`null` value.
     *
     * Example:
     *
     * ```
     * x?.M();
     * ```
     *
     * The node `x?.M()`, representing the call to `M`, is a non-`null` successor
     * of the node `x`.
     */
    deprecated Node getANonNullSuccessor() {
      result = getASuccessorByType(any(NullnessSuccessor t | not t.isNull()))
    }

    /** Holds if this node has more than one predecessor. */
    predicate isJoin() { strictcount(getAPredecessor()) > 1 }
  }

  /** Provides different types of control flow nodes. */
  module Nodes {
    /** A node for a callable entry point. */
    class EntryNode extends Node, TEntryNode {
      /** Gets the callable that this entry applies to. */
      Callable getCallable() { this = TEntryNode(result) }

      override BasicBlocks::EntryBlock getBasicBlock() { result = Node.super.getBasicBlock() }

      override Location getLocation() { result = getCallable().getLocation() }

      override string toString() { result = "enter " + getCallable().toString() }
    }

    /** A node for a callable exit point. */
    class ExitNode extends Node, TExitNode {
      /** Gets the callable that this exit applies to. */
      Callable getCallable() { this = TExitNode(result) }

      override BasicBlocks::ExitBlock getBasicBlock() { result = Node.super.getBasicBlock() }

      override Location getLocation() { result = getCallable().getLocation() }

      override string toString() { result = "exit " + getCallable().toString() }
    }

    /**
     * A node for a control flow element, that is, an expression or a statement.
     *
     * Each control flow element maps to zero or more `ElementNode`s: zero when
     * the element is in unreachable (dead) code, and multiple when there are
     * different splits for the element.
     */
    class ElementNode extends Node, TElementNode {
      private Splits splits;

      private ControlFlowElement cfe;

      ElementNode() { this = TElementNode(cfe, splits) }

      override ControlFlowElement getElement() { result = cfe }

      override string toString() {
        result = "[" + this.getSplitsString() + "] " + cfe.toString()
        or
        not exists(this.getSplitsString()) and result = cfe.toString()
      }

      /** Gets a comma-separated list of strings for each split in this node, if any. */
      string getSplitsString() {
        result = splits.toString() and
        result != ""
      }

      /** Gets a split for this control flow node, if any. */
      Split getASplit() { result = splits.getASplit() }
    }

    class Split = SplitImpl;

    class FinallySplit = FinallySplitting::FinallySplitImpl;

    class ExceptionHandlerSplit = ExceptionHandlerSplitting::ExceptionHandlerSplitImpl;

    class BooleanSplit = BooleanSplitting::BooleanSplitImpl;
  }

  class BasicBlock = BBs::BasicBlock;

  /** Provides different types of basic blocks. */
  module BasicBlocks {
    class EntryBlock = BBs::EntryBasicBlock;

    class ExitBlock = BBs::ExitBasicBlock;

    class JoinBlock = BBs::JoinBlock;

    class JoinBlockPredecessor = BBs::JoinBlockPredecessor;

    class ConditionBlock = BBs::ConditionBlock;
  }

  /**
   * INTERNAL: Do not use.
   */
  module Internal {
    import semmle.code.csharp.controlflow.internal.Splitting

    /**
     * Provides auxiliary classes and predicates used to construct the basic successor
     * relation on control flow elements.
     *
     * The implementation is centered around the concept of a _completion_, which
     * models how the execution of a statement or expression terminates.
     * Completions are represented as an algebraic data type `Completion` defined in
     * `Completion.qll`.
     *
     * The CFG is built by structural recursion over the AST. To achieve this the
     * CFG edges related to a given AST node, `n`, are divided into three categories:
     *
     *   1. The in-going edge that points to the first CFG node to execute when
     *      `n` is going to be executed.
     *   2. The out-going edges for control flow leaving `n` that are going to some
     *      other node in the surrounding context of `n`.
     *   3. The edges that have both of their end-points entirely within the AST
     *      node and its children.
     *
     * The edges in (1) and (2) are inherently non-local and are therefore
     * initially calculated as half-edges, that is, the single node, `k`, of the
     * edge contained within `n`, by the predicates `k = first(n)` and `k = last(n, _)`,
     * respectively. The edges in (3) can then be enumerated directly by the predicate
     * `succ` by calling `first` and `last` recursively on the children of `n` and
     * connecting the end-points. This yields the entire CFG, since all edges are in
     * (3) for _some_ AST node.
     *
     * The second parameter of `last` is the completion, which is necessary to distinguish
     * the out-going edges from `n`. Note that the completion changes as the calculation of
     * `last` proceeds outward through the AST; for example, a `BreakCompletion` is
     * caught up by its surrounding loop and turned into a `NormalCompletion`, and a
     * `NormalCompletion` proceeds outward through the end of a `finally` block and is
     * turned into whatever completion was caught by the `finally`.
     *
     * An important goal of the CFG is to get the order of side-effects correct.
     * Most expressions can have side-effects and must therefore be modeled in the
     * CFG in AST post-order. For example, a `MethodCall` evaluates its arguments
     * before the call. Most statements do not have side-effects, but merely affect
     * the control flow and some could therefore be excluded from the CFG. However,
     * as a design choice, all statements are included in the CFG and generally
     * serve as their own entry-points, thus executing in some version of AST
     * pre-order.
     */
    module Successor {
      private import semmle.code.csharp.ExprOrStmtParent
      private import semmle.code.csharp.controlflow.internal.NonReturning

      /**
       * A control flow element where the children are evaluated following a
       * standard left-to-right evaluation. The actual evaluation order is
       * determined by the predicate `getChildElement()`.
       */
      abstract private class StandardElement extends ControlFlowElement {
        /** Gets the first child element of this element. */
        ControlFlowElement getFirstChildElement() { result = this.getChildElement(0) }

        /** Holds if this element has no children. */
        predicate isLeafElement() { not exists(this.getFirstChildElement()) }

        /** Gets the last child element of this element. */
        ControlFlowElement getLastChildElement() {
          exists(int last |
            last = max(int i | exists(this.getChildElement(i))) and
            result = this.getChildElement(last)
          )
        }

        /** Gets the `i`th child element, which is not the last element. */
        ControlFlowElement getNonLastChildElement(int i) {
          result = this.getChildElement(i) and
          not result = this.getLastChildElement()
        }

        /** Gets the `i`th child element, in order of evaluation, starting from 0. */
        abstract ControlFlowElement getChildElement(int i);
      }

      private class StandardStmt extends StandardElement, Stmt {
        StandardStmt() {
          // The following statements need special treatment
          not this instanceof IfStmt and
          not this instanceof SwitchStmt and
          not this instanceof ConstCase and
          not this instanceof TypeCase and
          not this instanceof LoopStmt and
          not this instanceof TryStmt and
          not this instanceof SpecificCatchClause and
          not this instanceof JumpStmt
        }

        override ControlFlowElement getChildElement(int i) {
          not this instanceof FixedStmt and
          not this instanceof UsingStmt and
          result = this.getChild(i)
          or
          this = any(GeneralCatchClause gcc | i = 0 and result = gcc.getBlock())
          or
          this = any(FixedStmt fs |
              result = fs.getVariableDeclExpr(i)
              or
              result = fs.getBody() and
              i = max(int j | exists(fs.getVariableDeclExpr(j))) + 1
            )
          or
          this = any(UsingStmt us |
              if exists(us.getExpr())
              then (
                result = us.getExpr() and
                i = 0
                or
                result = us.getBody() and
                i = 1
              ) else (
                result = us.getVariableDeclExpr(i)
                or
                result = us.getBody() and
                i = max(int j | exists(us.getVariableDeclExpr(j))) + 1
              )
            )
        }
      }

      /**
       * An assignment operation that has an expanded version. We use the expanded
       * version in the control flow graph in order to get better data flow / taint
       * tracking.
       */
      private class AssignOperationWithExpandedAssignment extends AssignOperation {
        AssignOperationWithExpandedAssignment() { this.hasExpandedAssignment() }
      }

      /** A conditionally qualified expression. */
      private class ConditionalQualifiableExpr extends QualifiableExpr {
        ConditionalQualifiableExpr() { this.isConditional() }
      }

      private class StandardExpr extends StandardElement, Expr {
        StandardExpr() {
          // The following expressions need special treatment
          not this instanceof LogicalNotExpr and
          not this instanceof LogicalAndExpr and
          not this instanceof LogicalOrExpr and
          not this instanceof NullCoalescingExpr and
          not this instanceof ConditionalExpr and
          not this instanceof AssignOperationWithExpandedAssignment and
          not this instanceof ConditionalQualifiableExpr and
          not this instanceof ThrowExpr and
          not this instanceof TypeAccess and
          not this instanceof ObjectCreation and
          not this instanceof ArrayCreation
        }

        override ControlFlowElement getChildElement(int i) {
          not this instanceof TypeofExpr and
          not this instanceof DefaultValueExpr and
          not this instanceof SizeofExpr and
          not this instanceof NameOfExpr and
          not this instanceof QualifiableExpr and
          not this instanceof Assignment and
          not this instanceof IsExpr and
          not this instanceof AsExpr and
          not this instanceof CastExpr and
          not this instanceof AnonymousFunctionExpr and
          not this instanceof DelegateCall and
          not this instanceof @unknown_expr and
          result = this.getChild(i)
          or
          this = any(ExtensionMethodCall emc | result = emc.getArgument(i))
          or
          result = getQualifiableExprChild(this, i)
          or
          result = getAssignmentChild(this, i)
          or
          result = getIsExprChild(this, i)
          or
          result = getAsExprChild(this, i)
          or
          result = getCastExprChild(this, i)
          or
          result = this.(DelegateCall).getChild(i - 1)
          or
          result = getUnknownExprChild(this, i)
        }
      }

      private ControlFlowElement getQualifiableExprChild(QualifiableExpr qe, int i) {
        i >= 0 and
        not qe instanceof ExtensionMethodCall and
        not qe.isConditional() and
        if exists(Expr q | q = qe.getQualifier() | not q instanceof TypeAccess)
        then result = qe.getChild(i - 1)
        else result = qe.getChild(i)
      }

      private ControlFlowElement getAssignmentChild(Assignment a, int i) {
        // The left-hand side of an assignment is evaluated before the right-hand side
        i = 0 and result = a.getLValue()
        or
        i = 1 and result = a.getRValue()
      }

      private ControlFlowElement getIsExprChild(IsExpr ie, int i) {
        // The type access at index 1 is not evaluated at run-time
        i = 0 and result = ie.getExpr()
        or
        i = 1 and result = ie.(IsPatternExpr).getVariableDeclExpr()
        or
        i = 1 and result = ie.(IsConstantExpr).getConstant()
      }

      private ControlFlowElement getAsExprChild(AsExpr ae, int i) {
        // The type access at index 1 is not evaluated at run-time
        i = 0 and result = ae.getExpr()
      }

      private ControlFlowElement getUnknownExprChild(@unknown_expr e, int i) {
        exists(int c | result = e.(Expr).getChild(c) |
          c = rank[i + 1](int j | exists(e.(Expr).getChild(j)))
        )
      }

      private ControlFlowElement getCastExprChild(CastExpr ce, int i) {
        // The type access at index 1 is not evaluated at run-time
        i = 0 and result = ce.getExpr()
      }

      /**
       * Gets the first element executed within control flow element `cfe`.
       */
      ControlFlowElement first(ControlFlowElement cfe) {
        // Pre-order: element itself
        cfe instanceof PreOrderElement and
        result = cfe
        or
        // Post-order: first element of first child (or self, if no children)
        cfe = any(PostOrderElement poe |
            result = first(poe.getFirstChild())
            or
            not exists(poe.getFirstChild()) and
            result = poe
          )
        or
        cfe = any(AssignOperationWithExpandedAssignment a |
            result = first(a.getExpandedAssignment())
          )
        or
        cfe = any(ConditionalQualifiableExpr cqe | result = first(cqe.getChildExpr(-1)))
        or
        cfe = any(ArrayCreation ac |
            if ac.isImplicitlySized()
            then
              // No length argument: element itself
              result = ac
            else
              // First element of first length argument
              result = first(ac.getLengthArgument(0))
          )
        or
        cfe = any(ForeachStmt fs |
            // Unlike most other statements, `foreach` statements are not modelled in
            // pre-order, because we use the `foreach` node itself to represent the
            // emptiness test that determines whether to execute the loop body
            result = first(fs.getIterableExpr())
          )
      }

      private class PreOrderElement extends ControlFlowElement {
        PreOrderElement() {
          this instanceof StandardStmt
          or
          this instanceof IfStmt
          or
          this instanceof SwitchStmt
          or
          this instanceof ConstCase
          or
          this instanceof TypeCase
          or
          this instanceof TryStmt
          or
          this instanceof SpecificCatchClause
          or
          this instanceof LoopStmt and not this instanceof ForeachStmt
          or
          this instanceof LogicalNotExpr
          or
          this instanceof LogicalAndExpr
          or
          this instanceof LogicalOrExpr
          or
          this instanceof NullCoalescingExpr
          or
          this instanceof ConditionalExpr
        }
      }

      private class PostOrderElement extends ControlFlowElement {
        PostOrderElement() {
          this instanceof StandardExpr or
          this instanceof JumpStmt or
          this instanceof ThrowExpr or
          this instanceof ObjectCreation
        }

        ControlFlowElement getFirstChild() {
          result = this.(StandardExpr).getFirstChildElement() or
          result = this.(JumpStmt).getChild(0) or
          result = this.(ThrowExpr).getExpr() or
          result = this.(ObjectCreation).getArgument(0)
        }
      }

      /**
       * Gets a potential last element executed within control flow element `cfe`,
       * as well as its completion.
       *
       * For example, if `cfe` is `A || B` then both `A` and `B` are potential
       * last elements with Boolean completions.
       */
      ControlFlowElement last(ControlFlowElement cfe, Completion c) {
        // Pre-order: last element of last child (or self, if no children)
        cfe = any(StandardStmt ss |
            result = last(ss.getLastChildElement(), c)
            or
            ss.isLeafElement() and
            result = ss and
            c.isValidFor(result)
          )
        or
        // Post-order: element itself
        cfe instanceof StandardExpr and
        not cfe instanceof NonReturningCall and
        result = cfe and
        c.isValidFor(result)
        or
        // Pre/post order: a child exits abnormally
        result = last(cfe.(StandardElement).getChildElement(_), c) and
        not c instanceof NormalCompletion
        or
        cfe = any(LogicalNotExpr lne |
            // Operand exits with a Boolean completion
            exists(BooleanCompletion operandCompletion |
              result = lastLogicalNotExprOperand(lne, operandCompletion)
            |
              c = any(BooleanCompletion bc |
                  bc.getOuterValue() = operandCompletion.getOuterValue().booleanNot() and
                  bc.getInnerValue() = operandCompletion.getInnerValue()
                )
            )
            or
            // Operand exits with a non-Boolean completion
            result = lastLogicalNotExprOperand(lne, c) and
            not c instanceof BooleanCompletion
          )
        or
        cfe = any(LogicalAndExpr lae |
            // Left operand exits with a false completion
            result = lastLogicalAndExprLeftOperand(lae, c) and
            c instanceof FalseCompletion
            or
            // Left operand exits abnormally
            result = lastLogicalAndExprLeftOperand(lae, c) and
            not c instanceof NormalCompletion
            or
            // Right operand exits with any completion
            result = lastLogicalAndExprRightOperand(lae, c)
          )
        or
        cfe = any(LogicalOrExpr loe |
            // Left operand exits with a true completion
            result = lastLogicalOrExprLeftOperand(loe, c) and
            c instanceof TrueCompletion
            or
            // Left operand exits abnormally
            result = lastLogicalOrExprLeftOperand(loe, c) and
            not c instanceof NormalCompletion
            or
            // Right operand exits with any completion
            result = lastLogicalOrExprRightOperand(loe, c)
          )
        or
        cfe = any(NullCoalescingExpr nce |
            // Left operand exits with any non-`null` completion
            result = lastNullCoalescingExprLeftOperand(nce, c) and
            not c.(NullnessCompletion).isNull()
            or
            // Right operand exits with any completion
            result = lastNullCoalescingExprRightOperand(nce, c)
          )
        or
        cfe = any(ConditionalExpr ce |
            // Condition exits abnormally
            result = lastConditionalExprCondition(ce, c) and
            not c instanceof NormalCompletion
            or
            // Then branch exits with any completion
            result = lastConditionalExprThen(ce, c)
            or
            // Else branch exits with any completion
            result = lastConditionalExprElse(ce, c)
          )
        or
        result = lastAssignOperationWithExpandedAssignmentExpandedAssignment(cfe, c)
        or
        cfe = any(ConditionalQualifiableExpr cqe |
            // Post-order: element itself
            result = cqe and
            c.isValidFor(cqe)
            or
            // Qualifier exits with a `null` completion
            result = lastConditionalQualifiableExprChildExpr(cqe, -1, c) and
            c.(NullnessCompletion).isNull()
          )
        or
        cfe = any(ThrowExpr te |
            // Post-order: element itself
            te.getThrownExceptionType() = c.(ThrowCompletion).getExceptionClass() and
            result = te
            or
            // Expression being thrown exits abnormally
            result = lastThrowExprExpr(te, c) and
            not c instanceof NormalCompletion
          )
        or
        cfe = any(ObjectCreation oc |
            // Post-order: element itself (when no initializer)
            result = oc and
            not oc.hasInitializer() and
            c.isValidFor(result)
            or
            // Last element of initializer
            result = lastObjectCreationInitializer(oc, c)
          )
        or
        cfe = any(ArrayCreation ac |
            // Post-order: element itself (when no initializer)
            result = ac and
            not ac.hasInitializer() and
            c.isValidFor(result)
            or
            // Last element of initializer
            result = lastArrayCreationInitializer(ac, c)
          )
        or
        cfe = any(IfStmt is |
            // Condition exits with a false completion and there is no `else` branch
            result = lastIfStmtCondition(is, c) and
            c instanceof FalseCompletion and
            not exists(is.getElse())
            or
            // Condition exits abnormally
            result = lastIfStmtCondition(is, c) and
            not c instanceof NormalCompletion
            or
            // Then branch exits with any completion
            result = lastIfStmtThen(is, c)
            or
            // Else branch exits with any completion
            result = lastIfStmtElse(is, c)
          )
        or
        cfe = any(SwitchStmt ss |
            // Switch expression exits normally and there are no cases
            result = lastSwitchStmtCondition(ss, c) and
            not exists(ss.getACase()) and
            c instanceof NormalCompletion
            or
            // Switch expression exits abnormally
            result = lastSwitchStmtCondition(ss, c) and
            not c instanceof NormalCompletion
            or
            // A statement exits with a `break` completion
            result = lastSwitchStmtStmt(ss, _, any(BreakCompletion bc)) and
            c instanceof BreakNormalCompletion
            or
            // A statement exits abnormally
            result = lastSwitchStmtStmt(ss, _, c) and
            not c instanceof BreakCompletion and
            not c instanceof NormalCompletion and
            not c instanceof GotoDefaultCompletion and
            not c instanceof GotoCaseCompletion
            or
            // Last case exits with a non-match
            exists(int last | last = max(int i | exists(ss.getCase(i))) |
              result = lastConstCaseNoMatch(ss.getCase(last), c) or
              result = lastTypeCaseNoMatch(ss.getCase(last), c)
            )
            or
            // Last statement exits with any non-break completion
            exists(int last | last = max(int i | exists(ss.getStmt(i))) |
              result = lastSwitchStmtStmt(ss, last, c) and
              not c instanceof BreakCompletion
            )
          )
        or
        cfe = any(ConstCase cc |
            // Case expression exits with a non-match
            result = lastConstCaseNoMatch(cc, c)
            or
            // Case expression exits abnormally
            result = lastConstCaseExpr(cc, c) and
            not c instanceof NormalCompletion
          )
        or
        cfe = any(TypeCase tc |
            // Type test exits with a non-match
            result = lastTypeCaseNoMatch(tc, c)
          )
        or
        cfe = any(CaseStmt cs |
            // Condition exists with a `false` completion
            result = lastCaseCondition(cs, c) and
            c instanceof FalseCompletion
            or
            // Condition exists abnormally
            result = lastCaseCondition(cs, c) and
            not c instanceof NormalCompletion
            or
            // Case statement exits with any completion
            result = lastCaseStmt(cs, c)
          )
        or
        exists(LoopStmt ls |
          cfe = ls and
          not ls instanceof ForeachStmt
        |
          // Condition exits with a false completion
          result = lastLoopStmtCondition(ls, c) and
          c instanceof FalseCompletion
          or
          // Condition exits abnormally
          result = lastLoopStmtCondition(ls, c) and
          not c instanceof NormalCompletion
          or
          exists(Completion bodyCompletion | result = lastLoopStmtBody(ls, bodyCompletion) |
            if bodyCompletion instanceof BreakCompletion
            then
              // Body exits with a break completion; the loop exits normally
              // Note: we use a `BreakNormalCompletion` rather than a `NormalCompletion`
              // in order to be able to get the correct break label in the control flow
              // graph from the `result` node to the node after the loop.
              c instanceof BreakNormalCompletion
            else (
              // Body exits with a completion that does not continue the loop
              not bodyCompletion.continuesLoop() and
              c = bodyCompletion
            )
          )
        )
        or
        cfe = any(ForeachStmt fs |
            // Iterator expression exits abnormally
            result = lastForeachStmtIterableExpr(fs, c) and
            not c instanceof NormalCompletion
            or
            // Emptiness test exits with no more elements
            result = fs and
            c.(EmptinessCompletion).isEmpty()
            or
            exists(Completion bodyCompletion | result = lastLoopStmtBody(fs, bodyCompletion) |
              if bodyCompletion instanceof BreakCompletion
              then
                // Body exits with a break completion; the loop exits normally
                // Note: we use a `BreakNormalCompletion` rather than a `NormalCompletion`
                // in order to be able to get the correct break label in the control flow
                // graph from the `result` node to the node after the loop.
                c instanceof BreakNormalCompletion
              else (
                // Body exits abnormally
                c = bodyCompletion and
                not c instanceof NormalCompletion and
                not c instanceof ContinueCompletion
              )
            )
          )
        or
        cfe = any(TryStmt ts |
            // If the `finally` block completes normally, it resumes any non-normal
            // completion that was current before the `finally` block was entered
            exists(Completion finallyCompletion |
              result = lastTryStmtFinally(ts, finallyCompletion) and
              finallyCompletion instanceof NormalCompletion
            |
              exists(getBlockOrCatchFinallyPred(ts, any(NormalCompletion nc))) and
              c = finallyCompletion
              or
              exists(getBlockOrCatchFinallyPred(ts, c)) and
              not c instanceof NormalCompletion
            )
            or
            // If the `finally` block completes abnormally, take the completion of
            // the `finally` block itself
            result = lastTryStmtFinally(ts, c) and
            not c instanceof NormalCompletion
            or
            result = getBlockOrCatchFinallyPred(ts, c) and
            (
              // If there is no `finally` block, last elements are from the body, from
              // the blocks of one of the `catch` clauses, or from the last `catch` clause
              not ts.hasFinally()
              or
              // Exit completions ignore the `finally` block
              c instanceof ExitCompletion
            )
          )
        or
        cfe = any(SpecificCatchClause scc |
            // Last element of `catch` block
            result = lastCatchClauseBlock(cfe, c)
            or
            (
              if scc.isLast()
              then (
                // Last `catch` clause inherits throw completions from the `try` block,
                // when the clause does not match
                throwMayBeUncaught(scc, c) and
                (
                  // Incompatible exception type: clause itself
                  result = scc
                  or
                  // Incompatible filter
                  result = lastSpecificCatchClauseFilterClause(scc, _)
                )
              ) else (
                // Incompatible exception type: clause itself
                result = scc and
                c = any(MatchingCompletion mc | not mc.isMatch())
                or
                // Incompatible filter
                result = lastSpecificCatchClauseFilterClause(scc, c) and
                c instanceof FalseCompletion
              )
            )
          )
        or
        cfe = any(JumpStmt js |
            // Post-order: element itself
            result = js and
            (
              js instanceof BreakStmt and c instanceof BreakCompletion
              or
              js instanceof ContinueStmt and c instanceof ContinueCompletion
              or
              js = c.(GotoLabelCompletion).getGotoStmt()
              or
              js = c.(GotoCaseCompletion).getGotoStmt()
              or
              js instanceof GotoDefaultStmt and c instanceof GotoDefaultCompletion
              or
              js.(ThrowStmt).getThrownExceptionType() = c.(ThrowCompletion).getExceptionClass()
              or
              js instanceof ReturnStmt and c instanceof ReturnCompletion
              or
              // `yield break` behaves like a return statement
              js instanceof YieldBreakStmt and c instanceof ReturnCompletion
              or
              // `yield return` behaves like a normal statement
              js instanceof YieldReturnStmt and c.isValidFor(js)
            )
            or
            // Child exits abnormally
            result = lastJumpStmtChild(cfe, c) and
            not c instanceof NormalCompletion
          )
        or
        // Propagate completion from a call to a non-terminating callable
        cfe = any(NonReturningCall nrc |
            result = nrc and
            c = nrc.getACompletion()
          )
      }

      private ControlFlowElement lastConstCaseNoMatch(ConstCase cc, MatchingCompletion c) {
        result = lastConstCaseExpr(cc, c) and
        not c.isMatch()
      }

      private ControlFlowElement lastTypeCaseNoMatch(TypeCase tc, MatchingCompletion c) {
        result = tc.getTypeAccess() and
        not c.isMatch() and
        c.isValidFor(result)
      }

      pragma[nomagic]
      private ControlFlowElement lastStandardElementGetNonLastChildElement(
        StandardElement se, int i, Completion c
      ) {
        result = last(se.getNonLastChildElement(i), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastThrowExprExpr(ThrowExpr te, Completion c) {
        result = last(te.getExpr(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastLogicalNotExprOperand(LogicalNotExpr lne, Completion c) {
        result = last(lne.getOperand(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastLogicalAndExprLeftOperand(LogicalAndExpr lae, Completion c) {
        result = last(lae.getLeftOperand(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastLogicalAndExprRightOperand(LogicalAndExpr lae, Completion c) {
        result = last(lae.getRightOperand(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastLogicalOrExprLeftOperand(LogicalOrExpr loe, Completion c) {
        result = last(loe.getLeftOperand(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastLogicalOrExprRightOperand(LogicalOrExpr loe, Completion c) {
        result = last(loe.getRightOperand(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastNullCoalescingExprLeftOperand(
        NullCoalescingExpr nce, Completion c
      ) {
        result = last(nce.getLeftOperand(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastNullCoalescingExprRightOperand(
        NullCoalescingExpr nce, Completion c
      ) {
        result = last(nce.getRightOperand(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastConditionalExprCondition(ConditionalExpr ce, Completion c) {
        result = last(ce.getCondition(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastConditionalExprThen(ConditionalExpr ce, Completion c) {
        result = last(ce.getThen(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastConditionalExprElse(ConditionalExpr ce, Completion c) {
        result = last(ce.getElse(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastAssignOperationWithExpandedAssignmentExpandedAssignment(
        AssignOperationWithExpandedAssignment a, Completion c
      ) {
        result = last(a.getExpandedAssignment(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastConditionalQualifiableExprChildExpr(
        ConditionalQualifiableExpr cqe, int i, Completion c
      ) {
        result = last(cqe.getChildExpr(i), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastObjectCreationArgument(ObjectCreation oc, int i, Completion c) {
        result = last(oc.getArgument(i), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastObjectCreationInitializer(ObjectCreation oc, Completion c) {
        result = last(oc.getInitializer(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastArrayCreationInitializer(ArrayCreation ac, Completion c) {
        result = last(ac.getInitializer(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastArrayCreationLengthArgument(
        ArrayCreation ac, int i, Completion c
      ) {
        not ac.isImplicitlySized() and
        result = last(ac.getLengthArgument(i), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastIfStmtCondition(IfStmt is, Completion c) {
        result = last(is.getCondition(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastIfStmtThen(IfStmt is, Completion c) {
        result = last(is.getThen(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastIfStmtElse(IfStmt is, Completion c) {
        result = last(is.getElse(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastSwitchStmtCondition(SwitchStmt ss, Completion c) {
        result = last(ss.getCondition(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastSwitchStmtStmt(SwitchStmt ss, int i, Completion c) {
        result = last(ss.getStmt(i), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastSwitchStmtCaseStmt(SwitchStmt ss, int i, Completion c) {
        result = last(ss.getStmt(i).(ConstCase).getStmt(), c) or
        result = last(ss.getStmt(i).(TypeCase).getStmt(), c) or
        result = last(ss.getStmt(i).(DefaultCase), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastConstCaseExpr(ConstCase cc, Completion c) {
        result = last(cc.getExpr(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastCaseStmt(CaseStmt cs, Completion c) {
        result = last(cs.(TypeCase).getStmt(), c)
        or
        result = last(cs.(ConstCase).getStmt(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastCaseCondition(CaseStmt cs, Completion c) {
        result = last(cs.getCondition(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastTypeCaseVariableDeclExpr(TypeCase tc, Completion c) {
        result = last(tc.getVariableDeclExpr(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastLoopStmtCondition(LoopStmt ls, Completion c) {
        result = last(ls.getCondition(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastLoopStmtBody(LoopStmt ls, Completion c) {
        result = last(ls.getBody(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastForeachStmtIterableExpr(ForeachStmt fs, Completion c) {
        result = last(fs.getIterableExpr(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastForeachStmtVariableDecl(ForeachStmt fs, Completion c) {
        result = last(fs.getVariableDeclExpr(), c) or
        result = last(fs.getVariableDeclTuple(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastJumpStmtChild(JumpStmt js, Completion c) {
        result = last(js.getChild(0), c)
      }

      pragma[nomagic]
      ControlFlowElement lastTryStmtFinally(TryStmt ts, Completion c) {
        result = last(ts.getFinally(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastTryStmtBlock(TryStmt ts, Completion c) {
        result = last(ts.getBlock(), c)
      }

      pragma[nomagic]
      ControlFlowElement lastTryStmtCatchClause(TryStmt ts, int i, Completion c) {
        result = last(ts.getCatchClause(i), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastSpecificCatchClauseFilterClause(
        SpecificCatchClause scc, Completion c
      ) {
        result = last(scc.getFilterClause(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastCatchClauseBlock(CatchClause cc, Completion c) {
        result = last(cc.getBlock(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastStandardExprLastChildElement(StandardExpr se, Completion c) {
        result = last(se.getLastChildElement(), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastForStmtUpdate(ForStmt fs, int i, Completion c) {
        result = last(fs.getUpdate(i), c)
      }

      pragma[nomagic]
      private ControlFlowElement lastForStmtInitializer(ForStmt fs, int i, Completion c) {
        result = last(fs.getInitializer(i), c)
      }

      /**
       * Gets a last element from a `try` or `catch` block of this `try` statement
       * that may finish with completion `c`, such that control may be transferred
       * to the `finally` block (if it exists).
       */
      pragma[nomagic]
      private ControlFlowElement getBlockOrCatchFinallyPred(TryStmt ts, Completion c) {
        result = lastTryStmtBlock(ts, c) and
        (
          // Any non-throw completion from the `try` block will always continue directly
          // to the `finally` block
          not c instanceof ThrowCompletion
          or
          // Any completion from the `try` block will continue to the `finally` block
          // when there are no catch clauses
          not exists(ts.getACatchClause())
        )
        or
        // Last element from any of the `catch` clause blocks continues to the `finally` block
        result = lastCatchClauseBlock(ts.getACatchClause(), c)
        or
        // Last element of last `catch` clause continues to the `finally` block
        exists(int last | ts.getCatchClause(last).isLast() |
          result = lastTryStmtCatchClause(ts, last, c)
        )
      }

      /**
       * Holds if the `try` block that catch clause `scc` belongs to may throw an
       * exception of type `c`, where no `catch` clause is guaranteed to catch it.
       * The catch clause `last` is the last catch clause in the `try` statement
       * that it belongs to.
       */
      pragma[nomagic]
      private predicate throwMayBeUncaught(SpecificCatchClause last, ThrowCompletion c) {
        exists(TryStmt ts |
          ts = last.getTryStmt() and
          exists(lastTryStmtBlock(ts, c)) and
          not ts.getACatchClause() instanceof GeneralCatchClause and
          forall(SpecificCatchClause scc | scc = ts.getACatchClause() |
            scc.hasFilterClause()
            or
            not c.getExceptionClass().getABaseType*() = scc.getCaughtExceptionType()
          ) and
          last.isLast()
        )
      }

      /**
       * Gets a control flow successor for control flow element `cfe`, given that
       * `cfe` finishes with completion `c`.
       */
      pragma[nomagic]
      ControlFlowElement succ(ControlFlowElement cfe, Completion c) {
        // Pre-order: flow from element itself to first element of first child
        cfe = any(StandardStmt ss |
            result = first(ss.getFirstChildElement()) and
            c instanceof SimpleCompletion
          )
        or
        // Post-order: flow from last element of last child to element itself
        cfe = lastStandardExprLastChildElement(result, c) and
        c instanceof NormalCompletion
        or
        // Standard left-to-right evaluation
        exists(StandardElement parent, int i |
          cfe = lastStandardElementGetNonLastChildElement(parent, i, c) and
          c instanceof NormalCompletion and
          result = first(parent.getChildElement(i + 1))
        )
        or
        cfe = any(LogicalNotExpr lne |
            // Pre-order: flow from expression itself to first element of operand
            result = first(lne.getOperand()) and
            c instanceof SimpleCompletion
          )
        or
        exists(LogicalAndExpr lae |
          // Pre-order: flow from expression itself to first element of left operand
          lae = cfe and
          result = first(lae.getLeftOperand()) and
          c instanceof SimpleCompletion
          or
          // Flow from last element of left operand to first element of right operand
          cfe = lastLogicalAndExprLeftOperand(lae, c) and
          c instanceof TrueCompletion and
          result = first(lae.getRightOperand())
        )
        or
        exists(LogicalOrExpr loe |
          // Pre-order: flow from expression itself to first element of left operand
          loe = cfe and
          result = first(loe.getLeftOperand()) and
          c instanceof SimpleCompletion
          or
          // Flow from last element of left operand to first element of right operand
          cfe = lastLogicalOrExprLeftOperand(loe, c) and
          c instanceof FalseCompletion and
          result = first(loe.getRightOperand())
        )
        or
        exists(NullCoalescingExpr nce |
          // Pre-order: flow from expression itself to first element of left operand
          nce = cfe and
          result = first(nce.getLeftOperand()) and
          c instanceof SimpleCompletion
          or
          // Flow from last element of left operand to first element of right operand
          cfe = lastNullCoalescingExprLeftOperand(nce, c) and
          c.(NullnessCompletion).isNull() and
          result = first(nce.getRightOperand())
        )
        or
        exists(ConditionalExpr ce |
          // Pre-order: flow from expression itself to first element of condition
          ce = cfe and
          result = first(ce.getCondition()) and
          c instanceof SimpleCompletion
          or
          // Flow from last element of condition to first element of then branch
          cfe = lastConditionalExprCondition(ce, c) and
          c instanceof TrueCompletion and
          result = first(ce.getThen())
          or
          // Flow from last element of condition to first element of else branch
          cfe = lastConditionalExprCondition(ce, c) and
          c instanceof FalseCompletion and
          result = first(ce.getElse())
        )
        or
        exists(ConditionalQualifiableExpr parent, int i |
          cfe = lastConditionalQualifiableExprChildExpr(parent, i, c) and
          c instanceof NormalCompletion and
          not c.(NullnessCompletion).isNull()
        |
          // Post-order: flow from last element of last child to element itself
          i = max(int j | exists(parent.getChildExpr(j))) and
          result = parent
          or
          // Standard left-to-right evaluation
          result = first(parent.getChildExpr(i + 1))
        )
        or
        // Post-order: flow from last element of thrown expression to expression itself
        cfe = lastThrowExprExpr(result, c) and
        c instanceof NormalCompletion
        or
        exists(ObjectCreation oc |
          // Flow from last element of argument `i` to first element of argument `i+1`
          exists(int i | cfe = lastObjectCreationArgument(oc, i, c) |
            result = first(oc.getArgument(i + 1)) and
            c instanceof NormalCompletion
          )
          or
          // Flow from last element of last argument to self
          exists(int last | last = max(int i | exists(oc.getArgument(i))) |
            cfe = lastObjectCreationArgument(oc, last, c) and
            result = oc and
            c instanceof NormalCompletion
          )
          or
          // Flow from self to first element of initializer
          cfe = oc and
          result = first(oc.getInitializer()) and
          c instanceof SimpleCompletion
        )
        or
        exists(ArrayCreation ac |
          // Flow from self to first element of initializer
          cfe = ac and
          result = first(ac.getInitializer()) and
          c instanceof SimpleCompletion
          or
          exists(int i |
            cfe = lastArrayCreationLengthArgument(ac, i, c) and
            c instanceof SimpleCompletion
          |
            // Flow from last length argument to self
            i = max(int j | exists(ac.getLengthArgument(j))) and
            result = ac
            or
            // Flow from one length argument to the next
            result = first(ac.getLengthArgument(i + 1))
          )
        )
        or
        exists(IfStmt is |
          // Pre-order: flow from statement itself to first element of condition
          cfe = is and
          result = first(is.getCondition()) and
          c instanceof SimpleCompletion
          or
          cfe = lastIfStmtCondition(is, c) and
          (
            // Flow from last element of condition to first element of then branch
            c instanceof TrueCompletion and result = first(is.getThen())
            or
            // Flow from last element of condition to first element of else branch
            c instanceof FalseCompletion and result = first(is.getElse())
          )
        )
        or
        exists(SwitchStmt ss |
          // Pre-order: flow from statement itself to first element of switch expression
          cfe = ss and
          result = first(ss.getCondition()) and
          c instanceof SimpleCompletion
          or
          // Flow from last element of switch expression to first element of first statement
          cfe = lastSwitchStmtCondition(ss, c) and
          c instanceof NormalCompletion and
          result = first(ss.getStmt(0))
          or
          // Flow from last element of non-`case` statement `i` to first element of statement `i+1`
          exists(int i | cfe = lastSwitchStmtStmt(ss, i, c) |
            not ss.getStmt(i) instanceof CaseStmt and
            c instanceof NormalCompletion and
            result = first(ss.getStmt(i + 1))
          )
          or
          // Flow from last element of `case` statement `i` to first element of statement `i+1`
          exists(int i | cfe = lastSwitchStmtCaseStmt(ss, i, c) |
            c instanceof NormalCompletion and
            result = first(ss.getStmt(i + 1))
          )
          or
          // Flow from last element of case expression to next case
          exists(ConstCase cc, int i | cc = ss.getCase(i) |
            cfe = lastConstCaseExpr(cc, c) and
            c = any(MatchingCompletion mc | not mc.isMatch()) and
            result = first(ss.getCase(i + 1))
          )
          or
          // Flow from last element of condition to next case
          exists(CaseStmt tc, int i | tc = ss.getCase(i) |
            cfe = lastCaseCondition(tc, c) and
            c instanceof FalseCompletion and
            result = first(ss.getCase(i + 1))
          )
          or
          exists(GotoCompletion gc |
            cfe = lastSwitchStmtStmt(ss, _, gc) and
            gc = c
          |
            // Flow from last element of a statement with a `goto default` completion
            // to first element `default` statement
            gc instanceof GotoDefaultCompletion and
            result = first(ss.getDefaultCase())
            or
            // Flow from last element of a statement with a `goto case` completion
            // to first element of relevant case
            exists(ConstCase cc |
              cc = ss.getAConstCase() and
              cc.getLabel() = gc.(GotoCaseCompletion).getLabel() and
              result = first(cc.getStmt())
            )
          )
        )
        or
        exists(ConstCase cc |
          // Pre-order: flow from statement itself to first element of expression
          cfe = cc and
          result = first(cc.getExpr()) and
          c instanceof SimpleCompletion
          or
          cfe = lastConstCaseExpr(cc, c) and
          c.(MatchingCompletion).isMatch() and
          (
            if exists(cc.getCondition())
            then
              // Flow from the last element of case expression to the condition
              result = first(cc.getCondition())
            else
              // Flow from last element of case expression to first element of statement
              result = first(cc.getStmt())
          )
          or
          // Flow from last element of case condition to first element of statement
          cfe = lastCaseCondition(cc, c) and
          c instanceof TrueCompletion and
          result = first(cc.getStmt())
        )
        or
        exists(TypeCase tc |
          // Pre-order: flow from statement itself to type test
          cfe = tc and
          result = tc.getTypeAccess() and
          c instanceof SimpleCompletion
          or
          cfe = tc.getTypeAccess() and
          c.isValidFor(cfe) and
          c = any(MatchingCompletion mc |
              if mc.isMatch()
              then
                if exists(tc.getVariableDeclExpr())
                then
                  // Flow from type test to first element of variable declaration
                  result = first(tc.getVariableDeclExpr())
                else
                  if exists(tc.getCondition())
                  then
                    // Flow from type test to first element of condition
                    result = first(tc.getCondition())
                  else
                    // Flow from type test to first element of statement
                    result = first(tc.getStmt())
              else
                // Flow from type test to first element of next case
                exists(SwitchStmt ss, int i | tc = ss.getCase(i) |
                  result = first(ss.getCase(i + 1))
                )
            )
          or
          cfe = lastTypeCaseVariableDeclExpr(tc, c) and
          if exists(tc.getCondition())
          then
            // Flow from variable declaration to first element of condition
            result = first(tc.getCondition())
          else
            // Flow from variable declaration to first element of statement
            result = first(tc.getStmt())
          or
          // Flow from condition to first element of statement
          cfe = lastCaseCondition(tc, c) and
          c instanceof TrueCompletion and
          result = first(tc.getStmt())
        )
        or
        exists(LoopStmt ls |
          // Flow from last element of condition to first element of loop body
          cfe = lastLoopStmtCondition(ls, c) and
          c instanceof TrueCompletion and
          result = first(ls.getBody())
          or
          // Flow from last element of loop body back to first element of condition
          not ls instanceof ForStmt and
          cfe = lastLoopStmtBody(ls, c) and
          c.continuesLoop() and
          result = first(ls.getCondition())
        )
        or
        cfe = any(WhileStmt ws |
            // Pre-order: flow from statement itself to first element of condition
            result = first(ws.getCondition()) and
            c instanceof SimpleCompletion
          )
        or
        cfe = any(DoStmt ds |
            // Pre-order: flow from statement itself to first element of body
            result = first(ds.getBody()) and
            c instanceof SimpleCompletion
          )
        or
        exists(ForStmt fs |
          // Pre-order: flow from statement itself to first element of first initializer/
          // condition/loop body
          exists(ControlFlowElement next |
            cfe = fs and
            result = first(next) and
            c instanceof SimpleCompletion
          |
            next = fs.getInitializer(0)
            or
            not exists(fs.getInitializer(0)) and
            next = getForStmtConditionOrBody(fs)
          )
          or
          // Flow from last element of initializer `i` to first element of initializer `i+1`
          exists(int i | cfe = lastForStmtInitializer(fs, i, c) |
            c instanceof NormalCompletion and
            result = first(fs.getInitializer(i + 1))
          )
          or
          // Flow from last element of last initializer to first element of condition/loop body
          exists(int last | last = max(int i | exists(fs.getInitializer(i))) |
            cfe = lastForStmtInitializer(fs, last, c) and
            c instanceof NormalCompletion and
            result = first(getForStmtConditionOrBody(fs))
          )
          or
          // Flow from last element of condition into first element of loop body
          cfe = lastLoopStmtCondition(fs, c) and
          c instanceof TrueCompletion and
          result = first(fs.getBody())
          or
          // Flow from last element of loop body to first element of update/condition/self
          exists(ControlFlowElement next |
            cfe = lastLoopStmtBody(fs, c) and
            c.continuesLoop() and
            result = first(next) and
            if exists(fs.getUpdate(0))
            then next = fs.getUpdate(0)
            else next = getForStmtConditionOrBody(fs)
          )
          or
          // Flow from last element of update to first element of next update/condition/loop body
          exists(ControlFlowElement next, int i |
            cfe = lastForStmtUpdate(fs, i, c) and
            c instanceof NormalCompletion and
            result = first(next) and
            if exists(fs.getUpdate(i + 1))
            then next = fs.getUpdate(i + 1)
            else next = getForStmtConditionOrBody(fs)
          )
        )
        or
        exists(ForeachStmt fs |
          // Flow from last element of iterator expression to emptiness test
          cfe = lastForeachStmtIterableExpr(fs, c) and
          c instanceof NormalCompletion and
          result = fs
          or
          // Flow from emptiness test to first element of variable declaration/loop body
          cfe = fs and
          c = any(EmptinessCompletion ec | not ec.isEmpty()) and
          (
            result = first(fs.getVariableDeclExpr())
            or
            result = first(fs.getVariableDeclTuple())
            or
            not exists(fs.getVariableDeclExpr()) and
            not exists(fs.getVariableDeclTuple()) and
            result = first(fs.getBody())
          )
          or
          // Flow from last element of variable declaration to first element of loop body
          cfe = lastForeachStmtVariableDecl(fs, c) and
          c instanceof SimpleCompletion and
          result = first(fs.getBody())
          or
          // Flow from last element of loop body back to emptiness test
          cfe = lastLoopStmtBody(fs, c) and
          c.continuesLoop() and
          result = fs
        )
        or
        exists(TryStmt ts |
          // Pre-order: flow from statement itself to first element of body
          cfe = ts and
          result = first(ts.getBlock()) and
          c instanceof SimpleCompletion
          or
          // Flow from last element of body to first `catch` clause
          exists(getAThrownException(ts, cfe, c)) and
          result = first(ts.getCatchClause(0))
          or
          exists(SpecificCatchClause scc, int i | scc = ts.getCatchClause(i) |
            cfe = scc and
            scc = lastTryStmtCatchClause(ts, i, c) and
            (
              // Flow from one `catch` clause to the next
              result = first(ts.getCatchClause(i + 1)) and
              c = any(MatchingCompletion mc | not mc.isMatch())
              or
              // Flow from last `catch` clause to first element of `finally` block
              ts.getCatchClause(i).isLast() and
              result = first(ts.getFinally()) and
              c instanceof ThrowCompletion // inherited from `try` block
            )
            or
            cfe = lastTryStmtCatchClause(ts, i, c) and
            cfe = lastSpecificCatchClauseFilterClause(scc, _) and
            (
              // Flow from last element of `catch` clause filter to next `catch` clause
              result = first(ts.getCatchClause(i + 1)) and
              c instanceof FalseCompletion
              or
              // Flow from last element of `catch` clause filter, of last clause, to first
              // element of `finally` block
              ts.getCatchClause(i).isLast() and
              result = first(ts.getFinally()) and
              c instanceof ThrowCompletion // inherited from `try` block
            )
            or
            // Flow from last element of a `catch` block to first element of `finally` block
            cfe = lastCatchClauseBlock(scc, c) and
            result = first(ts.getFinally())
          )
          or
          // Flow from last element of `try` block to first element of `finally` block
          cfe = lastTryStmtBlock(ts, c) and
          result = first(ts.getFinally()) and
          not c instanceof ExitCompletion and
          (c instanceof ThrowCompletion implies not exists(ts.getACatchClause()))
        )
        or
        exists(SpecificCatchClause scc |
          // Flow from catch clause to variable declaration/filter clause/block
          cfe = scc and
          c.(MatchingCompletion).isMatch() and
          exists(ControlFlowElement next | result = first(next) |
            if exists(scc.getVariableDeclExpr())
            then next = scc.getVariableDeclExpr()
            else
              if exists(scc.getFilterClause())
              then next = scc.getFilterClause()
              else next = scc.getBlock()
          )
          or
          // Flow from variable declaration to filter clause/block
          cfe = last(scc.getVariableDeclExpr(), c) and
          c instanceof SimpleCompletion and
          exists(ControlFlowElement next | result = first(next) |
            if exists(scc.getFilterClause())
            then next = scc.getFilterClause()
            else next = scc.getBlock()
          )
          or
          // Flow from filter to block
          cfe = last(scc.getFilterClause(), c) and
          c instanceof TrueCompletion and
          result = first(scc.getBlock())
        )
        or
        // Post-order: flow from last element of child to statement itself
        cfe = lastJumpStmtChild(result, c) and
        c instanceof NormalCompletion
        or
        // Flow from constructor initializer to first element of constructor body
        cfe = any(ConstructorInitializer ci |
            c instanceof SimpleCompletion and
            result = first(ci.getConstructor().getBody())
          )
        or
        // Flow from element with `goto` completion to first element of relevant
        // target
        c = any(GotoLabelCompletion glc |
            cfe = last(_, glc) and
            // Special case: when a `goto` happens inside a `try` statement with a
            // `finally` block, flow does not go directly to the target, but instead
            // to the `finally` block (and from there possibly to the target)
            not cfe = getBlockOrCatchFinallyPred(any(TryStmt ts | ts.hasFinally()), _) and
            result = first(glc.getGotoStmt().getTarget())
          )
      }

      /**
       * Gets an exception type that is thrown by `cfe` in the block of `try` statement
       * `ts`. Throw completion `c` matches the exception type.
       */
      ExceptionClass getAThrownException(TryStmt ts, ControlFlowElement cfe, ThrowCompletion c) {
        cfe = lastTryStmtBlock(ts, c) and
        result = c.getExceptionClass()
      }

      /**
       * Gets the condition of `for` loop `fs` if it exists, otherwise the body.
       */
      private ControlFlowElement getForStmtConditionOrBody(ForStmt fs) {
        result = fs.getCondition()
        or
        not exists(fs.getCondition()) and
        result = fs.getBody()
      }

      /**
       * Gets the control flow element that is first executed when entering
       * callable `c`.
       */
      ControlFlowElement succEntry(@top_level_exprorstmt_parent p) {
        p = any(Callable c |
            if exists(c.(Constructor).getInitializer())
            then result = first(c.(Constructor).getInitializer())
            else result = first(c.getBody())
          )
        or
        expr_parent_top_level_adjusted(any(Expr e | result = first(e)), _, p) and
        not p instanceof Callable
      }

      /**
       * Gets the callable that is exited when `cfe` finishes with completion `c`,
       * if any.
       */
      Callable succExit(ControlFlowElement cfe, Completion c) {
        cfe = last(result.getBody(), c) and
        not c instanceof GotoCompletion
      }
    }
    import Successor

    cached
    private module Cached {
      cached
      predicate forceCachingInSameStage() { any() }

      /**
       * Internal representation of control flow nodes in the control flow graph.
       * The control flow graph is pruned for unreachable nodes.
       */
      cached
      newtype TNode =
        TEntryNode(Callable c) { succEntrySplits(c, _, _, _) } or
        TExitNode(Callable c) {
          exists(Reachability::SameSplitsBlock b | b.isReachable(_) |
            succExitSplits(b.getAnElement(), _, c, _)
          )
        } or
        TElementNode(ControlFlowElement cfe, Splits splits) {
          exists(Reachability::SameSplitsBlock b | b.isReachable(splits) | cfe = b.getAnElement())
        }

      /** Gets a successor node of a given flow type, if any. */
      cached
      Node getASuccessorByType(Node pred, SuccessorType t) {
        // Callable entry node -> callable body
        exists(ControlFlowElement succElement, Splits succSplits |
          result = TElementNode(succElement, succSplits)
        |
          succEntrySplits(pred.(Nodes::EntryNode).getCallable(), succElement, succSplits, t)
        )
        or
        exists(ControlFlowElement predElement, Splits predSplits |
          pred = TElementNode(predElement, predSplits)
        |
          // Element node -> callable exit
          succExitSplits(predElement, predSplits, result.(Nodes::ExitNode).getCallable(), t)
          or
          // Element node -> element node
          exists(ControlFlowElement succElement, Splits succSplits, Completion c |
            result = TElementNode(succElement, succSplits)
          |
            succSplits(predElement, predSplits, succElement, succSplits, c) and
            t.matchesCompletion(c)
          )
        )
      }

      /**
       * Gets a first control flow element executed within `cfe`.
       */
      cached
      ControlFlowElement getAControlFlowEntryNode(ControlFlowElement cfe) { result = first(cfe) }

      /**
       * Gets a potential last control flow element executed within `cfe`.
       */
      cached
      ControlFlowElement getAControlFlowExitNode(ControlFlowElement cfe) { result = last(cfe, _) }
    }
    import Cached

    /** A control flow element that is split into multiple control flow nodes. */
    class SplitControlFlowElement extends ControlFlowElement {
      SplitControlFlowElement() { strictcount(this.getAControlFlowNode()) > 1 }
    }
  }
  private import Internal
}

// The code below is all for backwards-compatibility; should be deleted eventually
deprecated class ControlFlowNode = ControlFlow::Node;

deprecated class CallableEntryNode = ControlFlow::Nodes::EntryNode;

deprecated class CallableExitNode = ControlFlow::Nodes::ExitNode;

/**
 * DEPRECATED: Use `ElementNode` instead.
 *
 * A node for a control flow element.
 */
deprecated class NormalControlFlowNode extends ControlFlow::Nodes::ElementNode {
  NormalControlFlowNode() {
    forall(ControlFlow::Nodes::FinallySplit s | s = this.getASplit() |
      s.getType() instanceof ControlFlow::SuccessorTypes::NormalSuccessor
    )
  }
}

/**
 * DEPRECATED: Use `ElementNode` instead.
 *
 * A split node for a control flow element that belongs to a `finally` block.
 */
deprecated class FinallySplitControlFlowNode extends ControlFlow::Nodes::ElementNode {
  FinallySplitControlFlowNode() {
    exists(ControlFlow::Internal::FinallySplitting::FinallySplitType type |
      type = this.getASplit().(ControlFlow::Nodes::FinallySplit).getType()
    |
      not type instanceof ControlFlow::SuccessorTypes::NormalSuccessor
    )
  }

  /** Gets the try statement that this `finally` node belongs to. */
  TryStmt getTryStmt() {
    this.getElement() = ControlFlow::Internal::FinallySplitting::getAFinallyDescendant(result)
  }
}

/** DEPRECATED: Use `ControlFlow::SuccessorType` instead. */
deprecated class ControlFlowEdgeType = ControlFlow::SuccessorType;

/** DEPRECATED: Use `ControlFlow::NormalSuccessor` instead. */
deprecated class ControlFlowEdgeSuccessor = ControlFlow::SuccessorTypes::NormalSuccessor;

/** DEPRECATED: Use `ControlFlow::ConditionalSuccessor` instead. */
deprecated class ControlFlowEdgeConditional = ControlFlow::SuccessorTypes::ConditionalSuccessor;

/** DEPRECATED: Use `ControlFlow::BooleanSuccessor` instead. */
deprecated class ControlFlowEdgeBoolean = ControlFlow::SuccessorTypes::BooleanSuccessor;

/** DEPRECATED: Use `ControlFlow::NullnessSuccessor` instead. */
deprecated class ControlFlowEdgeNullness = ControlFlow::SuccessorTypes::NullnessSuccessor;

/** DEPRECATED: Use `ControlFlow::MatchingSuccessor` instead. */
deprecated class ControlFlowEdgeMatching = ControlFlow::SuccessorTypes::MatchingSuccessor;

/** DEPRECATED: Use `ControlFlow::EmptinessSuccessor` instead. */
deprecated class ControlFlowEdgeEmptiness = ControlFlow::SuccessorTypes::EmptinessSuccessor;

/** DEPRECATED: Use `ControlFlow::ReturnSuccessor` instead. */
deprecated class ControlFlowEdgeReturn = ControlFlow::SuccessorTypes::ReturnSuccessor;

/** DEPRECATED: Use `ControlFlow::BreakSuccessor` instead. */
deprecated class ControlFlowEdgeBreak = ControlFlow::SuccessorTypes::BreakSuccessor;

/** DEPRECATED: Use `ControlFlow::ContinueSuccessor` instead. */
deprecated class ControlFlowEdgeContinue = ControlFlow::SuccessorTypes::ContinueSuccessor;

/** DEPRECATED: Use `ControlFlow::GotoLabelSuccessor` instead. */
deprecated class ControlFlowEdgeGotoLabel = ControlFlow::SuccessorTypes::GotoLabelSuccessor;

/** DEPRECATED: Use `ControlFlow::GotoCaseSuccessor` instead. */
deprecated class ControlFlowEdgeGotoCase = ControlFlow::SuccessorTypes::GotoCaseSuccessor;

/** DEPRECATED: Use `ControlFlow::GotoDefaultSuccessor` instead. */
deprecated class ControlFlowEdgeGotoDefault = ControlFlow::SuccessorTypes::GotoDefaultSuccessor;

/** DEPRECATED: Use `ControlFlow::ExceptionSuccessor` instead. */
deprecated class ControlFlowEdgeException = ControlFlow::SuccessorTypes::ExceptionSuccessor;
