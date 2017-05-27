(in-package :hu.dwim.zlib/test)

(defun make-random-ub8-vector (length &optional (mode :semi))
  (let* ((length (+ (/ length 2) (random length)))
         (vector (cffi:make-shareable-byte-vector length)))
    ;; TODO when it's fully random it triggers errors with the :gzip container
    (ecase mode
      (:random
       (loop
         :for index :from 0 :below length
         :do (setf (aref vector index) (random 255))
         :finally (return t)))
      (:semi
       ;; initialize first half to random, second half to zero
       (loop
         :for index :from 0 :below (floor length 2)
         :do (setf (aref vector index) (random 255)))
       (loop
         :for index :from (floor length 2) :below length
         :do (setf (aref vector index) 0))
       t))
    vector))

(defun compare-vectors (v1 v2 &key (start1 0) (start2 0) (end1 (length v1)) (end2 (length v2)))
  (check-type start1 (integer 0))
  (check-type start2 (integer 0))
  (check-type end1 (integer 0))
  (check-type end2 (integer 0))
  (assert (<= end1 (length v1)))
  (assert (<= start1 end1))
  (assert (<= end2 (length v2)))
  (assert (<= start2 end2))
  (and (= (- end1 start1)
          (- end2 start2))
       (loop
         :for index1 :from start1 :below end1
         :for index2 :from start2 :below end2
         :do (unless (eql (aref v1 index1) (aref v2 index2))
               (return nil))
         :finally (return t))))

(deftest test/deflate-random-bytes (&key (repeat 300000))
  (declare (optimize (debug 3)))
  (flet ((random-buffer-size ()
           (+ 8 (random 128))))
    (loop
      :with min-window-bits = 8 ; this could be 8 theoretically (or 9, see zlib docs), but below 12 it triggers often. TODO maybe zlib bugs?
      :repeat repeat
      :for source = (make-random-ub8-vector 256)
      :for source-length = (length source)
      :for count :upfrom 0
      :for level = (random |Z_BEST_COMPRESSION|)
      :for window-bits = (+ min-window-bits (random (- |MAX_WBITS| min-window-bits)))
      :for container = (alexandria:random-elt '(:raw :zlib :gzip))
      :for compress-buffer-size = (random-buffer-size)
      :for decompress-buffer-size = (random-buffer-size)
      :for start = (random (floor source-length 2))
      :for end = (- source-length (random (max 1 (floor source-length 8))))
      :do (when (and (eq container :gzip)
                     (zerop level))
            ;; TODO this is probably a zlib bug
            (setf level 1))
      :do (when (and (not (eq container :zlib))
                     (eql window-bits 8))
            ;; see zlib docs
            (setf window-bits 9))
      :do (multiple-value-bind (compressed compressed-length)
              (deflate-sequence source :start start :end end :buffer-size compress-buffer-size :level level :window-bits window-bits :container container)
            (multiple-value-bind (decompressed decompressed-length)
                (inflate-sequence compressed :end compressed-length :buffer-size decompress-buffer-size :window-bits window-bits :container container)
              (is (eql (- end start) decompressed-length))
              (is (compare-vectors decompressed source :start1 0 :end1 decompressed-length :start2 start :end2 end)))))))
