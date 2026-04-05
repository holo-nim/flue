import ./stringresize
import std/[streams, unicode] # just to expose API otherwise not used

type
  BufferConsumer* = proc (x: openArray[char]): int
  FlushBuffer* = object
    data*: string
    consumer*: BufferConsumer
      ## returns number of characters consumed
      ## set to nil after returning negative
    freeBefore*: int
      ## position before which we can cull the buffer
    flushPos*: int
      ## position before which the buffer has been flushed

{.push checks: off, stacktrace: off.}

proc initFlushBuffer*(capacity = 16): FlushBuffer {.inline.} =
  result = FlushBuffer(data: newStringOfCap(capacity), consumer: nil)

proc initFlushBuffer*(consumer: BufferConsumer, capacity = 16): FlushBuffer {.inline.} =
  result = FlushBuffer(data: newStringOfCap(capacity), consumer: consumer)

proc initFlushBuffer*(stream: Stream, capacity = 16): FlushBuffer {.inline.} =
  let consumer = proc (x: openArray[char]): int =
    when defined(js) or defined(nimscript):
      var s = newString(x.len)
      for i in 0 ..< x.len:
        s[i] = x[i]
      stream.write(s)
    else:
      stream.write(x)
    result = x.len
  result = initFlushBuffer(consumer, capacity)

when declared(File):
  proc initFlushBuffer*(file: File, capacity = 16): FlushBuffer {.inline.} =
    ## `file` has to last as long as the flush
    let consumer = proc (x: openArray[char]): int =
      result = file.writeChars(x, 0, x.len)
    result = initFlushBuffer(consumer, capacity)

proc add*(buffer: var FlushBuffer, c: char) {.inline.} =
  let moved = smartResizeAdd(buffer.data, c, buffer.freeBefore)
  if moved:
    buffer.flushPos -= buffer.freeBefore
    buffer.freeBefore = 0

proc add*(buffer: var FlushBuffer, s: string) {.inline.} =
  let moved = smartResizeAdd(buffer.data, s, buffer.freeBefore)
  if moved:
    buffer.flushPos -= buffer.freeBefore
    buffer.freeBefore = 0

proc add*(buffer: var FlushBuffer, s: openArray[char]) {.inline.} =
  let moved = smartResizeAdd(buffer.data, s, buffer.freeBefore)
  if moved:
    buffer.flushPos -= buffer.freeBefore
    buffer.freeBefore = 0

proc add*(buffer: var FlushBuffer, rune: Rune) {.inline.} =
  var bytes = newStringOfCap(size(rune)) # could be a constant array but fastToUTF8Copy does not allow it
  fastToUTF8Copy(rune, bytes, 0, doInc = false)
  let moved = smartResizeAdd(buffer.data, bytes, buffer.freeBefore)
  if moved:
    buffer.flushPos -= buffer.freeBefore
    buffer.freeBefore = 0

proc callConsumer*(buffer: var FlushBuffer) =
  ## for internal use, only called if buffer consumer is known not to be nil
  # probably better not to inline
  let len = buffer.data.len
  if buffer.flushPos < len:
    let consumed = buffer.consumer(buffer.data.toOpenArray(buffer.flushPos, len - 1))
    if consumed < 0:
      buffer.consumer = nil
      return
    buffer.flushPos += consumed

proc consume*(buffer: var FlushBuffer) {.inline.} =
  if not buffer.consumer.isNil:
    callConsumer(buffer)

proc callConsumerFull*(buffer: var FlushBuffer) =
  ## for internal use, only called if buffer consumer is known not to be nil
  # probably better not to inline
  let len = buffer.data.len
  while buffer.flushPos < len:
    let consumed = buffer.consumer(buffer.data.toOpenArray(buffer.flushPos, len - 1))
    if consumed < 0:
      buffer.consumer = nil
      return
    buffer.flushPos += consumed

proc consumeFull*(buffer: var FlushBuffer) {.inline.} =
  if not buffer.consumer.isNil:
    callConsumerFull(buffer)

proc callConsumerEnd*(buffer: var FlushBuffer) {.inline.} =
  ## for internal use, only called if buffer consumer is known not to be nil
  discard buffer.consumer([])
  buffer.consumer = nil

proc endFlush*(buffer: var FlushBuffer) {.inline.} =
  ## signals to consumer the end of flushing, leaves remaining buffer
  if not buffer.consumer.isNil:
    callConsumerEnd(buffer)

proc callConsumerFinish*(buffer: var FlushBuffer) {.inline.} =
  ## for internal use, only called if buffer consumer is known not to be nil
  buffer.callConsumerFull()
  if not buffer.consumer.isNil:
    callConsumerEnd(buffer)

proc finishFlush*(buffer: var FlushBuffer) {.inline.} =
  ## fully flushes buffer and signals end of flushing to consumer if consumer still exists
  if not buffer.consumer.isNil:
    callConsumerFinish(buffer)

{.pop.}
