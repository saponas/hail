package is.hail.services.shuffler.server

import java.net._
import java.security.SecureRandom
import java.util.concurrent.{ConcurrentSkipListMap, Executors, _}

import is.hail.annotations._
import is.hail.expr.ir._
import is.hail.types.encoded._
import is.hail.types.virtual._
import is.hail.types.physical._
import is.hail.io._
import is.hail.services.tls._
import is.hail.services.shuffler._
import is.hail.utils._
import javax.net.ssl._
import org.apache.log4j.Logger

import scala.annotation.switch
import is.hail.backend.local.LocalBackend
import is.hail.HailContext

class Handler (
  private[this] val server: ShuffleServer,
  private[this] val socket: Socket
) extends Runnable {
  private[this] val log = Logger.getLogger(getClass.getName())
  private[this] val in = shuffleBufferSpec.buildInputBuffer(socket.getInputStream)
  private[this] val out = shuffleBufferSpec.buildOutputBuffer(socket.getOutputStream)
  private[this] val random = new SecureRandom();

  def run(): Unit = {
    try {
      log.info(s"handle")
      try {
        var continue = true
        while (continue) {
          val op = in.readByte()
          log.info(s"operation ${op}")
            (op: @switch) match {
            case Wire.START => start()
            case Wire.PUT => put()
            case Wire.GET => get()
            case Wire.STOP => stop()
            case Wire.PARTITION_BOUNDS => partitionBounds()
            case Wire.EOS =>
              log.info(s"client ended session, replying, then exiting cleanly")
              eos()
              continue = false
            case op => fatal(s"bad operation number $op")
          }
        }
      } finally {
        socket.close()
      }
    } catch {
      case e: Exception =>
        log.warn(s"exception while serving", e)
    }
  }

  def readShuffleUUID(): Shuffle = {
    val uuid = Wire.readByteArray(in)
    assert(uuid.length == Wire.ID_SIZE, s"${uuid.length} ${Wire.ID_SIZE}")
    log.info(s"uuid ${uuidToString(uuid)}")
    val shuffle = server.shuffles.get(uuid)
    if (shuffle == null) {
      throw new RuntimeException(s"shuffle does not exist ${uuidToString(uuid)}")
    }
    shuffle
  }

  def start(): Unit = {
    log.info(s"start")
    val rowType = Wire.readTStruct(in)
    log.info(s"start got row type ${rowType}")
    val rowEType = Wire.readEBaseStruct(in)
    log.info(s"start got row encoded type ${rowEType}")
    val keyFields = Wire.readSortFieldArray(in)
    log.info(s"start got key fields ${keyFields.mkString("[", ",", "]")}")
    val keyEType = Wire.readEBaseStruct(in)
    log.info(s"start got key encoded type ${keyEType}")
    val uuid = new Array[Byte](Wire.ID_SIZE)
    random.nextBytes(uuid)
    server.shuffles.put(uuid, new Shuffle(uuid, TShuffle(keyFields, rowType, rowEType, keyEType)))
    Wire.writeByteArray(out, uuid)
    log.info(s"start wrote uuid")
    out.flush()
    log.info(s"start flush")
    log.info(s"start done")
  }

  def put(): Unit = {
    log.info(s"put")
    val shuffle = readShuffleUUID()
    shuffle.put(in, out)
    log.info(s"put done")
  }

  def get(): Unit = {
    log.info(s"get")
    val shuffle = readShuffleUUID()
    shuffle.get(in, out)
    log.info(s"get done")
  }

  def stop(): Unit = {
    log.info(s"stop")
    val uuid = Wire.readByteArray(in)
    assert(uuid.length == Wire.ID_SIZE, s"${uuid.length} ${Wire.ID_SIZE}")
    val shuffle = server.shuffles.remove(uuid)
    if (shuffle != null) {
      shuffle.close()
    }
    out.writeByte(0.toByte)
    out.flush()
    log.info(s"stop done")
  }

  def partitionBounds(): Unit = {
    log.info(s"partitionBounds")
    val shuffle = readShuffleUUID()
    shuffle.partitionBounds(in, out)
    log.info(s"partitionBounds done")
  }

  def eos(): Unit = {
    out.writeByte(Wire.EOS)
    out.flush()
  }
}

class Shuffle (
  uuid: Array[Byte],
  shuffleType: TShuffle
) extends AutoCloseable {
  private[this] val log = Logger.getLogger(getClass.getName)
  private[this] val pool = RegionPool()
  private[this] val rootRegion = Region(pool=pool)
  private[this] val codecs = {
    ExecutionTimer.logTime("Shuffle.codecs") { timer =>
      using(new ExecuteContext("/tmp", "file:///tmp", null, null, rootRegion, timer, null)) { ctx =>
        new ShuffleCodecSpec(ctx, shuffleType)
      }
    }
  }

  private[this] val store = new LSM(s"/tmp/${uuidToString(uuid)}", codecs, pool)

  private[this] def makeRegion(): Region = {
    val region = Region(pool=pool)
    rootRegion.addReferenceTo(region)
    region
  }

  def close(): Unit = {
    rootRegion.close()
  }

  def put(in: InputBuffer, out: OutputBuffer) {
    val decoder = codecs.makeRowDecoder(in)
    val region = makeRegion()
    var hasNext = in.readByte()
    assert(hasNext != -1)
    while (hasNext == 1) {
      val off = decoder.readRegionValue(region)
      val koff = codecs.constructKeyFromDecodedRow(region, off)
      store.put(koff, off)
      hasNext = in.readByte()
    }
    // fixme: server needs to send uuid for the successful partition
    out.writeByte(0)
    out.flush()
  }

  def get(in: InputBuffer, out: OutputBuffer) {
    val region = makeRegion()
    val keyDecoder = codecs.makeKeyDecoder(in)
    val encoder = codecs.makeRowEncoder(out)
    val start = keyDecoder.readRegionValue(region)
    val startInclusive = keyDecoder.readByte() == 1.toByte
    val end = keyDecoder.readRegionValue(region)
    val endInclusive = keyDecoder.readByte() == 1.toByte

    log.info(s"get start ${rvstr(codecs.keyDecodedPType, start)} ${startInclusive} end ${rvstr(codecs.keyDecodedPType, end)} ${endInclusive}")
    val it = store.iterator(start, startInclusive)
    var continue = it.hasNext
    val inRange =
      if (endInclusive) (key: Long) => store.keyOrd.lteq(key, end)
      else              (key: Long) => store.keyOrd.lt(key, end)
    while (continue) {
      val kv = it.next
      val k = kv.getKey
      val v = kv.getValue
      continue = inRange(k)
      if (continue) {
        encoder.writeByte(1)
        encoder.writeRegionValue(v)
        continue = it.hasNext
      }
    }
    encoder.writeByte(0)
    encoder.flush()
  }

  def partitionBounds(in: InputBuffer, out: OutputBuffer) {
    val nPartitions = in.readInt()

    val keyEncoder = codecs.makeKeyEncoder(out)

    val keys = store.partitionKeys(nPartitions)
    log.info(s"partitionBounds ${nPartitions}")
    assert((nPartitions == 0 && keys.length == 0) ||
      keys.length == nPartitions + 1)
    writeRegionValueArray(keyEncoder, keys)
    keyEncoder.flush()
  }
}

object ShuffleServer {
  def main(args: Array[String]): Unit =
    using(new ShuffleServer())(_.serve())
}

class ShuffleServer() extends AutoCloseable {
  val ssl = getSSLContext
  val port = 443
  val log = Logger.getLogger(this.getClass.getName());

  val shuffles = new ConcurrentSkipListMap[Array[Byte], Shuffle](new SameLengthByteArrayComparator())

  val ssf = ssl.getServerSocketFactory()
  val ss = ssf.createServerSocket(port).asInstanceOf[SSLServerSocket]

  val executor = Executors.newCachedThreadPool()
  var stopped = false

  val context = HailContext(LocalBackend("/tmp"), skipLoggingConfiguration = true)

  def serveInBackground(): Future[_] =
    executor.submit(new Runnable() { def run(): Unit = serve() })

  def serve(): Unit = {
    try {
      log.info(s"serving on ${port}")
      while (true) {
        val sock = ss.accept()
        log.info(s"accepted")
        executor.execute(new Handler(this, sock))
      }
    } catch {
      case se: SocketException =>
        if (stopped) {
          log.info(s"exiting")
          return
        } else {
          fatal("unexpected closed server socket", se)
        }
    }
  }

  def stop(): Unit = {
    log.info(s"stopping")
    stopped = true
    ss.close()
    executor.shutdownNow()
  }

  def close(): Unit = stop()
}
