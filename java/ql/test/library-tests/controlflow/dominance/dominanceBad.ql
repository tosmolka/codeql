import java
import semmle.code.java.controlflow.Dominance

from IfStmt i, Block b
where b = i.getThen() and
      dominates(i.getThen(), b) and
      dominates(i.getElse(), b)
select i, b
