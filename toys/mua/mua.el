;;; mua.el -- part of mua, the mu mail user agent
;;
;; Copyright (C) 2011 Dirk-Jan C. Binnema

;; Author: Dirk-Jan C. Binnema <djcb@djcbsoftware.nl>
;; Maintainer: Dirk-Jan C. Binnema <djcb@djcbsoftware.nl>
;; Keywords: email
;; Version: 0.0

;; This file is not part of GNU Emacs.
;;
;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; mu

;;; Code:
 
(eval-when-compile (require 'cl))

(require 'mua-common)
(require 'mua-hdrs)
(require 'mua-view)

(defvar mua/mu-home nil "location of the mu homedir, or nil for
the default")
(defvar mua/mu-binary "mu" "name/path of the mu binary")
(setq mua/mu-binary "/home/djcb/src/mu/src/mu")

(defvar mua/user-agent nil "User-specified User-Agent string")

(defvar mua/parent-buffer nil "parent buffer; if a buffer is
quitted, it switches back to its parent buffer")

(defvar mua/maildir nil "our maildir")

(defvar mu/maildir nil "location of your maildir, typically ~/Maildir")
(defvar mu/inbox-folder	 nil  "location of your inbox folder")
(defvar mu/outbox-folder nil "location of your outbox folder")
(defvar mu/sent-folder	 nil "location of your sent folder")
(defvar mu/trash-folder	 nil "location of your trash folder")
(defvar mu/drafts-folder nil "location of your drafts folder")

(setq
  mua/maildir       "/home/djcb/Maildir"
  mua/inbox-folder  "/inbox"
  mua/outbox-folder "/outbox"
  mua/sent-folder   "/sent"
  mua/drafts-folder "/drafts"
  mua/trash-folder  "/trash")

(defvar mua/working-folders nil)

(setq mua/working-folders
  '("/archive" "/bulkarchive" "/todo"))

(setq mua/header-fields
  '( (:date          .  25)
     (:flags         .   6)
     (:from          .  22)
     (:subject       .  40)))


(defface mua/date-face		'((t (:foreground "#8c5353"))) "")
(defface mua/header-title-face  '((t (:foreground "#df558f"))) "") 
(defface mua/header-face	'((t (:foreground "#dfaf8f"))) "") 
(defface mua/contacts-face	'((t (:foreground "#7f9f7f"))) "") 
(defface mua/body-face		'((t (:foreground "#8cd0d3"))) "") 


(setq mua/hdrs-mode-map
  (let ((map (make-sparse-keymap)))
    
    (define-key map "s" 'mua/hdrs-search)
    (define-key map "q" 'mua/quit-buffer)
    (define-key map "o" 'mu-headers-change-sort)
    (define-key map "g" 'mua/hdrs-refresh)
    
    ;; navigation
    (define-key map "n" 'mua/hdrs-next)
    (define-key map "p" 'mua/hdrs-prev)
    (define-key map (kbd "<down>") 'mua/hdrs-next)
    (define-key map (kbd "<up>")   'mua/hdrs-prev)

    (define-key map (kbd "<SPC>")  'scroll-up)
       
    (define-key map "j" 'mua/hdrs-jump-to-maildir)
    
    ;; marking/unmarking/executing
    (define-key map "m" (lambda()(interactive)(mua/hdrs-mark 'move)))
    (define-key map "d" (lambda()(interactive)(mua/hdrs-mark 'trash)))
    (define-key map "D" (lambda()(interactive)(mua/hdrs-mark 'delete)))
    (define-key map "u" (lambda()(interactive)(mua/hdrs-mark 'unmark)))
    (define-key map "U" (lambda()(interactive)(mua/hdrs-mark 'unmark-all)))
    (define-key map "x" 'mua/hdrs-marks-execute)
    
    ;; message composition
    (define-key map "r" 'mua/hdrs-reply)
    (define-key map "f" 'mua/hdrs-forward)
    (define-key map "c" 'mua/hdrs-compose)
    
    (define-key map (kbd "RET") 'mua/hdrs-view)
    map))
(fset 'mua/hdrs-mode-map mua/hdrs-mode-map)



(provide 'mua)
