;;; my-agent-shell.el --- Agent Shell configuration -*- lexical-binding: t; -*-

(require 'subr-x)
(require 'use-package)

(defun my-agent-shell-data-subdir (subdir)
  "Return SUBDIR under Emacs config, partitioned by project."
  (let* ((cwd (directory-file-name (agent-shell-cwd)))
         (project (replace-regexp-in-string
                   "/" "-" (string-remove-prefix "/" cwd))))
    (locate-user-emacs-file
     (file-name-concat "agent-shell" project subdir))))

(defvar-local my-agent-shell-auto-title-prompt nil
  "First prompt awaiting a persisted automatic OMP session title.")

(defun my-agent-shell-track-untitled-input (event)
  "Mark an untitled OMP session after a real user prompt EVENT."
  (let ((prompt (map-nested-elt event '(:data :prompt))))
    (when (and (not (map-nested-elt agent-shell--state '(:session :title)))
               (stringp prompt)
               (not (string-prefix-p "/" (string-trim-left prompt))))
      (setq my-agent-shell-auto-title-prompt
            (substring-no-properties prompt)))))

(defun my-agent-shell-generate-title (_event)
  "Ask OMP to persist an automatic title for an untitled session."
  (when-let* ((prompt my-agent-shell-auto-title-prompt))
    (setq my-agent-shell-auto-title-prompt nil)
    ;; OMP may eventually generate its own ACP title during the first turn.
    ;; Only repair the current behavior, where agent-shell's prompt seed remains.
    (when (equal prompt
                 (map-nested-elt agent-shell--state '(:session :title)))
      (when-let* ((client (map-elt agent-shell--state :client))
                  (session-id (map-nested-elt agent-shell--state '(:session :id))))
        (acp-send-request
         :client client
         :request (acp-make-session-prompt-request
                   :session-id session-id
                   :prompt (vector '((type . "text") (text . "/rename"))))
         :buffer (current-buffer)
         :on-success #'ignore
         :on-failure
         (lambda (_error raw-message)
           (when (equal session-id
                        (map-nested-elt agent-shell--state '(:session :id)))
             (setq my-agent-shell-auto-title-prompt prompt))
           (message "agent-shell: automatic session title failed: %S"
                    raw-message)))))))

(defun my-agent-shell-mode-setup ()
  "Apply local UI settings and automatic OMP session titles."
  (display-line-numbers-mode -1)
  (when (eq (map-nested-elt agent-shell--state
                            '(:agent-config :identifier))
            'omp)
    (agent-shell-subscribe-to
     :shell-buffer (current-buffer)
     :event 'input-submitted
     :on-event #'my-agent-shell-track-untitled-input)
    (agent-shell-subscribe-to
     :shell-buffer (current-buffer)
     :event 'turn-complete
     :on-event #'my-agent-shell-generate-title)))

;; Agent Shell: нативный Emacs-интерфейс к Oh My Pi через корпоративный proxy-скрипт.
(use-package agent-shell
  :ensure t
  :functions (agent-shell-cwd agent-shell-subscribe-to)
  :commands agent-shell
  :bind (("C-c a" . agent-shell)
         :map agent-shell-mode-map
         ("C-c q" . agent-shell-prompt-queue))
  :custom
  (agent-shell-preferred-agent-config 'omp)
  (agent-shell-session-strategy 'prompt)
  (agent-shell-display-action
   '((display-buffer-in-side-window)
     (side . right)
     (window-width . 0.4)))
  (agent-shell-dot-subdir-function #'my-agent-shell-data-subdir)
  (agent-shell-omp-acp-command
   (list (expand-file-name "~/omp-proxy.sh") "acp"))
  :hook (agent-shell-mode . my-agent-shell-mode-setup))

(provide 'my-agent-shell)
;;; my-agent-shell.el ends here
