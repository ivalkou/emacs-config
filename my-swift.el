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
;; в index store. Сначала открываем interface модуля через import, затем
;; находим точное объявление по USR.
(defun my-eglot-swift--lsp-items (response)
  "Return RESPONSE as a list of LSP items."
  (if (vectorp response) response (and response (list response))))

(defun my-eglot-swift--module-interface (server module)
  "Return SERVER's existing or generated interface location for MODULE."
  (or (seq-some
       (lambda (buffer)
         (with-current-buffer buffer
           (and buffer-file-name
                (string= (file-name-nondirectory buffer-file-name)
                         (concat module ".swiftinterface"))
                (eq server (eglot-current-server))
                `(:uri ,(eglot-path-to-uri buffer-file-name)))))
       (buffer-list))
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
                            (eglot--TextDocumentPositionParams))))))))

(defun my-eglot-swift--interface-xref (server interface symbol identifier)
  "Find SYMBOL's exact USR in INTERFACE and return an Eglot xref."
  (let* ((uri (or (plist-get interface :uri)
                  (plist-get interface :targetUri)))
         (path (and uri (eglot-uri-to-path uri)))
         (document-uri (and path (eglot-path-to-uri path)))
         (managed
          (when-let* ((buffer (and path (find-buffer-visiting path))))
            (with-current-buffer buffer
              (eq server (eglot-current-server)))))
         (usr (plist-get symbol :usr))
         (name (plist-get symbol :name))
         (regexp
          (if (string= identifier "init")
              "\\_<\\(init\\)\\_>[[:space:]]*("
            (format
             "\\_<\\(?:actor\\|associatedtype\\|case\\|class\\|enum\\|func\\|let\\|macro\\|protocol\\|struct\\|typealias\\|var\\)\\_>[^\n]*?\\_<\\(%s\\)"
             (regexp-quote identifier))))
         match)
    (when (and usr path (file-readable-p path))
      (let ((text (with-temp-buffer
                    (insert-file-contents path)
                    (buffer-string))))
        (unless managed
          (jsonrpc-notify
           server :textDocument/didOpen
           `(:textDocument (:uri ,document-uri :languageId "swift" :version 0
                           :text ,text))))
        (unwind-protect
            (with-temp-buffer
              (insert text)
              (goto-char (point-min))
              (while (and (not match) (re-search-forward regexp nil t))
                (let* ((start (match-beginning 1))
                       (position
                        `(:line ,(1- (line-number-at-pos start t))
                          :character ,(save-excursion
                                        (goto-char start)
                                        (current-column))))
                       (candidates
                        (my-eglot-swift--lsp-items
                         (eglot--request
                          server :textDocument/symbolInfo
                          `(:textDocument (:uri ,document-uri) :position ,position)))))
                  (when-let* ((candidate
                               (or (seq-find
                                    (lambda (item)
                                      (equal usr (plist-get item :usr)))
                                    candidates)
                                   ;; Objective-C extensions have another USR
                                   ;; in SourceKit's generated interface.
                                   (and (eq t (plist-get symbol :isDynamic))
                                        (seq-find
                                         (lambda (item)
                                           (equal name (plist-get item :name)))
                                         candidates)))))
                    (setq match
                          (or (plist-get candidate :bestLocalDeclaration)
                              `(:uri ,document-uri
                                :range (:start ,position :end ,position)))))))
              match)
          (unless managed
            (jsonrpc-notify server :textDocument/didClose
                            `(:textDocument (:uri ,document-uri)))))))
    (when match
      (eglot--collecting-xrefs (collect)
        (collect
         (eglot--xref-make-match
          name (plist-get match :uri) (plist-get match :range)))))))

(defun my-eglot-swift--framework-definition (identifier)
  "Return an interface definition for external Swift IDENTIFIER."
  (let* ((server (eglot--current-server-or-lose))
         (source-identifier (or (thing-at-point 'symbol t) identifier))
         (symbols
          (my-eglot-swift--lsp-items
           (eglot--request server :textDocument/symbolInfo
                           (eglot--TextDocumentPositionParams))))
         (symbol
          (or (seq-find
               (lambda (item)
                 (when-let* ((name (plist-get item :name)))
                   (and (plist-get item :systemModule)
                        (or (equal name source-identifier)
                            (string-prefix-p (concat source-identifier "(") name)))))
               symbols)
              (seq-find (lambda (item) (plist-get item :systemModule)) symbols)))
         (module (plist-get (plist-get symbol :systemModule) :moduleName))
         (interface (and module
                         (my-eglot-swift--module-interface server module))))
    (and interface
         (my-eglot-swift--interface-xref
          server interface symbol source-identifier))))

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
                     :relativePatternSupport t)))
      capabilities))

  ;; ponytail: удалить fallback, когда Xcode получит SourceKit-LSP 6.4+.
  (cl-defmethod xref-backend-definitions :around
    ((_backend (eql eglot)) identifier)
    (or (cl-call-next-method)
        (and (derived-mode-p 'swift-mode)
             (my-eglot-swift--framework-definition identifier)))))

(with-eval-after-load 'consult-eglot
  ;; SourceKit-LSP exposes ABI names such as `$s4App...'; they are not source
  ;; declarations and only obstruct workspace symbol search.
  (advice-remove 'consult-eglot--make-async-source
                 #'my-consult-eglot--filter-generated-symbols)
  (advice-add 'consult-eglot--make-async-source :around
              #'my-consult-eglot--filter-generated-symbols))

(provide 'my-swift)
;;; my-swift.el ends here
