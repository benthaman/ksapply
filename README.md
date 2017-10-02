Installing
==========
Some scripts in the current repository require utilities available in the
git-helpers repository (https://github.com/benthaman/git-helpers).
That repository is configured as a submodule of ksapply.git. After cloning the
current repository, run:
```
git submodule init
git submodule update
```

The functions in quilt-mode.sh are meant to be used with a modified `quilt`
that can use kernel-source.git's series.conf directly instead of a shadow
copy.

Install it from  
https://gitlab.suse.de/benjamin_poirier/quilt


The LINUX_GIT environment variable must be set to the path of a fresh Linux
kernel git clone; it will be used as a reference for upstream commit
information. Specifically, this must be a clone of
git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git or one of the
alternate URLs found on kernel.org. The `user.name` and `user.email` git
config variables must be set to sensible values in that clone; they will be
used to tag patches.

If you want to import patches that are not yet in mainline but that are in a
subsystem maintainer's tree, this repository must be configured as an
additional remote of the local repository cloned under LINUX_GIT. For example:
```
linux$ git remote show
net # git://git.kernel.org/pub/scm/linux/kernel/git/davem/net.git
net-next # git://git.kernel.org/pub/scm/linux/kernel/git/davem/net-next.git
origin # git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
stable # git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
```

Please note that linux-next is not a subsystem maintainer tree. If a commit is
in linux-next, it comes from some other tree.

Example workflow to backport a single commit
============================================
For example, we want to backport f5a952c08e84 which is a fix for another
commit which was already backported:
```
# adjust the path to `sequence-insert.py` according to your environment
ben@f1:~/local/src/kernel-source$ ./scripts/sequence-patch.sh $(~/programming/suse/ksapply/sequence-insert.py f5a952c08e84)
[...]
ben@f1:~/local/src/kernel-source$ cd tmp/current
ben@f1:~/local/src/kernel-source/tmp/current$ . ~/programming/suse/ksapply/quilt-mode.sh
# Note that we are using the "-f" option of qcp since f5a952c08e84 is a
# followup to another commit; its log contains a "Fixes" tag. If that was not
# the case, we would use the "-d" and "-r" options of qcp.
ben@f1:~/local/src/kernel-source/tmp/current$ qcp -f f5a952c08e84
Info: using references "bsc#1026030 FATE#321670" from patch "patches.drivers/of-of_mdio-Add-a-whitelist-of-PHY-compatibilities.patch" which contains commit ae461131960b.
Importing patch /tmp/qcp.d82Wqi/0001-of-of_mdio-Add-marvell-88e1145-to-whitelist-of-PHY-c.patch (stored as patches/patches.drivers/of-of_mdio-Add-marvell-88e1145-to-whitelist-of-PHY-c.patch)
# Note that `q` is an alias for `quilt`. You may be using `q` a lot...
ben@f1:~/local/src/kernel-source/tmp/current$ q push
Applying patch patches/patches.drivers/of-of_mdio-Add-marvell-88e1145-to-whitelist-of-PHY-c.patch
File drivers/of/of_mdio.c is read-only; trying to patch anyway
patching file drivers/of/of_mdio.c
Applied patch patches/patches.drivers/of-of_mdio-Add-marvell-88e1145-to-whitelist-of-PHY-c.patch (needs refresh)

Now at patch patches/patches.drivers/of-of_mdio-Add-marvell-88e1145-to-whitelist-of-PHY-c.patch
ben@f1:~/local/src/kernel-source/tmp/current$ make olddefconfig
  HOSTCC  scripts/basic/fixdep
  HOSTCC  scripts/kconfig/conf.o
  SHIPPED scripts/kconfig/zconf.tab.c
  SHIPPED scripts/kconfig/zconf.lex.c
  SHIPPED scripts/kconfig/zconf.hash.c
  HOSTCC  scripts/kconfig/zconf.tab.o
  HOSTLD  scripts/kconfig/conf
scripts/kconfig/conf  --olddefconfig Kconfig
ben@f1:~/local/src/kernel-source/tmp/current$ qfmake
[...]
ben@f1:~/local/src/kernel-source/tmp/current$ ./refresh_patch.sh
Refreshed patch patches/patches.drivers/of-of_mdio-Add-marvell-88e1145-to-whitelist-of-PHY-c.patch
ben@f1:~/local/src/kernel-source/tmp/current$ cd ../../
ben@f1:~/local/src/kernel-source$ git st
On branch SLE12-SP3
Your branch is up-to-date with 'kerncvs/SLE12-SP3'.
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

	modified:   series.conf

Untracked files:
  (use "git add <file>..." to include in what will be committed)

	patches.drivers/of-of_mdio-Add-marvell-88e1145-to-whitelist-of-PHY-c.patch

no changes added to commit (use "git add" and/or "git commit -a")
ben@f1:~/local/src/kernel-source$ git add -A
ben@f1:~/local/src/kernel-source$ ./scripts/log
```

Example workflow to backport a series of commits using kernel-source.git
========================================================================
Refer to the section "Generate the list of commit ids to backport" to generate
the primary list of commits to backport, /tmp/list

Generate the work tree with patches applied up to the first patch in the
list of commits to backport:
```
# adjust the path to `sequence-insert.py` according to your environment
kernel-source$ ./scripts/sequence-patch.sh $(~/programming/suse/ksapply/sequence-insert.py $(head -n1 /tmp/list | awk '{print $1}'))
```

It is preferable to check that the driver builds before getting started:
```
kernel-source/tmp/current$ make -j4 drivers/net/ethernet/intel/e1000/
```

Import the quilt-mode functions:
```
kernel-source/tmp/current$ . ~/programming/suse/ksapply/quilt-mode.sh
```

Set the list of commits to backport:
```
kernel-source/tmp/current$ qadd -r "bsc#1024371 FATE#321245" -d patches.drivers < /tmp/list
```

Note that the commits are automatically sorted using git-sort.
The references and destination are saved in environment variables and reused
later by `qcp` (see below). They can also be specified directly to `qcp`.

The working list can be queried at any time. Note that it is kept in the
$series environment variable. It will be lost if the shell exits. It is not
available in other terminals.
```
kernel-source/tmp/current$ qnext
847a1d6796c7 e1000: Do not overestimate descriptor counts in Tx pre-check (v4.6-rc3)
kernel-source/tmp/current$ qcat
	847a1d6796c7 e1000: Do not overestimate descriptor counts in Tx pre-check (v4.6-rc3)
	a4605fef7132 e1000: Double Tx descriptors needed check for 82544 (v4.6-rc3)
	1f2f83f83848 e1000: call ndo_stop() instead of dev_close() when running offline selftest (v4.7-rc1)
	91c527a55664 ethernet/intel: use core min/max MTU checking (v4.10-rc1)
	311191297125 e1000: use disable_hardirq() for e1000_netpoll() (v4.10-rc1)
```

Start backporting:
```
kernel-source/tmp/current$ qdoit -j4 drivers/net/ethernet/intel/e1000/
```

For each commit in the list, this command will
* go to the appropriate location in the series using `qgoto` which calls
  `quilt push/pop`
* check that the commit is not already present somewhere in the series using
  `qdupcheck`
* import the commit using `qcp` which calls `git format-patch` and `quilt
  import`
* add required tags using `clean_header.sh`
* apply the commit using `quilt push`
* build test the result using `qfmake`. This calls make with the options
  specified to `qdoit` plus the .o targets corresponding to the .c files
  changed by the topmost patch.

The process will stop automatically in case of error. At that time the user
must address the situation and then call `qdoit` again when ready.

To address the situation,
* if a commit is already present in an existing patch
	* possibly leave the patch where it is or move it to the current
	  location. To move a patch, edit series.conf. However, if the patch
	  is already applied, make sure to use `q pop` or `qgoto` first.
	  Then call `qskip` to skip the commit.
	* remove the other copy, using `q delete -r <patch`, then call
	  `qcp <commit>` and follow as indicated below (q push, qfmake,
	  ./refresh_patch.sh)
* if a commit does not apply
	`q push -f # or -fm`
	`vi-conflicts # also from git-helpers`
	`qfmake [...]`
	`./refresh_patch.sh`
* if one or more additional commits are necessary to fix the problem
	Use `qedit` to add these additional commits to the list of commits to
	backport.

	Note that the queue of commits to backport is sorted after invoking
	qadd or qedit. Therefore, commits can be added anywhere in the list
	when using qedit.
	After editing the queue of commits to backport, `qnext` will show one
	of the new commits since it should be backported before the current
	one. You can continue by calling `qdoit` to backport the dependent
	commits.
* if it turns out that the commit should be skipped
	`q delete -r`
	or, if after having done `q push -f`:
	`q pop -f`
	`q delete -r $(q next)`

The following commands can be useful to identify the origin of code lines when
fixing conflicts:
```
quilt annotate <file>
git gui blame --line=<line> <commit> <file>
```

Using your own workflow and then inserting a new patch at the right position in series.conf
===========================================================================================
It is not mandatory to use the quilt-mode helpers to add patches to the sorted
section of series.conf. You can also import a patch into kernel-source.git
using whatever means you prefer, add a new line for this patch anywhere in the
"sorted patches" section of series.conf and perform a sort of the entire
section (from the start of "sorted patches" to the end of "out-of-tree
patches") which will reposition the new entry. This last step is done using
the "series_sort.py" script:
```
kernel-source$ ~/programming/suse/ksapply/series_sort.py series.conf
```

Example workflow to backport a series of commits using kernel.git
=================================================================
The following instructions detail an older approach, before series.conf was
sorted. The instructions may still be relevant to die hard users of
kernel.git but the resulting series.conf will need to be reordered, which may
create some context conflicts.

Obtain a patch set
------------------
### Option 1) Patch files from an external source
When the patches come from vendors and have uncertain content: run a first
pass of clean_patch.sh.
```
patches$ for file in *; do echo $file; clean_header.sh -r "bnc#790588 FATE#313912" $file; done
```

Although not mandatory, this step gives an idea of what condition the patch
set is in to begin with. If this step succeeds, we will be able to have nice
tags at the end.

#### Import the patch set into kernel.git
Import the patch set into kernel.git to make sure that it applies, compiles
and works. The custom SUSE tags (Patch-mainline, ...) will be lost in the
process. Before doing `git am`, run armor_origin.sh which transforms the
"Git-commit" tag into a "(cherry picked from ...)" line.
```
patches$ for file in *; do echo $file; armor_origin.sh $file; done
kernel$ git am /tmp/patches/cleaned/*
```

Use `git rebase -i` to add missing commits where they belong or generally fixup
what needs to be.

```
kernel$ git format-patch -o /tmp/patches/sp3 origin/SLE11-SP3..
```

### Option 2) Commits from a git repository
As an alternative to the previous steps, use this procedure when there is no
patch set that comes from the vendor and it is instead us who are doing the
backport.

#### Generate the list of commit ids to backport
```
upstream$ git log --no-merges --topo-order --reverse --pretty=tformat:%H v3.12.6.. -- drivers/net/ethernet/emulex/benet/ > /tmp/output
```

Optionally, generate a description of the commits to backport.
```
upstream$ cat /tmp/output | xargs -n1 git log -n1 --oneline > /tmp/list
```

Optionally, check if commits in the list are referenced in the logs of later
commits which are not in the list themselves. You may wish to review these
later commits and add them to the list.
```
upstream$ cat /tmp/list | check_missing_fixes.sh
```

Optionally, check which commits in the list have already been applied to
kernel-source.git. Afterwards, you may wish to regenerate the list of commit
ids with a different starting point; or remove from series.conf the commits
that have already been applied and cherry-pick them again during the backport;
or skip them during the backport.

```
# note that the path is a pattern, not just a base directory
kernel-source$ cat /tmp/list | refs_in_series.sh "drivers/net/ethernet/emulex/benet/*"
```

#### Cherry-pick each desired commit to kernel.git
```
kernel$ . ~/programming/suse/ksapply/backport-mode.sh
# note that the pattern is quoted
kernel$ bpset -s -p ../kernel-source/ -a /tmp/list_series -c /tmp/list2 "drivers/net/ethernet/emulex/benet/*"
```

Examine the next commit using the following commands
```
bpref
bpnext
bpstat
```
Apply the next commit completely
```
bpcherry-pick-all
bpcp
```

Apply a subset of the next commit. The changes under the path specified to
bpset are included, more can optionally be specified.
```
bpcherry-pick-include <path>
bpcpi
```

After applying a commit, you may have to fix conflicts manually. Moreover,
it's a good thing to check that the result builds. Sometimes the driver commit
depends on a core change. In that case, the core change can be cherry-picked
and moved just before the current commit using git rebase -i.

Alternatively, instead of applying the next commit, skip it
```
bpskip
```

There is a command to automate the above steps. It applies the next commit and
checks that the result builds, for all remaining commits that were fed to
`bpset`, one commit at a time. The command stops when there are problems.
After manually fixing the problems, the command can be run again to resume
where it stopped. To speed things up, `make` is called with a target
directory, which is the argument.
```
bpdoit drivers/net/ethernet/emulex/benet/

kernel$ git format-patch -o /tmp/patches/sp3 ccdc24086d54
```

Import the patch set into kernel-source.git
-------------------------------------------
Check series.conf to find where the patch set will go and note the last patch
before that (ex:
"patches.drivers/IB-0004-mlx4-Configure-extended-active-speeds.patch") and the
next patch after that (ex: "patches.drivers/iwlwifi-sp1-compatible-options").
```
kernel-source$ ./scripts/sequence-patch.sh patches.drivers/IB-0004-mlx4-Configure-extended-active-speeds.patch
kernel-source$ cd tmp/current
kernel-source/tmp/current$ quilt import /tmp/patches/sp3/*
kernel-source/tmp/current$ while ! ( quilt next | grep -q iwlwifi-sp1-compatible-options) &&
	ksapply.sh -R "bnc#790588 FATE#313912" -s suse.com patches.drivers/; do true; done
kernel-source/tmp/current$ cd ../../
```

Copy the new entries to their desired location in series.conf
```
kernel-source/tmp/current$ vi -p series.conf tmp/current/series

kernel-source$ git add -A
kernel-source$ scripts/log
```
