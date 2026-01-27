;;; tpp-mode.el --- Major mode for tpp presentations -*- lexical-binding: t; -*-

;; Author: Christian Dietrich <stettberger@gmx.de>
;; Version: 0.2
;; License: GNU General Public License

;;; Commentary:
;; Major mode for editing tpp presentation files.

;;; Code:

(require 'easymenu)

(defgroup tpp nil
  "Major mode for tpp presentation files."
  :group 'text)

(defcustom tpp-command "xterm -e tpp"
  "Command used by `tpp-preview-file'."
  :type 'string
  :group 'tpp)

(defcustom tpp-helpcommand "cat /usr/local/share/doc/tpp/README | xless"
  "Command used by `tpp-open-help'."
  :type 'string
  :group 'tpp)

(defcustom tpp-visualize-auto-refresh t
  "When non-nil, refresh visualization overlays after edits."
  :type 'boolean
  :group 'tpp)

(defcustom tpp-visualize-idle-delay 0.2
  "Idle time in seconds before refreshing visualization overlays."
  :type 'number
  :group 'tpp)

(defcustom tpp-visualize-width nil
  "Override width for visualization overlays.
When nil, use current window width."
  :type '(choice (const :tag "Use window width" nil) integer)
  :group 'tpp)

(defcustom tpp-visualize-inline t
  "When non-nil, visualize inline formatting tokens."
  :type 'boolean
  :group 'tpp)

(defcustom tpp-visualize-hide-inline-tokens nil
  "When non-nil, hide inline formatting tokens in visualization overlays."
  :type 'boolean
  :group 'tpp)

(defface tpp-abstract-face
  '((t :inherit font-lock-constant-face))
  "Face for abstract directives."
  :group 'tpp)

(defface tpp-page-directive-face
  '((t :inherit font-lock-keyword-face))
  "Face for page directives."
  :group 'tpp)

(defface tpp-switch-face
  '((t :inherit font-lock-builtin-face))
  "Face for switch directives."
  :group 'tpp)

(defface tpp-newpage-face
  '((t :inherit font-lock-preprocessor-face :weight bold))
  "Face for --newpage."
  :group 'tpp)

(defface tpp-inline-token-face
  '((t :inherit font-lock-preprocessor-face))
  "Face for inline formatting tokens."
  :group 'tpp)

(defface tpp-inline-bold-face
  '((t :weight bold))
  "Face for inline bold text."
  :group 'tpp)

(defface tpp-inline-underline-face
  '((t :underline t))
  "Face for inline underlined text."
  :group 'tpp)

(defface tpp-inline-reverse-face
  '((t :inverse-video t))
  "Face for inline reverse-video text."
  :group 'tpp)

(defface tpp-argument-face
  '((t :inherit font-lock-string-face))
  "Face for directive arguments."
  :group 'tpp)

(defface tpp-heading-face
  '((t :inherit font-lock-type-face :weight bold))
  "Face for --heading text."
  :group 'tpp)

(defface tpp-huge-face
  '((t :inherit tpp-heading-face))
  "Face for --huge text."
  :group 'tpp)

(defface tpp-color-name-face
  '((t :inherit font-lock-constant-face))
  "Face for color names."
  :group 'tpp)

(defface tpp-shell-directive-face
  '((t :inherit font-lock-comment-delimiter-face))
  "Face for $$/$% directives."
  :group 'tpp)

(defface tpp-shell-command-face
  '((t :inherit font-lock-string-face))
  "Face for shell commands."
  :group 'tpp)

(defface tpp-output-face
  '((t :inherit shadow))
  "Face for output blocks."
  :group 'tpp)

(defface tpp-visual-page-break-face
  '((t :inherit shadow))
  "Face for visual page breaks."
  :group 'tpp)

(defface tpp-visual-horline-face
  '((t :inherit shadow))
  "Face for visual horizontal lines."
  :group 'tpp)

(defface tpp-visual-heading-face
  '((t :inherit tpp-heading-face))
  "Face for visualized headings."
  :group 'tpp)

(defface tpp-visual-huge-face
  '((t :inherit tpp-huge-face))
  "Face for visualized huge text."
  :group 'tpp)

(defconst tpp--color-names
  '("white" "yellow" "red" "green" "blue" "cyan" "magenta" "black" "default"))

(defconst tpp--inline-token-regexp
  "--\\(?:b\\|u\\|rev\\|/b\\|/u\\|/rev\\|c\\|/c\\)\\b")

(defconst tpp--switch-directives
  '("horline" "withborder"
    "beginoutput" "endoutput" "beginshelloutput" "endshelloutput"
    "beginslideleft" "endslideleft"
    "beginslideright" "endslideright"
    "beginslidetop" "endslidetop"
    "beginslidebottom" "endslidebottom"
    "boldon" "boldoff" "revon" "revoff" "ulon" "uloff"))

(defconst tpp-font-lock-keywords
  (let ((color-regexp (regexp-opt tpp--color-names 'words))
        (switch-regexp (regexp-opt tpp--switch-directives)))
    `(
      ("^---\\s-*$" (0 'tpp-switch-face))
      (,(concat "^\\(--newpage\\)\\b\\s-*\\(\\S-.*\\)?$")
       (1 'tpp-newpage-face)
       (2 'tpp-argument-face nil t))
      (,(concat "^\\(--\\(?:bgcolor\\|fgcolor\\)\\)\\s-+\\(" color-regexp "\\)")
       (1 'tpp-abstract-face)
       (2 'tpp-color-name-face))
      (,(concat "^\\(--color\\)\\s-+\\(" color-regexp "\\)")
       (1 'tpp-page-directive-face)
       (2 'tpp-color-name-face))
      (,(concat "^\\(--\\(?:author\\|title\\|date\\)\\)\\s-+\\(.*\\)$")
       (1 'tpp-abstract-face)
       (2 'tpp-argument-face))
      (,(concat "^\\(--\\(?:header\\|footer\\)\\)\\s-+\\(.*\\)$")
       (1 'tpp-page-directive-face)
       (2 'tpp-argument-face))
      (,(concat "^\\(--heading\\)\\s-+\\(.*\\)$")
       (1 'tpp-page-directive-face)
       (2 'tpp-heading-face))
      (,(concat "^\\(--huge\\)\\s-+\\(.*\\)$")
       (1 'tpp-page-directive-face)
       (2 'tpp-huge-face))
      (,(concat "^\\(--\\(?:center\\|right\\)\\)\\s-+\\(.*\\)$")
       (1 'tpp-page-directive-face)
       (2 'tpp-argument-face))
      (,(concat "^\\(--sethugefont\\)\\s-+\\(.*\\)$")
       (1 'tpp-page-directive-face)
       (2 'tpp-argument-face))
      (,(concat "^\\(--exec\\)\\s-+\\(.*\\)$")
       (1 'tpp-page-directive-face)
       (2 'tpp-shell-command-face))
      (,(concat "^\\(--sleep\\)\\s-+\\([0-9]+\\)\\b")
       (1 'tpp-switch-face)
       (2 'font-lock-constant-face))
      (,(concat "^\\(--\\(?:" switch-regexp "\\)\\)\\b")
       (1 'tpp-switch-face))
      ("^\\(\\$\\$\\|\\$%\\)\\s-+\\(.*\\)$"
       (1 'tpp-shell-directive-face)
       (2 'tpp-shell-command-face))
      (,(concat "\\(--c\\)\\s-+\\(" color-regexp "\\)")
       (1 'tpp-inline-token-face)
       (2 'tpp-color-name-face))
      ("\\(--/c\\)\\b" (1 'tpp-inline-token-face))
      ("\\(--\\(?:b\\|u\\|rev\\|/b\\|/u\\|/rev\\)\\)\\b"
       (1 'tpp-inline-token-face))
      ("^--\\S-+" (0 'tpp-page-directive-face keep))
      ("^--##.*$" (0 'font-lock-comment-face t))
      )))

(defvar tpp-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-b") #'tpp-preview-file)
    (define-key map (kbd "C-c C-c") #'tpp-comment-region)
    (define-key map (kbd "C-c C-u") #'tpp-uncomment-region)
    (define-key map (kbd "C-c C-v") #'tpp-visualize-mode)
    (define-key map (kbd "C-c C-r") #'tpp-visualize-refresh)
    map)
  "Keymap for `tpp-mode'.")

(easy-menu-define tpp-mode-menu tpp-mode-map
  "Menu for `tpp-mode'."
  '("TPP"
    ["Preview Buffer" tpp-preview-file]
    ["Comment Region" tpp-comment-region]
    ["Uncomment Region" tpp-uncomment-region]
    ["Toggle Visualization" tpp-visualize-mode]
    ["Refresh Visualization" tpp-visualize-refresh]
    ["Syntax Help" tpp-open-help]
    ["Options" (customize-group "tpp")]))

(defun tpp-preview-file ()
  "Preview current file with tpp."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (save-buffer)
  (shell-command
   (format "%s %s" tpp-command (shell-quote-argument buffer-file-name))))

(defun tpp-open-help ()
  "Show tpp syntax help."
  (interactive)
  (shell-command tpp-helpcommand))

(defun tpp-comment-region (start end)
  "Comment region using --##."
  (interactive "r")
  (comment-region start end))

(defun tpp-uncomment-region (start end)
  "Uncomment region using --##."
  (interactive "r")
  (uncomment-region start end))

(defvar-local tpp--visual-overlays nil)
(defvar-local tpp--visualize-timer nil)

(defun tpp--visualize-clear ()
  (when tpp--visual-overlays
    (mapc #'delete-overlay tpp--visual-overlays)
    (setq tpp--visual-overlays nil)))

(defun tpp--visual-width ()
  (or tpp-visualize-width
      (let ((win (get-buffer-window (current-buffer) t)))
        (if win
            (window-body-width win)
          (frame-width)))))

(defun tpp--visual-align-column (text align width)
  (let ((text-width (string-width text)))
    (pcase align
      ('center (max 0 (/ (- width text-width) 2)))
      ('right (max 0 (- width text-width)))
      (_ 0))))

(defun tpp--visualize-line (display)
  (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
    (overlay-put ov 'tpp-visual t)
    (overlay-put ov 'evaporate t)
    (overlay-put ov 'priority 100)
    (overlay-put ov 'display display)
    (push ov tpp--visual-overlays)))

(defun tpp--visualize-region (beg end face)
  (when (< beg end)
    (let ((ov (make-overlay beg end)))
      (overlay-put ov 'tpp-visual t)
      (overlay-put ov 'evaporate t)
      (overlay-put ov 'priority 50)
      (overlay-put ov 'face face)
      (push ov tpp--visual-overlays))))

(defun tpp--normalize-color (name)
  (when name
    (let ((lower (downcase name)))
      (when (member lower tpp--color-names)
        (unless (string= lower "default")
          lower)))))

(defun tpp--inline-face-spec (styles color base-face)
  (let (faces)
    (when base-face (push base-face faces))
    (when (memq 'bold styles) (push 'tpp-inline-bold-face faces))
    (when (memq 'underline styles) (push 'tpp-inline-underline-face faces))
    (when (memq 'reverse styles) (push 'tpp-inline-reverse-face faces))
    (when color (push `(:foreground ,color) faces))
    (nreverse faces)))

(defun tpp--visualize-inline-apply (beg end styles color &optional base-face)
  (when (and (< beg end) (or styles color))
    (let ((face (tpp--inline-face-spec styles color base-face)))
      (when face
        (let ((ov (make-overlay beg end)))
          (overlay-put ov 'tpp-visual t)
          (overlay-put ov 'evaporate t)
          (overlay-put ov 'priority 60)
          (overlay-put ov 'face face)
          (push ov tpp--visual-overlays))))))

(defun tpp--visualize-hide (beg end)
  (when (< beg end)
    (let ((ov (make-overlay beg end)))
      (overlay-put ov 'tpp-visual t)
      (overlay-put ov 'evaporate t)
      (overlay-put ov 'priority 70)
      (overlay-put ov 'display "")
      (push ov tpp--visual-overlays))))

(defun tpp--inline-apply-string (text styles color base-face)
  (if (or (not (or styles color base-face)) (string= text ""))
      text
    (let ((face (tpp--inline-face-spec styles color base-face)))
      (propertize text 'face face))))

(defun tpp--inline-render-string (text base-face)
  "Return propertized TEXT with inline tokens applied and removed."
  (let* ((len (length text))
         (pos 0)
         (case-fold-search nil)
         (styles nil)
         (color nil)
         (segments nil))
    (while (< pos len)
      (let ((match-pos (string-match tpp--inline-token-regexp text pos)))
        (if (not match-pos)
            (progn
              (push (tpp--inline-apply-string
                     (substring text pos) styles color base-face)
                    segments)
              (setq pos len))
          (let* ((token-start match-pos)
                 (token-end (match-end 0))
                 (token (substring text token-start token-end)))
            (if (and (> token-start 0)
                     (eq (aref text (1- token-start)) ?\\))
                (progn
                  (when (< pos (1- token-start))
                    (push (tpp--inline-apply-string
                           (substring text pos (1- token-start))
                           styles color base-face)
                          segments))
                  (push (tpp--inline-apply-string
                         (substring text token-start token-end)
                         styles color base-face)
                        segments)
                  (setq pos token-end))
              (when (< pos token-start)
                (push (tpp--inline-apply-string
                       (substring text pos token-start)
                       styles color base-face)
                      segments))
              (pcase token
                ("--b" (push 'bold styles) (setq pos token-end))
                ("--/b" (setq styles (delq 'bold styles)) (setq pos token-end))
                ("--u" (push 'underline styles) (setq pos token-end))
                ("--/u" (setq styles (delq 'underline styles)) (setq pos token-end))
                ("--rev" (push 'reverse styles) (setq pos token-end))
                ("--/rev" (setq styles (delq 'reverse styles)) (setq pos token-end))
                ("--c"
                 (let* ((color-start (progn
                                       (setq token-end (match-end 0))
                                       (while (and (< token-end len)
                                                   (memq (aref text token-end) '(?\s ?\t)))
                                         (setq token-end (1+ token-end)))
                                       token-end))
                        (color-end color-start))
                   (while (and (< color-end len)
                               (let ((ch (aref text color-end)))
                                 (or (and (>= ch ?a) (<= ch ?z))
                                     (and (>= ch ?A) (<= ch ?Z)))))
                     (setq color-end (1+ color-end)))
                   (let* ((color-name (and (< color-start color-end)
                                           (substring text color-start color-end)))
                          (normalized (tpp--normalize-color color-name)))
                     (cond
                      ((and color-name
                            (string= (downcase color-name) "default"))
                       (setq color nil))
                      (normalized
                       (setq color normalized))))
                   (setq pos color-end)))
                ("--/c" (setq color nil) (setq pos token-end))
                (_ (setq pos token-end))))))))
    (apply #'concat (nreverse segments))))

(defun tpp--visualize-inline-region (beg end &optional base-face)
  (let ((case-fold-search nil)
        (segment-start beg)
        (styles nil)
        (color nil))
    (save-excursion
      (goto-char beg)
      (while (re-search-forward tpp--inline-token-regexp end t)
        (let ((token-start (match-beginning 0))
              (token-end (match-end 0))
              (token (match-string 0)))
          (if (and (> token-start beg)
                   (eq (char-before token-start) ?\\))
              (progn
                (when tpp-visualize-hide-inline-tokens
                  (tpp--visualize-hide (1- token-start) token-start))
                (goto-char token-end))
            (tpp--visualize-inline-apply segment-start token-start styles color base-face)
            (when tpp-visualize-hide-inline-tokens
              (tpp--visualize-hide token-start token-end))
            (pcase token
              ("--b" (push 'bold styles))
              ("--/b" (setq styles (delq 'bold styles)))
              ("--u" (push 'underline styles))
              ("--/u" (setq styles (delq 'underline styles)))
              ("--rev" (push 'reverse styles))
              ("--/rev" (setq styles (delq 'reverse styles)))
              ("--c"
               (let* ((color-start (progn
                                     (goto-char token-end)
                                     (skip-chars-forward " \t" end)
                                     (point)))
                      (color-end (progn
                                   (skip-chars-forward "A-Za-z" end)
                                   (point)))
                      (color-name (and (< color-start color-end)
                                       (buffer-substring-no-properties
                                        color-start color-end)))
                      (normalized (tpp--normalize-color color-name)))
                 (cond
                  ((and color-name
                        (string= (downcase color-name) "default"))
                   (setq color nil))
                  (normalized
                   (setq color normalized)))
                 (when tpp-visualize-hide-inline-tokens
                   (tpp--visualize-hide token-end color-end))
                 (setq token-end color-end)))
              ("--/c" (setq color nil)))
            (setq segment-start token-end))))
      (tpp--visualize-inline-apply segment-start end styles color base-face))))

(defun tpp--inline-region-for-line ()
  (save-excursion
    (beginning-of-line)
    (cond
     ((looking-at "^--\\(center\\|right\\|heading\\|huge\\)\\s-+")
      nil)
     ((looking-at "^--\\(author\\|title\\|date\\|header\\|footer\\)\\s-+")
      (list (match-end 0) (line-end-position) 'tpp-argument-face))
     ((looking-at "^--")
      nil)
     ((looking-at "^\\(\\$\\$\\|\\$%\\)\\s-+")
      nil)
     (t (list (line-beginning-position) (line-end-position) nil)))))

(defun tpp--pos-in-ranges-p (pos ranges)
  (let ((hit nil))
    (while (and ranges (not hit))
      (let ((range (car ranges)))
        (when (and (<= (car range) pos) (< pos (cdr range)))
          (setq hit t)))
      (setq ranges (cdr ranges)))
    hit))

(defun tpp--visualize-page-break (name)
  (let* ((width (tpp--visual-width))
         (label (if (and name (not (string= name "")))
                    (concat "[ " name " ]")
                  "[ new page ]"))
         (gap (- width (string-width label) 2))
         (left (max 0 (/ gap 2)))
         (right (max 0 (- gap left)))
         (line (concat (make-string left ?-) " " label " " (make-string right ?-))))
    (if (> (string-width line) width)
        (substring line 0 width)
      line)))

(defun tpp--visualize-horline ()
  (make-string (max 1 (tpp--visual-width)) ?-))

(defun tpp--visualize-aligned (text align face)
  (let* ((text (or text ""))
         (rendered (tpp--inline-render-string text face))
         (width (tpp--visual-width))
         (col (tpp--visual-align-column rendered align width))
         (prefix (if (> col 0)
                     (propertize " " 'display `(space :align-to ,col))
                   ""))
         (display (concat prefix rendered)))
    (tpp--visualize-line display)))

(defun tpp--visualize-buffer (&optional buffer)
  (let ((buf (or buffer (current-buffer))))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when tpp--visualize-timer
          (cancel-timer tpp--visualize-timer)
          (setq tpp--visualize-timer nil))
        (when tpp-visualize-mode
          (tpp--visualize-clear)
          (save-excursion
            (let (output-ranges)
              (goto-char (point-min))
              (while (re-search-forward "^--newpage\\b\\s-*\\(\\S-.*\\)?$" nil t)
                (let ((line (tpp--visualize-page-break (match-string 1))))
                  (tpp--visualize-line
                   (propertize line 'face 'tpp-visual-page-break-face))))
              (goto-char (point-min))
              (while (re-search-forward "^--horline\\s-*$" nil t)
                (tpp--visualize-line
                 (propertize (tpp--visualize-horline) 'face 'tpp-visual-horline-face)))
              (goto-char (point-min))
              (while (re-search-forward "^--\\(center\\|right\\|heading\\|huge\\)\\s-+\\(.*\\)$" nil t)
                (let ((directive (match-string 1))
                      (text (match-string 2)))
                  (pcase directive
                    ("center" (tpp--visualize-aligned text 'center 'tpp-argument-face))
                    ("right" (tpp--visualize-aligned text 'right 'tpp-argument-face))
                    ("heading" (tpp--visualize-aligned text 'center 'tpp-visual-heading-face))
                    ("huge" (tpp--visualize-aligned text 'center 'tpp-visual-huge-face)))))
              (goto-char (point-min))
              (while (re-search-forward "^---\\s-*$" nil t)
                (tpp--visualize-line (propertize "[ pause ]" 'face 'tpp-switch-face)))
              (goto-char (point-min))
              (while (re-search-forward "^--begin\\(shell\\)?output\\s-*$" nil t)
                (let ((start (line-beginning-position 2)))
                  (if (re-search-forward "^--end\\(shell\\)?output\\s-*$" nil t)
                      (let ((end (line-beginning-position)))
                        (push (cons start end) output-ranges)
                        (tpp--visualize-region start end 'tpp-output-face))
                    (let ((end (point-max)))
                      (push (cons start end) output-ranges)
                      (tpp--visualize-region start end 'tpp-output-face)))))
              (when tpp-visualize-inline
                (setq output-ranges (nreverse output-ranges))
                (goto-char (point-min))
                (while (not (eobp))
                  (let ((line-start (line-beginning-position)))
                    (unless (tpp--pos-in-ranges-p line-start output-ranges)
                      (let ((region (tpp--inline-region-for-line)))
                        (when region
                          (tpp--visualize-inline-region
                           (nth 0 region)
                           (nth 1 region)
                           (nth 2 region))))))
                  (forward-line 1)))))))))))

(defun tpp--visualize-after-change (&rest _)
  (when tpp-visualize-mode
    (when tpp--visualize-timer
      (cancel-timer tpp--visualize-timer))
    (setq tpp--visualize-timer
          (run-with-idle-timer tpp-visualize-idle-delay nil
                               #'tpp--visualize-buffer (current-buffer)))))

(defun tpp-visualize-refresh ()
  "Refresh visualization overlays."
  (interactive)
  (tpp--visualize-buffer))

(define-minor-mode tpp-visualize-mode
  "Toggle visualization overlays for tpp."
  :lighter " TPP-Vis"
  (if tpp-visualize-mode
      (progn
        (tpp--visualize-buffer)
        (when tpp-visualize-auto-refresh
          (add-hook 'after-change-functions #'tpp--visualize-after-change nil t)))
    (remove-hook 'after-change-functions #'tpp--visualize-after-change t)
    (when tpp--visualize-timer
      (cancel-timer tpp--visualize-timer)
      (setq tpp--visualize-timer nil))
    (tpp--visualize-clear)))

(defconst tpp--imenu-generic-expression
  '(("Pages" "^--newpage\\s-+\\(.*\\)$" 1)
    ("Headings" "^--heading\\s-+\\(.*\\)$" 1)
    ("Huge" "^--huge\\s-+\\(.*\\)$" 1))
  "Imenu expressions for `tpp-mode'.")

;;;###autoload
(define-derived-mode tpp-mode text-mode "TPP"
  "Major mode for editing tpp presentation files."
  (setq-local font-lock-defaults '(tpp-font-lock-keywords))
  (setq-local comment-start "--## ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "^--##+\\s-*")
  (setq-local imenu-generic-expression tpp--imenu-generic-expression)
  (setq-local outline-regexp "^--newpage\\b")
  (easy-menu-add tpp-mode-menu))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tpp\\'" . tpp-mode))

(provide 'tpp-mode)

;;; tpp-mode.el ends here
