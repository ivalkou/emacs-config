;;; early-init.el --- Early initialization for Emacs -*- lexical-binding: t -*-

;;; Commentary:
;; Этот файл загружается ДО создания первого GUI-фрейма.
;; Используется для настроек, которые должны примениться к первому окну.

;;; Code:

;; Отключить декорации окна (title bar с кнопками close/minimize/maximize),
;; но оставить скругления углов (macOS).
;; Нужно задать до создания фрейма, иначе первая рамка будет с заголовком.
(push '(undecorated-round . t) default-frame-alist)
;; Убрать элементы интерфейса до создания первого окна, чтобы избежать мигания.
(scroll-bar-mode -1)
(tool-bar-mode -1)
(tooltip-mode -1)
(menu-bar-mode -1)

(setq frame-resize-pixelwise t)
(provide 'early-init)
;;; early-init.el ends here
