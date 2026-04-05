## included in load_reader module

when false:
  # in reverse order of definition:
  when declared(TrackedLoadReader):
    type LoadReaderType = TrackedLoadReader
  elif declared(LoadReader):
    type LoadReaderType = LoadReader
  else:
    {.fatal: "this is an include in the load_reader module".}
elif not declared(LoadReaderType):
  {.fatal: "this is an include in the load_reader module".}

proc startRead*(reader: var LoadReaderType, str: sink string) {.inline.} =
  startLoad(reader.load, str)
  startRead(reader.state)

proc startRead*(reader: var LoadReaderType, loader: BufferLoader, bufferCapacity = 32) {.inline.} =
  startLoad(reader.load, loader, bufferCapacity)
  startRead(reader.state)

proc startRead*(reader: var LoadReaderType, stream: Stream, loadAmount = 16, bufferCapacity = 32) {.inline.} =
  startLoad(reader.load, stream, loadAmount, bufferCapacity)
  startRead(reader.state)

when declared(File):
  proc startRead*(reader: var LoadReaderType, file: File, loadAmount = 16, bufferCapacity = 32) {.inline.} =
    ## `file` has to last as long as the reader
    startLoad(reader.load, file, loadAmount, bufferCapacity)
    startRead(reader.state)

template currentBuffer*(reader: LoadReaderType): string =
  reader.load.buffer.data

template bufferPos*(reader: LoadReaderType): int =
  reader.state.pos

proc callLoader*(reader: var LoadReaderType) {.inline.} =
  ## for internal use, only called if buffer loader is known not to be nil
  reader.state.pos -= reader.load.buffer.callLoader()

proc loadOnce*(reader: var LoadReaderType) {.inline.} =
  if not reader.load.buffer.loader.isNil:
    callLoader(reader)

proc callLoaderBy*(reader: var LoadReaderType, n: int) {.inline.} =
  ## for internal use, only called if buffer loader is known not to be nil
  reader.state.pos -= reader.load.buffer.callLoaderBy(n)

proc loadBy*(reader: var LoadReaderType, n: int) {.inline.} =
  if not reader.load.buffer.loader.isNil:
    callLoaderBy(reader, n)

proc peekAfterLoadCall*(reader: var LoadReaderType, nextPos: int, c: var char): bool =
  ## for internal use, only called if buffer loader is known not to be nil
  callLoader(reader)
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)

proc peek*(reader: var LoadReaderType, c: var char): bool {.inline.} =
  let nextPos = reader.state.pos + 1
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)
  if not result and not reader.load.buffer.loader.isNil:
    result = peekAfterLoadCall(reader, nextPos, c)

proc unsafePeek*(reader: var LoadReaderType): char {.inline.} =
  result = reader.currentBuffer[reader.state.pos + 1]

proc peekAfterLoadCallBy*(reader: var LoadReaderType, n: int, nextPos: int, c: var char): bool =
  ## for internal use, only called if buffer loader is known not to be nil
  callLoaderBy(reader, n)
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)

proc peek*(reader: var LoadReaderType, c: var char, offset: int): bool {.inline.} =
  let nextPos = reader.state.pos + 1 + offset
  doPeek(reader.currentBuffer, reader.currentBuffer.len, nextPos, c, result)
  if not result and not reader.load.buffer.loader.isNil:
    result = peekAfterLoadCallBy(reader, 1 + offset, nextPos, c)

proc unsafePeek*(reader: var LoadReaderType, offset: int): char {.inline.} =
  result = reader.currentBuffer[reader.state.pos + 1 + offset]

template prepareBuffer(reader: var LoadReaderType, n: int, offset = 0) =
  if not reader.load.buffer.loader.isNil:
    if reader.state.pos + n + offset >= reader.currentBuffer.len:
      callLoaderBy(reader, n)

proc peekCount*(reader: var LoadReaderType, rune: var Rune): int {.inline.} =
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

proc peek*(reader: var LoadReaderType, rune: var Rune): bool {.inline.} =
  result = peekCount(reader, rune) != 0

template peekStrImpl(reader: var LoadReaderType, cs) =
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

proc peek*(reader: var LoadReaderType, cs: var openArray[char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peek*[I](reader: var LoadReaderType, cs: var array[I, char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peekOrZero*(reader: var LoadReaderType): char {.inline.} =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: var LoadReaderType): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: var LoadReaderType, offset: int): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy, offset)

proc lockBuffer*(reader: var LoadReaderType) {.inline.} =
  inc reader.load.bufferLocks

proc unlockBuffer*(reader: var LoadReaderType) {.inline.} =
  doAssert reader.load.bufferLocks > 0, "unpaired buffer unlock"
  dec reader.load.bufferLocks

proc unsafeNext*(reader: var LoadReaderType) {.inline.} =
  let prevPos = reader.state.pos
  reader.advance(reader.state)
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = prevPos

proc unsafeNext*(reader: var LoadReaderType, last: char) {.inline.} =
  let prevPos = reader.state.pos
  reader.advance(reader.state, last)
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = prevPos

proc unsafeNext*(reader: var LoadReaderType, last: Rune) {.inline.} =
  let prevPos = reader.state.pos
  reader.advance(reader.state, last, sizeof(last))
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = prevPos

proc unsafeNextBy*(reader: var LoadReaderType, n: int) {.inline.} =
  # keep separate from next for now
  reader.advanceBy(reader.state, n)
  if reader.load.bufferLocks == 0: reader.load.buffer.freeBefore = reader.state.pos - 1

proc next*(reader: var LoadReaderType, c: var char): bool {.inline.} =
  # keep separate from unsafeNext for now
  if not peek(reader, c):
    return false
  result = true
  unsafeNext(reader, last = c)

proc next*(reader: var LoadReaderType, rune: var Rune): bool {.inline.} =
  let size = peekCount(reader, rune)
  if size == 0:
    return false
  result = true
  unsafeNext(reader, last = rune)

proc next*(reader: var LoadReaderType): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator chars*(reader: var LoadReaderType): char =
  var c: char
  while peek(reader, c):
    yield c
    unsafeNext(reader)

iterator peekNext*(reader: var LoadReaderType): char {.deprecated.} =
  ## deprecated alias for `chars`
  for c in chars(reader):
    yield c

proc peekMatch*(reader: var LoadReaderType, c: char): bool {.inline.} =
  var c2: char
  if peek(reader, c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: var LoadReaderType, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    unsafeNext(reader)

proc peekMatch*(reader: var LoadReaderType, c: char, offset: int): bool {.inline.} =
  prepareBuffer(reader, 1 + offset)
  let bpos = reader.state.pos
  if bpos + 1 + offset < reader.currentBuffer.len:
    if c != reader.currentBuffer[bpos + 1 + offset]:
      return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var LoadReaderType, rune: Rune): bool {.inline.} =
  var rune2: Rune
  if peek(reader, rune2) and rune2 == rune:
    result = true
  else:
    result = false

proc nextMatch*(reader: var LoadReaderType, rune: Rune): bool {.inline.} =
  result = peekMatch(reader, rune)
  if result:
    unsafeNextBy(reader, size(rune))

proc peekMatch*(reader: var LoadReaderType, cs: set[char], c: var char): bool {.inline.} =
  if peek(reader, c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: var LoadReaderType, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    unsafeNext(reader)

proc peekMatch*(reader: var LoadReaderType, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = peekMatch(reader, cs, dummy)

proc nextMatch*(reader: var LoadReaderType, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = nextMatch(reader, cs, dummy)

proc peekMatch*(reader: var LoadReaderType, cs: set[char], offset: int, c: var char): bool {.inline.} =
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

proc peekMatch*(reader: var LoadReaderType, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = peekMatch(reader, cs, offset, dummy)

template peekMatchStrImpl(reader: var LoadReaderType, str: untyped, isStatic: bool = false) =
  prepareBuffer(reader, str.len)
  let bpos = reader.state.pos
  if bpos + str.len < reader.currentBuffer.len:
    when nimvm:
      for i in 0 ..< str.len:
        if str[i] != reader.currentBuffer[bpos + 1 + i]:
          return false
      result = true
    else:
      when not holoReaderMatchStrEqualMem or isStatic or defined(js) or defined(nimscript):
        for i in 0 ..< str.len:
          if str[i] != reader.currentBuffer[bpos + 1 + i]:
            return false
        result = true
      else:
        when isStatic:
          let str = str
        result = equalMem(unsafeAddr str[0], addr reader.currentBuffer[bpos + 1], str.len)
  else:
    result = false

proc peekMatch*(reader: var LoadReaderType, str: openArray[char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*[I](reader: var LoadReaderType, str: array[I, char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*(reader: var LoadReaderType, str: static string): bool {.inline.} =
  # maybe make a const array
  peekMatchStrImpl(reader, str, isStatic = true)

proc nextMatch*(reader: var LoadReaderType, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)

proc nextMatch*[I](reader: var LoadReaderType, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)

proc nextMatch*(reader: var LoadReaderType, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    unsafeNextBy(reader, str.len)
