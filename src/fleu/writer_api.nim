## include file to ensure writer implementation is complete
## not actually used since forward declarations don't support {.inline.} after the fact

import std/unicode # just to expose API otherwise not used

when defined(nimdoc):
  type WriterType = object
elif not declared(WriterType):
  {.fatal: "need to include with `WriterType` defined".}

when false:
  import std/streams

  proc startWrite*(writer: WriterType, bufferCapacity = 16) = discard

  proc startWrite*(writer: WriterType, consumer: BufferConsumer, bufferCapacity = 16) = discard

  proc startWrite*(writer: WriterType, stream: Stream, bufferCapacity = 16) = discard

  when declared(File):
    proc startWrite*(writer: WriterType, file: File, bufferCapacity = 16) = discard

template currentBuffer*(writer: WriterType): string =
  ## the type does not have to be `string`, at most it has to behave like `openArray[char]`
  discard
template bufferStart*(writer: WriterType): int = discard

proc lockFlush*(writer: WriterType) = discard
proc unlockFlush*(writer: WriterType) = discard

proc addToBuffer*(writer: WriterType, c: char) = discard
proc addToBuffer*(writer: WriterType, c: Rune) = discard
proc addToBuffer*(writer: WriterType, s: string) = discard
proc addToBuffer*(writer: WriterType, s: openArray[char]) = discard

proc write*(writer: WriterType, c: char) = discard
proc write*(writer: WriterType, c: Rune) = discard
proc write*(writer: WriterType, s: string) = discard
proc write*(writer: WriterType, s: openArray[char]) = discard

proc finishWrite*(writer: WriterType): string = discard
