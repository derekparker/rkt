# check if we have undefine feature (only in make >=3.82)
ifneq ($(filter undefine,$(.FEATURES)),)

# we have undefine
define undef
$(eval undefine $1)
endef

else

# no undefine available, simply set the variable to empty value
define undef
$(eval $1 :=)
endef

endif

# 1 - a list of variables to undefine
#
# Simply uses undefine directive on all passed variables.
#
# It does not check if variables are in any way special (like being
# special make variables or else).
#
# Example: $(call undefine-variables-unchecked,VAR1 VAR2 VAR3)
define undefine-variables-unchecked
$(strip \
	$(foreach v,$1, \
		$(call undef,$v)))
endef

# 1 - a list of variable namespaces
# 2 - a list of excluded variables
#
# Undefines all variables in all given namespaces (which basically
# means variables with names prefixed with <namespace>_) except for
# ones listed in a given exclusions list.
#
# It does not check if variables are in any way special (like being
# special make variables or else).
#
# It is a bit of make-golf to avoid using variables. See
# undefine-namespaces below, which has clearer code, is doing exactly
# the same, but calls undefine-variables instead (which changes its
# behaviour wrt. the origin of the variables).
#
# Example: $(call undefine-namespaces-unchecked,NS1 NS2 NS3,N1_KEEP_THIS N3_THIS_TOO)
define undefine-namespaces-unchecked
$(strip \
	$(foreach ,x x, \
		$(call undefine-variables-unchecked, \
			$(filter-out $2, \
				$(filter $(foreach n,$1,$n_%),$(.VARIABLES))))))
endef

# 1 - a list of variables to undefine
#
# Undefines those variables from a given list, which have origin
# "file". If the origin of a variable is different, it is left
# untouched.
#
# This function will bail out if any of the variables starts with a
# dot or MAKE.
#
# Example: $(call undefine-variables,VAR1 VAR2 VAR3)
define undefine-variables
$(strip \
	$(foreach p,.% MAKE%, \
		$(eval _MISC_UV_FORBIDDEN_ := $(strip $(filter $p,$1))) \
		$(if $(_MISC_UV_FORBIDDEN_), \
			$(eval _MISC_UV_ERROR_ += Trying to undefine $(_MISC_UV_FORBIDDEN_) variables which match the forbidden pattern $p.))) \
	$(if $(_MISC_UV_ERROR_), \
		$(error $(_MISC_UV_ERROR_))) \
	$(foreach v,$1, \
		$(if $(filter-out file,$(origin $v)), \
			$(eval _MISC_UV_EXCLUDES_ += $v))) \
	$(eval _MISC_UV_VARS_ := $(filter-out $(_MISC_UV_EXCLUDES_), $1)) \
	$(call undefine-variables-unchecked,$(_MISC_UV_VARS_)) \
	$(call undefine-namespaces-unchecked,_MISC_UV))
endef

# 1 - a list of variable namespaces
# 2 - a list of excluded variables
#
# Undefines those variables in all given namespaces (which basically
# means variables with names prefixed with <namespace>_), which have
# origin "file". If the origin of the variable is different or the
# variable is a part of exclusions list, it is left untouched.
#
# This function will bail out if any of the variables starts with a
# dot or MAKE.
#
# The function performs the action twice - sometimes defined variables
# are not listed in .VARIABLES list initially, but they do show up
# there after first iteration, so we can remove them then. It is
# likely a make bug.
#
# Example: $(call undefine-namespaces,NS1 NS2 NS3,N1_KEEP_THIS N3_THIS_TOO)
define undefine-namespaces
$(strip \
	$(foreach ,x x, \
		$(eval _MISC_UN_VARS_ := $(filter $(foreach n,$1,$n_%),$(.VARIABLES))) \
		$(eval _MISC_UN_VARS_ := $(filter-out $2,$(_MISC_UN_VARS_))) \
		$(call undefine-variables,$(_MISC_UN_VARS_)) \
		$(call undefine-namespaces-unchecked,_MISC_UN)))
endef

define multi-subst
$(strip \
	$(eval _MISC_MS_TMP_ := $(strip $3)) \
	$(eval $(foreach s,$1, \
		$(eval _MISC_MS_TMP_ := $(subst $s,$2,$(_MISC_MS_TMP_))))) \
	$(_MISC_MS_TMP_) \
	$(call undefine-namespaces,_MISC_MS))
endef

# When updating replaced chars here, remember to update them in
# libdepsgen.pm in escape_path sub.
define escape-for-file
$(call multi-subst,- / . : +,_,$1)
endef

define path-to-file-with-suffix
$(call escape-for-file,$1).$2
endef

define stamp-file
$(STAMPSDIR)/$(call path-to-file-with-suffix,$1,stamp)
endef

# Generates a stamp filename and assigns it to passed variable
# name. Generates a stamp's dependency on stamps directory. Adds stamp
# to CLEAN_FILES. Optional second parameter is for adding a suffix to
# stamp.
# Example: $(call setup-custom-stamp-file,FOO_STAMP,/some_suffix)
define setup-custom-stamp-file
$(strip \
	$(eval $1 := $(call stamp-file,$2)) \
	$(eval $($1): | $$(call to-dir,$($1))) \
	$(eval CLEAN_FILES += $($1)))
endef

# Generates a stamp filename and assigns it to passed variable
# name. Generates a stamp's dependency on stamps directory. Adds stamp
# to CLEAN_FILES. Optional second parameter is for adding a suffix to
# stamp.
# Example: $(call setup-stamp-file,FOO_STAMP,/some_suffix)
define setup-stamp-file
$(eval $(call setup-custom-stamp-file,$1,$(MK_PATH)$2))
endef

define dep-file
$(DEPSDIR)/$(call path-to-file-with-suffix,$1,dep.mk)
endef

define setup-custom-dep-file
$(strip \
	$(eval $1 := $(call dep-file,$2)) \
	$(eval $($1): | $$(call to-dir,$($1))) \
	$(eval CLEAN_FILES += $($1)))
endef

define setup-dep-file
$(eval $(call setup-custom-dep-file,$1,$(MK_PATH)$2))
endef

# Returns all not-excluded directories inside $REPO_PATH that have
# nonzero files matching given "go list -f {{.ITEM}}".
# 1 - where to look for files (./... to look for all files inside the project)
# 2 - a "go list -f {{.ITEM}}" item (GoFiles, TestGoFiles, etc)
# 3 - space-separated list of excluded directories
# Example: $(call go-find-directories,./...,TestGoFiles,tests)
define go-find-directories
$(strip \
	$(eval _MISC_GFD_ESCAPED_SRCDIR := $(MK_TOPLEVEL_ABS_SRCDIR)) \
	$(eval _MISC_GFD_ESCAPED_SRCDIR := $(subst .,\.,$(_MISC_GFD_ESCAPED_SRCDIR))) \
	$(eval _MISC_GFD_ESCAPED_SRCDIR := $(subst /,\/,$(_MISC_GFD_ESCAPED_SRCDIR))) \
	$(eval _MISC_GFD_SPACE_ :=) \
	$(eval _MISC_GFD_SPACE_ +=) \
	$(eval _MISC_GFD_FILES_ := $(shell $(GO_ENV) "$(GO)" list -f '{{.ImportPath}} {{.$2}}' $1 | \
		grep --invert-match '\[\]' | \
		sed -e 's/.*$(_MISC_GFD_ESCAPED_SRCDIR)\///' -e 's/[[:space:]]*\[.*\]$$//' \
		$(if $3,| grep --invert-match '^\($(subst $(_MISC_GFD_SPACE_),\|,$3)\)'))) \
	$(_MISC_GFD_FILES_) \
	$(call undefine-namespaces,_MISC_GFD))
endef

# Returns 1 if both parameters are equal, otherwise returns empty
# string.
# Example: is_a_equal_to_b := $(if $(call equal,a,b),yes,no)
define equal
$(strip \
        $(eval _MISC_EQ_TMP_ := $(shell expr '$1' = '$2')) \
        $(filter $(_MISC_EQ_TMP_),1) \
        $(call undefine-namespaces,_MISC_EQ))
endef

# Returns a string with all backslashes and double quotes escaped and
# wrapped in another double quotes. Useful for passing a string as a
# single parameter. In general the following should print the same:
# str := "aaa"
# $(info $(str))
# $(shell echo $(call escape-and-wrap,$(str)))
define escape-and-wrap
"$(subst ",\",$(subst \,\\,$1))"
endef
# "
# the double quotes in comment above remove highlighting confusion

# Forwards given variables to a given rule.
# 1 - a rule target
# 2 - a list of variables to forward
#
# Example: $(call forward-vars,$(MY_TARGET),VAR1 VAR2 VAR3)
#
# The effect is basically:
# $(MY_TARGET): VAR1 := $(VAR1)
# $(MY_TARGET): VAR2 := $(VAR2)
# $(MY_TARGET): VAR3 := $(VAR3)
define forward-vars
$(strip \
	$(foreach v,$2, \
		$(eval $1: $v := $($v))))
endef

# Returns a colon (:) if passed value is empty. Useful for avoiding
# shell errors about an empty body.
# 1 - bash code
define colon-if-empty
$(if $(strip $1),$1,:)
endef

# Used by generate-simple-rule, see its docs.
define simple-rule-template
$1: $2 $(if $(strip $3),| $3)
	$(call colon-if-empty,$4)
endef

# Generates a simple rule - without variable forwarding and with only
# a single-command recipe.
# 1 - targets
# 2 - reqs
# 3 - order-only reqs
# 4 - recipe
define generate-simple-rule
$(eval $(call simple-rule-template,$1,$2,$3,$4))
endef

# Generates a rule with a "set -e".
# 1 - target (stamp file)
# 2 - reqs
# 3 - order-only reqs
# 4 - recipe placed after 'set -e'
define generate-strict-rule
$(call generate-simple-rule,$1,$2,$3,set -e; $(call colon-if-empty,$4))
endef

# Generates a rule for creating a stamp with additional actions to be
# performed before the actual stamp creation.
# 1 - target (stamp file)
# 2 - reqs
# 3 - order-only reqs
# 4 - recipe placed between 'set -e' and 'touch "$@"'
define generate-stamp-rule
$(call generate-strict-rule,$1,$2,$3,$(call colon-if-empty,$4); touch "$$@")
endef

# 1 - from
# 2 - to
define bash-cond-rename
if cmp --silent "$1" "$2"; then rm -f "$1"; else mv "$1" "$2"; fi
endef

# Generates a rule for generating a depmk for a given go binary from a
# given package. It also tries to include the depmk.
#
# This function (and the other generate-*-deps) are stamp-based. It
# generates no rule for actual depmk. Instead it generates a rule for
# creating a stamp, which will also generate the depmk. This is to
# avoid generating depmk at make startup, when it parses the
# Makefile. At startup, make tries to rebuild all the files it tries
# to include if there is a rule for the file. We do not want that -
# that would override a depmk with a fresh one, so no file
# additions/deletions made before running make would be detected.
#
# 1 - a stamp file
# 2 - a binary name
# 3 - depmk name
# 4 - a package name
define generate-go-deps
$(strip \
	$(if $(call equal,$2,$(DEPSGENTOOL)), \
		$(eval _MISC_GGD_DEP_ := $(DEPSGENTOOL)), \
		$(eval _MISC_GGD_DEP_ := $(DEPSGENTOOL_STAMP))) \
	$(eval -include $3) \
	$(eval $(call generate-stamp-rule,$1,$(_MISC_GGD_DEP_),$(DEPSDIR),$(GO_ENV) "$(DEPSGENTOOL)" go --repo "$(REPO_PATH)" --module "$4" --target '$2 $1' >"$3.tmp"; $(call bash-cond-rename,$3.tmp,$3))) \
	$(call undefine-namespaces,_MISC_GGD))
endef

# Generates a rule for generating a key-value depmk for a given target
# with given variable names to store. It also tries to include the
# depmk.
# 1 - a stamp file
# 2 - a target
# 3 - depmk name
# 4 - a list of variable names to store
define generate-kv-deps
$(strip \
	$(if $(call equal,$2,$(DEPSGENTOOL)), \
		$(eval _MISC_GKD_DEP_ := $(DEPSGENTOOL)), \
		$(eval _MISC_GKD_DEP_ := $(DEPSGENTOOL_STAMP))) \
	$(foreach v,$4, \
		$(eval _MISC_GKD_KV_ += $v $(call escape-and-wrap,$($v)))) \
	$(eval -include $3) \
	$(eval $(call generate-stamp-rule,$1,$(_MISC_GKD_DEP_),$(DEPSDIR),"$(DEPSGENTOOL)" kv --target '$2 $1' $(_MISC_GKD_KV_) >"$3.tmp"; $(call bash-cond-rename,$3.tmp,$3))) \
	$(call undefine-namespaces,_MISC_GKD))
endef

define filelist-file
$(FILELISTDIR)/$(call path-to-file-with-suffix,$1,filelist)
endef

define setup-custom-filelist-file
$(eval $1 := $(call filelist-file,$2)) \
$(eval $($1): | $$(call to-dir,$($1))) \
$(eval CLEAN_FILES += $($1))
endef

define setup-filelist-file
$(eval $(call setup-custom-filelist-file,$1,$(MK_PATH)$2))
endef

# 1 - filelist
define generate-empty-filelist
$(eval $(call generate-strict-rule,$1,$(FILELISTGENTOOL_STAMP),$(FILELISTDIR),"$(FILELISTGENTOOL)" --empty >"$1.tmp"; $(call bash-cond-rename,$1.tmp,$1)))
endef

# 1 - filelist
# 2 - directory
define generate-deep-filelist
$(eval $(call generate-strict-rule,$1,$(FILELISTGENTOOL_STAMP),$(FILELISTDIR),"$(FILELISTGENTOOL)" --directory="$2" >"$1.tmp"; $(call bash-cond-rename,$1.tmp,$1)))
endef

# 1 - filelist
# 2 - a directory
# 3 - a suffix
define generate-shallow-filelist
$(eval $(call generate-strict-rule,$1,$(FILELISTGENTOOL_STAMP),$(FILELISTDIR),"$(FILELISTGENTOOL)" --directory="$2" --suffix="$3" >"$1.tmp"; $(call bash-cond-rename,$1.tmp,$1)))
endef

# Generates a rule for generating a glob depmk for a given target
# based on a given filelist. This is up to you to ensure that every
# file in a filelist ends with a given suffix.
# 1 - a stamp file
# 2 - a target
# 3 - depmk name
# 4 - a suffix
# 5 - a filelist
# 6 - a list of directories to map the files from filelist to
# 7 - glob mode, can be all, dot-files, normal (empty means all)
define generate-glob-deps
$(strip \
	$(if $(call equal,$2,$(DEPSGENTOOL)), \
		$(eval _MISC_GLDF_DEP_ := $(DEPSGENTOOL)), \
		$(eval _MISC_GLDF_DEP_ := $(DEPSGENTOOL_STAMP))) \
	$(if $(strip $7), \
		$(eval _MISC_GLDF_GLOB_ := --glob-mode="$(strip $7)")) \
	$(eval -include $3) \
	$(eval $(call generate-stamp-rule,$1,$(_MISC_GLDF_DEP_) $5,$(DEPSDIR),shopt -s nullglob; "$(DEPSGENTOOL)" glob --target "$2 $1" --suffix="$4" --filelist="$5" $(foreach m,$6,--map-to="$m") $(_MISC_GLDF_GLOB_)>"$3.tmp"; $(call bash-cond-rename,$3.tmp,$3))) \
	$(call undefine-namespaces,_MISC_GLDF))
endef

# Returns a list of directories starting from a subdirectory of given
# base up to the full path made of the given base and a rest. So, if
# base is "base" and rest is "r/e/s/t" then the returned list is
# "base/r base/r/e base/r/e/s base/r/e/s/t".
#
# Useful for getting a list of directories to be removed.
# 1 - a base
# 2 - a dir (or dirs) in base
#
# Example: CREATE_DIRS += $(call dir-chain,$(BASE),src/foo/bar/baz)
define dir-chain
$(strip \
	$(eval _MISC_DC_DIRS_ := $(subst /, ,$2)) \
	$(eval _MISC_DC_PATHS_ :=) \
	$(eval _MISC_DC_LIST_ :=) \
	$(eval $(foreach d,$(_MISC_DC_DIRS_), \
		$(eval _MISC_DC_LAST_ := $(lastword $(_MISC_DC_PATHS_))) \
		$(eval $(if $(_MISC_DC_LAST_), \
			$(eval _MISC_DC_PATHS_ += $(_MISC_DC_LAST_)/$d), \
			$(eval _MISC_DC_PATHS_ := $d))))) \
	$(eval $(foreach d,$(_MISC_DC_PATHS_), \
		$(eval _MISC_DC_LIST_ += $1/$d))) \
	$(_MISC_DC_LIST_) \
	$(call undefine-namespaces,_MISC_DC))
endef

# 1 - variable for dirname
define setup-tmp-dir
$(strip \
	$(eval _MISC_TMP_DIR_ := $(MAINTEMPDIR)/$(subst .mk,,$(MK_FILENAME)))
	$(eval CREATE_DIRS += $(_MISC_TMP_DIR_)) \
	$(eval $1 := $(_MISC_TMP_DIR_)) \
	$(call undefine-namespaces,_MISC_TMP))
endef

define clean-file
$(CLEANDIR)/$(call path-to-file-with-suffix,$1,clean.mk)
endef

define setup-custom-clean-file
$(eval $1 := $(call clean-file,$2)) \
$(eval $($1): | $$(call to-dir,$($1))) \
$(eval CLEAN_FILES += $($1))
endef

define setup-clean-file
$(eval $(call setup-custom-clean-file,$1,$(MK_PATH)$2))
endef

# 1 - stamp file
# 2 - cleanmk file
# 3 - filelist name
# 4 - a list of directory mappings
define generate-clean-mk
$(strip \
	$(eval -include $2) \
	$(eval $(call generate-stamp-rule,$1,$(CLEANGENTOOL_STAMP) $3,$(CLEANDIR),"$(CLEANGENTOOL)" --filelist="$3" $(foreach m,$4,--map-to="$m") >"$2.tmp"; $(call bash-cond-rename,$2.tmp,$2))))
endef
