;;; my-xcode.el --- Xcode commands for Swift projects -*- lexical-binding: t; -*-

;; Xcode: project-scoped scheme/device selection and Dape launch assembly.
(require 'cl-lib)
(require 'json)
(require 'map)
(require 'project)
(require 'seq)
(require 'subr-x)


(defvar my-xcode-project-selections (make-hash-table :test #'equal)
  "Selected Xcode state, keyed by project root.")

(defconst my-xcode--excluded-container-directories
  '(".git" ".build" ".swiftpm" "DerivedData" "SourcePackages"
    "checkouts" "Pods" "Carthage")
  "Directory names ignored while discovering Xcode containers.")

(defun my-xcode--project-root ()
  "Return the current project root as an absolute directory name."
  (if-let* ((project (project-current nil)))
      (file-name-as-directory (expand-file-name (project-root project)))
    (user-error "The current buffer does not belong to a project")))

(defun my-xcode--state (&optional root)
  "Return cached Xcode state for ROOT or the current project."
  (gethash (or root (my-xcode--project-root)) my-xcode-project-selections))

(defun my-xcode--state-put (key value)
  "Store VALUE under KEY for the current project."
  (let* ((root (my-xcode--project-root))
         (state (plist-put (copy-sequence (my-xcode--state root)) key value)))
    (puthash root state my-xcode-project-selections)
    value))

(defun my-xcode--discoverable-path-p (path)
  "Return non-nil when PATH may contain a user Xcode container."
  (let ((components (split-string
                     (file-relative-name path (my-xcode--project-root)) "/" t)))
    (and (not (seq-intersection
               components my-xcode--excluded-container-directories #'string=))
         (not (member "project.xcworkspace" components)))))

(defun my-xcode--container-candidates (extension)
  "Return real project containers ending with EXTENSION."
  (let* ((root (my-xcode--project-root))
         (regexp (concat (regexp-quote extension) "\\'"))
         (root-level (seq-filter #'file-directory-p
                                 (directory-files root t regexp t)))
         (paths (or root-level
                    (directory-files-recursively
                     root regexp t #'my-xcode--discoverable-path-p nil))))
    (sort (delete-dups
           (seq-filter (lambda (path)
                         (and (file-directory-p path)
                              (my-xcode--discoverable-path-p path)))
                       paths))
          #'string-lessp)))

(defun my-xcode--choose-container (candidates)
  "Choose one Xcode container from CANDIDATES."
  (pcase candidates
    ('nil (user-error "No Xcode workspace or project found below %s"
                      (my-xcode--project-root)))
    (`(,only) only)
    (_ (let* ((root (my-xcode--project-root))
              (choices (mapcar (lambda (path)
                                 (cons (file-relative-name path root) path))
                               candidates))
              (choice (completing-read "Xcode container: " choices nil t)))
         (cdr (assoc choice choices))))))

(defun my-xcode--container ()
  "Return the cached or discovered Xcode workspace/project."
  (let ((cached (plist-get (my-xcode--state) :container)))
    (if (and cached (file-directory-p cached))
        cached
      (let* ((workspaces (my-xcode--container-candidates ".xcworkspace"))
             (candidates (or workspaces
                             (my-xcode--container-candidates ".xcodeproj")))
             (container (my-xcode--choose-container candidates)))
        (my-xcode--state-put :container container)))))

(defun my-xcode--container-arguments (&optional container)
  "Return xcodebuild arguments for CONTAINER."
  (let ((container (or container (my-xcode--container))))
    (cond
     ((string-suffix-p ".xcworkspace" container) (list "-workspace" container))
     ((string-suffix-p ".xcodeproj" container) (list "-project" container))
     (t (user-error "Unsupported Xcode container: %s" container)))))

(defun my-xcode--json-get (key object)
  "Read string KEY from JSON alist OBJECT."
  (alist-get key object nil nil #'string=))

(defun my-xcode--parse-json-buffer ()
  "Parse JSON from the current buffer."
  (goto-char (point-min))
  (json-parse-buffer :object-type 'alist :array-type 'list
                     :null-object nil :false-object nil))

(defun my-xcode--process-json-async
    (label command callback &optional json-file error-callback)
  "Run COMMAND asynchronously and pass parsed JSON to CALLBACK.
When JSON-FILE is non-nil, parse that supported CoreDevice output file.
Invoke ERROR-CALLBACK after a process or JSON parsing failure."
  (let ((origin (current-buffer))
        (buffer (generate-new-buffer (format " *Xcode %s*" label))))
    (message "Xcode: %s…" label)
    (make-process
     :name (generate-new-buffer-name (format "xcode-%s" label))
     :buffer buffer :command command :noquery t :connection-type 'pipe
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (unwind-protect
             (if (zerop (process-exit-status process))
                 (let (json parse-error)
                   (condition-case error
                       (setq json
                             (if json-file
                                 (with-temp-buffer
                                   (insert-file-contents json-file)
                                   (my-xcode--parse-json-buffer))
                               (with-current-buffer buffer
                                 (my-xcode--parse-json-buffer))))
                     (error (setq parse-error error)))
                   (if parse-error
                       (progn
                         (message "Xcode %s parse failed: %s"
                                  label (error-message-string parse-error))
                         (when (and error-callback (buffer-live-p origin))
                           (with-current-buffer origin
                             (funcall error-callback))))
                     (when (buffer-live-p origin)
                       (let (continuation-error)
                         (condition-case error
                             (with-current-buffer origin
                               (funcall callback json))
                           (error (setq continuation-error error)))
                         (when continuation-error
                           (message "Xcode %s continuation failed: %s"
                                    label
                                    (error-message-string continuation-error))
                           (when error-callback
                             (with-current-buffer origin
                               (funcall error-callback))))))))
               (progn
                 (message "Xcode %s failed: %s" label
                          (string-trim
                           (with-current-buffer buffer (buffer-string))))
                 (when (and error-callback (buffer-live-p origin))
                   (with-current-buffer origin (funcall error-callback)))))
           (when (and json-file (file-exists-p json-file))
             (delete-file json-file))
           (kill-buffer buffer)))))))

(defun my-xcode--parse-simulator-destinations (json)
  "Return simulator destinations parsed from JSON."
  (let ((runtimes (my-xcode--json-get "devices" json)))
    (cl-loop for (runtime . devices) in runtimes
             when (string-match-p "\\.iOS-" (format "%s" runtime))
             append (cl-loop for device in devices
                             when (my-xcode--json-get "isAvailable" device)
                             collect (list :kind 'simulator
                                           :name (my-xcode--json-get "name" device)
                                           :id (my-xcode--json-get "udid" device))))))

(defun my-xcode--parse-physical-destinations (json)
  "Return physical destinations parsed from CoreDevice JSON."
  (let* ((result (my-xcode--json-get "result" json))
         (devices (my-xcode--json-get "devices" result)))
    (cl-loop
     for device in devices
     for connection = (my-xcode--json-get "connectionProperties" device)
     for properties = (my-xcode--json-get "deviceProperties" device)
     for hardware = (my-xcode--json-get "hardwareProperties" device)
     when (and (equal (my-xcode--json-get "reality" hardware) "physical")
               (equal (my-xcode--json-get "platform" hardware) "iOS")
               (or (my-xcode--json-get "ddiServicesAvailable" properties)
                   (not (equal (my-xcode--json-get "tunnelState" connection)
                               "unavailable"))))
     collect (list :kind 'device :name (my-xcode--json-get "name" properties)
                   :id (my-xcode--json-get "udid" hardware)
                   :core-device-id (my-xcode--json-get "identifier" device)))))

(defun my-xcode--destinations-async (callback)
  "Pass all live destinations to CALLBACK after both queries settle."
  (let ((remaining 2) simulators physicals failures)
    (cl-labels
        ((finish (failed-source)
           (when failed-source (push failed-source failures))
           (cl-decf remaining)
           (when (zerop remaining)
             (let* ((destinations (append physicals simulators))
                    (failed-labels (string-join (nreverse failures) ", ")))
               (if (not destinations)
                   (message "Xcode: no destinations available%s"
                            (if failures
                                (format "; failed sources: %s" failed-labels)
                              ""))
                 (when failures
                   (message "Xcode destination list is partial; failed: %s"
                            failed-labels))
                 (funcall callback destinations))))))
      (my-xcode--process-json-async
       "listing simulators"
       '("xcrun" "simctl" "list" "devices" "available" "--json")
       (lambda (json)
         (setq simulators (my-xcode--parse-simulator-destinations json))
         (finish nil))
       nil (lambda () (finish "simulators")))
      (let ((json-file (make-temp-file "emacs-devicectl-" nil ".json")))
        (my-xcode--process-json-async
         "listing physical devices"
         (list "xcrun" "devicectl" "list" "devices"
               "--json-output" json-file)
         (lambda (json)
           (setq physicals (my-xcode--parse-physical-destinations json))
           (finish nil))
         json-file (lambda () (finish "physical devices")))))))

(defun my-xcode--destination-label (destination)
  "Return a completion label for DESTINATION."
  (format "[%s] %s — %s"
          (if (eq (plist-get destination :kind) 'simulator) "Simulator" "Device")
          (plist-get destination :name) (plist-get destination :id)))

(defun my-xcode-select-destination (&optional callback)
  "Select a live destination, then invoke CALLBACK when non-nil."
  (interactive)
  (my-xcode--destinations-async
   (lambda (destinations)
     (unless destinations (user-error "No available physical devices or simulators"))
     (let* ((choices (mapcar (lambda (destination)
                               (cons (my-xcode--destination-label destination)
                                     destination))
                             destinations))
            (current (plist-get (my-xcode--state) :destination))
            (choice (completing-read
                     "Xcode destination: " choices nil t nil nil
                     (and current (my-xcode--destination-label current))))
            (destination (cdr (assoc choice choices))))
       (my-xcode--state-put :destination destination)
       (message "Xcode destination: %s" choice)
       (when callback (funcall callback destination))))))

(defun my-xcode--container-json-object (json)
  "Return the workspace or project object from xcodebuild JSON."
  (or (my-xcode--json-get "workspace" json)
      (my-xcode--json-get "project" json)
      (user-error "xcodebuild returned neither workspace nor project data")))

(defun my-xcode--scheme-directories ()
  "Return shared-scheme directories reachable from the container."
  (let* ((container (my-xcode--container))
         (root (my-xcode--project-root))
         (directories (list (expand-file-name "xcshareddata/xcschemes" container))))
    (when (string-suffix-p ".xcworkspace" container)
      (let ((contents (expand-file-name "contents.xcworkspacedata" container)))
        (when (file-readable-p contents)
          (with-temp-buffer
            (insert-file-contents contents)
            (while (re-search-forward
                    "location = \"group:\\([^\"]+\\.xcodeproj\\)\"" nil t)
              (push (expand-file-name "xcshareddata/xcschemes"
                                      (expand-file-name (match-string 1) root))
                    directories))))))
    (delete-dups directories)))

(defun my-xcode--scheme-project (scheme-file reference)
  "Resolve REFERENCE from SCHEME-FILE to an existing project."
  (let* ((root (my-xcode--project-root))
         (reference (string-remove-prefix "container:" reference))
         (root-candidate (expand-file-name reference root))
         (directory (directory-file-name (file-name-directory scheme-file)))
         ancestor)
    (while (and (not ancestor) (file-in-directory-p directory root)
                (not (equal directory (directory-file-name root))))
      (when (and (string-suffix-p ".xcodeproj" directory)
                 (equal (file-name-nondirectory directory)
                        (file-name-nondirectory reference)))
        (setq ancestor directory))
      (setq directory (directory-file-name (file-name-directory directory))))
    (or (and (file-directory-p root-candidate) root-candidate)
        ancestor
        (seq-find (lambda (candidate)
                    (equal (file-name-nondirectory candidate)
                           (file-name-nondirectory reference)))
                  (my-xcode--container-candidates ".xcodeproj"))
        (user-error "Cannot resolve scheme project %s" reference))))

(defun my-xcode--read-launchable-scheme (file)
  "Return FILE's scheme, project and LaunchAction app product, or nil."
  (with-temp-buffer
    (insert-file-contents file)
    (when (search-forward "<LaunchAction" nil t)
      (let ((launch-end (save-excursion (search-forward "</LaunchAction>" nil t))))
        (when (and launch-end (search-forward "<BuildableProductRunnable" launch-end t))
          (let ((runnable-end
                 (save-excursion
                   (search-forward "</BuildableProductRunnable>" launch-end t))))
            (when runnable-end
              (save-restriction
                (narrow-to-region (point) runnable-end)
                (when (re-search-forward
                       "BuildableName = \"\\([^\"]+\\.app\\)\"" nil t)
                  (let ((buildable-name (match-string 1)))
                    (goto-char (point-min))
                    (when (re-search-forward
                           "BlueprintName = \"\\([^\"]+\\)\"" nil t)
                      (let ((target (match-string 1)))
                        (goto-char (point-min))
                        (when (re-search-forward
                               "ReferencedContainer = \"\\([^\"]+\\)\"" nil t)
                          (list :scheme (file-name-base file)
                                :buildable-name buildable-name :target target
                                :project (my-xcode--scheme-project
                                          file (match-string 1))))))))))))))))

(defun my-xcode--local-scheme-infos ()
  "Return locally parsed launchable shared scheme information."
  (cl-loop for directory in (my-xcode--scheme-directories)
           when (file-directory-p directory)
           append (cl-loop for file in (directory-files directory t "\\.xcscheme\\'")
                           for info = (my-xcode--read-launchable-scheme file)
                           when info collect info)))

(defun my-xcode--scheme-infos-async (callback &optional error-callback)
  "Pass launchable schemes to CALLBACK, or invoke ERROR-CALLBACK."
  (my-xcode--process-json-async
   "listing schemes"
   (append '("xcrun" "xcodebuild") (my-xcode--container-arguments)
           '("-list" "-json"))
   (lambda (json)
     (let* ((schemes (my-xcode--json-get "schemes"
                                         (my-xcode--container-json-object json)))
            (infos (seq-filter
                    (lambda (info) (member (plist-get info :scheme) schemes))
                    (my-xcode--local-scheme-infos))))
       (my-xcode--state-put :scheme-infos infos)
       (funcall callback infos)))
   nil error-callback))

(defun my-xcode--scheme-info (scheme)
  "Return cached launchable information for SCHEME."
  (seq-find (lambda (info) (equal (plist-get info :scheme) scheme))
            (plist-get (my-xcode--state) :scheme-infos)))

(defun my-xcode-select-scheme (&optional callback error-callback)
  "Select a runnable scheme, then invoke CALLBACK or ERROR-CALLBACK."
  (interactive)
  (my-xcode--scheme-infos-async
   (lambda (infos)
     (let ((schemes (mapcar (lambda (info) (plist-get info :scheme)) infos))
           (current (plist-get (my-xcode--state) :scheme)))
       (unless schemes (user-error "The Xcode container has no launchable shared schemes"))
       (let ((scheme (completing-read "Runnable Xcode scheme: " schemes nil t
                                      nil nil current)))
         (my-xcode--state-put :scheme scheme)
         (unless (equal scheme current) (my-xcode--state-put :configuration nil))
         (message "Xcode scheme: %s" scheme)
         (when callback (funcall callback scheme)))))
   error-callback))

(defun my-xcode--ensure-scheme (callback &optional error-callback)
  "Pass a valid selected scheme to CALLBACK, or invoke ERROR-CALLBACK."
  (let ((scheme (plist-get (my-xcode--state) :scheme)))
    (if (and scheme (my-xcode--scheme-info scheme))
        (funcall callback scheme)
      (my-xcode--scheme-infos-async
       (lambda (infos)
         (if (and scheme (seq-find (lambda (info)
                                     (equal (plist-get info :scheme) scheme)) infos))
             (funcall callback scheme)
           (my-xcode-select-scheme callback error-callback)))
       error-callback))))

(defun my-xcode--configurations-async (scheme callback &optional error-callback)
  "Pass configurations for SCHEME to CALLBACK, or invoke ERROR-CALLBACK."
  (let ((project (plist-get (my-xcode--scheme-info scheme) :project)))
    (my-xcode--process-json-async
     "listing configurations"
     (list "xcrun" "xcodebuild" "-project" project "-list" "-json")
     (lambda (json)
       (let ((configurations
              (my-xcode--json-get "configurations"
                                  (my-xcode--json-get "project" json))))
         (unless configurations
           (user-error "Project %s reports no build configurations" project))
         (funcall callback configurations)))
     nil error-callback)))

(defun my-xcode-select-configuration (&optional callback)
  "Select an actual configuration asynchronously, then invoke CALLBACK."
  (interactive)
  (my-xcode--ensure-scheme
   (lambda (scheme)
     (my-xcode--configurations-async
      scheme
      (lambda (configurations)
        (let ((configuration
               (completing-read "Xcode configuration: " configurations nil t
                                nil nil
                                (plist-get (my-xcode--state) :configuration))))
          (my-xcode--state-put :configuration configuration)
          (message "Xcode configuration: %s" configuration)
          (when callback (funcall callback configuration))))))))

(defun my-xcode--ensure-configuration
    (scheme callback &optional error-callback)
  "Pass a valid configuration to CALLBACK, or invoke ERROR-CALLBACK."
  (let ((selected (plist-get (my-xcode--state) :configuration)))
    (my-xcode--configurations-async
     scheme
     (lambda (configurations)
       (let ((configuration
              (if (member selected configurations) selected
                (or (and (member "Debug" configurations) "Debug")
                    (car configurations)))))
         (my-xcode--state-put :configuration configuration)
         (funcall callback configuration)))
     error-callback)))

(defun my-xcode--destination-spec (destination)
  "Return an xcodebuild destination specifier for DESTINATION."
  (format "platform=%s,id=%s"
          (if (eq (plist-get destination :kind) 'simulator) "iOS Simulator" "iOS")
          (plist-get destination :id)))

(defun my-xcode--with-selection (callback)
  "Resolve selection asynchronously and pass it to CALLBACK."
  (my-xcode--ensure-scheme
   (lambda (scheme)
     (cl-labels ((with-destination
                   (destination)
                   (my-xcode--ensure-configuration
                    scheme
                    (lambda (configuration)
                      (funcall callback
                               (list :scheme scheme :destination destination
                                     :configuration configuration))))))
       (if-let* ((destination (plist-get (my-xcode--state) :destination)))
           (with-destination destination)
         (my-xcode-select-destination #'with-destination))))))

(defun my-xcode--product-from-settings (entries scheme-info)
  "Extract the launch product from ENTRIES using SCHEME-INFO."
  (let* ((target (plist-get scheme-info :target))
         (buildable-name (plist-get scheme-info :buildable-name))
         (entry (seq-find
                 (lambda (candidate)
                   (let ((settings (my-xcode--json-get "buildSettings" candidate)))
                     (and (equal (or (my-xcode--json-get "target" candidate)
                                     (my-xcode--json-get "TARGET_NAME" settings)) target)
                          (equal (my-xcode--json-get "WRAPPER_EXTENSION" settings) "app")
                          (equal (my-xcode--json-get "FULL_PRODUCT_NAME" settings)
                                 buildable-name))))
                 entries))
         (settings (and entry (my-xcode--json-get "buildSettings" entry)))
         (full-name (and settings (my-xcode--json-get "FULL_PRODUCT_NAME" settings)))
         (build-dir (and settings (my-xcode--json-get "TARGET_BUILD_DIR" settings)))
         (executable (and settings (my-xcode--json-get "EXECUTABLE_PATH" settings)))
         (bundle-id (and settings
                         (my-xcode--json-get "PRODUCT_BUNDLE_IDENTIFIER" settings))))
    (unless (seq-every-p (lambda (value)
                           (and (stringp value) (not (string-empty-p value))))
                         (list full-name build-dir executable bundle-id))
      (user-error "Incomplete app build settings for scheme %s"
                  (plist-get scheme-info :scheme)))
    (list :app (expand-file-name full-name build-dir)
          :program (expand-file-name executable build-dir)
          :executable-name (file-name-nondirectory executable)
          :bundle-id bundle-id :target target :buildable-name buildable-name)))

(defun my-xcode--product-settings-async
    (selection callback &optional error-callback)
  "Resolve SELECTION's product via CALLBACK, or invoke ERROR-CALLBACK."
  (let* ((scheme (plist-get selection :scheme))
         (destination (plist-get selection :destination))
         (configuration (plist-get selection :configuration))
         (scheme-info (my-xcode--scheme-info scheme)))
    (my-xcode--process-json-async
     "resolving app product"
     (append '("xcrun" "xcodebuild") (my-xcode--container-arguments)
             (list "-scheme" scheme "-configuration" configuration
                   "-destination" (my-xcode--destination-spec destination)
                   "-showBuildSettings" "-json"))
     (lambda (entries)
       (condition-case error
           (funcall callback
                    (my-xcode--product-from-settings entries scheme-info))
         (error
          (message "Xcode product resolution failed: %s"
                   (error-message-string error))
          (when error-callback (funcall error-callback)))))
     nil error-callback)))

(defun my-xcode--shell-command (arguments)
  "Quote ARGUMENTS as one shell command."
  (mapconcat #'shell-quote-argument arguments " "))

(defun my-xcode--command-chain (commands)
  "Join COMMANDS into a fail-fast shell command."
  (mapconcat #'my-xcode--shell-command commands " && "))

(defun my-xcode--build-command (selection)
  "Return the selected xcodebuild command as an argument list."
  (append '("xcrun" "xcodebuild") (my-xcode--container-arguments)
          (list "-scheme" (plist-get selection :scheme)
                "-configuration" (plist-get selection :configuration)
                "-destination" (my-xcode--destination-spec
                                 (plist-get selection :destination))
                "build")))

(defun my-xcode--install-command (destination product)
  "Return the Apple CLI install command for DESTINATION and PRODUCT."
  (if (eq (plist-get destination :kind) 'simulator)
      (list "xcrun" "simctl" "install"
            (plist-get destination :id) (plist-get product :app))
    (let ((core-id (plist-get destination :core-device-id)))
      (unless core-id (user-error "Physical destination has no CoreDevice identifier"))
      (list "xcrun" "devicectl" "device" "install" "app"
            "--device" core-id (plist-get product :app)))))

(defun my-xcode--launch-command (destination product debug json-file)
  "Return an Apple CLI launch command.
DEBUG requests a debugger wait; JSON-FILE captures a physical launch PID."
  (if (eq (plist-get destination :kind) 'simulator)
      (append '("xcrun" "simctl" "launch")
              (when debug '("--wait-for-debugger"))
              (list "--terminate-running-process" (plist-get destination :id)
                    (plist-get product :bundle-id)))
    (let ((core-id (plist-get destination :core-device-id)))
      (unless core-id (user-error "Physical destination has no CoreDevice identifier"))
      (append (list "xcrun" "devicectl" "device" "process" "launch"
                    "--device" core-id)
              (when debug '("--start-stopped")) '("--terminate-existing")
              (when json-file (list "--json-output" json-file))
              (list (plist-get product :bundle-id))))))

(defconst my-xcode--device-pid-extractor
  (concat "import json, pathlib, sys\n"
          "def find_pid(value):\n"
          "    if isinstance(value, dict):\n"
          "        candidate = value.get('processIdentifier')\n"
          "        if isinstance(candidate, int) and not isinstance(candidate, bool) and candidate > 0:\n"
          "            return str(candidate)\n"
          "        if isinstance(candidate, str) and candidate.isdigit() and int(candidate) > 0:\n"
          "            return candidate\n"
          "        for child in value.values():\n"
          "            pid = find_pid(child)\n"
          "            if pid is not None: return pid\n"
          "    elif isinstance(value, list):\n"
          "        for child in value:\n"
          "            pid = find_pid(child)\n"
          "            if pid is not None: return pid\n"
          "    return None\n"
          "pid = find_pid(json.loads(pathlib.Path(sys.argv[1]).read_text()))\n"
          "if pid is None: raise SystemExit('devicectl JSON has no positive processIdentifier')\n"
          "pathlib.Path(sys.argv[2]).write_text(pid + '\\n')\n")
  "Python program that recursively extracts a CoreDevice launch PID.")

(defconst my-xcode--device-pid-ttl 1800
  "Maximum PID-file age in seconds before physical termination is refused.")

(defconst my-xcode--device-pid-candidate-limit 4
  "Maximum reusable PID-file paths per physical app selection.")

(defun my-xcode--device-pid-key (destination product)
  "Return the cache key for DESTINATION and PRODUCT."
  (cons (plist-get destination :core-device-id)
        (plist-get product :bundle-id)))

(defun my-xcode--device-pid-candidates (destination product)
  "Return registered PID-file candidates for DESTINATION and PRODUCT."
  (let ((value (cdr (assoc (my-xcode--device-pid-key destination product)
                           (plist-get (my-xcode--state) :device-pid-files)))))
    (cond ((null value) nil)
          ((stringp value) (list value))
          ((plist-get value :file) (list (plist-get value :file)))
          (t value))))

(defun my-xcode--register-device-pid-candidate
    (destination product pid-file)
  "Register reusable PID-FILE for DESTINATION and PRODUCT."
  (let* ((key (my-xcode--device-pid-key destination product))
         (records (plist-get (my-xcode--state) :device-pid-files))
         (candidates (cons pid-file
                           (delete pid-file
                                   (my-xcode--device-pid-candidates
                                    destination product)))))
    (my-xcode--state-put
     :device-pid-files
     (cons (cons key (seq-take candidates my-xcode--device-pid-candidate-limit))
           (assoc-delete-all key records #'equal)))))

(defun my-xcode--allocate-device-pid-file (destination product json-file)
  "Return a bounded reusable PID-file path for a new physical launch."
  (let* ((candidates (my-xcode--device-pid-candidates destination product))
         (missing (seq-find (lambda (file) (not (file-exists-p file)))
                            candidates))
         (pid-file
          (or missing
              (and (< (length candidates) my-xcode--device-pid-candidate-limit)
                   (concat json-file ".pid"))
              (car (sort (copy-sequence candidates)
                         (lambda (left right)
                           (time-less-p
                            (file-attribute-modification-time
                             (file-attributes left))
                            (file-attribute-modification-time
                             (file-attributes right)))))))))
    (my-xcode--register-device-pid-candidate destination product pid-file)
    pid-file))

(defun my-xcode--app-workflow (selection product debug)
  "Return build/install/launch workflow for SELECTION and PRODUCT."
  (let* ((destination (plist-get selection :destination))
         (simulator-p (eq (plist-get destination :kind) 'simulator))
         (json-file (unless simulator-p
                      (make-temp-file "emacs-xcode-device-" nil ".json")))
         (pid-file (and json-file
                        (my-xcode--allocate-device-pid-file
                         destination product json-file)))
         (commands
          (append (when json-file (list (list "/bin/rm" "-f" json-file)))
                  (list (my-xcode--build-command selection))
                  (when simulator-p
                    (list (list "xcrun" "simctl" "bootstatus"
                                (plist-get destination :id) "-b")))
                  (list (my-xcode--install-command destination product))
                  (when pid-file
                    (list (list "/bin/rm" "-f" pid-file)))
                  (list (my-xcode--launch-command
                         destination product debug json-file))
                  (when json-file
                    (list (list "xcrun" "python3" "-c"
                                my-xcode--device-pid-extractor json-file pid-file)
                          (list "/bin/rm" "-f" json-file))))))
    (list :commands commands :json-file json-file :pid-file pid-file
          :pid-key (and pid-file
                        (my-xcode--device-pid-key destination product)))))

(defun my-xcode--start-compilation (name commands)
  "Run COMMANDS asynchronously in a compilation buffer named NAME."
  (let ((default-directory (my-xcode--project-root)))
    (compilation-start (my-xcode--command-chain commands) 'compilation-mode
                       (lambda (_) (format "*Xcode %s*" name)))))

(defun my-xcode-build ()
  "Build the selected scheme, destination and configuration asynchronously."
  (interactive)
  (my-xcode--with-selection
   (lambda (selection)
     (my-xcode--start-compilation "Build"
                                  (list (my-xcode--build-command selection))))))

(defun my-xcode-run ()
  "Build, install and launch the selected app without a debugger."
  (interactive)
  (my-xcode--with-selection
   (lambda (selection)
     (my-xcode--product-settings-async
      selection
      (lambda (product)
        (my-xcode--start-compilation
         "Run" (plist-get (my-xcode--app-workflow selection product nil)
                          :commands)))))))

(defun my-xcode--dape-command (selection product)
  "Build a Dape command for SELECTION and PRODUCT."
  (let* ((destination (plist-get selection :destination))
         (simulator-p (eq (plist-get destination :kind) 'simulator))
         (core-id (plist-get destination :core-device-id))
         (workflow (my-xcode--app-workflow selection product t))
         (pid-file (plist-get workflow :pid-file))
         (base `(lldb-dap modes (swift-mode) ensure dape-ensure-command
                    command "xcrun" command-args ("lldb-dap")
                    command-cwd ,(my-xcode--project-root)
                    compile ,(my-xcode--command-chain (plist-get workflow :commands))
                    :type "lldb-dap" :request "attach"
                    :cwd ,(my-xcode--project-root) :program ,(plist-get product :program))))
    (unless simulator-p
      (my-xcode--state-put
       :last-dape-pid
       (list :destination destination :product product :file pid-file)))
    (if simulator-p
        (append base
                `(:initCommands
                  ["platform select ios-simulator"
                   ,(format "platform connect %s"
                            (plist-get destination :id))]))
      (append base
              `(:attachCommands
                [,(format "device select %s" core-id)
                 ,(format "script import lldb, pathlib; pid = pathlib.Path(%S).read_text().strip(); lldb.debugger.HandleCommand('device process attach -p ' + pid)"
                          pid-file)])))))

(defun my-xcode--ensure-last-dape-pid-registered ()
  "Ensure the cached physical Dape PID path remains discoverable."
  (when-let* ((registration (plist-get (my-xcode--state) :last-dape-pid))
              (destination (plist-get registration :destination))
              (product (plist-get registration :product))
              (pid-file (plist-get registration :file)))
    (my-xcode--register-device-pid-candidate
     destination product pid-file)))

(defun my-xcode-dape-debug ()
  "Build, launch and debug the selected Xcode app through Dape."
  (interactive)
  (my-xcode--with-selection
   (lambda (selection)
     (my-xcode--product-settings-async
      selection
      (lambda (product)
        (let ((command (my-xcode--dape-command selection product)))
          (setq-local dape-command command)
          (my-xcode--state-put :last-dape-command command)
          (dape (cdr command))))))))

(defun my-xcode--display-info (container state &optional product)
  "Display CONTAINER, STATE and optional resolved PRODUCT."
  (let ((destination (plist-get state :destination)))
    (with-help-window "*Xcode Info*"
      (princ (format "Project:       %s\nContainer:     %s\nScheme:        %s\n"
                     (my-xcode--project-root) container
                     (or (plist-get state :scheme) "<not selected>")))
      (princ (format "Destination:   %s\nConfiguration: %s\n"
                     (if destination (my-xcode--destination-label destination)
                       "<not selected>")
                     (or (plist-get state :configuration) "<not selected>")))
      (if product
          (let ((app (plist-get product :app))
                (program (plist-get product :program)))
            (princ (format "Bundle ID:     %s\nApp product:   %s\n"
                           (plist-get product :bundle-id) app))
            (princ (format "App state:     %s\nExecutable:    %s\n"
                           (if (file-directory-p app) "present" "missing")
                           program))
            (princ (format "Program state: %s\n"
                           (cond ((not (file-exists-p program)) "missing")
                                 ((file-executable-p program) "executable")
                                 (t "present, not executable")))))
        (princ "Product:       <unresolved until selection is complete>\n")))))

(defun my-xcode-info ()
  "Show current Xcode selection and observed resolved product state."
  (interactive)
  (let ((container (my-xcode--container))
        (state (my-xcode--state)))
    (if (not (and (plist-get state :scheme) (plist-get state :destination)
                  (plist-get state :configuration)))
        (my-xcode--display-info container state)
      (my-xcode--ensure-scheme
       (lambda (scheme)
         (let ((destination (plist-get (my-xcode--state) :destination)))
           (my-xcode--ensure-configuration
            scheme
            (lambda (configuration)
              (let ((selection (list :scheme scheme :destination destination
                                     :configuration configuration)))
                (my-xcode--product-settings-async
                 selection
                 (lambda (product)
                   (my-xcode--display-info
                    container (my-xcode--state) product))))))))))))


(defun my-xcode-open-container ()
  "Open the selected workspace or project directly in Xcode."
  (interactive)
  (make-process :name (generate-new-buffer-name "xcode-open")
                :command (list "/usr/bin/open" "-a" "Xcode" (my-xcode--container))
                :noquery t :connection-type 'pipe))

(defun my-xcode--physical-pid-candidates (destination product)
  "Return valid PID candidate metadata, newest first.
Expired and malformed candidate files are deleted but their reusable paths stay
registered for a cached Dape restart."
  (let ((now (float-time)) valid)
    (dolist (pid-file (my-xcode--device-pid-candidates destination product))
      (when (file-readable-p pid-file)
        (let* ((attributes (file-attributes pid-file))
               (mtime (float-time
                       (file-attribute-modification-time attributes))))
          (if (> (- now mtime) my-xcode--device-pid-ttl)
              (delete-file pid-file)
            (let ((pid (string-trim
                        (with-temp-buffer
                          (insert-file-contents pid-file)
                          (buffer-string)))))
              (if (string-match-p "\\`[1-9][0-9]*\\'" pid)
                  (push (list :file pid-file :mtime mtime :pid pid) valid)
                (delete-file pid-file)))))))
    (sort valid (lambda (left right)
                  (> (plist-get left :mtime) (plist-get right :mtime))))))

(defun my-xcode--termination-spec (destination product)
  "Return termination command and any consumed PID-file for the selected app."
  (if (eq (plist-get destination :kind) 'simulator)
      (list :command
            (list "xcrun" "simctl" "terminate"
                  (plist-get destination :id) (plist-get product :bundle-id)))
    (let ((core-id (plist-get destination :core-device-id)))
      (unless core-id
        (user-error "Physical destination has no CoreDevice identifier"))
      (let ((candidate (car (my-xcode--physical-pid-candidates
                             destination product))))
        (unless candidate
          (user-error
           "No unexpired PID recorded for %s on the selected physical device"
           (plist-get product :bundle-id)))
        (list :command
              (list "xcrun" "devicectl" "device" "process" "terminate"
                    "--device" core-id "--pid" (plist-get candidate :pid))
              :pid-file (plist-get candidate :file))))))

(defun my-xcode--terminate-command (destination product)
  "Return the documented termination command for DESTINATION and PRODUCT."
  (plist-get (my-xcode--termination-spec destination product) :command))

(defun my-xcode--consume-device-pid-file (pid-file)
  "Delete a successfully consumed PID-FILE while retaining its registration."
  (when (and pid-file (file-exists-p pid-file))
    (delete-file pid-file)))

(defun my-xcode--start-short-process (label command &optional exit-callback)
  "Run COMMAND asynchronously and invoke EXIT-CALLBACK with its process."
  (let ((buffer (get-buffer-create (format "*Xcode %s*" label))))
    (display-buffer buffer)
    (make-process
     :name (generate-new-buffer-name (format "xcode-%s" (downcase label)))
     :buffer buffer :command command :noquery t :connection-type 'pipe
     :sentinel (lambda (process _event)
                 (when (memq (process-status process) '(exit signal))
                   (message "Xcode %s %s" label
                            (if (zerop (process-exit-status process))
                                "finished" "was not needed or failed"))
                   (when exit-callback
                     (funcall exit-callback process)))))))

(defun my-xcode-stop ()
  "Stop active Dape sessions and best-effort terminate the selected app."
  (interactive)
  (require 'dape)
  (cl-labels
      ((quit-only (message-text)
         (when dape--connections (dape-quit))
         (message "%s" message-text)))
    (let ((state (my-xcode--state)))
      (if (not (and (plist-get state :scheme)
                    (plist-get state :destination)
                    (plist-get state :configuration)))
          (quit-only "Dape stopped; no complete Xcode app selection")
        (my-xcode--ensure-scheme
         (lambda (scheme)
           (let ((destination (plist-get (my-xcode--state) :destination)))
             (my-xcode--ensure-configuration
              scheme
              (lambda (configuration)
                (let ((selection (list :scheme scheme :destination destination
                                       :configuration configuration)))
                  (my-xcode--product-settings-async
                   selection
                   (lambda (product)
                     (let* ((termination
                             (condition-case error
                                 (my-xcode--termination-spec destination product)
                               (user-error
                                (message "%s" (error-message-string error))
                                nil)))
                            (command (plist-get termination :command))
                            (pid-file (plist-get termination :pid-file)))
                       (when dape--connections (dape-quit))
                       (if command
                           (my-xcode--start-short-process
                            "Stop" command
                            (lambda (process)
                              (when (zerop (process-exit-status process))
                                (my-xcode--consume-device-pid-file pid-file))))
                         (message "Dape stopped; app termination unavailable"))))
                   (lambda ()
                     (quit-only
                      "Dape stopped; app product resolution failed")))))
              (lambda ()
                (quit-only "Dape stopped; configuration query failed")))))
         (lambda () (quit-only "Dape stopped; scheme query failed")))))))

(defun my-xcode-stream-logs ()
  "Stream logs for the selected simulator app asynchronously."
  (interactive)
  (my-xcode--with-selection
   (lambda (selection)
     (let ((destination (plist-get selection :destination)))
       (when (eq (plist-get destination :kind) 'device)
         (user-error "Installed Apple tools cannot independently stream physical app logs; devicectl --console would relaunch it"))
       (my-xcode--product-settings-async
        selection
        (lambda (product)
          (my-xcode--start-compilation
           "Logs" (list (list "xcrun" "simctl" "spawn"
                              (plist-get destination :id)
                              "log" "stream" "--style" "compact"
                              "--level" "debug" "--process"
                              (plist-get product :executable-name))))))))))

(defun my-xcode-restart-dape ()
  "Restart the current, most recent, or last project Xcode Dape session."
  (interactive)
  (require 'dape)
  (my-xcode--ensure-last-dape-pid-registered)
  (condition-case error
      (call-interactively #'dape-restart)
    (user-error
     (let ((command (plist-get (my-xcode--state) :last-dape-command)))
       (if (and command
                (string-match-p "Unable to derive session to restart"
                                (error-message-string error)))
           (dape (cdr command))
         (signal (car error) (cdr error)))))))

(defvar-keymap my-xcode-prefix-map
  :doc "Project Xcode build, run and debug commands."
  "t" #'my-xcode-select-destination "s" #'my-xcode-select-scheme
  "c" #'my-xcode-select-configuration "b" #'my-xcode-build
  "r" #'my-xcode-run "i" #'my-xcode-info "q" #'my-xcode-stop
  "o" #'my-xcode-open-container "l" #'my-xcode-stream-logs
  "R" #'my-xcode-restart-dape "d" #'my-xcode-dape-debug
  "C-g" #'keyboard-quit)

(keymap-unset global-map "C-c x")
(with-eval-after-load 'swift-mode
  (keymap-set swift-mode-map "C-c x" my-xcode-prefix-map))

(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements
    my-xcode-prefix-map
    "t" "target device" "s" "scheme" "c" "configuration" "b" "build"
    "r" "build, install and run" "i" "show selection and product"
    "q" "stop debugger and app" "o" "open in Xcode"
    "l" "stream app logs" "R" "restart Dape session" "d" "debug with Dape"))

(provide 'my-xcode)

;;; my-xcode.el ends here
