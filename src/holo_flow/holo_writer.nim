import hemodyne/syncartery, std/[streams, unicode]

type HoloWriter* = object
  artery*: Artery # for like buffering writing to a file
  flushLocks*: int
  flushPos*: int

{.push checks: off, stacktrace: off.}

proc initHoloWriter*(): HoloWriter {.inline.} =
  result = HoloWriter()

template buffer*(writer: HoloWriter): string = writer.artery.buffer

proc lockFlush*(writer: var HoloWriter) {.inline.} =
  inc writer.flushLocks

proc unlockFlush*(writer: var HoloWriter) {.inline.} =
  doAssert writer.flushLocks > 0, "unpaired flush unlock"
  dec writer.flushLocks

proc startDump*(writer: var HoloWriter, artery: Artery) {.inline.} =
  writer.artery = artery
  writer.flushLocks = 0
  writer.flushPos = 0

proc startDump*(writer: var HoloWriter, bufferCapacity = 16) {.inline.} =
  writer.startDump(Artery(buffer: newStringOfCap(bufferCapacity), bufferConsumer: nil))

proc startDump*(writer: var HoloWriter, stream: Stream) {.inline.} =
  writer.startDump(initArtery(stream))

proc finishDump*(writer: var HoloWriter): string {.inline.} =
  ## returns leftover buffer
  doAssert writer.flushLocks == 0, "unpaired flush lock"
  writer.flushPos += writer.artery.consumeBufferFull(writer.flushPos)
  if writer.flushPos < writer.artery.buffer.len:
    result = writer.artery.buffer[writer.flushPos ..< writer.artery.buffer.len]
  else:
    result = ""

proc addToBuffer*(writer: var HoloWriter, c: char) {.inline.} =
  writer.flushPos -= writer.artery.addToBuffer(c)

proc addToBuffer*(writer: var HoloWriter, rune: Rune) {.inline.} =
  var bytes = newString(size(rune))
  fastToUTF8Copy(rune, bytes, 0, doInc = false)
  writer.flushPos -= writer.artery.addToBuffer(bytes)

proc addToBuffer*(writer: var HoloWriter, s: sink string) {.inline.} =
  writer.flushPos -= writer.artery.addToBuffer(s)

proc consumeBuffer*(writer: var HoloWriter) {.inline.} =
  #writer.artery.consumeBufferOnce(bufferPos)
  writer.flushPos += writer.artery.consumeBuffer(writer.flushPos)
  if writer.flushLocks == 0: writer.artery.freeBefore = writer.flushPos

proc write*(writer: var HoloWriter, c: char) {.inline.} =
  writer.addToBuffer(c)
  writer.consumeBuffer()

proc write*(writer: var HoloWriter, c: Rune) {.inline.} =
  writer.addToBuffer(c)
  writer.consumeBuffer()

proc write*(writer: var HoloWriter, s: sink string) {.inline.} =
  writer.addToBuffer(s)
  writer.consumeBuffer()

{.pop.}
