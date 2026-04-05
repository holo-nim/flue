## include file to ensure reader implementation is complete
## not actually used since forward declarations don't support {.inline.} after the fact

import std/unicode # just to expose API otherwise not used

when defined(nimdoc):
  type ReaderType = object
  type ReadState = object
elif not declared(ReaderType):
  {.fatal: "need to include with `ReaderType` defined".}

proc startRead*(reader: ReaderType, str: sink string) = discard

when false:
  import std/streams

  proc startRead*(reader: ReaderType, loader: BufferLoader, bufferCapacity = 32) = discard

  proc startRead*(reader: ReaderType, stream: Stream, loadAmount = 16, bufferCapacity = 32) = discard

  when declared(File):
    proc startRead*(reader: ReaderType, file: File, loadAmount = 16, bufferCapacity = 32) = discard

proc currentBuffer*(reader: ReaderType): string =
  ## the type does not have to be `string`, at most it has to behave like `openArray[char]`
  discard
proc bufferPos*(reader: ReaderType): int = discard

proc state*(reader: ReaderType): ReadState =
  ## stand-in for custom state type
  discard
proc `state=`*(reader: ReaderType, state: ReadState) =
  ## stand-in for custom state type
  discard

proc lockBuffer*(reader: ReaderType) = discard
proc unlockBuffer*(reader: ReaderType) = discard

proc peek*(reader: ReaderType, c: var char): bool = discard

proc unsafePeek*(reader: ReaderType): char = discard

proc peek*(reader: ReaderType, c: var char, offset: int): bool = discard

proc unsafePeek*(reader: ReaderType, offset: int): char = discard

proc peekCount*(reader: ReaderType, rune: var Rune): int = discard

proc peek*(reader: ReaderType, rune: var Rune): bool {.inline.} =
  peekCount(reader, rune) != 0

proc peek*(reader: ReaderType, cs: var openArray[char]): bool = discard

proc peek*[I](reader: ReaderType, cs: var array[I, char]): bool = discard

proc peekOrZero*(reader: ReaderType): char = discard

proc hasNext*(reader: ReaderType): bool = discard

proc hasNext*(reader: ReaderType, offset: int): bool = discard

proc unsafeNext*(reader: ReaderType) = discard

proc unsafeNextBy*(reader: ReaderType, n: int) = discard

proc next*(reader: ReaderType, c: var char): bool = discard

proc next*(reader: ReaderType, rune: var Rune): bool = discard

proc next*(reader: ReaderType): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator chars*(reader: ReaderType): char =
  var c: char
  while peek(reader, c):
    yield c
    unsafeNext(reader)

iterator peekNext*(reader: ReaderType): char {.deprecated.} =
  ## deprecated alias for `chars`
  for c in chars(reader):
    yield c

proc peekMatch*(reader: ReaderType, c: char): bool = discard

proc nextMatch*(reader: ReaderType, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    unsafeNext(reader)

proc peekMatch*(reader: ReaderType, c: char, offset: int): bool = discard

proc peekMatch*(reader: ReaderType, rune: Rune): bool = discard

proc nextMatch*(reader: ReaderType, rune: Rune): bool {.inline.} =
  result = peekMatch(reader, rune)
  if result:
    unsafeNextBy(reader, size(rune))

proc peekMatch*(reader: ReaderType, cs: set[char], c: var char): bool = discard

proc nextMatch*(reader: ReaderType, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    unsafeNext(reader)

proc peekMatch*(reader: ReaderType, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = peekMatch(reader, cs, dummy)

proc nextMatch*(reader: ReaderType, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = nextMatch(reader, cs, dummy)

proc peekMatch*(reader: ReaderType, cs: set[char], offset: int, c: var char): bool = discard

proc peekMatch*(reader: ReaderType, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = peekMatch(reader, cs, offset, dummy)

proc peekMatch*(reader: ReaderType, str: openArray[char]): bool = discard

proc peekMatch*[I](reader: ReaderType, str: array[I, char]): bool = discard

proc peekMatch*(reader: ReaderType, str: static string): bool = discard

proc nextMatch*(reader: ReaderType, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)

proc nextMatch*[I](reader: ReaderType, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)

proc nextMatch*(reader: ReaderType, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)
