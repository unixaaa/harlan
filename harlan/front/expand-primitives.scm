(library
  (harlan front expand-primitives)
  (export expand-primitives)
  (import
    (rnrs)
    (elegant-weapons helpers)
    (elegant-weapons compat)
    (only (chezscheme) printf trace-define))

  (define externs (make-parameter '()))

  (define (add-externs prim)
    (case prim
      ((write-pgm)
       (externs
        (append
         `((extern open_outfile (str) -> (ptr ofstream))
           (extern close_outfile ((ptr ofstream)) -> void))
         (externs))))))

  (define-match expand-primitives
    ((module ,[expand-prim-decl -> decl*] ...)
     `(module ,(externs) ... ,decl* ...)))
  
  (define-match expand-prim-decl
    ((fn ,name ,args ,t ,[expand-prim-stmt -> stmt])
     `(fn ,name ,args ,t ,stmt))
    ((extern ,name ,args -> ,rtype)
     `(extern ,name ,args -> ,rtype)))

  (define-match expand-prim-stmt
    ((let ((,x* ,t* ,[expand-prim-expr -> e*]) ...) ,[body])
     `(let ((,x* ,t* ,e*) ...) ,body))
    ((set! ,[expand-prim-expr -> lhs] ,[expand-prim-expr -> rhs])
     `(set! ,lhs ,rhs))
    ((vector-set! ,t
      ,[expand-prim-expr -> v]
      ,[expand-prim-expr -> i]
      ,[expand-prim-expr -> e])
     `(vector-set! ,t ,v ,i ,e))
    ((if ,[expand-prim-expr -> test] ,[conseq] ,[altern])
     `(if ,test ,conseq ,altern))
    ((if ,[expand-prim-expr -> test] ,[conseq])
     `(if ,test ,conseq))
    ((while ,[expand-prim-expr -> test] ,[body])
     `(while ,test ,body))
    ((for (,x ,[expand-prim-expr -> start]
              ,[expand-prim-expr -> stop]
              ,[expand-prim-expr -> step]) ,[body])
     `(for (,x ,start ,stop ,step) ,body))
    ((begin ,[stmt*] ...)
     `(begin . ,stmt*))
    ((print (vec ,t) ,[expand-prim-expr -> e]
            ,[expand-prim-expr -> stream])
     (expand-print t e stream))
    ((print (vec ,t) ,[expand-prim-expr -> e])
     (expand-print t e))
    ((print ,t ,[expand-prim-expr -> e] ...)
     `(print . ,e))
    ((assert ,[expand-prim-expr -> e])
     `(assert ,e))
    ((return) `(return))
    ((return ,[expand-prim-expr -> e])
     `(return ,e))
    ((do ,[expand-prim-expr -> e])
     `(do ,e))
    ((write-pgm ,file ,data)
     (expand-write-pgm file data)))
  
  (define-match expand-prim-expr
    ((,t ,v) (guard (scalar-type? t)) `(,t ,v))
    ((var ,t ,x) `(var ,t ,x))
    ((int->float ,[e]) `(int->float ,e))
    ((iota ,[e])
     (let ((i (gensym 'i))
           (x (gensym 'x))
           (vlen (gensym 'vlen)))
       `(let ((,vlen int ,e))
          (let ((,x (vec int) (make-vector int (var int ,vlen))))
            (begin
              (for (,i (int 0) (var int ,vlen) (int 1))
                   (vector-set! int (var (vec int) ,x) (var int ,i) (var int ,i)))
              (var (vec int) ,x))))))
    ((vector ,t ,[e*] ...)
     (let ((x (gensym 'x)))
       `(let ((,x (vec ,t) (make-vector ,t (int ,(length e*)))))
          ,(make-begin
            (let loop ((e* e*) (i 0))
              (if (null? e*)
                  `((var (vec ,t) ,x))
                  `((vector-set!
                     ,t (var (vec ,t) ,x) (int ,i) ,(car e*))
                    . ,(loop (cdr e*) (+ 1 i)))))))))
    ((make-vector ,t ,[e])
     `(make-vector ,t ,e))
    ((vector-ref ,t ,[v] ,[i])
     `(vector-ref ,t ,v ,i))
    ((length ,[e])
     `(length ,e))
    ((call ,[f] ,[args] ...)
     `(call ,f . ,args))
    ((if ,[test] ,[conseq] ,[altern])
     `(if ,test ,conseq ,altern))
    ((if ,[test] ,[conseq])
     `(if ,test ,conseq))
    ((reduce ,t ,op ,[e])
     (let ((i (gensym 'i))
           (v (gensym 'v))
           (x (gensym 'x)))
       `(let ((,v ,t ,e))
          (let ((,x int (vector-ref ,t (var ,t ,v) (int 0))))
            (begin
              (for (,i (int 1) (length (var ,t ,v)) (int 1))
                   (set! (var int ,x)
                         (,op (var int ,x)
                              (vector-ref ,t (var ,t ,v) (var int ,i)))))
              (var int ,x))))))
    ((kernel ,ktype (((,x ,t) (,[xs] ,ts)) ...) ,[body])
     `(kernel ,ktype (((,x ,t) (,xs ,ts)) ...) ,body))
    ((let ((,x* ,t* ,[e*]) ...) ,[e])
     `(let ((,x* ,t* ,e*) ...) ,e))
    ((begin ,[expand-prim-stmt -> s*] ... ,[e])
     `(begin ,s* ... ,e))
    ((+ (vec ,t) ,[lhs] ,[rhs])
     (expand-vec-addition t lhs rhs))
    ((= (vec ,t) ,[lhs] ,[rhs])
     (expand-vec-comparison t lhs rhs))
    ((,op ,t ,[lhs] ,[rhs])
     (guard (or (relop? op) (binop? op)))
     `(,op ,lhs ,rhs)))

  (define (expand-print t e . stream)
    (let ((v (gensym 'v)) 
          (i (gensym 'i)))
      `(let ((,v (vec ,t) ,e))
         (begin
           (print (str "[") . ,stream)
           (for (,i (int 0) (length (var (vec ,t) ,v)) (int 1))
                (begin
                  ,(if (scalar-type? t)
                       `(if (> (var int ,i) (int 0))
                            (print (str " ") . ,stream))
                       `(if (> (var int ,i) (int 0))
                            (print (str " \n ") . ,stream)))
                  ,(expand-prim-stmt
                    `(print ,t
                            (vector-ref ,t
                                        (var (vec ,t) ,v) (var int ,i))
                            . ,stream))))
           (print (str "]") . ,stream)))))

  (define (expand-write-pgm file data)
    (let ((p (gensym 'p))
          (f (gensym 'file))
          (i (gensym 'i))
          (stream (gensym 'stream)))
      (add-externs 'write-pgm)
      `(let ((,f str ,file))
         (let ((,stream (ptr ofstream)
                        (call (var ((str) -> (ptr ofstream)) open_outfile)
                              (var str ,f))))
           (begin
             (print (str "P2\n") (var ofstream ,stream))
             (print (str "1024 1024\n") (var ofstream ,stream))
             (print (str "255\n") (var ofstream ,stream))
             (for (,i (int 0) (* (int 1024) (int 1024)) (int 1))
                  (let ((,p int (vector-ref int
                                            (vector-ref (vec int)
                                                        ,data
                                                        (/ (var int ,i) (int 1024)))
                                            (mod (var int ,i) (int 1024)))))
                    (begin
                      (if (< (var int ,p) (int 0))
                          (set! (var int ,p) (int 0))
                          (if (> (var int ,p) (int 255))
                              (set! (var int ,p) (int 255))))
                      (print (var int ,p)
                             (var ofstream ,stream)))))
             (print (str " ") (var ofstream ,stream))
             (do (call (var (((ptr ofstream)) -> void) close_outfile)
                       (var (ptr ofstream) ,stream))))))))

  (define (expand-vec-addition t lhs rhs)
    (let ((l (gensym 'lhs))
          (r (gensym 'rhs))
          (len (gensym 'len))
          (i (gensym 'i))
          (res (gensym 'res))
          (lhsi (gensym 'lhsi))
          (rhsi (gensym 'rhsi)))
      `(let ((,l (vec ,t) ,lhs)
             (,r (vec ,t) ,rhs))
         (let ((,len int (length (var (vec ,t) ,l))))
           (let ((,res (vec ,t) (make-vector ,t (var int ,len))))
             (begin
               (for (,i (int 0) (var int ,len) (int 1))
                    (let ((,lhsi
                           ,t
                           (vector-ref ,t (var (vec ,t) ,l)
                                       (var int ,i)))
                          (,rhsi
                           ,t
                           (vector-ref ,t (var (vec ,t) ,r)
                                       (var int ,i))))
                      (vector-set! ,t (var (vec ,t) ,res)
                                   (var int ,i)
                                   ,(expand-prim-expr
                                     `(+ ,t (var ,t ,lhsi) (var ,t ,rhsi))))))
               (var (vec ,t) ,res)))))))

  (define (expand-vec-comparison t lhs rhs)
    (let ((l (gensym 'lhs))
          (r (gensym 'rhs))
          (len (gensym 'len))
          (i (gensym 'i))
          (res (gensym 'res))
          (lhsi (gensym 'lhsi))
          (rhsi (gensym 'rhsi)))
      `(let ((,l (vec ,t) ,lhs)
             (,r (vec ,t) ,rhs))
         (let ((,len int (length (var (vec ,t) ,l)))
               (,res bool (bool #t)))
           (begin
             (if (= (var int ,len)
                    (length (var (vec ,t) ,r)))
                 (for (,i (int 0) (var int ,len) (int 1))
                      (let ((,lhsi ,t
                                   (vector-ref ,t (var (vec ,t) ,l)
                                               (var int ,i)))
                            (,rhsi ,t
                                   (vector-ref ,t (var (vec ,t) ,r)
                                               (var int ,i))))
                        (if (= ,(expand-prim-expr
                                 `(= ,t (var ,t ,lhsi) (var ,t ,rhsi)))
                               (bool #f))
                            (begin (set! (var bool ,res) (bool #f))
                                   (set! (var int ,i) (var int ,len))))))
                 (set! (var bool ,res) (bool #f)))
             (var bool ,res))))))

  ;; end library
  )
