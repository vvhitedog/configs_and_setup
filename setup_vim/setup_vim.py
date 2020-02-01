#!/usr/bin/python

import os
from os.path import expanduser
import sys
from shutil import copyfile

def mkdir(d):
    if not os.path.exists(vimdir):
        os.mkdir(vimdir)

def run_cmd(cmd):
    ret = os.system(cmd)
    if ret != 0:
        print "Error running command: '%s'" % cmd
        #sys.exit(-1)

# Write hard-coded vimrc as vimrc
home = expanduser("~")
vimrc_file = os.path.join(home,".vimrc") 
copyfile('.vimrc.install',vimrc_file)

# Change to home
os.chdir(home)

vimdir = os.path.join(home,".vim")
mkdir(vimdir)
vundledir = os.path.join(vimdir,"bundle")
mkdir(vundledir)

# Install vundle
run_cmd("git clone https://github.com/VundleVim/Vundle.vim.git %s/Vundle.vim" % vundledir)

# Install plugins via vundle
run_cmd("vim +PluginInstall +qall")

# Setup pydoc to use numpy-type docstring
copfile('.multi.txt',os.path.join(vimdir,'/bundle/vim-pydocstring/template/pydocstring/multi.txt'))

