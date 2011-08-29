;;; mua-hdrs.el -- part of mua, the mu mail user agent
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

;; In this file are function related to creating the list of one-line
;; descriptions of emails, aka 'headers' (not to be confused with headers like
;; 'To:' or 'Subject:')

;; mu

;;; Code:
 
(eval-when-compile (require 'cl))

(require 'mua-common)
(require 'mua-msg)

;; note: these next two are *not* buffer-local, so they persist during a session
(defvar mua/hdrs-sortfield nil
  "*internal* Field to sort headers by")
(defvar mua/hdrs-sort-descending nil
  "*internal Whether to sort in descending order")

(defvar mua/hdrs-fields
  '( (:date          .  25)
     (:from-or-to    .  22)
     (:subject       .  40))
  "A list of header fields and their character widths")

;; internal stuff
(defvar mua/buf ""
  "*internal* Buffer for results data.")
(defvar mua/last-expression nil
  "*internal* The most recent search expression.")
(defvar mua/hdrs-proc nil
  "*internal* The mu-find process.")

(defconst mua/eom-mark "\n;;eom\n"
  "*internal* Marker for the end of message in the mu find
  output.")
(defconst mua/hdrs-buffer-name "*mua-headers*"
  "*internal* Name of the mua headers buffer.")

(defun mua/hdrs-proc-filter (proc str)
  "A process-filter for the 'mu find --format=sexp output; it
  accumulates the strings into valid sexps by checking of the
  ';;eom' end-of-msg marker, and then evaluating them."
  (setq mua/buf (concat mua/buf str)) ;; update our buffer
  (let ((buf (process-buffer proc)))  ;; check the buffer
    (unless (buffer-live-p buf)
      (error "No live buffer for process filter"))
    (while ;; for-each-sex
      ;; Process the sexp in `mua/buf', and remove it if it worked and return
      ;; t. If no complete sexp is found, return nil."
      (let ((eom (string-match mua/eom-mark mua/buf))
	     (after-eom (match-end 0)) (inhibit-read-only t))
	(when (numberp eom) ;; was the marker found?
	  (with-current-buffer buf
	    (mua/hdrs-append-message (mua/msg-from-string
				       (substring mua/buf 0 eom))))
	  (setq mua/buf (substring mua/buf after-eom)) t)))))
          
  
(defun mua/hdrs-proc-sentinel (proc msg)
  "Sentinel funtion for the mu-find process -- ie., will be called upon its ."
  (let ((procbuf (process-buffer proc))
	 (status (process-status proc))
	 (exit-status (process-exit-status proc)))
    (when (and (buffer-live-p procbuf) (memq status '(exit signal)))
      (let ((msg
	      (case status
		('signal "Search process killed (results incomplete)")
		('exit
		  (if (= 0 exit-status)
		    "End of search results"
		    (mua/mu-error exit-status))))))	  
	      (with-current-buffer procbuf
		(save-excursion
		  (goto-char (point-max))
		  (mua/message "%s" msg)))))))

(defun mua/hdrs-search-execute (expr)
  "Search in the mu database, and output the results in the current
buffer."
  (let* ((argl
	   (remove-if 'not
	     (list "find" "--format=sexp" "--threads"
	       (when mua/mu-home (concat "--muhome=" mua/mu-home))
	       (when mua/hdrs-sortfield
		 (concat "--sortfield=" mua/hdrs-sortfield))
	       (when mua/hdrs-sort-descending "--descending")
	       expr)))
	  (mua/buf "") 
	  ;; start the process
	  (proc (apply 'start-process
		  mua/hdrs-buffer-name (current-buffer) mua/mu-binary argl)))
    (setq mua/hdrs-proc proc)
    (set-process-filter   proc 'mua/hdrs-proc-filter)
    (set-process-sentinel proc 'mua/hdrs-proc-sentinel)
    (mua/log (concat mua/mu-binary " " (mapconcat 'identity argl " ")))))

;; Note, the 'mu find --format=sexp' sexp is almost the same as the ones that
;; 'mu view --format=sexp' produces (see mu-get-message), with the difference
;; that former may give more than one result, and that mu-headers output comes
;; from the database rather than file, and does _not_ contain the message body
(defun mua/hdrs-search (expr)
  "Search in the mu database for EXPR, and switch to the output
buffer for the results."
  (interactive "s[mu] search for: ")
  ;; kill a running process if needed
  (when (and mua/hdrs-proc (eq (process-status mua/hdrs-proc) 'run))
    (kill-process mua/hdrs-proc))
  (let ((buf (mua/new-buffer mua/hdrs-buffer-name)))
    (switch-to-buffer buf)
    (mua/hdrs-mode)
    (mua/hdrs-search-execute expr)))


(defun mua/hdrs-mode ()
  "Major mode for displaying mua search results."
  (interactive)
  (kill-all-local-variables)
  (use-local-map mua/hdrs-mode-map)
  
  (make-local-variable 'mua/buf)
  (make-local-variable 'mua/last-expression)
  (make-local-variable 'mua/hdrs-proc)
  (make-local-variable 'mua/hdrs-hash)
  (make-local-variable 'mua/hdrs-marks-hash)

  (setq
    mua/last-expression expr
    mua/hdrs-marks-hash (make-hash-table :size 16  :rehash-size 2)
    major-mode 'mua/mua/hdrs-mode mode-name "*mua-headers*"
    truncate-lines t
    buffer-read-only t
    overwrite-mode 'overwrite-mode-binary))

(defun mua/hdrs-line (msg)
  "Return line describing a message (ie., a header line)."
  (mapconcat
    (lambda(fieldpair)
      (let ((field (car fieldpair)) (width (cdr fieldpair)))
	(case field
	  (:subject (mua/hdrs-header   msg :subject width))
	  (:to      (mua/hdrs-contact  msg field width))
	  (:from    (mua/hdrs-contact  msg field width))
	  ;;(:from-or-to (mua/msg-header-header-from-or-to msg width 'mua/header-face))
	  (:cc      (mua/hdrs-contact  msg field width))
	  (:bcc     (mua/hdrs-contact  msg field width))
	  (:date    (mua/hdrs-date     msg width))
	  (:flags   (mua/hdrs-flags    msg width))
	  (:size    (mua/hdrs-size     msg width))
	  (t        (error "Unsupported field: %S" field)))))
    mua/header-fields " "))

;;
;; Note: we maintain a hash table to remember what message-path corresponds to a
;; certain line in the buffer. (mua/hdrs-set-path, mua/hdrs-get-path)
;;
;; data is stored like the following: for each header-line, we
;; take the (point) at beginning-of-line (bol) and use that as the key in the
;; mu-headers-hash hash, which does
;;
;;    point-of-bol -> path
;;
(defun mua/hdrs-get-uid ()
  "Get the uid for the message header at point."
  (get-text-property (point) 'uid))

(defun mua/hdrs-get-path ()
  "Get the current path for the header at point."
  (mua/msg-map-get-path (mua/hdrs-get-uid)))

(defun mua/hdrs-append-message (msg)
  "Append a one-line description of MSG to the buffer, and register
it with `mua/msg-map-add' to `mua/msg-map'; add the uid for this
message as a text-property `uid'."
  (let* ((uid (mua/msg-map-add (mua/msg-field msg :path)))
	  (line (propertize (concat "  " (mua/hdrs-line msg) "\n") 'uid uid))
	  (inhibit-read-only t))
    (save-excursion
      (goto-char (point-max))
      (insert line))))



;; Now follow a bunch of function to turn some message field in a
;; string for display

(defun mua/hdrs-header (msg field width)
  "Get a string at WIDTH (truncate or ' '-pad) for display as a
header."
  (let* ((str (mua/msg-field msg field)) (str (if str str "")))
    (propertize (truncate-string-to-width str width 0 ?\s t)
      'face 'mua/header-face)))

(defun mua/hdrs-contact (msg field width)
  "get display string for a list of contacts in a header, truncated for
fitting in WIDTH"
  (unless (member field '(:to :from :bcc :cc))
    (error "Illegal type for contact"))
  (let* ((lst (mua/msg-field msg field))
	  (str (mapconcat
		 (lambda (ctc)
		   (let ((name (car ctc)) (email (cdr ctc)))
		     (or name email "?"))) lst ",")))
    (propertize (truncate-string-to-width str width 0 ?\s t)
      'face 'mua/contacts-face)))


(defun mua/hdrs-size (msg width)
  "return a string for size of MSG of WIDTH"
  (let* ((size (mua/msg-field msg :size))
	  ((str
	   (cond
	     ((>= size 1000000) (format "%2.1fM" (/ size 1000000.0)))
	     ((and (>= size 1000) (< size 1000000)) (format "%2.1fK" (/ size 1000.0)))
	     ((< size 1000) (format "%d" size)))))
    (propertize  (truncate-string-to-width str width 0 ?\s)
      'face 'mua/header-face))))


(defun mua/hdrs-date (msg width)
  "Return a string for the date of MSG of WIDTH."
  (let* ((date (mua/msg-field msg :date)))
    (if date
      (propertize  (truncate-string-to-width (format-time-string "%x %X" date)
		     width 0 ?\s) 'face 'mua/date-face))))

(defun mua/hdrs-flags (msg width)
  "Return a string describing the flags of MSG at WIDTH."
  (let ((flagstr (mua/msg-flags-to-string (mua/msg-field msg :flags))))
    (propertize  (truncate-string-to-width flagstr width 0 ?\s)
      'face 'mua/header-face)))


;; some keybinding / functions for basic navigation

(defvar mua/hdrs-mode-map
  (let ((map (make-sparse-keymap)))
    
    (define-key map "s" 'mua/hdrs-search)
    (define-key map "q" 'mua/quit-buffer)
    (define-key map "o" 'mua/hdrs-change-sort)
    (define-key map "g" 'mua/hdrs-refresh)
    
    ;; navigation
    (define-key map "n" 'mua/hdrs-next)
    (define-key map "p" 'mua/hdrs-prev)
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
    map)
  "Keymap for *mua-headers* buffers.")
(fset 'mua/hdrs-mode-map mua/hdrs-mode-map)

(defun mua/hdrs-next  ()
  "go to the next line; t if it worked, nil otherwise"
  (interactive) ;; TODO: check if next line has path, if not, don't go there
  (if (or (/= 0 (forward-line 1)) (not (mua/hdrs-get-path)))
    (mua/warn "No message after this one")
    t))

(defun mua/hdrs-prev ()  
  "Go to the previous line; t if it worked, nil otherwise."
  (when (buffer-live-p mua/hdrs-buffer)
    (with-current-buffer mua/hdrs-buffer
      (if (or (/= 0 (forward-line -1)) (not (mua/hdrs-get-uid)))
	(mua/warn "No message before this one")))
    (when mua/view-uid ;; are we in view buffer?
      (mua/view (mua/hdrs-get-uid) mua/hdrs-buffer))))

(defun mua/hdrs-view ()
  (interactive)
  (let ((uid (mua/hdrs-get-uid)))
    (if uid
      (mua/view uid (current-buffer))
      (mua/warn "No message at point"))))

(defun mua/hdrs-jump-to-maildir ()
  "Show the messages in one of the standard folders."
  (interactive)
  (let ((fld (mua/ask-maildir "Jump to maildir: ")))
    (mua/hdrs-search (concat "maildir:" fld))))

(defun mua/hdrs-refresh ()
  "Re-run the query for the current search expression, but only
if the search process is not already running"
  (interactive)
  (when mua/last-expression
    (mua/hdrs-search mua/last-expression)))


;;; functions for sorting
(defun mua/hdrs-change-sort-order (fieldchar)
  "Change the sortfield to FIELDCHAR."
  (interactive "cField to sort by ('d', 's', etc.; see mu-headers(1)):\n")
  (let ((field
	  (case fieldchar
	    (?b "bcc")
	    (?c "cc")
	    (?d "date")
	    (?f "from")
	    (?i "msgid")
	    (?m "maildir")
	    (?p "prio")
	    (?s "subject")
	    (?t "to")
	    (?z "size"))))
    (if field
      (setq mua/hdrs-sortfield field)
      (mua/warn "Invalid sort-field; use one of bcdfimpstz (see mu-headers(1)"))
    field))

(defun mua/hdrs-change-sort-direction (dirchar)
  "Change the sort direction, either [a]scending or [d]escending."
  (interactive)
  (setq mua/hdrs-sort-descending
    (y-or-n-p "Set sorting direction to descending(y) or ascending(n)")))
     

(defun mua/hdrs-change-sort ()
  "Change thee sort field and dirtrection."
  (interactive)
  (and (call-interactively 'mua/hdrs-change-sort-order)
    (call-interactively 'mua/hdrs-change-sort-direction)))



;;; functions for marking

(defvar mua/hdrs-marks-hash nil
  "*internal* The hash for marked messages. The hash maps
   bol (beginning-of-line) to a 3-tuple: [UID TARGET FLAGS], where UID is the
   the UID of the message file (see `mua/msg-map'), TARGET is the
   target maildir (ie., \"/inbox\", but can also be nil (for 'delete);
   and finally FLAGS is the flags to set when the message is moved.")

(defun mua/hdrs-set-mark-ui (bol action)
  "Display (or undisplay) the mark for BOL for action ACTION."
  (unless (member action '(delete trash move unmark))
    (error "Invalid action %S" action))
  (save-excursion    
    (let ((inhibit-read-only t))
      (delete-char 2)
      (insert
	(case action
	  (delete "d ")
	  (trash  "D ")
	  (move   "m ")
	  (unmark "  "))))))

(defun mua/hdrs-set-mark (bol uid &optional target flags)
  "Add a mark to `mua/hdrs-marks-hash', with BOL being the beginning of the line
of the marked message and (optionally) TARGET the target for the trash or move,
and FLAGS the flags to set for the message, either as a string or as a list (see
`mua/msg-move' for a discussion of the format)."
  (if (gethash bol mua/hdrs-marks-hash)
    (mua/warn "Message is already marked")
    (let ((tuple `[,uid ,target ,flags]))
      (puthash bol tuple mua/hdrs-marks-hash) ;; add to the hash...
      (mua/hdrs-set-mark-ui bol action))))

(defun mua/hdrs-remove-mark (bol)
  "Remove the mark for the message at BOL from the markings
hash. BOL must be the point at the beginning of the line."
  (if (not (gethash bol mua/hdrs-marks-hash))
    (mua/warn "Message is not marked")
    (progn
      (remhash bol mua/hdrs-marks-hash)       ;; remove from the hash...
      (mua/hdrs-set-mark-ui bol 'unmark))))
     
(defun mua/hdrs-marks-execute ()
  "Execute the corresponding actions for all marked messages in
`mua/hdrs-marks-hash'."
  (interactive)
  (let ((n-marked (hash-table-count mua/hdrs-marks-hash)))
    (if (= 0 n-marked)
      (mua/warn "No marked messages")
      (when (y-or-n-p
	      (format "Execute actions for %d marked message(s)? " n-marked))
	(save-excursion
	  (maphash
	    (lambda(bol tuple)
	      (let* ((uid (aref tuple 0)) (target (aref tuple 1))
		      (flags (aref tuple 2)) (inhibit-read-only t))
		(when (mua/msg-move uid target flags)
		  ;; remember the updated path -- for now not too useful
		  ;; as we're hiding the header, but...
		  (save-excursion 
		    (mua/hdrs-remove-mark bol)
		    (goto-char bol)
		    ;; when it succeedes, hide msg..)
		    (put-text-property (line-beginning-position 1)
		      (line-beginning-position 2) 'invisible t)))))
	      mua/hdrs-marks-hash))))))

(defun mua/hdrs-mark (action)
  "Mark the message at point BOL (the beginning of the line) with
one of the symbols: move, delete, trash, unmark, unmark-all; the
latter two are pseudo-markings."
  (let* ((bol (line-beginning-position 1)) (uid (mua/hdrs-get-uid)))
    (when uid
      (case action
	(move
	  (mua/hdrs-set-mark bol uid (mua/ask-maildir "Target maildir: " t)))
	(trash
	  (if (member 'trashed (mua/msg-flags-from-path (mua/hdrs-get-path)))
	    (mua/warn "Message is already trashed")
	    (mua/hdrs-set-mark bol uid (concat mua/maildir mua/trash-folder) "+T")))
	(delete
	  (mua/hdrs-set-mark bol action uid "/dev/null"))
	(unmark
	  (mua/hdrs-remove-mark bol))
	(unmark-all
	  (when (y-or-n-p (format "Sure you want to remove all (%d) marks? "
			    (hash-table-count mua/hdrs-marks-hash)))
	    (save-excursion
	      (maphash (lambda (k v) (goto-char k) (mua/hdrs-mark 'unmark))
		mua/hdrs-marks-hash))))
	(t (error "Unsupported mark type")))
      (move-beginning-of-line 2))))
    


;; functions for creating new message -- reply, forward, and new
(defun mua/hdrs-reply ()
  "Reply to message at point."
  (interactive)
  (let* ((uid (mua/hdrs-get-uid))
	  (path (mua/hdrs-get-path))
	  (str (when path (mua/mu-view-sexp path)))
	  (msg (and str (mua/msg-from-string str))))
    (if msg
      (mua/msg-reply msg uid)	  
      (mua/warn "No message at point"))))

(defun mua/hdrs-for-reply ()
  "Forward the message at point."
  (interactive)
  (let* ((uid (mua/hdrs-get-uid))
	  (path (mua/hdrs-get-path))
	  (str (when path (mua/mu-view-sexp path)))
	  (msg (and str (mua/msg-from-string str))))
    (if msg
      (mua/msg-reply msg uid)	  
      (mua/warn "No message at point"))))

(defun mua/hdrs-compose ()
  "Create a new message."
  (interactive)
  (mua/msg-compose-new))


(provide 'mua-hdrs)
