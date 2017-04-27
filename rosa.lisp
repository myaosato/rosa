(in-package :cl-user)
(defpackage rosa
  (:use :cl
        :trivial-gray-streams)
  (:import-from :alexandria
                :plist-hash-table)
  (:import-from :anaphora
                :aif)
  (:export :index
           :indite
           :peruse
           :peruse-as-plist
           :pick))
(in-package :rosa)


(defmacro with-linereader ((instream) &body body)
  `(let ((linereader (if (subtypep (type-of ,instream)
                               'fundamental-character-input-stream)
                     #'(lambda () (multiple-value-bind (line eof)
                                      (stream-read-char ,instream)
                                    (and line eof)))
                     #'(lambda () (read-line ,instream nil :eof)))))
     (declare (ignorable linereader))
     ,@body))

(defun label-p (text)
  "label identifier is defined by regex \"[a-zA-Z][a-zA-Z0-9-_]*\""
  ;; but this impl depends on ASCII-like char-code...
  (labels ((identifier-first-char-p (ch)
             (let ((ch-code (char-code ch)))
               (or (and (<= (char-code #\a) ch-code)
                        (>= (char-code #\z) ch-code))
                   (and (<= (char-code #\A) ch-code)
                        (>= (char-code #\Z) ch-code)))))
           (identifier-char-p (ch)
             (let ((ch-code (char-code ch)))
               (or (identifier-first-char-p ch)
                   (and (<= (char-code #\0) ch-code)
                        (>= (char-code #\9) ch-code))
                   (char= ch #\_)
                   (char= ch #\-)))))
    (loop
       :for ch :across text
       :with first-p := t
       :always (if first-p
                   (progn
                     (setf first-p nil)
                     (identifier-first-char-p ch))
                   (identifier-char-p ch)))))

(defun escaped-line-p (line)
  (and (> (length line) 2)
       (or (char= (char line 1) #\:)
           (char= (char line 1) #\;))))

(defun remove-eol (string)
  "Remove EOL positioned in front of EOF"
  (let* ((tail-pos (1- (length string))))
    (cond ((< tail-pos 0) "")
          ((char= (char string tail-pos) #\newline)
           (subseq string 0 tail-pos))
          (t string))))

(defun push-body (hash label body)
  (let ((key (intern label :keyword)))
    (if (gethash key hash)
        (vector-push-extend body (gethash key hash))
        (let ((val (make-array 1 :initial-element body :fill-pointer 1 :adjustable t)))
          (setf (gethash key hash) val)))))

(defun peruse (stream)
  "parse stream and return parsed rosa data as hash table"
  (let ((rosa-data (make-hash-table))
        (block-label)
        (block-text))
    (labels ((update-state-as-inline (label text)
               (when block-label
                 (push-body rosa-data block-label
                            (remove-eol (get-output-stream-string block-text))))
               (setf block-label nil)
               (push-body rosa-data label text))
             (update-state-as-block (label)
               (when block-label
                 (push-body rosa-data block-label
                            (remove-eol (get-output-stream-string block-text))))
               (setf block-label label
                     block-text (make-string-output-stream)))
             (append-line-to-block (line)
               (when block-label
                 (format block-text "~a~%" line)))
             (colon-line (s)
               (if (escaped-line-p s)
                   (append-line-to-block (subseq s 1))
                   (aif (position #\space s)
                        (let ((label (subseq s 1 anaphora:it))
                              (text (subseq s (1+ anaphora:it))))
                          (if (label-p label)
                              (update-state-as-inline label text)
                              (append-line-to-block (format nil "~a ~a" label text))))
                        (let ((label (subseq s 1)))
                          (if (label-p label)
                              (update-state-as-block (subseq s 1))
                              (append-line-to-block label))))))
             (otherwise-line (s) (append-line-to-block s)))
      (with-linereader (stream)
        (loop :named parse
           :for line := (read-line stream nil :eof)
           :do (cond ((eq line :eof) (progn
                                       (update-state-as-block block-label)
                                       (return-from parse rosa-data)))
                     ((and (> (length line) 0)
                           (char= (char line 0) #\:))
                      (colon-line line))
                     ((and (> (length line) 0)
                           (char= (char line 0) #\;)) :do-nothing)
                     (t (otherwise-line line))))))))



(defmethod indite ((data hash-table))
  "write key-value data into string."
  (with-output-to-string (out)
    (labels ((block-p (s) (find #\newline s))
             (print-inline (name body)
               (format out ":~a ~a~%" name body))
             (print-block (name body)
               (format out ":~a~%~a~%" name
                       (with-output-to-string (out)
                         (with-input-from-string (in body)
                           (loop
                              :for ch := (read-char in nil :eof)
                              :until (eq ch :eof)
                              :do (cond ((char= ch #\:) (format out "::"))
                                        ((char= ch #\;) (format out ":;"))
                                        (t (write-char ch out))))))))
             (print-label (label-name body)
               (if (block-p body)
                   (print-block label-name body)
                   (print-inline label-name body))))
      (loop
         :for k :being :each :hash-keys :of data :using (:hash-value v)
         :do (if (stringp v)
                 (print-label k v)
                 (loop :for s :across v :do (print-label k s)))))))

(defmethod indite ((data list))
  "indite plist."
  (indite (plist-hash-table data)))

(defun peruse-as-plist (stream)
  "read key-value data as plist."
  (let ((data (peruse stream)))
    (loop
       :for k :being :each :hash-keys :of data :using (:hash-value v)
       :nconc (list k v))))

(defun index (stream)
  "returns all keys in `stream`."
  (let ((data (peruse stream)))
    (loop
       :for k :being :each :hash-keys :of data
       :collect k)))

(defun pick (stream label)
  "returns value corresponded `label`."
  (let ((data (peruse stream)))
    (gethash label data)))