import ./[load_buffer, reader_common]
import std/[streams, unicode] # just to expose API otherwise not used

type
  LoadState* = object
    buffer*: LoadBuffer
    bufferLocks*: int
  LoadReader* = object
    state*: ReadState
    load*: LoadState

{.push checks: off, stacktrace: off.}

proc initLoadReader*(doLineColumn = holoReaderLineColumn): LoadReader {.inline.} =
  result = LoadReader(state: initReadState(doLineColumn))

proc startLoad*(load: var LoadState, str: sink string) {.inline.} =
  load.buffer = initLoadBuffer(str)
  load.bufferLocks = 0

proc startLoad*(load: var LoadState, loader: BufferLoader, bufferCapacity = 32) {.inline.} =
  load.buffer = initLoadBuffer(loader, bufferCapacity)
  load.bufferLocks = 0

proc startLoad*(load: var LoadState, stream: Stream, loadAmount = 16, bufferCapacity = 32) {.inline.} =
  load.buffer = initLoadBuffer(stream, loadAmount, bufferCapacity)
  load.bufferLocks = 0

when declared(File):
  proc startLoad*(load: var LoadState, file: File, loadAmount = 16, bufferCapacity = 32) {.inline.} =
    ## `file` has to last as long as the loader
    load.buffer = initLoadBuffer(file, loadAmount, bufferCapacity)
    load.bufferLocks = 0

proc startRead*(reader: var LoadReader, str: sink string) {.inline.} =
  startLoad(reader.load, str)
  startRead(reader.state)

proc startRead*(reader: var LoadReader, loader: BufferLoader, bufferCapacity = 32) {.inline.} =
  startLoad(reader.load, loader, bufferCapacity)
  startRead(reader.state)

proc startRead*(reader: var LoadReader, stream: Stream, loadAmount = 16, bufferCapacity = 32) {.inline.} =
  startLoad(reader.load, stream, loadAmount, bufferCapacity)
  startRead(reader.state)

when declared(File):
  proc startRead*(reader: var LoadReader, file: File, loadAmount = 16, bufferCapacity = 32) {.inline.} =
    ## `file` has to last as long as the reader
    startLoad(reader.load, file, loadAmount, bufferCapacity)
    startRead(reader.state)

template currentBuffer*(reader: LoadReader): string =
  reader.load.buffer.data

template bufferPos*(reader: LoadReader): int =
  reader.state.pos

proc callLoader*(reader: var LoadReader) {.inline.} =
  ## for internal use, only called if buffer loader is known not to be nil
  reader.state.pos -= reader.load.buffer.callLoader()

proc loadOnce*(reader: var LoadReader) {.inline.} =
  if not reader.load.buffer.loader.isNil:
    callLoader(reader)

proc callLoaderBy*(reader: var LoadReader, n: int) {.inline.} =
  ## for internal use, only called if buffer loader is known not to be nil
  reader.state.pos -= reader.load.buffer.callLoaderBy(n)

proc loadBy*(reader: var LoadReader, n: int) {.inline.} =
  if not reader.load.buffer.loader.isNil:
    callLoaderBy(reader, n)

proc peekAfterLoadCall*(reader: var LoadReader, nextPos: int, c: var char): bool =
  ## for internal use, only called if buffer loader is known not to be nil
  callLoader(reader)
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)

proc peek*(reader: var LoadReader, c: var char): bool {.inline.} =
  let nextPos = reader.state.pos + 1
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)
  if not result and not reader.load.buffer.loader.isNil:
    result = peekAfterLoadCall(reader, nextPos, c)

proc unsafePeek*(reader: var LoadReader): char {.inline.} =
  result = reader.currentBuffer[reader.state.pos + 1]

proc peekAfterLoadCallBy*(reader: var LoadReader, n: int, nextPos: int, c: var char): bool =
  ## for internal use, only called if buffer loader is known not to be nil
  callLoaderBy(reader, n)
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)

proc peek*(reader: var LoadReader, c: var char, offset: int): bool {.inline.} =
  let nextPos = reader.state.pos + 1 + offset
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)
  if not result and not reader.load.buffer.loader.isNil:
    result = peekAfterLoadCallBy(reader, 1 + offset, nextPos, c)

proc unsafePeek*(reader: var LoadReader, offset: int): char {.inline.} =
  result = reader.currentBuffer[reader.state.pos + 1 + offset]

template prepareBuffer(reader: var LoadReader, n: int, offset = 0) =
  if not reader.load.buffer.loader.isNil:
    if reader.state.pos + n + offset >= reader.currentBuffer.len:
      callLoaderBy(reader, n)

proc peekCount*(reader: var LoadReader, rune: var Rune): int {.inline.} =
  ## returns rune size if rune is peeked
  var start: char
  if peek(reader, start):
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
    prepareBuffer(reader, n, offset = 1)
    if reader.state.pos + 1 + n < reader.currentBuffer.len:
      result = n
      fastRuneAt(reader.currentBuffer, reader.state.pos + 1, rune, doInc = false)

proc peek*(reader: var LoadReader, rune: var Rune): bool {.inline.} =
  result = peekCount(reader, rune) != 0

template peekStrImpl(reader: var LoadReader, cs) =
  result = false
  let n = cs.len
  prepareBuffer(reader, n)
  let bpos = reader.state.pos
  if bpos + n < reader.currentBuffer.len:
    result = true
    when nimvm:
      for i in 0 ..< n:
        cs[i] = reader.currentBuffer[bpos + 1 + i]
    else:
      when not holoReaderPeekStrCopyMem or defined(js) or defined(nimscript):
        for i in 0 ..< n:
          cs[i] = reader.currentBuffer[bpos + 1 + i]
      else:
        copyMem(addr cs[0], addr reader.currentBuffer[bpos + 1], n)

proc peek*(reader: var LoadReader, cs: var openArray[char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peek*[I](reader: var LoadReader, cs: var array[I, char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peekOrZero*(reader: var LoadReader): char {.inline.} =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: var LoadReader): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: var LoadReader, offset: int): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy, offset)

proc lockBuffer*(reader: var LoadReader) {.inline.} =
  inc reader.load.bufferLocks

proc unlockBuffer*(reader: var LoadReader) {.inline.} =
  doAssert reader.load.bufferLocks > 0, "unpaired buffer unlock"
  dec reader.load.bufferLocks

proc unsafeNext*(reader: var LoadReader) {.inline.} =
  let prevPos = reader.state.pos
  inc reader.state.pos
  if reader.state.doLineColumn:
    let c = reader.load.buffer.data[reader.state.pos]
    if c == '\n' or (c == '\r' and peekOrZero(reader) != '\n'):
      inc reader.state.line
      reader.state.column = 1
    else:
      inc reader.state.column
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = prevPos

proc unsafeNext*(reader: var LoadReader, last: char) {.inline.} =
  let prevPos = reader.state.pos
  inc reader.state.pos
  if reader.state.doLineColumn:
    if last == '\n' or (last == '\r' and peekOrZero(reader) != '\n'):
      inc reader.state.line
      reader.state.column = 1
    else:
      inc reader.state.column
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = prevPos

proc unsafeNext*(reader: var LoadReader, last: Rune) {.inline.} =
  let prevPos = reader.state.pos
  inc reader.state.pos
  if reader.state.doLineColumn:
    if last == Rune('\n') or (last == Rune('\r') and peekOrZero(reader) != '\n'):
      inc reader.state.line
      reader.state.column = 1
    else:
      inc reader.state.column
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = prevPos

proc unsafeNextBy*(reader: var LoadReader, n: int) {.inline.} =
  # keep separate from next for now
  inc reader.state.pos, n
  if reader.state.doLineColumn:
    for i in reader.state.pos - n + 1 ..< reader.state.pos:
      let c = reader.currentBuffer[i]
      if c == '\n' or (c == '\r' and reader.currentBuffer[i + 1] != '\n'):
        inc reader.state.line
        reader.state.column = 1
      else:
        inc reader.state.column
    let cf = reader.currentBuffer[reader.state.pos]
    if cf == '\n' or (cf == '\r' and peekOrZero(reader) != '\n'):
      inc reader.state.line
      reader.state.column = 1
    else:
      inc reader.state.column
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = reader.state.pos - 1

proc next*(reader: var LoadReader, c: var char): bool {.inline.} =
  # keep separate from unsafeNext for now
  if not peek(reader, c):
    return false
  result = true
  unsafeNext(reader, last = c)

proc next*(reader: var LoadReader, rune: var Rune): bool {.inline.} =
  let size = peekCount(reader, rune)
  if size == 0:
    return false
  result = true
  unsafeNext(reader, last = rune)

proc next*(reader: var LoadReader): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator peekNext*(reader: var LoadReader): char =
  var c: char
  while peek(reader, c):
    yield c
    unsafeNext(reader)

proc peekMatch*(reader: var LoadReader, c: char): bool {.inline.} =
  var c2: char
  if peek(reader, c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: var LoadReader, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    unsafeNext(reader)

proc peekMatch*(reader: var LoadReader, c: char, offset: int): bool {.inline.} =
  prepareBuffer(reader, 1 + offset)
  let bpos = reader.state.pos
  if bpos + 1 + offset < reader.currentBuffer.len:
    if c != reader.currentBuffer[bpos + 1 + offset]:
      return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var LoadReader, rune: Rune): bool {.inline.} =
  var rune2: Rune
  if peek(reader, rune2) and rune2 == rune:
    result = true
  else:
    result = false

proc nextMatch*(reader: var LoadReader, rune: Rune): bool {.inline.} =
  result = peekMatch(reader, rune)
  if result:
    unsafeNextBy(reader, size(rune))

proc peekMatch*(reader: var LoadReader, cs: set[char], c: var char): bool {.inline.} =
  if peek(reader, c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: var LoadReader, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    unsafeNext(reader)

proc peekMatch*(reader: var LoadReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = peekMatch(reader, cs, dummy)

proc nextMatch*(reader: var LoadReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = nextMatch(reader, cs, dummy)

proc peekMatch*(reader: var LoadReader, cs: set[char], offset: int, c: var char): bool {.inline.} =
  prepareBuffer(reader, 1 + offset)
  let bpos = reader.state.pos
  if bpos + 1 + offset < reader.currentBuffer.len:
    let c2 = reader.currentBuffer[bpos + 1 + offset]
    if c2 in cs:
      c = c2
      return true
    result = false
  else:
    result = false

proc peekMatch*(reader: var LoadReader, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = peekMatch(reader, cs, offset, dummy)

template peekMatchStrImpl(reader: var LoadReader, str) =
  prepareBuffer(reader, str.len)
  let bpos = reader.state.pos
  if bpos + str.len < reader.currentBuffer.len:
    for i in 0 ..< str.len:
      if str[i] != reader.currentBuffer[bpos + 1 + i]:
        return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var LoadReader, str: openArray[char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*[I](reader: var LoadReader, str: array[I, char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*(reader: var LoadReader, str: static string): bool {.inline.} =
  # maybe make a const array
  peekMatchStrImpl(reader, str)

proc nextMatch*(reader: var LoadReader, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)

proc nextMatch*[I](reader: var LoadReader, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)

proc nextMatch*(reader: var LoadReader, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)

{.pop.}
