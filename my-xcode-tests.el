;;; my-xcode-tests.el --- Build cancellation checks -*- lexical-binding: t; -*-

;; Run: emacs --batch -Q -L . -l my-xcode-tests.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'my-xcode)

(ert-deftest my-xcode-stop-build-interrupts-project-workflow ()
  (let* ((root (file-name-as-directory (make-temp-file "xcode-stop-" t)))
         (pid-file (expand-file-name "child.pid" root))
         (launched (expand-file-name "launched" root))
         (my-xcode-project-selections (make-hash-table :test #'equal))
         (my-xcode--build-status nil)
         (my-xcode--build-mode-line-timer nil)
         buffer process child-pid)
    (unwind-protect
        (cl-letf (((symbol-function 'my-xcode--project-root) (lambda () root)))
          (setq buffer
                (my-xcode--start-compilation
                 "Cancellation Check"
                 (list (list "/bin/sh" "-c"
                             (format "/bin/sh -c %s; status=$?; exit $status"
                                     (shell-quote-argument
                                      (format "echo $$ > %s; exec sleep 60"
                                              (shell-quote-argument pid-file)))))
                       (list "/usr/bin/touch" launched)))
                process (get-buffer-process buffer))
          (let ((deadline (+ (float-time) 5)))
            (while (and (not (file-exists-p pid-file))
                        (< (float-time) deadline))
              (accept-process-output process 0.05)))
          (should (file-exists-p pid-file))
          (setq child-pid
                (with-temp-buffer
                  (insert-file-contents pid-file)
                  (string-to-number (buffer-string))))
          ;; Another project cannot cancel this project's compilation.
          (cl-letf (((symbol-function 'my-xcode--project-root)
                     (lambda () (concat root "other/"))))
            (should-error (my-xcode-stop-build) :type 'user-error))
          (should (process-live-p process))
          (call-interactively (keymap-lookup my-xcode-prefix-map "k"))
          (let ((deadline (+ (float-time) 5)))
            (while (and (process-live-p process) (< (float-time) deadline))
              (accept-process-output process 0.05)))
          (should-not (process-live-p process))
          (should-not (file-exists-p launched))
          (should (eq (plist-get my-xcode--build-status :state) 'stopped))
          (should-not my-xcode--build-mode-line-timer)
          (should-not (process-attributes child-pid))
          (should-error (my-xcode-stop-build) :type 'user-error))
      (when (and process (process-live-p process)) (delete-process process))
      (when (and child-pid (process-attributes child-pid))
        (ignore-errors (signal-process child-pid 'SIGKILL)))
      (my-xcode--stop-build-mode-line-timer)
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (delete-directory root t))))

;;; my-xcode-tests.el ends here
