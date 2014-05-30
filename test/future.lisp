(in-package :cl-async-future-test)
(in-suite cl-async-future-test)

;; TODO: finishing, forwarding, error handling, syntax macros, attach with value
;; vs future (immediate finish)

(test make-future
  "Test that make-future returns a future, also test futurep"
  (is (futurep (make-future)))
  (is (futurep (make-future :preserve-callbacks t :reattach-callbacks nil)))
  (is (not (futurep 'hai)))
  (is (not (futurep "omg, WHERE did you get those shoes?!")))
  (is (not (futurep nil))))

(test future-callbacks
  "Test that finishing a future fires its callbacks, also test multiple callbacks"
  (let ((future (make-future))
        (res1 nil)
        (res2 nil))
    (attach future
      (lambda (x)
        (setf res1 (+ 3 x))))
    (attach future
      (lambda (x)
        (setf res2 (+ 7 x))))
    (finish future 5)
    (is (= res1 8))
    (is (= res2 12))))

(test future-errbacks
  "Test that errbacks are fired (also test multiple errbacks)"
  (let ((future (make-future))
        (fired1 nil)
        (fired2 nil))
    (attach-errback future
      (lambda (ev)
        (setf fired1 ev)))
    (attach-errback future
      (lambda (ev)
        (setf fired2 ev)))
    (signal-error future 'omg-lol-wtf)
    (is (eq fired1 'omg-lol-wtf))
    (is (eq fired2 'omg-lol-wtf))))

(defun future-gen (&rest vals)
  (let ((future (make-future)))
    (as:delay (lambda () (apply #'finish (append (list future) vals)))
              :time .2
              :event-cb (lambda (ev) (signal-error future ev)))
    future))

(test future-alet
  "Test that the alet macro functions correctly"
  (let ((time-start nil))  ; tests that alet bindings happen in parallel
    (multiple-value-bind (val-x val-y)
        (async-let ((val-x nil)
                    (val-y nil))
          (setf time-start (get-internal-real-time))
          (alet ((x (future-gen 5))
                 (y (future-gen 2)))
            (setf val-x x
                  val-y y)))
      (is (<= .19 (/ (- (get-internal-real-time) time-start) internal-time-units-per-second) .22))
      (is (= val-x 5))
      (is (= val-y 2)))))

(test future-alet*
  "Test that the alet* macro functions correctly"
  (let ((time-start nil))  ; tests that alet bindings happen in sequence
    (multiple-value-bind (val-x val-y)
        (async-let ((val-x nil)
                    (val-y nil))
          (setf time-start (get-internal-real-time))
          (alet* ((x (future-gen 5))
                  (y (future-gen (+ 2 x))))
            (setf val-x x
                  val-y y)))
      (let ((alet*-run-time (/ (- (get-internal-real-time) time-start) internal-time-units-per-second)))
        (is (<= .38 alet*-run-time .42))
        (is (= val-x 5))
        (is (= val-y 7))))))

(test future-multiple-future-bind
  "Test multiple-future-bind macro"
  (multiple-value-bind (name age)
      (async-let ((name-res nil)
                  (age-res nil))
        (multiple-future-bind (name age)
            (future-gen "andrew" 69)
          (setf name-res name
                age-res age)))
    (is (string= name "andrew"))
    (is (= age 69))))

(test future-wait-for
  "Test wait-for macro"
  (multiple-value-bind (res1 res2)
      (async-let ((res1 nil)
                  (res2 nil))
        (wait-for (future-gen nil)
          (setf res1 2))
        (wait-for (future-gen nil)
          (setf res2 4)))
    (is (= res1 2))
    (is (= res2 4))))

(define-condition test-error-lol (error) ())

(test future-handler-case
  "Test future error handling"
  (multiple-value-bind (err1 err2)
      (async-let ((err1 nil)
                  (err2 nil))
        (future-handler-case
          (future-handler-case
            (alet ((x (future-gen 'sym1)))
              (+ x 7))
            (type-error (e)
              (setf err1 e)))
          (t (e)
            (declare (ignore e))
            (setf err1 :failwhale)))
        (future-handler-case
          (future-handler-case
            (multiple-future-bind (name age)
                (future-gen "leonard" 69)
              (declare (ignore name age))
              (error (make-instance 'test-error-lol)))
            (type-error (e)
              (setf err2 e)))
          (t (e)
            (setf err2 e))))
    (is (subtypep (type-of err1) 'type-error))
    (is (subtypep (type-of err2) 'test-error-lol))))

(test forwarding
  "Test future forwarding"
  (flet ((get-val ()
           (alet ((x 4))
             (alet ((y (+ x 4)))
               (+ x y)))))
    (alet ((res (get-val)))
      (is (= res 12)))))


;; -----------------------------------------------------------------------------
;; test error propagation
;; -----------------------------------------------------------------------------

(defun fdelay (val)
  (let ((future (make-future)))
    (finish future (+ val 1))
    future))

(defmacro defafun (name (future-bind) args &body body)
  `(defun ,name ,args
     (let ((,future-bind (make-future)))
       (future-handler-case
         (progn ,@body)
         (t (e)
           (signal-error ,future-bind e)))
       ,future-bind)))

(defafun async2 (future) (a)
  (alet* ((z (fdelay a))
          (b (+ z 1)))
    (finish future (+ b "5"))))

(defafun async1 (future) (a)
  (alet* ((x (fdelay a))
          (y (async2 x)))
    (finish future y)))

(test error-propagation
  "Test error propagation"
  (let ((error-triggered nil))
    (future-handler-case
      (attach (async1 1)
        (lambda (_)
          (declare (ignore _))
          (setf error-triggered nil)))
      (t (e)
        (setf error-triggered t)
        (is (typep e 'type-error))))
    (is (eq t error-triggered))))

