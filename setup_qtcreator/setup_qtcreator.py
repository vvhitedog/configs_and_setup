#!/usr/bin/python

import os
from os.path import expanduser
from distutils.dir_util import copy_tree

def mkdir(d):
    if not os.path.exists(d):
        os.mkdir(d)

# copy QtProject -> ~/.config/QtProject recursively
home = expanduser("~")
confd = os.path.join(home,".config") 
mkdir(confd)
qtpd = os.path.join(confd,"QtProject") 
copy_tree('QtProject/',qtpd)

