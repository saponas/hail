package is.hail.expr.types

import is.hail.annotations.{UnsafeUtils, _}
import is.hail.check.Gen
import is.hail.expr.types.physical.PSet
import is.hail.utils._
import org.json4s.jackson.JsonMethods

import scala.reflect.{ClassTag, _}

final case class TSet(elementType: Type, override val required: Boolean = false) extends TIterable {
  lazy val physicalType: PSet = PSet(elementType.physicalType, required)

  override val fundamentalType: TArray = TArray(elementType.fundamentalType, required)

  def _toPretty = s"Set[$elementType]"

  override def pyString(sb: StringBuilder): Unit = {
    sb.append("set<")
    elementType.pyString(sb)
    sb.append('>')
  }

  override def canCompare(other: Type): Boolean = other match {
    case TSet(otherType, _) => elementType.canCompare(otherType)
    case _ => false
  }

  override def unify(concrete: Type): Boolean = concrete match {
    case TSet(celementType, _) => elementType.unify(celementType)
    case _ => false
  }

  override def subst() = TSet(elementType.subst())

  def _typeCheck(a: Any): Boolean =
    a.isInstanceOf[Set[_]] && a.asInstanceOf[Set[_]].forall(elementType.typeCheck)

  override def _pretty(sb: StringBuilder, indent: Int, compact: Boolean = false) {
    sb.append("Set[")
    elementType.pretty(sb, indent, compact)
    sb.append("]")
  }

  val ordering: ExtendedOrdering =
    ExtendedOrdering.setOrdering(elementType.ordering)

  override def str(a: Annotation): String = JsonMethods.compact(toJSON(a))

  override def genNonmissingValue: Gen[Annotation] = Gen.buildableOf[Set](elementType.genValue)

  override def scalaClassTag: ClassTag[Set[AnyRef]] = classTag[Set[AnyRef]]

  override def _showStr(a: Annotation, cfg: ShowStrConfig, sb: StringBuilder): Unit = {
    val set = a.asInstanceOf[Set[Any]]
    sb.append('{')
    set.foreachBetween({ elt => elementType._showStrNA(elt, cfg, sb) }) {
      sb.append(',')
    }
    sb.append('}')
  }
}
