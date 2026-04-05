import ./reader_common
import std/unicode # just to expose API otherwise not used

export doLineColumn, line, column

when defined(js):
  type BufferView* = string
  type
    StateView* = ref ReadState
    TrackedStateView* = ref TrackedReadState
else:
  type BufferView* = object
    data*: ptr UncheckedArray[char]
    len*: int
  
  template `[]`*(a: BufferView, b: untyped): untyped = a.data[b]
  proc `[]`*(a: BufferView, b: Slice[int]): string =
    if b.b < b.a: return ""
    result = newString(b.b - b.a + 1)
    for i in b.a .. b.b:
      result[i] = a.data[i]
  #template `[]=`*(a: BufferView, b, c: untyped): untyped = a.data[b] = c
  template toOpenArray*(a: BufferView, i, j: untyped): untyped =
    a.data.toOpenArray(i, j)

  when holoReaderUseViews:
    type
      StateView* = var ReadState
      TrackedStateView* = var TrackedReadState
  else:
    type
      StateView* = ptr ReadState
      TrackedStateView* = ptr TrackedReadState

type
  # XXX actually makes sense for view reader to be generic over state here
  ViewReader* = object
    ## reader over a string view, to reduce pointer dereferences
    bufferView*: BufferView
    statePtr*: StateView
  TrackedViewReader* = object
    ## same as ViewReader but optionally tracks line/column
    bufferView*: BufferView
    statePtr*: TrackedStateView

{.push checks: off, stacktrace: off.}

template ViewReaderType: untyped = ViewReader
template ViewStateType: untyped = ReadState

include includes/view_reader_impl

type ViewedState* = viewed(ReadState)

proc initViewReader*(originalState: ViewedState): ViewReader {.inline.} =
  result = ViewReader()
  result.stateSource = originalState

template ViewReaderType: untyped {.redefine.} = TrackedViewReader
template ViewStateType: untyped {.redefine.} = TrackedReadState

include includes/view_reader_impl

type ViewedTrackedState* = viewed(TrackedReadState)

proc initTrackedViewReader*(originalState: ViewedTrackedState): TrackedViewReader {.inline.} =
  result = TrackedViewReader()
  result.stateSource = originalState

{.pop.}
