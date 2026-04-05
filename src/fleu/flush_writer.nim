import ./flush_buffer
import std/[streams, unicode] # just to expose API otherwise not used

type
  FlushState* = object
    buffer*: FlushBuffer
    bufferLocks*: int
  FlushWriter* = object
    flush*: FlushState
    # can also add write state that keeps track of line column etc if it was useful

{.push checks: off, stacktrace: off.}

proc initFlushWriter*(): FlushWriter {.inline.} =
  result = FlushWriter()

proc startFlush*(flush: var FlushState, bufferCapacity = 16) {.inline.} =
  flush.buffer = initFlushBuffer(bufferCapacity)

proc startFlush*(flush: var FlushState, consumer: BufferConsumer, bufferCapacity = 16) {.inline.} =
  flush.buffer = initFlushBuffer(consumer, bufferCapacity)

proc startFlush*(flush: var FlushState, stream: Stream, bufferCapacity = 16) {.inline.} =
  flush.buffer = initFlushBuffer(stream, bufferCapacity)

when declared(File):
  proc startFlush*(flush: var FlushState, file: File, bufferCapacity = 16) {.inline.} =
    ## `file` has to last as long as the writer
    flush.buffer = initFlushBuffer(file, bufferCapacity)

when false:
  type WriterType = var FlushWriter
  include writer_api

proc startWrite*(writer: var FlushWriter, bufferCapacity = 16) {.inline.} =
  writer.flush.startFlush(bufferCapacity)

proc startWrite*(writer: var FlushWriter, consumer: BufferConsumer, bufferCapacity = 16) {.inline.} =
  writer.flush.startFlush(consumer, bufferCapacity)

proc startWrite*(writer: var FlushWriter, stream: Stream, bufferCapacity = 16) {.inline.} =
  writer.flush.startFlush(stream, bufferCapacity)

when declared(File):
  proc startWrite*(writer: var FlushWriter, file: File, bufferCapacity = 16) {.inline.} =
    ## `file` has to last as long as the writer
    writer.flush.startFlush(file, bufferCapacity)

template currentBuffer*(writer: FlushWriter): string =
  writer.flush.buffer.data

template bufferStart*(writer: FlushWriter): int =
  writer.flush.buffer.flushPos

proc addToBuffer*(writer: var FlushWriter, c: char) {.inline.} =
  writer.flush.buffer.add(c)

proc addToBuffer*(writer: var FlushWriter, s: string) {.inline.} =
  writer.flush.buffer.add(s)

proc addToBuffer*(writer: var FlushWriter, s: openArray[char]) {.inline.} =
  writer.flush.buffer.add(s)

proc addToBuffer*(writer: var FlushWriter, rune: Rune) {.inline.} =
  writer.flush.buffer.add(rune)

proc lockFlush*(writer: var FlushWriter) {.inline.} =
  inc writer.flush.bufferLocks

proc unlockFlush*(writer: var FlushWriter) {.inline.} =
  assert writer.flush.bufferLocks > 0, "unpaired flush unlock"
  dec writer.flush.bufferLocks

proc callBufferConsumer*(writer: var FlushWriter) {.inline.} =
  ## for internal use, only called if buffer consumer is known not to be nil
  callConsumer(writer.flush.buffer)
  if writer.flush.bufferLocks == 0: writer.flush.buffer.freeBefore = writer.flush.buffer.flushPos

proc consumeBuffer*(writer: var FlushWriter) {.inline.} =
  if not writer.flush.buffer.consumer.isNil:
    callBufferConsumer(writer)

proc callBufferConsumerFull*(writer: var FlushWriter) {.inline.} =
  ## for internal use, only called if buffer consumer is known not to be nil
  callConsumerFull(writer.flush.buffer)
  if writer.flush.bufferLocks == 0: writer.flush.buffer.freeBefore = writer.flush.buffer.flushPos

proc consumeBufferFull*(writer: var FlushWriter) {.inline.} =
  if not writer.flush.buffer.consumer.isNil:
    callBufferConsumerFull(writer)

proc write*(writer: var FlushWriter, c: char) {.inline.} =
  writer.addToBuffer(c)
  writer.consumeBuffer()

proc write*(writer: var FlushWriter, c: Rune) {.inline.} =
  writer.addToBuffer(c)
  writer.consumeBuffer()

proc write*(writer: var FlushWriter, s: string) {.inline.} =
  writer.addToBuffer(s)
  writer.consumeBuffer()

proc write*(writer: var FlushWriter, s: openArray[char]) {.inline.} =
  writer.addToBuffer(s)
  writer.consumeBuffer()

proc finishWrite*(writer: var FlushWriter): string {.inline.} =
  ## returns leftover buffer
  if false: assert writer.flush.bufferLocks == 0, "unpaired flush lock"
  if not writer.flush.buffer.consumer.isNil:
    writer.flush.buffer.callConsumerFinish()
  if writer.bufferStart == 0:
    result = move writer.currentBuffer
  elif writer.bufferStart < writer.currentBuffer.len:
    result = writer.currentBuffer[writer.bufferStart ..< writer.currentBuffer.len]
  else:
    result = ""

{.pop.}
