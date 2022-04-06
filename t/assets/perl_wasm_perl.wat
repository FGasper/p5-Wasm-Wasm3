(module
    ;; function import:
    (import "my" "func" (func $mf (param i32 i32) (result f64)))

    (func (export "callfunc") (result f64)
        i32.const 0  ;; pass offset 0 to log
        i32.const 2  ;; pass length 2 to log
        call $mf
    )
)
