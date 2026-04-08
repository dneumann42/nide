type WidgetRef*[T] = object
  h*: pointer

proc capture*[T](w: T): WidgetRef[T] = WidgetRef[T](h: w.h)
proc get*[T](wr: WidgetRef[T]): T = T(h: wr.h, owned: false)
proc isNil*[T](wr: WidgetRef[T]): bool = wr.h == nil
