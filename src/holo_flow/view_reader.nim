import ./[load_reader, load_buffer, reader_common]
import std/[streams, unicode] # just to expose API otherwise not used

const experimentalViewsAvailable = compiles do:
  var x: int
  let y: var int = y

const holoFlowViewReaderUseViews* {.booldefine.} = experimentalViewsAvailable

when defined(js):
  type LoadReaderView* = ref LoadReader
elif holoFlowViewReaderUseViews:
  type LoadReaderView* = var LoadReader
else:
  type LoadReaderView* = ptr LoadReader

type
  ViewReader* = object
    ## view type over the `LoadReader` type,
    ## to reduce pointer dereferences
    # XXX option to use normal string on js to force utf 8
    bufferView*: cstring
    bufferViewLen*: int
    readerPtr*: LoadReaderView

when defined(js):
  type AbsorbedState = LoadReader
  template state*(reader: ViewReader): LoadReader =
    reader.readerPtr[]
  template `state=`*(reader: ViewReader, s: AbsorbedState) =
    reader.readerPtr = cast[ReaderState](s)
elif LoadReaderView is ptr:
  type AbsorbedState = var LoadReader
  template state*(reader: ViewReader): var LoadReader =
    reader.readerPtr[]
  template `state=`*(reader: ViewReader, s: AbsorbedState) =
    reader.readerPtr = addr s
elif holoFlowViewReaderUseViews:
  type AbsorbedState = var LoadReader
  template state*(reader: ViewReader): var LoadReader =
    reader.readerPtr
  template `state=`*(reader: ViewReader, s: AbsorbedState) =
    reader.readerPtr = s
else:
  {.error: "unknown way to handle state type: " & $ReaderState.}

{.push checks: off, stacktrace: off.}

proc initViewReader*(original: AbsorbedState): ViewReader {.inline.} =
  result = ViewReader()
  result.state = original

proc startRead*(reader: var ViewReader, str: sink string) {.inline.} =
  reader.state.startRead(str)
  reader.bufferView = cstring(reader.state.currentBuffer)
  reader.bufferViewLen = reader.state.currentBuffer.len
  inc reader.state.load.bufferLocks

proc startRead*(reader: var ViewReader, loader: BufferLoader, bufferCapacity = 32) {.inline.} =
  reader.state.startRead(loader, bufferCapacity)
  reader.bufferView = nil

proc startRead*(reader: var ViewReader, stream: Stream, loadAmount = 16, bufferCapacity = 32) {.inline.} =
  reader.startRead(stream, loadAmount, bufferCapacity)
  reader.bufferView = nil

when declared(File):
  proc startRead*(reader: var ViewReader, file: File, loadAmount = 16, bufferCapacity = 32) {.inline.} =
    reader.startRead(file, loadAmount, bufferCapacity)
    reader.bufferView = nil

proc loadBufferOne*(reader: ViewReader) {.inline.} =
  if reader.bufferView.isNil:
    reader.state.callLoader()

proc loadBufferBy*(reader: ViewReader, n: int) {.inline.} =
  if reader.bufferView.isNil:
    reader.state.callLoaderBy(n)

proc peek*(reader: ViewReader, c: var char): bool {.inline.} =
  if reader.bufferView.isNil:
    result = reader.state.peek(c)
  else:
    let nextPos = reader.state.bufferPos + 1
    doPeek(reader.bufferView, reader.bufferViewLen, nextPos, c, result)

proc unsafePeek*(reader: ViewReader): char {.inline.} =
  if reader.bufferView.isNil:
    result = reader.state.unsafePeek()
  else:
    # this is extra unsafe
    result = reader.bufferView[reader.state.bufferPos + 1]

proc peek*(reader: ViewReader, c: var char, offset: int): bool {.inline.} =
  if reader.bufferView.isNil:
    result = reader.state.peek(c, offset)
  else:
    let nextPos = reader.state.bufferPos + 1 + offset
    doPeek(reader.bufferView, reader.bufferViewLen, nextPos, c, result)

proc unsafePeek*(reader: ViewReader, offset: int): char {.inline.} =
  if reader.bufferView.isNil:
    result = reader.state.unsafePeek(offset)
  else:
    # this is extra unsafe
    result = reader.bufferView[reader.state.bufferPos + 1 + offset]

proc peekCount*(reader: ViewReader, rune: var Rune): int {.inline.} =
  ## returns rune size if rune is peeked
  if reader.bufferView.isNil:
    result = reader.state.peekCount(rune)
  else:
    let bpos = reader.state.bufferPos
    if bpos + 1 < reader.bufferViewLen:
      let start = reader.bufferView[bpos + 1]
      result = 0
      let b = start.byte
      var n = 0
      if b shr 5 == 0b110:
        n = 1
      elif b shr 4 == 0b1110:
        n = 2
      elif b shr 3 == 0b11110:
        n = 3
      elif b shr 2 == 0b111110:
        n = 4
      elif b shr 1 == 0b1111110:
        n = 5
      else:
        return
      if bpos + 1 + n < reader.bufferViewLen:
        result = n
        fastRuneAt(reader.bufferView.toOpenArray(0, reader.bufferViewLen - 1), bpos + 1, rune, doInc = false)

proc peek*(reader: ViewReader, rune: var Rune): bool {.inline.} =
  result = peekCount(reader, rune) != 0

template peekStrImpl(reader: ViewReader, cs) =
  if reader.bufferView.isNil:
    result = reader.state.peek(cs)
  else:
    result = false
    let n = cs.len
    let bpos = reader.state.bufferPos
    if bpos + n < reader.bufferViewLen:
      result = true
      when nimvm:
        for i in 0 ..< n:
          cs[i] = reader.bufferView[bpos + 1 + i]
      else:
        when not holoReaderPeekStrCopyMem or defined(js) or defined(nimscript):
          for i in 0 ..< n:
            cs[i] = reader.bufferView[bpos + 1 + i]
        else:
          copyMem(addr cs[0], addr reader.bufferView[bpos + 1], n)

proc peek*(reader: ViewReader, cs: var openArray[char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peek*[I](reader: ViewReader, cs: var array[I, char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peekOrZero*(reader: ViewReader): char {.inline.} =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: ViewReader): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: ViewReader, offset: int): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy, offset)

proc lockBuffer*(reader: ViewReader) {.inline.} =
  if reader.bufferView.isNil:
    reader.state.lockBuffer()

proc unlockBuffer*(reader: ViewReader) {.inline.} =
  if reader.bufferView.isNil:
    reader.state.unlockBuffer()

proc unsafeNext*(reader: ViewReader) {.inline.} =
  reader.state.unsafeNext()

proc unsafeNextBy*(reader: ViewReader, n: int) {.inline.} =
  reader.state.unsafeNextBy(n)

proc next*(reader: ViewReader, c: var char): bool {.inline.} =
  if not peek(reader, c):
    return false
  result = true
  reader.state.unsafeNext(last = c)

proc next*(reader: ViewReader, rune: var Rune): bool {.inline.} =
  let size = peekCount(reader, rune)
  if size == 0:
    return false
  result = true
  reader.state.unsafeNext(last = rune)

proc next*(reader: ViewReader): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator peekNext*(reader: ViewReader): char =
  var c: char
  while reader.peek(c):
    yield c
    reader.unsafeNext()

proc peekMatch*(reader: ViewReader, c: char): bool {.inline.} =
  var c2: char
  if reader.peek(c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: ViewReader, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: ViewReader, c: char, offset: int): bool {.inline.} =
  if reader.bufferView.isNil:
    result = reader.state.peekMatch(c, offset)
  else:
    let bpos = reader.state.bufferPos
    if bpos + 1 + offset < reader.bufferViewLen:
      if c != reader.bufferView[bpos + 1 + offset]:
        return false
      result = true
    else:
      result = false

proc peekMatch*(reader: ViewReader, rune: Rune): bool {.inline.} =
  var rune2: Rune
  if reader.peek(rune2) and rune2 == rune:
    result = true
  else:
    result = false

proc nextMatch*(reader: ViewReader, rune: Rune): bool {.inline.} =
  result = peekMatch(reader, rune)
  if result:
    reader.unsafeNextBy(size(rune))

proc peekMatch*(reader: ViewReader, cs: set[char], c: var char): bool {.inline.} =
  if reader.peek(c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: ViewReader, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: ViewReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, dummy)

proc nextMatch*(reader: ViewReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.nextMatch(cs, dummy)

proc peekMatch*(reader: ViewReader, cs: set[char], offset: int, c: var char): bool {.inline.} =
  if reader.bufferView.isNil:
    result = reader.state.peekMatch(cs, offset, c)
  else:
    let bpos = reader.state.bufferPos
    if bpos + 1 + offset < reader.bufferViewLen:
      let c2 = reader.bufferView[bpos + 1 + offset]
      if c2 in cs:
        c = c2
        return true
      result = false
    else:
      result = false

proc peekMatch*(reader: ViewReader, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, offset, dummy)

template peekMatchStrImpl(reader: ViewReader, str) =
  if reader.bufferView.isNil:
    result = reader.state.peekMatch(str)
  else:
    let bpos = reader.state.bufferPos
    if bpos + str.len < reader.bufferViewLen:
      for i in 0 ..< str.len:
        if str[i] != reader.bufferView[bpos + 1 + i]:
          return false
      result = true
    else:
      result = false

proc peekMatch*(reader: ViewReader, str: openArray[char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*[I](reader: ViewReader, str: array[I, char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*(reader: ViewReader, str: static string): bool {.inline.} =
  # maybe make a const array
  peekMatchStrImpl(reader, str)

proc nextMatch*(reader: ViewReader, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*[I](reader: ViewReader, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*(reader: ViewReader, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

{.pop.}
