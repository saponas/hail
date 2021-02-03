package is.hail.types.physical

import is.hail.annotations.{CodeOrdering, Region, StagedRegionValueBuilder}
import is.hail.asm4s.{Code, _}
import is.hail.expr.Nat
import is.hail.expr.ir.{EmitCodeBuilder, EmitMethodBuilder}
import is.hail.types.physical.stypes.SCode
import is.hail.types.physical.stypes.interfaces.{SBaseStructCode, SNDArrayCode, SNDArrayValue}
import is.hail.types.virtual.TNDArray

abstract class PNDArray extends PType {
  val elementType: PType
  val nDims: Int

  assert(elementType.isRealizable)

  lazy val virtualType: TNDArray = TNDArray(elementType.virtualType, Nat(nDims))
  assert(elementType.required, "elementType must be required")

  def codeOrdering(mb: EmitMethodBuilder[_], other: PType): CodeOrdering = throw new UnsupportedOperationException

  def dataFirstElementPointer(ndAddr: Code[Long]): Code[Long]
  def dataPArrayPointer(ndAddr: Code[Long]): Code[Long]

  def loadShape(off: Long, idx: Int): Long

  def loadShapes(cb: EmitCodeBuilder, addr: Value[Long], settables: IndexedSeq[Settable[Long]]): Unit
  def loadStrides(cb: EmitCodeBuilder, addr: Value[Long], settables: IndexedSeq[Settable[Long]]): Unit

  def numElements(shape: IndexedSeq[Value[Long]]): Code[Long]
  
  def makeRowMajorStrides(sourceShapeArray: IndexedSeq[Value[Long]], region: Value[Region], cb: EmitCodeBuilder): IndexedSeq[Value[Long]]

  def makeColumnMajorStrides(sourceShapeArray: IndexedSeq[Value[Long]], region: Value[Region], cb: EmitCodeBuilder): IndexedSeq[Value[Long]]

  def getElementAddress(indices: IndexedSeq[Long], nd: Long): Long

  def loadElement(cb: EmitCodeBuilder, indices: IndexedSeq[Value[Long]], ndAddress: Value[Long]): SCode

  def construct(
    shape: IndexedSeq[Value[Long]],
    strides: IndexedSeq[Value[Long]],
    data: Code[Long],
    mb: EmitCodeBuilder,
    region: Value[Region]
  ): PNDArrayCode
}

abstract class PNDArrayValue extends PValue with SNDArrayValue {
  def pt: PNDArray
}

abstract class PNDArrayCode extends PCode with SNDArrayCode {
  def pt: PNDArray

  def memoize(cb: EmitCodeBuilder, name: String): PNDArrayValue
}
