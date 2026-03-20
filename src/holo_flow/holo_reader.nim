import hemodyne/syncvein, std/[streams, unicode]

const holoflowLineColumn* {.booldefine.} = true
  ## enables/disables line column tracking by default, has very little impact on performance

type HoloReader* = object
  doLineColumn*: bool = holoflowLineColumn
  vein*: Vein
  bufferLocks*: int
  bufferPos*: int
  line*, column*: int

{.push checks: off, stacktrace: off.}

proc initHoloReader*(doLineColumn = holoflowLineColumn): HoloReader {.inline.} =
  result = HoloReader(doLineColumn: doLineColumn)

template buffer*(writer: HoloWriter): string = writer.artery.buffer

proc startRead*(reader: var HoloReader, vein: Vein) {.inline.} =
  reader.vein = vein
  reader.bufferPos = -1
  reader.bufferLocks = 0
  reader.line = 1
  reader.column = 1

proc startRead*(reader: var HoloReader, str: string) {.inline.} =
  reader.startRead(initVein(str))

proc startRead*(reader: var HoloReader, stream: Stream, loadAmount = 4) {.inline.} =
  reader.startRead(initVein(stream, loadAmount))

proc loadBufferOne*(reader: var HoloReader) {.inline.} =
  let remove = reader.vein.loadBufferOne()
  reader.bufferPos -= remove

proc loadBufferBy*(reader: var HoloReader, n: int) {.inline.} =
  let remove = reader.vein.loadBufferBy(n)
  reader.bufferPos -= remove

proc peek*(reader: var HoloReader, c: var char): bool {.inline.} =
  let nextPos = reader.bufferPos + 1
  if nextPos < reader.vein.buffer.len:
    c = reader.vein.buffer[nextPos]
    result = true
  else:
    reader.loadBufferOne()
    if nextPos < reader.vein.buffer.len:
      c = reader.vein.buffer[nextPos]
      result = true
    else:
      result = false

proc unsafePeek*(reader: var HoloReader): char {.inline.} =
  result = reader.vein.buffer[reader.bufferPos + 1]

proc peek*(reader: var HoloReader, c: var char, offset: int): bool {.inline.} =
  let nextPos = reader.bufferPos + 1 + offset
  if nextPos < reader.vein.buffer.len:
    c = reader.vein.buffer[nextPos]
    result = true
  else:
    reader.loadBufferBy(1 + offset)
    if nextPos < reader.vein.buffer.len:
      c = reader.vein.buffer[nextPos]
      result = true
    else:
      result = false

proc unsafePeek*(reader: var HoloReader, offset: int): char {.inline.} =
  result = reader.vein.buffer[reader.bufferPos + 1 + offset]

proc peek*(reader: var HoloReader, rune: var Rune): bool {.inline.} =
  var start: char
  result = peek(reader, start)
  if result:
    result = false
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
    if reader.bufferPos + 1 + n >= reader.vein.buffer.len:
      reader.loadBufferBy(n)
    if reader.bufferPos + 1 + n < reader.vein.buffer.len:
      result = true
      fastRuneAt(reader.vein.buffer, reader.bufferPos + 1, rune, doInc = false)

template peekStrImpl(reader: var HoloReader, cs) =
  result = false
  let n = cs.len
  if reader.bufferPos + n >= reader.vein.buffer.len:
    reader.loadBufferBy(n)
  if reader.bufferPos + n < reader.vein.buffer.len:
    result = true
    for i in 0 ..< n:
      cs[i] = reader.vein.buffer[reader.bufferPos + 1 + i]

proc peek*(reader: var HoloReader, cs: var openArray[char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peek*[I](reader: var HoloReader, cs: var array[I, char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peekOrZero*(reader: var HoloReader): char {.inline.} =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: var HoloReader): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: var HoloReader, offset: int): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy, offset)

proc lockBuffer*(reader: var HoloReader) {.inline.} =
  inc reader.bufferLocks

proc unlockBuffer*(reader: var HoloReader) {.inline.} =
  doAssert reader.bufferLocks > 0, "unpaired buffer unlock"
  dec reader.bufferLocks

proc unsafeNext*(reader: var HoloReader) {.inline.} =
  # keep separate from next for now
  let prevPos = reader.bufferPos
  inc reader.bufferPos
  if reader.doLineColumn:
    let c = reader.vein.buffer[reader.bufferPos]
    if c == '\n' or (c == '\r' and reader.peekOrZero() != '\n'):
      inc reader.line
      reader.column = 1
    else:
      inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(prevPos)

proc unsafeNextBy*(reader: var HoloReader, n: int) {.inline.} =
  # keep separate from next for now
  inc reader.bufferPos, n
  if reader.doLineColumn:
    for i in reader.bufferPos - n + 1 ..< reader.bufferPos:
      let c = reader.vein.buffer[i]
      if c == '\n' or (c == '\r' and reader.vein.buffer[i + 1] != '\n'):
        inc reader.line
        reader.column = 1
      else:
        inc reader.column
    let cf = reader.vein.buffer[reader.bufferPos]
    if cf == '\n' or (cf == '\r' and reader.peekOrZero() != '\n'):
      inc reader.line
      reader.column = 1
    else:
      inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(reader.bufferPos - 1)

proc next*(reader: var HoloReader, c: var char): bool {.inline.} =
  # keep separate from unsafeNext for now
  if not peek(reader, c):
    return false
  let prevPos = reader.bufferPos
  inc reader.bufferPos
  if reader.doLineColumn:
    if c == '\n' or (c == '\r' and reader.peekOrZero() != '\n'):
      inc reader.line
      reader.column = 1
    else:
      inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(prevPos)
  result = true

proc next*(reader: var HoloReader, rune: var Rune): bool {.inline.} =
  if not peek(reader, rune):
    return false
  let prevPos = reader.bufferPos
  inc reader.bufferPos, size(rune)
  if reader.doLineColumn:
    if rune == Rune('\n') or (rune == Rune('\r') and reader.peekOrZero() != '\n'):
      inc reader.line
      reader.column = 1
    else:
      inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(prevPos)
  result = true

proc next*(reader: var HoloReader): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator peekNext*(reader: var HoloReader): char =
  var c: char
  while reader.peek(c):
    yield c
    reader.unsafeNext()

proc peekMatch*(reader: var HoloReader, c: char): bool {.inline.} =
  var c2: char
  if reader.peek(c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: var HoloReader, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: var HoloReader, c: char, offset: int): bool {.inline.} =
  if reader.bufferPos + 1 + offset >= reader.vein.buffer.len:
    reader.loadBufferBy(1 + offset)
  if reader.bufferPos + 1 + offset < reader.vein.buffer.len:
    if c != reader.vein.buffer[reader.bufferPos + 1 + offset]:
      return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var HoloReader, rune: Rune): bool {.inline.} =
  var rune2: Rune
  if reader.peek(rune2) and rune2 == rune:
    result = true
  else:
    result = false

proc nextMatch*(reader: var HoloReader, rune: Rune): bool {.inline.} =
  result = peekMatch(reader, rune)
  if result:
    reader.unsafeNextBy(size(rune))

proc peekMatch*(reader: var HoloReader, cs: set[char], c: var char): bool {.inline.} =
  if reader.peek(c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: var HoloReader, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: var HoloReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, dummy)

proc nextMatch*(reader: var HoloReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.nextMatch(cs, dummy)

proc peekMatch*(reader: var HoloReader, cs: set[char], offset: int, c: var char): bool {.inline.} =
  if reader.bufferPos + 1 + offset >= reader.vein.buffer.len:
    reader.loadBufferBy(1 + offset)
  if reader.bufferPos + 1 + offset < reader.vein.buffer.len:
    let c2 = reader.vein.buffer[reader.bufferPos + 1 + offset]
    if c2 in cs:
      c = c2
      return true
    result = false
  else:
    result = false

proc peekMatch*(reader: var HoloReader, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, offset, dummy)

template peekMatchStrImpl(reader: var HoloReader, str) =
  if reader.bufferPos + str.len >= reader.vein.buffer.len:
    reader.loadBufferBy(str.len)
  if reader.bufferPos + str.len < reader.vein.buffer.len:
    for i in 0 ..< str.len:
      if str[i] != reader.vein.buffer[reader.bufferPos + 1 + i]:
        return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var HoloReader, str: openArray[char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*[I](reader: var HoloReader, str: array[I, char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*(reader: var HoloReader, str: static string): bool {.inline.} =
  # maybe make a const array
  peekMatchStrImpl(reader, str)

proc nextMatch*(reader: var HoloReader, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*[I](reader: var HoloReader, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*(reader: var HoloReader, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

{.pop.}
