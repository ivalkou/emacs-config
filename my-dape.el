;;; my-dape.el --- Dape debugger configuration -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'use-package)

(declare-function catppuccin-color "catppuccin-theme" (color))
(declare-function my-xcode-dape-compile "my-xcode" (command))

(defconst my-dape--swift-assertion-frame-regexp
  (regexp-opt '("_assertionFailure"
                "_preconditionFailure"
                "_swift_runtime_on_report"
                "_swift_stdlib_reportFatalError"))
  "Regexp matching Swift assertion runtime frames.")

(defvar my-dape--swift-assertion-connection nil)
(defvar my-dape--swift-assertion-request nil)

(defface my-dape-assertion-line-face '((t (:extend t)))
  "Face for the source line responsible for a Swift assertion.")

(defun my-dape--swift-assertion-caller (connection frames)
  "Return the first source frame after a Swift assertion in FRAMES."
  (let (caller-frames)
    (cl-loop for tail on frames
             when (string-match-p my-dape--swift-assertion-frame-regexp
                                  (or (plist-get (car tail) :name) ""))
             do (setq caller-frames (cdr tail)))
    (cl-find-if
     (lambda (frame)
       (when-let* ((remote-path (plist-get (plist-get frame :source) :path))
                   (path (dape--file-name-local connection remote-path)))
         (file-exists-p path)))
     caller-frames)))

(defun my-dape--reset-swift-assertion ()
  "Forget the Swift assertion state for the previous stop."
  (setq my-dape--swift-assertion-connection nil
        my-dape--swift-assertion-request nil))

(defun my-dape--detect-swift-assertion ()
  "Select and highlight the source frame responsible for a Swift assertion."
  (if-let* ((connection (dape--live-connection 'stopped t t))
            (thread (dape--current-thread connection)))
      (unless (eq connection (car-safe my-dape--swift-assertion-request))
        (let ((request (list connection)))
          (setq my-dape--swift-assertion-request request)
          (dape--stack-trace
           connection thread dape-stack-trace-levels
           (lambda (_body error)
             (when (eq request my-dape--swift-assertion-request)
               (setq my-dape--swift-assertion-request nil)
               (when (and (null error)
                          (eq (dape--state connection) 'stopped))
                 (let ((frame (my-dape--swift-assertion-caller
                               connection (plist-get thread :stackFrames))))
                   (setq my-dape--swift-assertion-connection
                         (and frame connection))
                   (when (and frame
                              (not (equal (plist-get frame :id)
                                          (plist-get
                                           (dape--current-stack-frame connection)
                                           :id))))
                     (dape-select-stack connection (plist-get frame :id))))))))))
    (my-dape--reset-swift-assertion)))

(defun my-dape-style-stopped-source ()
  "Use the Xcode-like execution marker in the current source buffer."
  (let ((indicators (copy-tree fringe-indicator-alist)))
    (setf (alist-get 'overlay-arrow indicators) 'my-dape-current-line)
    (setq-local fringe-indicator-alist indicators))
  (when (and (overlayp dape--stack-position-overlay)
             (eq (overlay-buffer dape--stack-position-overlay)
                 (current-buffer)))
    (overlay-put dape--stack-position-overlay 'face
                 (if (eq my-dape--swift-assertion-connection
                         dape--connection-selected)
                     'my-dape-assertion-line-face
                   'dape-source-line-face))))

(defun my-dape-breakpoint-symbol-indicator
    (original string bitmap face)
  "Render Dape breakpoints as STRING while preserving other indicators."
  (if (eq bitmap 'breakpoint)
      (let ((window-system nil))
        (funcall original string bitmap face))
    (funcall original string bitmap face)))

;; Debug Adapter Protocol — отладка через lldb-dap.
(use-package dape
  :ensure t
  :custom
  (dape-request-timeout 60)
  (dape-compile-function #'my-xcode-dape-compile)
  (dape-breakpoint-margin-string "●")
  :functions
  (dape--current-stack-frame
   dape--current-thread
   dape--file-name-local
   dape--live-connection
   dape--stack-trace
   dape--state
   dape-breakpoint-load
   dape-breakpoint-save
   dape-mouse-breakpoint-toggle
   dape-quit
   dape-restart
   dape-select-stack)
  :defines
  (dape--connection-selected
   dape--info-stack-font-lock-keywords
   dape--stack-position-overlay
   dape-stack-trace-levels)
  :config
  ;; Green marks ordinary stops; Swift assertion callers use a red row.
  (require 'color)
  (define-fringe-bitmap 'my-dape-current-line
    [#x80 #xc0 #xe0 #xf0 #xf8 #xfc #xfe #xff
     #xfe #xfc #xf8 #xf0 #xe0 #xc0 #x80]
    15 8 'center)
  (let* ((hex-to-rgb
          (lambda (hex)
            (mapcar (lambda (offset)
                      (/ (string-to-number
                          (substring hex offset (+ offset 2)) 16)
                         255.0))
                    '(1 3 5))))
         (base (funcall hex-to-rgb (catppuccin-color 'base)))
         (green (funcall hex-to-rgb (catppuccin-color 'green)))
         (red (funcall hex-to-rgb (catppuccin-color 'red)))
         (green-background
          (apply #'color-rgb-to-hex
                 (append (color-blend green base 0.18) '(2))))
         (red-background
          (apply #'color-rgb-to-hex
                 (append (color-blend red base 0.18) '(2)))))
    (set-face-attribute 'dape-source-line-face nil
                        :background green-background
                        :extend t)
    (set-face-attribute 'my-dape-assertion-line-face nil
                        :background red-background
                        :extend t))
  (add-hook 'dape-display-source-hook #'my-dape-style-stopped-source)
  (add-hook 'dape-stopped-hook #'my-dape--reset-swift-assertion)
  (add-hook 'dape-update-ui-hook #'my-dape--detect-swift-assertion t)
  (add-to-list 'dape--info-stack-font-lock-keywords
               (list (concat "^.*" my-dape--swift-assertion-frame-regexp ".*$")
                     '(0 'error prepend)))

  ;; A fringe can only display bitmaps, so render breakpoint indicators in
  ;; Dape's left margin instead.  Flymake and mouse handling keep their fringe.
  (advice-remove 'dape--indicator #'my-dape-breakpoint-symbol-indicator)
  (advice-add 'dape--indicator :around
              #'my-dape-breakpoint-symbol-indicator)
  (set-face-attribute 'dape-breakpoint-face nil
                      :foreground (catppuccin-color 'blue))
  (set-face-attribute 'dape-breakpoint-until-face nil
                      :foreground (catppuccin-color 'green))
  ;; Сохранять breakpoints между перезапусками Emacs.
  (add-hook 'kill-emacs-hook #'dape-breakpoint-save)
  (add-hook 'after-init-hook #'dape-breakpoint-load)
  (dape-breakpoint-global-mode 1)

  ;; Ctrl + click в левом fringe ставит/снимает breakpoint.
  ;; Обычный click остаётся у Flymake для diagnostics.
  (define-key dape-breakpoint-mode-map
              [left-fringe C-mouse-1]
              #'dape-mouse-breakpoint-toggle))

;; Компактное меню основных команд отладчика.
(use-package transient
  :ensure nil
  :after dape
  :bind ("C-c d" . my-dape-menu)
  :config
  (transient-define-prefix my-dape-menu ()
    "Show Dape debugger controls."
    [["Execution"
      ("c" "Continue" dape-continue)
      ("p" "Pause" dape-pause)
      ("n" "Next" dape-next)
      ("s" "Step in" dape-step-in)
      ("o" "Step out" dape-step-out)
      ("u" "Run until" dape-until)]
     ["Session"
      ("r" "Restart" dape-restart)
      ("q" "Stop" dape-quit)
      ("R" "REPL" dape-repl)
      ("i" "Info" dape-info)
      ("x" "Evaluate" dape-evaluate-expression)]
     ["Breakpoints"
      ("b" "Toggle" dape-breakpoint-toggle)
      ("B" "Remove all" dape-breakpoint-remove-all)
      ("e" "Conditional" dape-breakpoint-expression)
      ("l" "Logpoint" dape-breakpoint-log)]]))

(provide 'my-dape)
;;; my-dape.el ends here
