;;; init.el --- Personal Emacs configuration -*- lexical-binding: t; -*-
;; Lexical binding ограничивает локальные переменные их областью видимости
;; и позволяет замыканиям безопасно сохранять значения.

(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file t)

;; Не открывать окно предупреждений native-compiler, но сохранять их в журнале.
(with-eval-after-load 'comp-run
  (customize-set-variable 'native-comp-async-report-warnings-errors 'silent))

;; Показывать номера строк во всех буферах.
(global-display-line-numbers-mode t)

;; Подсвечивать текущую строку курсора.
(global-hl-line-mode t)

;; Курсор в виде вертикальной линии.
(setq-default cursor-type 'bar)

(set-face-attribute 'default nil :family "Hack Nerd Font Mono" :height 150)

;; Настройка клавиш Command и Option на macOS.
;; Command работает как Meta (M-), Option остаётся для ввода спецсимволов.
(setq mac-command-modifier 'meta)
(setq mac-option-modifier 'none)
(global-unset-key (kbd "C-z"))

;; Добавление репозитория MELPA к стандартным архивам пакетов.
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

;; Telephone-line: красивая строка статуса со стрелками.
(use-package telephone-line
  :ensure t
  :config
  (telephone-line-mode 1))

;; exec-path-from-shell: переносит PATH и другие переменные из shell в Emacs.
;; Запускать его только для GUI и daemon на macOS: терминальный Emacs уже
;; наследует окружение от родительского shell.
(use-package exec-path-from-shell
  :ensure t
  :if (and (eq system-type 'darwin)
           (or (display-graphic-p) (daemonp)))
  :config
  (exec-path-from-shell-initialize))

;; Тема Catppuccin (вариант mocha используется по умолчанию).
(use-package catppuccin-theme
  :ensure t
  :functions (catppuccin-color)
  :config
  (load-theme 'catppuccin t)
  ;; Разделители окон того же цвета, что и затемнённый текст.
  (let ((text-color (face-foreground 'shadow nil t)))
    (dolist (face '(window-divider
                    window-divider-first-pixel
                    window-divider-last-pixel
                    vertical-border))
      (set-face-attribute face nil :foreground text-color)))
  ;; Подсветка парных скобок цветом и фоном.
  ;; Настройка после загрузки темы, чтобы тема не перебила её.
  (set-face-attribute 'show-paren-match nil
                      :background "#6c7086"
                      :foreground "#a6e3a1"
                      :weight 'bold))

;; Org mode: настройка органайзера.
(use-package org
  :ensure nil
  :defer t
  :init
  (setq org-directory "~/org/"
        org-agenda-files (list org-directory)
        org-default-notes-file (concat org-directory "tasks.org")
        calendar-week-start-day 1)
  :config
  (set-face-attribute 'org-level-1 nil :height 1.5)
  (set-face-attribute 'org-level-2 nil :height 1.2))

;; Встроенный в Emacs 31 tree-sitter режим Markdown. При первом открытии
;; сам регистрирует и устанавливает grammars markdown и markdown-inline.
(use-package markdown-ts-mode
  :ensure nil
  :mode
  (("\\.md\\'" . markdown-ts-mode-maybe)
   ("README\\.md\\'" . markdown-ts-mode-maybe))
  :hook (markdown-ts-mode . visual-line-mode))

;; Nerd Icons: пиктограммы из уже используемого Nerd Font.
(use-package nerd-icons
  :ensure t
  :defer t
  :custom
  (nerd-icons-font-family "Hack Nerd Font Mono"))

;; Отключить стартовое приветственное окно Emacs.
(setq inhibit-startup-message t)

;; См. ~/.config/emacs/early-init.el для отключения декораций окна.

(require 'project)

(defun my-tab-bar-tab-name ()
  "Показывать имя текущего проекта или имя буфера вне проекта."
  (if-let* ((project (project-current nil)))
      (project-name project)
    (buffer-name)))

;; Tab Bar: встроенные рабочие пространства с независимым расположением окон.
(use-package tab-bar
  :ensure nil
  :custom
  (tab-bar-tab-name-function #'my-tab-bar-tab-name)
  ;; Не занимать место, пока открыт только один таб.
  (tab-bar-show 1)
  ;; Убрать кнопки создания и закрытия: команды доступны через C-x t.
  (tab-bar-new-button-show nil)
  (tab-bar-close-button-show nil)
  :config
  (tab-bar-mode 1))

;; Копировать выделенный текст при перетаскивании мышью.
(setq mouse-drag-copy-region t)

;; Короткие подтверждения y/n вместо yes/no.
;; Перед удалением сохранять внешний clipboard в kill ring и не добавлять
;; туда повторяющиеся записи.
(setq use-short-answers t
      save-interprogram-paste-before-kill t
      kill-do-not-save-duplicates t)

;; Vertico: вертикальный интерфейс дополнения в минибуфере.
;; Показывает варианты дополнения в виде вертикального списка.
(use-package vertico
  :ensure t
  :config
  (vertico-mode 1))

;; Orderless: поиск по частям слов при дополнении.
;; Позволяет искать "fi em" и находить "find-file-emacs".
(use-package orderless
  :ensure t
  :config
  (setq completion-styles '(orderless basic))
  (setq completion-category-overrides '((file (styles basic partial-completion)))))

;; Marginalia: показывает полезные подсказки рядом с вариантами дополнения.
;; Например, описание функций, размер файлов, статус буферов.
(use-package marginalia
  :ensure t
  :config
  (marginalia-mode 1))

;; Rainbow-delimiters: раскрашивает вложенные скобки в разные цвета.
(use-package rainbow-delimiters
  :ensure t
  :hook (prog-mode . rainbow-delimiters-mode))

;; Savehist: сохраняет историю минибуфера между сессиями.
(use-package savehist
  :ensure nil
  :config
  (savehist-mode 1))

;; Сохранять список недавно открытых файлов и позицию курсора в них.
;; Оба режима встроены в Emacs и не требуют дополнительных пакетов.
(recentf-mode 1)
(save-place-mode 1)

(require 'xref)

;; Consult: улучшенные команды поиска и навигации.
(use-package consult
  :ensure t
  :defer t
  :init
  ;; Показывать определения и references через Consult с интерактивным preview.
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  :custom
  ;; Искать скрытые файлы тоже, но исключить .git.
  (consult-fd-args
   '((if (executable-find "fdfind" 'remote) "fdfind" "fd")
     "--full-path --color=never --hidden --exclude .git")))

;; Embark: действия над объектом под курсором или выбранным кандидатом.
(use-package embark
  :ensure t
  :defer t
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

;; Интеграция Embark с Consult.
(use-package embark-consult
  :ensure t
  :after (embark consult))

;; Reverse-im: горячие клавиши работают в любой раскладке.
;; Например, при русской раскладке C-s остаётся C-s, а не C-ы.
(use-package reverse-im
  :ensure t
  :demand t
  :custom
  (reverse-im-input-methods '("russian-computer"))
  :config
  (reverse-im-mode 1))

;; Which-key: показывает подсказки по доступным клавишам.
(use-package which-key
  :ensure nil
  :config
  (which-key-mode 1))

;; Magit: интерфейс для Git в Emacs.
(use-package magit
  :ensure t
  :commands magit-status)

(defun my-treemacs-toggle-current-project ()
  "Toggle Treemacs for the project containing the current buffer."
  (interactive)
  (require 'treemacs)
  (if (eq (treemacs-current-visibility) 'visible)
      (treemacs)
    (treemacs-add-and-display-current-project-exclusively)))

;; Treemacs: дерево текущего проекта со слежением за активным буфером.
(use-package treemacs
  :ensure t
  :defer t
  :bind (("C-c e" . my-treemacs-toggle-current-project))
  :custom
  (treemacs-follow-after-init t)
  :config
  (treemacs-follow-mode 1))

;; Тема Treemacs использует glyphs из Nerd Fonts вместо SVG-иконок.
(use-package treemacs-nerd-icons
  :ensure t
  :after treemacs
  :config
  (treemacs-nerd-icons-config))

;; Tree-sitter в Emacs 31 автоматически устанавливает grammars, которые
;; регистрируют встроенные ts-modes, и включает их вместо обычных modes.
(require 'treesit)
(setopt treesit-auto-install-grammar 'always
        treesit-enabled-modes t
        treesit-font-lock-level 4)

;; swift-mode 10 пока не регистрирует grammar сам, поэтому для Swift остаётся
;; единственный внешний recipe.
(add-to-list 'treesit-language-source-alist
             '(swift "https://github.com/alex-pinkus/tree-sitter-swift"
                     :revision "0.7.3-with-generated-files"
                     :copy-queries t))

(defun my-swift-treesit-setup ()
  "Установить и подключить Swift tree-sitter parser к текущему буферу."
  (when (treesit-ensure-installed 'swift)
    (treesit-parser-create 'swift)))

;; swift-mode отвечает за редактирование и подсветку, а подключённый parser
;; даёт структурное дерево для treesit-команд и расширений.
(use-package swift-mode
  :ensure t
  :mode "\\.swift\\'"
  :hook (swift-mode . my-swift-treesit-setup))

;; Увеличенный блок чтения ускоряет обмен крупными ответами с rust-analyzer.
;; Цена — до 4 МиБ памяти на одну операцию чтения процесса.
(setq read-process-output-max (* 4 1024 1024))

;; Eglot: встроенный LSP-клиент (с Emacs 29).
;; Автоматически подключает rust-analyzer и SourceKit-LSP.
(use-package eglot
  :ensure nil
  :hook
  ((rust-ts-mode . eglot-ensure)
   (swift-mode . eglot-ensure))
  :init
  ;; Подключать LSP асинхронно, не блокируя интерфейс до трёх секунд.
  ;; Разрешить Xref продолжать навигацию во внешних файлах проекта.
  (setq eglot-sync-connect 0
        eglot-extend-to-xref t)
  :config
  ;; Eglot implements recursive watches as one kqueue descriptor per directory.
  ;; This repository exceeds the macOS GUI process descriptor limit, while
  ;; SourceKit-LSP still receives open-buffer changes through standard LSP sync.
  (cl-defmethod eglot-client-capabilities :around ((server eglot-lsp-server))
    (let ((capabilities (cl-call-next-method)))
      (when (assq 'swift-mode (eglot--languages server))
        (plist-put (plist-get capabilities :workspace)
                   :didChangeWatchedFiles
                   '(:dynamicRegistration :json-false
                     :relativePatternSupport t)))
      capabilities))
  ;; xcrun выбирает SourceKit-LSP из активного Xcode/DEVELOPER_DIR.
  (add-to-list 'eglot-server-programs
               '((swift-mode :language-id "swift")
                 . ("xcrun" "sourcekit-lsp")))
  ;; Автоматически выключать сервер при закрытии последнего управляемого буфера.
  (setq eglot-autoshutdown t))

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

;; Поиск символов во всём Eglot workspace через Consult.
(use-package consult-eglot
  :ensure t
  :after (consult eglot)
  :bind ("M-g s" . consult-eglot-symbols)
  :config
  ;; SourceKit-LSP can expose Swift ABI names such as `$s4App...'.  They are
  ;; compiler artifacts rather than source declarations and obstruct search.
  (advice-remove 'consult-eglot--make-async-source
                 #'my-consult-eglot--filter-generated-symbols)
  (advice-add 'consult-eglot--make-async-source :around
              #'my-consult-eglot--filter-generated-symbols))

;; Embark actions и export результатов `consult-eglot-symbols' в grep-буфер.
(use-package consult-eglot-embark
  :ensure t
  :after (embark consult-eglot)
  :config
  (consult-eglot-embark-mode 1))

;; Vterm: быстрый терминал внутри Emacs на основе libvterm.
;; Требует cmake и libtool. На macOS: brew install cmake libtool.
(use-package vterm
  :ensure t
  :config
  (setq vterm-shell (or (getenv "SHELL") "/bin/zsh"))
  (setq vterm-max-scrollback 10000)
  (setq vterm-min-window-width 30)
  ;; Даже без запущенной команды vterm держит shell-процесс.
  ;; Завершать его вместе с буфером или Emacs без подтверждения.
  (add-hook 'vterm-mode-hook
            (lambda ()
              (display-line-numbers-mode -1)
              (setq-local kill-buffer-query-functions
                          (delq 'process-kill-buffer-query-function
                                kill-buffer-query-functions))
              (when-let* ((process (get-buffer-process (current-buffer))))
                (set-process-query-on-exit-flag process nil))))
  :bind
  (("C-c t" . vterm)
   ("C-c T" . vterm-other-window)))

;; Makefile targets через Vertico и стандартный compilation buffer.
(use-package makefile-executor
  :ensure t
  :hook (makefile-mode . makefile-executor-mode)
  :bind (:map project-prefix-map
              ("m" . makefile-executor-execute-project-target)))

;; Diff-hl: цветовые полосы слева для изменений в git.
(use-package diff-hl
  :ensure t
  :functions (diff-hl-magit-post-refresh)
  :config
  (global-diff-hl-mode 1)
  ;; Показывать полосы в отступе слева (margin), а не во фринже.
  ;; Это работает и в GUI, и в терминале.
  (diff-hl-margin-mode 1)
  ;; Обновлять полосы во время редактирования, без сохранения файла.
  (require 'diff-hl-flydiff)
  ;; После операций Magit обновлять отметки во всех буферах репозитория.
  (with-eval-after-load 'magit-mode
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))
  (add-hook 'diff-hl-mode-hook #'diff-hl-flydiff-mode))

;; Глобальные горячие клавиши.
(use-package emacs
  :ensure nil
  :bind
  (("C-s" . consult-line)
   ("C-c s" . consult-ripgrep)
   ("C-c f" . project-find-file)
   ("C-c F" . consult-fd)
   ("C-x b" . consult-buffer)
   ("M-y" . consult-yank-pop)
   ("C-c m" . consult-imenu)
   ;; Встроенная `project-prefix-map' уже назначена на C-x p.
   ("C-." . embark-act)
   ("C-x g" . magit-status)
   ;; Быстрый literal search с C-s/C-r внутри поиска.
   ("C-c i" . isearch-forward)
   ("C-c I" . isearch-backward)
   ("C-c c" . eglot-code-actions)))

;; Удалять выделенный текст при редактировании.
(use-package delsel
  :ensure nil
  :config
  (delete-selection-mode 1))

;; Автодополнение кода
(use-package corfu
  :ensure t
  :custom
  (corfu-auto t)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  :config
  (global-corfu-mode 1)
  (corfu-popupinfo-mode 1))

;; Автодополнение из слов буфера
(use-package cape
  :ensure t
  :custom
  (cape-dabbr-check-other-buffers nil)
  :config
  (add-hook 'completion-at-point-functions #'cape-dabbrev 90))

;; Homebrew устанавливает LLVM как keg-only, поэтому его /bin не попадает
;; в PATH автоматически. На этом Mac Homebrew расположен в /opt/homebrew.
(let* ((llvm-bin "/opt/homebrew/opt/llvm/bin")
       (path (or (getenv "PATH") ""))
       (path-dirs (split-string path path-separator t)))
  (add-to-list 'exec-path llvm-bin)
  (unless (member llvm-bin path-dirs)
    (setenv "PATH"
            (concat llvm-bin path-separator path))))

;; Xcode build, run and debug commands for Swift projects.
(load (expand-file-name "my-xcode.el" user-emacs-directory) nil nil t)

(defun my-dape-style-stopped-source ()
  "Use the Xcode-like execution marker in the current source buffer."
  (let ((indicators (copy-tree fringe-indicator-alist)))
    (setf (alist-get 'overlay-arrow indicators) 'my-dape-current-line)
    (setq-local fringe-indicator-alist indicators)))

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
  (dape-breakpoint-load
   dape-breakpoint-save
   dape-mouse-breakpoint-toggle
   dape-quit
   dape-restart)
  :config
  ;; Xcode-like stopped line: a green-tinted row and a wide execution arrow.
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
         (background
          (apply #'color-rgb-to-hex
                 (append (color-blend green base 0.18) '(2)))))
    (set-face-attribute 'dape-source-line-face nil
                        :background background
                        :extend t))
  (add-hook 'dape-display-source-hook #'my-dape-style-stopped-source)

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

;; repeat-mode позволяет несколько раз подряд вызывать команды,
;; относящиеся к одной группе, одиночными клавишами.
;; В частности, это удобно в отладке: next / step / continue и т. п.
(use-package repeat
  :config
  (repeat-mode 1))

;; Автоматическое обновление буферов из файлов
(global-auto-revert-mode 1)


;; Перемещение текста M-<up>, M-<down>
(use-package move-text
  :ensure t
  :config
  (move-text-default-bindings))

;; Denote - заметки
(use-package denote
  :ensure t
  :init
  (setq denote-directory (expand-file-name "~/org/notes/"))
  ;; Включить режим при запуске, чтобы его find-file-hook уже существовал,
  ;; когда Denote-файл открывают напрямую, а не через команду Denote.
  (denote-rename-buffer-mode 1)
  :hook (dired-mode . denote-dired-mode)
  :bind
  (("C-c n n" . denote)
   ("C-c n r" . denote-rename-file)
   ("C-c n l" . denote-link)
   ("C-c n b" . denote-backlinks)
   ("C-c n d" . denote-dired)
   ("C-c n g" . denote-grep)))

;; Визуальное перемещение курсора
(use-package avy
  :ensure t
  :bind
  ("C-:" . avy-goto-char)
  ("C-;" . avy-goto-char-timer)
  :custom
  (avy-timeout-seconds 1.0))

;; Видимая метка
(use-package visible-mark
  :ensure t
  :config
  (set-face-attribute 'visible-mark-face1 nil
                      :background (catppuccin-color 'surface1)
                      :foreground (catppuccin-color 'text))
  (set-face-attribute 'visible-mark-face2 nil
                      :background (catppuccin-color 'surface2)
                      :foreground (catppuccin-color 'text))
  (global-visible-mark-mode 2)
  (setq visible-mark-max 1)
  (setq visible-mark-faces `(visible-mark-face1 visible-mark-face2)))

;; Выделение регионов
(use-package expreg
  :ensure t
  :bind (("C-=" . expreg-expand)
         ("C--" . expreg-contract)))

;; Vundo: визуальная навигация по ветвящемуся дереву undo.
(use-package vundo
  :ensure t
  :commands vundo
  :bind
  ("C-c u" . vundo)
  :custom
  ;; Компактнее располагать узлы дерева.
  (vundo-compact-display t)
  :config
  ;; Использовать Unicode-глифы; текущий Nerd Font их поддерживает.
  (setq vundo-glyph-alist vundo-unicode-symbols))

;; Автозакрытие скобок
(electric-pair-mode 1)
