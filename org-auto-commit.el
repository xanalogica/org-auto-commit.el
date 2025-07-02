;;; org-auto-commit.el --- Auto-commit Org buffers with policy control -*- lexical-binding: t -*-

;; Author: Your Name <you@example.com>
;; Version: 0.1
;; Package-Requires: ((emacs "27.1") (magit "3.0.0"))
;; Keywords: org, git, convenience
;; URL: https://github.com/yourusername/org-auto-commit

;;; Commentary:
;;
;; This package defines a minor mode `org-auto-commit-mode` which automatically commits
;; Org-mode buffers under user-defined conditions. It supports idle-based commits,
;; predicate-based filtering, and optional post-commit hooks (like AI processing).
;;
;; To enable this mode, use:
;;
;;   (require 'org-auto-commit)
;;   (add-hook 'org-mode-hook #'org-auto-commit-mode)
;;
;; Customize via `M-x customize-group RET org-auto-commit RET`.

;;; Code:

(require 'magit)
(require 'org)

(defgroup org-auto-commit nil
  "Auto-commit changes to Org-mode buffers."
  :group 'org)

(defcustom org-auto-commit-idle-time 600
  "Idle time in seconds before auto-commit is triggered."
  :type 'integer)

(defcustom org-auto-commit-min-interval 300
  "Minimum time in seconds between two auto-commits."
  :type 'integer)

(defcustom org-auto-commit-predicate-function #'org-auto-commit-predicate-by-directory
  "Function to determine whether a buffer should be auto-committed.
It should return t or nil."
  :type 'function)

(defcustom org-auto-commit-session-dir "~/org/sessions/"
  "Directory under which .org files are considered for auto-commit."
  :type 'directory)

(defcustom org-auto-commit-post-commit-cmd nil
  "Shell command to execute after a successful commit.
If non-nil, it will be run in the Git repo's root directory after commit."
  :type '(choice (const :tag "None" nil)
                 (string :tag "Shell command")))

(defvar-local org-auto-commit--last-time 0
  "Internal timestamp of the last auto-commit for this buffer.")

(defun org-auto-commit-predicate-by-directory ()
  "Default predicate that returns t if file is under session dir."
  (and buffer-file-name
       (string-prefix-p (expand-file-name org-auto-commit-session-dir)
                        (expand-file-name buffer-file-name))))

(defun org-auto-commit-predicate-by-local-variable ()
  "Alternative predicate that checks for a buffer-local `auto-commit` variable."
  (and (boundp 'auto-commit) auto-commit))

(defun org-auto-commit--should-commit-p ()
  "Determine if current buffer should be committed."
  (funcall org-auto-commit-predicate-function))

(defun org-auto-commit--in-git-repo-p ()
  (and buffer-file-name
       (magit-toplevel)))

(defun org-auto-commit--file-in-git-p (file)
  (string-match-p (regexp-quote file)
                  (shell-command-to-string "git ls-files")))

(defun org-auto-commit--do-commit (&optional reason)
  (let ((file buffer-file-name))
    (when (and file (org-auto-commit--in-git-repo-p))
      (let* ((repo-dir (magit-toplevel))
             (default-directory repo-dir)
             (in-repo (org-auto-commit--file-in-git-p file)))
        (if (not in-repo)
            (message "[org-auto-commit] WARNING: %s not added to Git repo." file)
          (let ((now (float-time (current-time))))
            (when (> (- now org-auto-commit--last-time) org-auto-commit-min-interval)
              (setq org-auto-commit--last-time now)
              (magit-call-git "add" file)
              (magit-call-git "commit" "-m" (format "Auto-commit (%s): %s"
                                                     (or reason "timer")
                                                     (file-name-nondirectory file)))
              (message "[org-auto-commit] Committed: %s" file)
              (when org-auto-commit-post-commit-cmd
                (let ((default-directory repo-dir))
                  (start-process-shell-command
                   "org-auto-commit-post" nil org-auto-commit-post-commit-cmd))))))))))

(defun org-auto-commit--maybe-commit ()
  "Check commit conditions and trigger if needed."
  (when (and (eq major-mode 'org-mode)
             (org-auto-commit--should-commit-p))
    (org-auto-commit--do-commit "save")))

(defun org-auto-commit--maybe-commit-on-idle ()
  "Idle-timer based commit trigger."
  (when (and (eq major-mode 'org-mode)
             (org-auto-commit--should-commit-p))
    (org-auto-commit--do-commit "idle")))

;;;###autoload
(define-minor-mode org-auto-commit-mode
  "Minor mode to auto-commit Org-mode buffers under user-defined conditions."
  :lighter " 🤖"
  (if org-auto-commit-mode
      (progn
        (add-hook 'after-save-hook #'org-auto-commit--maybe-commit nil t)
        (run-with-idle-timer 60 t #'org-auto-commit--maybe-commit-on-idle))
    (remove-hook 'after-save-hook #'org-auto-commit--maybe-commit t)))

(provide 'org-auto-commit)
;;; org-auto-commit.el ends here
