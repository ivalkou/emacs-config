;;; init.el --- Personal Emacs configuration -*- lexical-binding: t; -*-
;; Lexical binding ограничивает локальные переменные их областью видимости
;; и позволяет замыканиям безопасно сохранять значения.

;;; Основа и платформа

(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file t)

;; Хранить резервные копии отдельно от редактируемых файлов.
(let ((directory (locate-user-emacs-file "backups/")))
  (make-directory directory t)
  (setopt backup-directory-alist `(("." . ,directory))))

;; Не открывать окно предупреждений native-compiler, но сохранять их в журнале.
(with-eval-after-load 'comp-run
  (customize-set-variable 'native-comp-async-report-warnings-errors 'silent))

;; Настройка клавиш Command и Option на macOS.
;; Command работает как Meta (M-), Option остаётся для ввода спецсимволов.
(setq mac-command-modifier 'meta)
(setq mac-option-modifier 'none)
(global-unset-key (kbd "C-z"))

;; Добавление репозитория MELPA к стандартным архивам пакетов.
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

;; exec-path-from-shell: переносит PATH и другие переменные из shell в Emacs.
;; Запускать его только для GUI и daemon на macOS: терминальный Emacs уже
;; наследует окружение от родительского shell.
(use-package exec-path-from-shell
  :ensure t
  :if (and (eq system-type 'darwin)
           (or (display-graphic-p) (daemonp)))
  :config
  (exec-path-from-shell-initialize))

;; Использовать привычные границы предложений и равномерно делить окна.
(setopt sentence-end-double-space nil
        window-combination-resize t)

;; Не выполнять сетевые проверки для строк, похожих на имена хостов.
(with-eval-after-load 'ffap
  (setopt ffap-machine-p-known 'reject))

;;; Интерфейс

;; Показывать номера строк во всех буферах.
(global-display-line-numbers-mode t)

;; Подсвечивать текущую строку курсора.
(global-hl-line-mode t)
(setopt global-hl-line-sticky-flag 'window)

;; Курсор в виде вертикальной линии.
(setq-default cursor-type 'bar)

(set-face-attribute 'default nil :family "Hack Nerd Font Mono" :height 150)

(defun my-telephone-line-meow-face (active)
  "Return the face for the current Meow state."
  (if (and active (bound-and-true-p meow-mode))
      (alist-get (meow--current-state) meow-indicator-face-alist 'mode-line)
    'mode-line-inactive))

;; Telephone-line: красивая строка статуса со стрелками.
(use-package telephone-line
  :ensure t
  :config
  ;; Использовать встроенный сегмент Meow с цветом текущего состояния.
  (setf (alist-get 'meow telephone-line-faces)
        #'my-telephone-line-meow-face
        (car telephone-line-lhs)
        '(meow . (telephone-line-meow-tag-segment)))
  (telephone-line-mode 1))

;; Сразу показывать парную скобку и контекст за границей окна.
(setopt show-paren-delay 0
        show-paren-context-when-offscreen 'overlay)

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

;; Nerd Icons: пиктограммы из уже используемого Nerd Font.
(use-package nerd-icons
  :ensure t
  :defer t
  :custom
  (nerd-icons-font-family "Hack Nerd Font Mono"))

;; Вместо стартового приветствия открывать рабочий Org dashboard.
(setq inhibit-startup-message t
      initial-buffer-choice (expand-file-name "~/org/dashboard.org"))

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

;; Точная прокрутка трекпадом и безопасная активация окна на macOS.
(pixel-scroll-precision-mode 1)
(when (display-graphic-p)
  (context-menu-mode 1))
(when (eq system-type 'darwin)
  (setopt ns-click-through nil))

;; Короткие подтверждения y/n вместо yes/no.
;; Перед удалением сохранять внешний clipboard в kill ring и не добавлять
;; туда повторяющиеся записи.
(setq use-short-answers t
      save-interprogram-paste-before-kill t
      kill-do-not-save-duplicates t)

;;; Дополнение и поиск

(setopt tab-always-indent 'complete)

;; Vertico: вертикальный интерфейс дополнения в минибуфере.
;; Показывает варианты дополнения в виде вертикального списка.
(use-package vertico
  :ensure t
  :config
  (vertico-mode 1))

;; Удалять M-DEL целый компонент пути в Vertico.
(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map
              ("M-DEL" . vertico-directory-delete-word)))

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

;; Savehist: сохраняет историю минибуфера между сессиями.
(use-package savehist
  :ensure nil
  :config
  (savehist-mode 1))

;; Счётчик совпадений, свободная прокрутка и циклический Isearch.
(setopt isearch-lazy-count t
        isearch-allow-motion t
        isearch-allow-scroll t
        isearch-repeat-on-direction-change t
        isearch-wrap-pause 'no-ding)

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
  (add-hook 'completion-at-point-functions #'cape-dabbrev 90)
  (add-hook 'completion-at-point-functions #'cape-file 90))

;; Reverse-im: горячие клавиши работают в любой раскладке.
;; Например, при русской раскладке C-s остаётся C-s, а не C-ы.
(use-package reverse-im
  :ensure t
  :demand t
  :custom
  (reverse-im-input-methods '("russian-computer"))
  (reverse-im-read-char-advice-function #'reverse-im-read-char-include)
  :config
  (add-to-list 'reverse-im-read-char-include-commands
               "\\`meow-.*-of-thing\\'")
  (reverse-im-mode 1))

;; Which-key: показывает подсказки по доступным клавишам.
(use-package which-key
  :ensure nil
  :config
  (which-key-mode 1))

;;; Проекты и навигация

;; Magit: интерфейс для Git в Emacs.
(use-package magit
  :ensure t
  :commands magit-status
  :config
  (add-hook 'magit-status-sections-hook #'magit-insert-worktrees t))

(defun my-treemacs-toggle-current-project ()
  "Toggle Treemacs for the project containing the current buffer."
  (interactive)
  (require 'treemacs)
  (if (eq (treemacs-current-visibility) 'visible)
      (treemacs)
    (treemacs-add-and-display-current-project-exclusively)))

(defun my-treemacs-buffer-setup ()
  "Keep long paths on one line and enable horizontal mouse scrolling."
  (setq-local truncate-lines t
              word-wrap nil
              auto-hscroll-mode nil
              mouse-wheel-tilt-scroll t
              mouse-wheel-flip-direction t
              mouse-wheel-scroll-amount-horizontal 3))

(defun my-treemacs-mode-line-project-name ()
  "Return the current Treemacs project name for the mode line."
  (if-let* ((workspace (treemacs-current-workspace))
            (project (car (treemacs-workspace->projects workspace))))
      (format " Treemacs: %s" (treemacs-project->name project))
    " Treemacs"))

;; Treemacs: дерево текущего проекта со слежением за активным буфером.
(use-package treemacs
  :ensure t
  :defer t
  :bind (("C-c e" . my-treemacs-toggle-current-project))
  :custom
  (treemacs-follow-after-init t)
  (treemacs-text-scale -1)
  (treemacs-width 45)
  (treemacs-user-mode-line-format
   '(:eval (my-treemacs-mode-line-project-name)))
  :hook (treemacs-mode . my-treemacs-buffer-setup)
  :config
  (treemacs-follow-mode 1))

;; Тема Treemacs использует glyphs из Nerd Fonts вместо SVG-иконок.
(use-package treemacs-nerd-icons
  :ensure t
  :after treemacs
  :config
  (treemacs-nerd-icons-config))

;;; Тексты и заметки

;; Выравнивать продолжения строк под списками и цитатами.
(add-hook 'text-mode-hook #'visual-wrap-prefix-mode)

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

;;; Программирование

;; Rainbow-delimiters: раскрашивает вложенные скобки в разные цвета.
(use-package rainbow-delimiters
  :ensure t
  :hook (prog-mode . rainbow-delimiters-mode))

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

;; Dape debugger configuration and controls.
(load (expand-file-name "my-dape.el" user-emacs-directory) nil nil t)

;;; Инструменты разработки

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

(defun my-agent-shell-data-subdir (subdir)
  "Return SUBDIR under Emacs config, partitioned by project."
  (let* ((cwd (directory-file-name (agent-shell-cwd)))
         (project (replace-regexp-in-string
                   "/" "-" (string-remove-prefix "/" cwd))))
    (locate-user-emacs-file
     (file-name-concat "agent-shell" project subdir))))

;; Agent Shell: нативный Emacs-интерфейс к Oh My Pi через корпоративный proxy-скрипт.
(use-package agent-shell
  :ensure t
  :functions agent-shell-cwd
  :commands agent-shell
  :bind ("C-c a" . agent-shell)
  :custom
  (agent-shell-preferred-agent-config 'omp)
  (agent-shell-display-action
   '((display-buffer-in-side-window)
     (side . right)
     (window-width . 0.4)))
  (agent-shell-dot-subdir-function #'my-agent-shell-data-subdir)
  (agent-shell-omp-acp-command
   (list (expand-file-name "~/omp-proxy.sh") "acp"))
  :hook (agent-shell-mode . (lambda () (display-line-numbers-mode -1))))

;; Цветной вывод Make и других команд в `compilation-mode'.
;; PTY сообщает инструментам терминал с поддержкой цветов, а фильтр
;; преобразует ANSI SGR-последовательности в faces Emacs.
(use-package compile
  :ensure nil
  :custom
  (compilation-environment '("TERM=xterm-256color"))
  :config
  (require 'ansi-color)
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter))

(defun my-makefile--target-comments (filename)
  "Return Make target comments from FILENAME as a hash table."
  (let ((comments (make-hash-table :test #'equal)))
    (when (file-readable-p filename)
      (with-temp-buffer
        (insert-file-contents filename)
        (goto-char (point-min))
        (while (re-search-forward
                "^\\([[:alnum:]_.-]+\\):.*##[ \\t]+\\(.+\\)$" nil t)
          (puthash (match-string-no-properties 1)
                   (string-trim (match-string-no-properties 2))
                   comments))))
    comments))

(defun my-makefile--select-target-with-comments (original &optional filename)
  "Call ORIGINAL selector and annotate targets with comments from FILENAME."
  (let* ((filename (or filename (buffer-file-name)))
         (comments (my-makefile--target-comments filename))
         (completion-extra-properties
          (plist-put
           (copy-sequence completion-extra-properties)
           :affixation-function
           (lambda (candidates)
             (let ((width (apply #'max 0 (mapcar #'string-width candidates))))
               (mapcar
                (lambda (candidate)
                  (let ((comment (gethash candidate comments)))
                    (list candidate ""
                          (if comment
                              (concat
                               (make-string
                                (+ 2 (- width (string-width candidate))) ?\s)
                               (propertize comment
                                           'face 'completions-annotations))
                            ""))))
                candidates))))))
    (funcall original filename)))

;; Makefile targets через Vertico из любого буфера текущего проекта.
(use-package makefile-executor
  :ensure t
  :functions (makefile-executor-select-target)
  :hook (makefile-mode . makefile-executor-mode)
  :bind (("C-c C-e" . makefile-executor-execute-project-target)
         :map project-prefix-map
         ("m" . makefile-executor-execute-project-target))
  :config
  (advice-remove 'makefile-executor-select-target
                 #'my-makefile--select-target-with-comments)
  (advice-add 'makefile-executor-select-target :around
              #'my-makefile--select-target-with-comments))

(defun my-diff-hl-update-after-revert ()
  "Refresh diff-hl immediately after an external file change."
  (when (bound-and-true-p diff-hl-mode)
    (diff-hl-update)))

;; Diff-hl: цветовые полосы слева для изменений в git.
(use-package diff-hl
  :ensure t
  :functions (diff-hl-magit-post-refresh)
  :config
  ;; External reverts in different buffers need independent deferred updates.
  (make-variable-buffer-local 'diff-hl-timer)
  (put 'diff-hl-timer 'permanent-local t)
  (global-diff-hl-mode 1)
  ;; Показывать полосы в отступе слева (margin), а не во фринже.
  ;; Это работает и в GUI, и в терминале.
  (diff-hl-margin-mode 1)
  ;; Обновлять полосы во время редактирования, без сохранения файла.
  (require 'diff-hl-flydiff)
  (add-hook 'after-revert-hook #'my-diff-hl-update-after-revert)
  ;; После операций Magit обновлять отметки во всех буферах репозитория.
  (with-eval-after-load 'magit-mode
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))
  (add-hook 'diff-hl-mode-hook #'diff-hl-flydiff-mode))

;;; Редактирование и клавиши

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

(defun my-meow-setup ()
  "Configure the standard QWERTY Meow command layout."
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (meow-leader-define-key
   '("1" . meow-digit-argument)
   '("2" . meow-digit-argument)
   '("3" . meow-digit-argument)
   '("4" . meow-digit-argument)
   '("5" . meow-digit-argument)
   '("6" . meow-digit-argument)
   '("7" . meow-digit-argument)
   '("8" . meow-digit-argument)
   '("9" . meow-digit-argument)
   '("0" . meow-digit-argument)
   '("/" . meow-keypad-describe-key)
   '("?" . meow-cheatsheet))
  (meow-normal-define-key
   '("0" . meow-expand-0)
   '("9" . meow-expand-9)
   '("8" . meow-expand-8)
   '("7" . meow-expand-7)
   '("6" . meow-expand-6)
   '("5" . meow-expand-5)
   '("4" . meow-expand-4)
   '("3" . meow-expand-3)
   '("2" . meow-expand-2)
   '("1" . meow-expand-1)
   '("-" . negative-argument)
   '(";" . meow-reverse)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   '("a" . meow-append)
   '("A" . meow-open-below)
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("c" . meow-change)
   '("d" . meow-delete)
   '("D" . meow-backward-delete)
   '("e" . meow-next-word)
   '("E" . meow-next-symbol)
   '("f" . meow-find)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . meow-left-expand)
   '("i" . meow-insert)
   '("I" . meow-open-above)
   '("j" . meow-next)
   '("J" . meow-next-expand)
   '("k" . meow-prev)
   '("K" . meow-prev-expand)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("m" . meow-join)
   '("n" . meow-search)
   '("o" . meow-block)
   '("O" . meow-to-block)
   '("p" . meow-yank)
   '("q" . meow-quit)
   '("Q" . meow-goto-line)
   '("r" . meow-replace)
   '("R" . meow-swap-grab)
   '("s" . meow-kill)
   '("t" . meow-till)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("v" . meow-visit)
   '("w" . meow-mark-word)
   '("W" . meow-mark-symbol)
   '("x" . meow-line)
   '("X" . meow-goto-line)
   '("y" . meow-save)
   '("Y" . meow-sync-grab)
   '("z" . meow-pop-selection)
   '("'" . repeat)
   '("<escape>" . ignore)))

(defun my-meow-disable-in-process-buffer ()
  "Disable Meow where keys must be sent directly to a process."
  (when (derived-mode-p 'vterm-mode 'agent-shell-mode 'comint-mode
                        'term-mode 'eshell-mode 'dape-repl-mode)
    (meow-mode -1)))

(defun my-meow-beacon-use-translated-entry-key (&rest _)
  "Store the logical key so Beacon replay works through `reverse-im'."
  (let ((keys (this-command-keys-vector)))
    (unless (seq-empty-p keys)
      (setq-local meow--beacon-insert-enter-key
                  (aref keys (1- (length keys)))))))

;; Meow: modal code editing over the existing Emacs keymaps.
(use-package meow
  :ensure t
  :demand t
  :config
  (my-meow-setup)
  ;; `last-input-event' retains the raw Russian character after reverse-im,
  ;; but Beacon must replay the translated Meow command key.
  (dolist (command '(meow-beacon-insert meow-beacon-append
                     meow-beacon-change meow-beacon-change-save
                     meow-beacon-change-char))
    (advice-add command :after #'my-meow-beacon-use-translated-entry-key))
  (dolist (state-color '((normal . blue)
                         (insert . green)
                         (motion . mauve)
                         (keypad . yellow)
                         (beacon . peach)))
    (set-face-attribute
     (alist-get (car state-color) meow-indicator-face-alist)
     nil
     :background (catppuccin-color (cdr state-color))
     :foreground (catppuccin-color 'base)
     :weight 'bold))
  ;; Не переопределять MOTION: Dired, Magit и Treemacs сохраняют свои клавиши.
  (add-hook 'after-change-major-mode-hook
            #'my-meow-disable-in-process-buffer 90)
  (meow-global-mode 1))

;; Удалять выделенный текст при редактировании.
(use-package delsel
  :ensure nil
  :config
  (delete-selection-mode 1))

;; repeat-mode позволяет несколько раз подряд вызывать команды,
;; относящиеся к одной группе, одиночными клавишами.
;; В частности, это удобно в отладке: next / step / continue и т. п.
(use-package repeat
  :config
  (repeat-mode 1))

;; Автоматически обновлять файлы через системные уведомления и Git-состояние.
(use-package autorevert
  :ensure nil
  :custom
  (auto-revert-avoid-polling t)
  (auto-revert-check-vc-info t)
  :config
  (global-auto-revert-mode 1))

;; Перемещение текста M-<up>, M-<down>
(use-package move-text
  :ensure t
  :config
  (move-text-default-bindings))

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

;;; init.el ends here
