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

;; Markdown: редактирование .md-файлов и README с подсветкой разметки.
(use-package markdown-mode
  :ensure t
  :mode
  (("\\.md\\'" . markdown-mode)
   ("README\\.md\\'" . gfm-mode))
  :hook (markdown-mode . visual-line-mode)
  :custom
  (markdown-command "pandoc"))

;; Nerd-icons пока не используется, но может понадобиться другим UI-пакетам.
;; (use-package nerd-icons
;;   :ensure t)

;; Отключить стартовое приветственное окно Emacs.
(setq inhibit-startup-message t)

;; См. ~/.config/emacs/early-init.el для отключения декораций окна.

(defun my-tab-bar-tab-name ()
  "Показывать имя текущего проекта или имя буфера вне проекта."
  (if-let ((project (project-current nil)))
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

;; Orderless: нечёткий поиск по частям слов при дополнении.
;; Позволяет искать "fi em" и находить "find-file-emacs".
(use-package orderless
  :ensure t
  :config
  (setq completion-styles '(orderless basic))
  (setq completion-category-overrides '((file (styles basic partial-completion))))
  ;; Включаем flex/fuzzy-совпадение: "iele" найдёт "init.el"
  (setq orderless-matching-styles '(orderless-literal orderless-regexp orderless-flex)))

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
  :config
  (setq reverse-im-input-methods '("russian-computer"))
  (reverse-im-mode 1))

;; Which-key: показывает подсказки по доступным клавишам.
(use-package which-key
  :ensure t
  :config
  (which-key-mode 1))

;; Magit: интерфейс для Git в Emacs.
(use-package magit
  :ensure t
  :commands magit-status)

;; Tree-sitter (treesit): встроен в Emacs, начиная с версии 29.
;; Грамматики для Rust и TOML устанавливаются через
;; M-x treesit-install-language-grammar.
(setq treesit-language-source-alist
      '((rust "https://github.com/tree-sitter/tree-sitter-rust")
        (toml "https://github.com/tree-sitter-grammars/tree-sitter-toml")))

;; Максимальный уровень подсветки tree-sitter.
(setq treesit-font-lock-level 4)

;; Привязать расширения файлов к tree-sitter режимам.
(add-to-list 'auto-mode-alist '("\\.rs\\'" . rust-ts-mode))
(add-to-list 'auto-mode-alist '("\\.toml\\'" . toml-ts-mode))


;; Увеличенный блок чтения ускоряет обмен крупными ответами с rust-analyzer.
;; Цена — до 4 МиБ памяти на одну операцию чтения процесса.
(setq read-process-output-max (* 4 1024 1024))

;; Eglot: встроенный LSP-клиент (с Emacs 29).
;; Автоматически подключается к rust-analyzer в Rust-буферах.
(use-package eglot
  :ensure nil
  :hook (rust-ts-mode . eglot-ensure)
  :init
  ;; Подключать LSP асинхронно, не блокируя интерфейс до трёх секунд.
  ;; Разрешить Xref продолжать навигацию во внешних файлах проекта.
  (setq eglot-sync-connect 0
        eglot-extend-to-xref t)
  :config
  ;; Автоматически выключать сервер при закрытии последнего управляемого буфера.
  (setq eglot-autoshutdown t)
  ;; Сервер для Rust.
  (add-to-list 'eglot-server-programs
               '(rust-ts-mode "rust-analyzer")))

;; Vterm: быстрый терминал внутри Emacs на основе libvterm.
;; Требует cmake и libtool. На macOS: brew install cmake libtool.
(defun my-project-vterm ()
  "Открыть отдельный vterm в корне текущего проекта."
  (interactive)
  (let* ((project (project-current t))
         (default-directory (project-root project)))
    (vterm
     (format "*vterm*<%s>"
             (file-name-nondirectory
              (directory-file-name default-directory))))))

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
              (when-let ((process (get-buffer-process (current-buffer))))
                (set-process-query-on-exit-flag process nil))))
  :bind
  (("C-c t" . vterm)
   ("C-c T" . vterm-other-window)
   ("C-x p s" . my-project-vterm)))

;; Diff-hl: цветовые полосы слева для изменений в git.
(use-package diff-hl
  :ensure t
  :config
  (global-diff-hl-mode 1)
  ;; Показывать полосы в отступе слева (margin), а не во фринже.
  ;; Это работает и в GUI, и в терминале.
  (diff-hl-margin-mode 1)
  ;; Обновлять полосы во время редактирования, без сохранения файла.
  (require 'diff-hl-flydiff)
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
   ("C-c I" . isearch-backward)))

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

;; Debug Adapter Protocol — отладка через lldb-dap.
(use-package dape
  :ensure t
  :functions
  (dape-breakpoint-load
   dape-breakpoint-save
   dape-cwd
   dape-mouse-breakpoint-toggle)
  :config
  ;; Сохранять breakpoints между перезапусками Emacs.
  (add-hook 'kill-emacs-hook #'dape-breakpoint-save)
  (add-hook 'after-init-hook #'dape-breakpoint-load)
  (dape-breakpoint-global-mode 1)

  ;; Ctrl + click в левом fringe ставит/снимает breakpoint.
  ;; Обычный click остаётся у Flymake для diagnostics.
  (define-key dape-breakpoint-mode-map
              [left-fringe C-mouse-1]
              #'dape-mouse-breakpoint-toggle))

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
