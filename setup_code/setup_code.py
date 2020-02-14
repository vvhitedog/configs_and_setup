#!/usr/bin/python

import os
import sys
from os.path import expanduser
from shutil import copyfile

def mkdir(d):
    if not os.path.exists(d):
        os.mkdir(d)

# copy 
home = expanduser("~")
confd = os.path.join(home,".config") 
mkdir(confd)
coded = os.path.join(confd,"Code") 
mkdir(coded)
userd = os.path.join(coded,"User") 
mkdir(userd)
print 'copy -> %s to %s' % ('keybindings.json',userd)
print 'copy -> %s to %s' % ('settings.json',userd)
copyfile('keybindings.json',os.path.join(userd,'keybindings.json'))
copyfile('settings.json',os.path.join(userd,'settings.json'))

# install extensions
with open('extensions.txt','r') as f:
    extensions = [ line.strip() for line in f.readlines() ]

for ext in extensions:
    cmd = 'code --install-extension {ext}'.format(ext=ext)
    print cmd
    os.system(cmd)
