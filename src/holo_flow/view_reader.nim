import ./reader_common
import std/unicode # just to expose API otherwise not used

export doLineColumn, line, column

when true or holoReaderDisableTracking:
  type StateType = ReadState
else:
  type StateType = TrackedReadState

when defined(js):
  type ViewBuffer* = string
  type StateView* = ref StateType
else:
  type ViewBuffer* = object
    data*: ptr UncheckedArray[char]
    len*: int
  
  template `[]`*(a: ViewBuffer, b: untyped): untyped = a.data[b]
  proc `[]`*(a: ViewBuffer, b: Slice[int]): string =
    if b.b < b.a: return ""
    result = newString(b.b - b.a + 1)
    for i in b.a .. b.b:
      result[i] = a.data[i]
  #template `[]=`*(a: ViewBuffer, b, c: untyped): untyped = a.data[b] = c
  template toOpenArray*(a: ViewBuffer, i, j: untyped): untyped =
    a.data.toOpenArray(i, j)

  when holoReaderUseViews:
    type StateView* = var StateType
  else:
    type StateView* = ptr StateType

type
  ViewReader* = object
    ## view type over the `LoadReader` type,
    ## to reduce pointer dereferences
    bufferView*: ViewBuffer
    statePtr*: StateView

when defined(js):
  template jsRawSet(a, b) =
    {.emit: [a, " = ", b, ";"].}

  template `buffer=`*(reader: ViewReader, s: string) =
    jsRawSet(reader.bufferView, s)

  type State = StateType
  template state*(reader: ViewReader): State =
    reader.statePtr[]
  template `stateSource=`*(reader: ViewReader, s: State) =
    jsRawSet(reader.statePtr, s)
  template `state=`*(reader: ViewReader, s: State) =
    reader.statePtr[] = s
else:
  template `buffer=`*(reader: ViewReader, s: string) =
    reader.bufferView = ViewBuffer(data: cast[ptr UncheckedArray[char]](cstring(s)), len: s.len)

  when StateView is ptr:
    type State = var StateType
    template state*(reader: ViewReader): var StateType =
      reader.statePtr[]
    template `stateSource=`*(reader: var ViewReader, s: State) =
      reader.statePtr = addr s
    template `state=`*(reader: ViewReader, s: State) =
      reader.statePtr[] = s
  elif holoReaderUseViews:
    type State = var StateType
    template state*(reader: ViewReader): var StateType =
      reader.statePtr
    template `stateSource=`*(reader: var ViewReader, s: State) =
      reader.statePtr = s
    template `state=`*(reader: ViewReader, s: State) =
      reader.statePtr = s
  else:
    {.error: "unknown way to handle state type: " & $ReaderState.}

template bufferPos*(reader: ViewReader): int = reader.state.pos
template currentBuffer*(reader: ViewReader): untyped =
  reader.bufferView

{.push checks: off, stacktrace: off.}

proc initViewReader*(originalState: State): ViewReader {.inline.} =
  result = ViewReader()
  result.stateSource = originalState

proc startRead*(reader: var ViewReader, str: string) {.inline.} =
  reader.buffer = str
  startRead(reader.state)

proc peek*(reader: ViewReader, c: var char): bool {.inline.} =
  let nextPos = reader.bufferPos + 1
  doPeek(reader.bufferView, reader.bufferView.len, nextPos, c, result)

proc unsafePeek*(reader: ViewReader): char {.inline.} =
  # this is extra unsafe
  result = reader.bufferView[reader.bufferPos + 1]

proc peek*(reader: ViewReader, c: var char, offset: int): bool {.inline.} =
  let nextPos = reader.bufferPos + 1 + offset
  doPeek(reader.bufferView, reader.bufferView.len, nextPos, c, result)

proc unsafePeek*(reader: ViewReader, offset: int): char {.inline.} =
  # this is extra unsafe
  result = reader.bufferView[reader.bufferPos + 1 + offset]

proc peekCount*(reader: ViewReader, rune: var Rune): int {.inline.} =
  ## returns rune size if rune is peeked
  let bpos = reader.bufferPos
  if bpos + 1 < reader.bufferView.len:
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
    if bpos + 1 + n < reader.bufferView.len:
      result = n
      fastRuneAt(reader.bufferView.toOpenArray(0, reader.bufferView.len - 1), bpos + 1, rune, doInc = false)

proc peek*(reader: ViewReader, rune: var Rune): bool {.inline.} =
  result = peekCount(reader, rune) != 0

template peekStrImpl(reader: ViewReader, cs) =
  result = false
  let n = cs.len
  let bpos = reader.bufferPos
  if bpos + n < reader.bufferView.len:
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

template lockBuffer*(reader: ViewReader) = discard

template unlockBuffer*(reader: ViewReader) = discard

proc unsafeNext*(reader: ViewReader) {.inline.} =
  reader.advance(reader.state)

proc unsafeNextBy*(reader: ViewReader, n: int) {.inline.} =
  reader.advanceBy(reader.state, n)

proc next*(reader: ViewReader, c: var char): bool {.inline.} =
  if not peek(reader, c):
    return false
  result = true
  reader.unsafeNext()

proc next*(reader: ViewReader, rune: var Rune): bool {.inline.} =
  let size = peekCount(reader, rune)
  if size == 0:
    return false
  result = true
  reader.unsafeNextBy(size)

proc next*(reader: ViewReader): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator chars*(reader: ViewReader): char =
  var c: char
  while reader.peek(c):
    yield c
    reader.unsafeNext()

iterator peekNext*(reader: ViewReader): char {.deprecated.} =
  ## deprecated alias for `chars`
  for c in chars(reader):
    yield c

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
  let bpos = reader.bufferPos
  if bpos + 1 + offset < reader.bufferView.len:
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
  let bpos = reader.bufferPos
  if bpos + 1 + offset < reader.bufferView.len:
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
  let bpos = reader.bufferPos
  if bpos + str.len < reader.bufferView.len:
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
