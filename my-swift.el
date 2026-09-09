;;; my-swift.el --- Swift and SourceKit-LSP integration -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(require 'treesit)

;; swift-mode 10 пока не регистрирует grammar сам.
(add-to-list 'treesit-language-source-alist
             '(swift "https://github.com/alex-pinkus/tree-sitter-swift"
                     :revision "0.7.3-with-generated-files"
                     :copy-queries t))

(defun my-swift-treesit-setup ()
  "Установить и подключить Swift tree-sitter parser к текущему буферу."
  (when (treesit-ensure-installed 'swift)
    (treesit-parser-create 'swift)))

;; swift-mode отвечает за подсветку, tree-sitter — за структурное дерево.
(use-package swift-mode
  :ensure t
  :mode "\\.swift\\'"
  :hook ((swift-mode . my-swift-treesit-setup)
         (swift-mode . eglot-ensure)))

;; SourceKit-LSP 6.3 не открывает interfaces сторонних модулей, если их нет
;; в index store. Используем его reference-document API и сверяем объявления
;; по точному USR в корректном build context.
(defun my-eglot-swift--lsp-items (response)
  "Return RESPONSE as a list of LSP items."
  (if (vectorp response) response (and response (list response))))

(defvar-local my-eglot-swift--reference-uri nil)
(defvar-local my-eglot-swift--reference-server nil)

(defun my-eglot-swift--module-interface (server module)
  "Return SERVER's generated interface location for MODULE."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "\\_<import[[:space:]]+\\(%s\\)\\_>"
                   (regexp-quote module))
           nil t)
      (goto-char (match-beginning 1))
      (seq-first
       (my-eglot-swift--lsp-items
        (eglot--request server :textDocument/definition
                        (eglot--TextDocumentPositionParams)))))))

(defun my-eglot-swift--reference-buffer (server uri)
  "Return a read-only buffer for SERVER's reference document URI."
  (or (seq-find
       (lambda (buffer)
         (with-current-buffer buffer
           (and (eq my-eglot-swift--reference-server server)
                (equal my-eglot-swift--reference-uri uri))))
       (buffer-list))
      (let* ((content
              (plist-get
               (eglot--request server :workspace/getReferenceDocument
                               `(:uri ,uri))
               :content))
             (name (file-name-nondirectory
                    (car (split-string uri "[?]" t))))
             (buffer (generate-new-buffer (format "*%s*" name)))
             (move-function eglot-move-to-linepos-function)
             (position-function eglot-current-linepos-function))
        (with-current-buffer buffer
          (insert content)
          (let ((swift-mode-hook nil))
            (swift-mode))
          (font-lock-ensure)
          (setq buffer-read-only t)
          (setq-local eglot-move-to-linepos-function move-function)
          (setq-local eglot-current-linepos-function position-function)
          (setq-local my-eglot-swift--reference-server server)
          (setq-local my-eglot-swift--reference-uri uri)
          (add-hook
           'kill-buffer-hook
           (lambda ()
             (ignore-errors
               (jsonrpc-notify
                server :textDocument/didClose
                `(:textDocument (:uri ,uri)))))
           nil t))
        (jsonrpc-notify
         server :textDocument/didOpen
         `(:textDocument (:uri ,uri :languageId "swift" :version 0
                         :text ,content)))
        buffer)))

(defun my-eglot-swift--materialize-reference-xref (server item)
  "Make custom SourceKit reference ITEM visitable through SERVER."
  (when-let* ((location (xref-item-location item))
              ((xref-file-location-p location))
              (uri (xref-file-location-file location))
              ((string-prefix-p "sourcekit-lsp:" uri))
              (buffer (my-eglot-swift--reference-buffer server uri)))
    (with-current-buffer buffer
      (goto-char (point-min))
      (forward-line (1- (xref-file-location-line location)))
      (funcall eglot-move-to-linepos-function
               (xref-file-location-column location))
      (let* ((begin (point))
             (length (or (ignore-errors (xref-match-length item)) 0))
             (summary (buffer-substring
                       (line-beginning-position) (line-end-position))))
        (xref-make-match summary
                         (xref-make-buffer-location buffer begin)
                         length)))))

(defun my-eglot-swift--interface-xref (server interface symbol)
  "Find SYMBOL by exact USR in SERVER's generated INTERFACE."
  (let* ((uri (or (plist-get interface :uri)
                  (plist-get interface :targetUri)))
         (usr (plist-get symbol :usr))
         (name (plist-get symbol :name))
         (buffer (and uri
                      (my-eglot-swift--reference-buffer server uri)))
         (document-symbols
          (and buffer
               (eglot--request
                server :textDocument/documentSymbol
                `(:textDocument (:uri ,uri))))))
    (let (range)
      (when (and usr name document-symbols)
        (cl-labels
            ((find-range
              (items)
              (seq-some
               (lambda (item)
                 (or
                  (when-let* (((equal name (plist-get item :name)))
                              (selection (plist-get item :selectionRange))
                              (position (plist-get selection :start))
                              (candidate
                               (seq-find
                                (lambda (value)
                                  (equal usr (plist-get value :usr)))
                                (my-eglot-swift--lsp-items
                                 (eglot--request
                                  server :textDocument/symbolInfo
                                  `(:textDocument (:uri ,uri)
                                    :position ,position))))))
                    selection)
                  (find-range (plist-get item :children))))
               items)))
          (setq range (find-range document-symbols))))
      (when range
        (with-current-buffer buffer
          (pcase-let ((`(,begin . ,end) (eglot-range-region range)))
            (goto-char begin)
            (list
             (xref-make-match
              (buffer-substring (line-beginning-position) (line-end-position))
              (xref-make-buffer-location buffer begin)
              (- end begin)))))))))

(defun my-eglot-swift--framework-definition (identifier)
  "Return an interface definition for external Swift IDENTIFIER."
  (let* ((server (eglot--current-server-or-lose))
         (source-identifier (or (thing-at-point 'symbol t) identifier))
         (symbols
          (my-eglot-swift--lsp-items
           (eglot--request server :textDocument/symbolInfo
                           (eglot--TextDocumentPositionParams))))
         (symbol
          (seq-find
           (lambda (item)
             (when-let* ((name (plist-get item :name)))
               (and (plist-get item :systemModule)
                    (or (equal name source-identifier)
                        (string-prefix-p
                         (concat source-identifier "(") name)))))
           symbols))
         (module (plist-get (plist-get symbol :systemModule) :moduleName))
         (interface (and module
                         (my-eglot-swift--module-interface server module))))
    (and interface
         (my-eglot-swift--interface-xref server interface symbol))))

(defun my-consult-eglot--generated-swift-symbol-p (symbol-info)
  "Return non-nil when SYMBOL-INFO names a Swift mangled symbol."
  (when-let* ((name (plist-get symbol-info :name)))
    (string-match-p "\\`_?\\$s" name)))

(defun my-consult-eglot--filter-generated-symbols (original servers)
  "Remove generated Swift symbols from ORIGINAL source using SERVERS."
  (let ((source (funcall original servers)))
    (lambda (sink)
      (let ((handler (funcall source sink)))
        (lambda (action)
          (if (stringp action)
              (let ((request (symbol-function 'jsonrpc-async-request)))
                (cl-letf (((symbol-function 'jsonrpc-async-request)
                           (lambda (connection method params &rest arguments)
                             (when (and (eq method :workspace/symbol)
                                        (assq 'swift-mode
                                              (eglot--languages connection)))
                               (when-let* ((success
                                            (plist-get arguments :success-fn)))
                                 (setq arguments
                                       (plist-put
                                        arguments :success-fn
                                        (lambda (response)
                                          (funcall
                                           success
                                           (seq-remove
                                            #'my-consult-eglot--generated-swift-symbol-p
                                            response)))))))
                             (apply request connection method params arguments))))
                  (funcall handler action)))
            (funcall handler action)))))))

(with-eval-after-load 'eglot
  ;; xcrun выбирает SourceKit-LSP из активного Xcode/DEVELOPER_DIR.
  (add-to-list 'eglot-server-programs
               '((swift-mode :language-id "swift")
                 . ("xcrun" "sourcekit-lsp")))

  ;; Recursive file watches exhaust macOS GUI file descriptors in this repo.
  ;; Open-buffer changes still reach SourceKit-LSP through standard LSP sync.
  (cl-defmethod eglot-client-capabilities :around ((server eglot-lsp-server))
    (let ((capabilities (cl-call-next-method)))
      (when (assq 'swift-mode (eglot--languages server))
        (plist-put (plist-get capabilities :workspace)
                   :didChangeWatchedFiles
                   '(:dynamicRegistration :json-false
                     :relativePatternSupport t))
        (setq capabilities
              (plist-put
               capabilities :experimental
               '(:workspace/getReferenceDocument (:supported t)))))
      capabilities))

  ;; ponytail: удалить fallback, когда Xcode получит SourceKit-LSP 6.4+.
  (cl-defmethod xref-backend-definitions :around
    ((_backend (eql eglot)) identifier)
    (let ((definitions (cl-call-next-method)))
      (if (derived-mode-p 'swift-mode)
          (let ((server (eglot--current-server-or-lose)))
            (or (and definitions
                     (mapcar
                      (lambda (item)
                        (or (my-eglot-swift--materialize-reference-xref
                             server item)
                            item))
                      definitions))
                (my-eglot-swift--framework-definition identifier)))
        definitions))))

(with-eval-after-load 'consult-eglot
  ;; SourceKit-LSP exposes ABI names such as `$s4App...'; they are not source
  ;; declarations and only obstruct workspace symbol search.
  (advice-remove 'consult-eglot--make-async-source
                 #'my-consult-eglot--filter-generated-symbols)
  (advice-add 'consult-eglot--make-async-source :around
              #'my-consult-eglot--filter-generated-symbols))

(provide 'my-swift)
;;; my-swift.el ends here
