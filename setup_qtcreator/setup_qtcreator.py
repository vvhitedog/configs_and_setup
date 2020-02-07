#!/usr/bin/python

import os
from os.path import expanduser
import sys
from shutil import copyfile

def mkdir(d):
    if not os.path.exists(d):
        os.mkdir(d)

# copy QtCreator.ini -> ~/.config/QtProject/QtCreator.ini
home = expanduser("~")
confd = os.path.join(home,".config") 
mkdir(confd)
qtpd = os.path.join(confd,"QtProject") 
mkdir(qtpd)
qtinif = os.path.join(qtpd,"QtCreator.ini") 
copyfile('QtCreator.ini',qtinif)

