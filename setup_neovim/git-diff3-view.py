'''
Helper to view git diff3 differences during a rebase

Before running make sure the following is satisfied:

* `g:git_diff3_view_path` in ~/.vimrc points to valid writable directory

To use:

* place cursor in a valid merge/rebase conflict block

* use appropriate keyboard shortcut or the command
  :py3f <path-to>/git-diff3-view.py<cr>

* You will be prompted for the mode which will be one of three:
    1. Compare HEAD to CURRENT 
    2. Compare HEAD to BASE
    3. Compare CURRENT to BASE

* The appropriate buffers will open with the coparison of two blocks from HEAD,
  CURRENT and BASE differenced
'''

from __future__ import print_function
import vim
import subprocess
import sys
import os

def get_diff_block(file_contents,offset):
    before_offset = file_contents[:offset]
    after_offset = file_contents[offset:]

    start_offset = before_offset.rfind('<<<<<<<')
    end_offset = after_offset.find('>>>>>>>')
    if start_offset == -1 or end_offset == -1:
        print("Couldn't find a diff block at this location,"
                " please ensure you are in a diff block.",file=sys.stderr)
        return
    real_end_offset = end_offset + after_offset[end_offset:].find('\n')

    diff_block = "".join([before_offset[start_offset:], after_offset[:real_end_offset]])

    return diff_block


def trim(text,trim_first_line=True,trim_last_line=False):
    lines = text.split('\n')
    if trim_first_line:
        lines = lines[1:]
    if trim_last_line:
        lines = lines[:-1]
    return "\n".join(lines)


def get_head_base_current(diff_block):

    base_start_offset = diff_block.find('|||||||')
    base_end_offset = diff_block.find('=======')

    head = diff_block[:base_start_offset]
    base = diff_block[base_start_offset:base_end_offset]
    current = diff_block[base_end_offset:]

    return trim(head), trim(base), trim(current,True,True)


def main():
    wdir = '/tmp/'
    if vim.eval('exists("g:git_diff3_view_path")') == "1":
        wdir = vim.eval('g:git_diff3_view_path')

    # Get arguments for clang-rename binary.
    offset = int(vim.eval('line2byte(line("."))+col(".")')) - 2
    if offset < 0:
        print('Couldn\'t determine cursor position. Is your file empty?',
              file=sys.stderr)
        return
    filename = vim.current.buffer.name

    prompt_request_message = 'select mode (h for help):'
    mode = vim.eval("input('{}')".format(prompt_request_message))

    vim.command('redraw')

    if mode == 'h' or mode == 'help':
        print('There are three modes:\n'
                '1. Compare HEAD to CURRENT\n'
                '2. Compare HEAD to BASE\n'
                '3. Compare CURRENT to BASE\n')
        return

    if mode != '1' and mode != '2' and mode != '3':
        print('Mode must be one of 1,2 or 3 (use h for help).',
              file=sys.stderr)
        return

    with open(filename,'r') as f:
        file_contents = f.read()

    diff_block = get_diff_block(file_contents,offset)
    if diff_block is None:
        return
    head,base,current = get_head_base_current(diff_block)

    head_file = os.path.join(wdir,'git_diff3_view_HEAD.txt')
    base_file = os.path.join(wdir,'git_diff3_view_BASE.txt')
    current_file = os.path.join(wdir,'git_diff3_view_CURRENT.txt')

    with open(head_file,'w') as f:
        f.write(head)
    with open(base_file,'w') as f:
        f.write(base)
    with open(current_file,'w') as f:
        f.write(current)

    bottom_file = None
    top_file = None

    if mode == '1':
        top_file = head_file
        bottom_file = current_file
    elif mode == '2':
        top_file = head_file
        bottom_file = base_file
    elif mode == '3':
        top_file = base_file
        bottom_file = current_file

    vim.command('wincmd n')
    vim.command('wincmd H')
    vim.command('e ' + bottom_file)
    vim.command('diffthis')

    vim.command('wincmd n')
    vim.command('e ' + top_file)
    vim.command('diffthis')

    #print ('HEAD:\n',head)
    #print ('BASE:\n',base)
    #print ('CURRENT:\n',current)

    # Reload all buffers in Vim.
    vim.command("checktime")


if __name__ == '__main__':
    main()

